#!/usr/bin/env bash
# relay-hook.sh — Adaptateur Claude Code (hook PreToolUse) du noyau RELAY « actif »  [RELAY-3]
# RELAY Framework — couche ADAPTATEUR, propre au harnais Claude Code (cf. docs/RELAY-CORE-ACTIF.md §1.2/§3).
#
# Câblé dans .claude/settings.json sur le matcher Edit|Write|MultiEdit. Reçoit le JSON PreToolUse sur
# stdin (tool_input.file_path + contenu PROPOSÉ), appelle relay-context.sh --path=<édité> --stdin sur ce
# contenu (shift-left : la règle AVANT l'écriture), et traduit la sortie du noyau en décision de hook :
#   • ≥1 pattern ERROR (proscrit) → permissionDecision:"deny" + raison  → bloque ; l'agent corrige AVANT
#                                    d'écrire → la réécriture aval n'a jamais lieu = tokens économisés.
#   • seulement WARN/INFO         → additionalContext (non-bloquant) → l'agent est informé, terse (§1.3).
#   • rien                        → silence (aucune sortie = flux de permission normal).
#
# FAIL-OPEN absolu : toute défaillance de l'adaptateur (python3 absent, JSON illisible, noyau
# introuvable, contenu vide) → aucune sortie / exit 0 = l'édition n'est JAMAIS bloquée par un bug
# d'outillage. Un garde-fou qui casse l'éditeur est pire que pas de garde-fou.
#
# 0 couplage du noyau : TOUTE la spécificité Claude Code vit ICI ; relay-context.sh reste agnostique.

set -uo pipefail

allow_silent() { exit 0; }   # aucune sortie JSON = laisse Claude Code suivre son flux normal

# ── 0. python3 requis pour les 2 frontières JSON (parse stdin + emit décision). Absent → fail-open ──
PY="$(command -v python3 2>/dev/null || true)"
[ -z "$PY" ] && allow_silent

# ── 1. Localiser le noyau relay-context.sh ─────────────────────────────────────────────────────
# Layout uniforme canonique/consommateur : adaptateur <base>/adapters/claude-code/, noyau <base>/scripts/
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
CONTEXT_BIN=""
for cand in "${RELAY_CONTEXT_BIN:-}" "${SELF:-}/../../scripts/relay-context.sh" "$(command -v relay-context.sh 2>/dev/null || true)"; do
  if [ -n "$cand" ] && [ -x "$cand" ]; then CONTEXT_BIN="$cand"; break; fi
done
[ -z "$CONTEXT_BIN" ] && allow_silent

# ── Helpers python3 (script via -c → stdin reste libre pour les DONNÉES) ────────────────────────
PARSE_PY='
import sys, json
out = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)                      # JSON illisible -> file_path vide -> fail-open en aval
ti = data.get("tool_input") or {}
fp = ti.get("file_path") or ti.get("path") or ""
# Contenu PROPOSE selon loutil : Write=content/file_text, Edit=new_string, MultiEdit=edits[].new_string
parts = []
for k in ("content", "file_text", "new_string"):
    v = ti.get(k)
    if isinstance(v, str):
        parts.append(v)
edits = ti.get("edits")
if isinstance(edits, list):
    for e in edits:
        if isinstance(e, dict) and isinstance(e.get("new_string"), str):
            parts.append(e["new_string"])
try:
    with open(out, "w") as f:
        f.write("\n".join(parts))
except Exception:
    sys.exit(0)
print(fp)
'

EMIT_PY='
import sys, json
decision = sys.argv[1]
text = sys.stdin.read().rstrip("\n")
hso = {"hookEventName": "PreToolUse"}
if decision == "deny":
    hso["permissionDecision"] = "deny"
    hso["permissionDecisionReason"] = text
else:
    hso["additionalContext"] = text
print(json.dumps({"hookSpecificOutput": hso}))
'

# ── 2. Parser le stdin PreToolUse → file_path (stdout) + contenu proposé (fichier) via python3 ──
#    Robuste aux échappements JSON (\n, \", \\, unicode) que le bash pur gère mal.
STDIN_JSON="$(cat)"
TMP_CONTENT="$(mktemp 2>/dev/null)" || allow_silent
trap 'rm -f "$TMP_CONTENT"' EXIT

FILE_PATH="$(printf '%s' "$STDIN_JSON" | "$PY" -c "$PARSE_PY" "$TMP_CONTENT" 2>/dev/null)"

[ -z "$FILE_PATH" ] && allow_silent
[ ! -s "$TMP_CONTENT" ] && allow_silent    # aucun contenu proposé (ex. suppression) → rien à analyser

# ── 3. Interroger le noyau sur le CONTENU PROPOSÉ — décision via sa sortie --json (déterministe) ──
JSON_OUT="$("$CONTEXT_BIN" --path="$FILE_PATH" --stdin --json < "$TMP_CONTENT" 2>/dev/null || true)"
[ -z "$JSON_OUT" ] && allow_silent

TOTAL="$(printf '%s' "$JSON_OUT" | grep -o '"total":[0-9]\{1,\}' | head -1 | grep -o '[0-9]\{1,\}')"
ERR="$(printf '%s' "$JSON_OUT"   | grep -o '"error_hits":[0-9]\{1,\}' | head -1 | grep -o '[0-9]\{1,\}')"
TOTAL="${TOTAL:-0}"; ERR="${ERR:-0}"
[ "$TOTAL" -eq 0 ] && allow_silent          # SILENCE (§1.3) — aucun pattern présent = token-négatif

# ── 4. Texte terse à montrer à l'agent = mode humain du noyau (déjà formaté « [RELAY] … ») ──────
TEXT="$("$CONTEXT_BIN" --path="$FILE_PATH" --stdin < "$TMP_CONTENT" 2>/dev/null || true)"
[ -z "$TEXT" ] && allow_silent

# ── 5. Émettre la décision de hook PreToolUse (python3 pour un JSON valide, raison échappée) ────
if [ "$ERR" -gt 0 ]; then DECISION="deny"; else DECISION="context"; fi

# ── 5b. Ledger d'instance (token-saved) — 1 ligne par firing, lue par relay-tokens.sh ───────────
#    deny = réécriture aval évitée (token-saved) ; context = injection amont (token-in). Source de la
#    métrique runtime que ni git ni NEXT_SESSION ne portent. FAIL-OPEN absolu : un échec d'écriture
#    du ledger ne doit JAMAIS bloquer l'édition (sous-shell, erreurs avalées). Gitignoré (donnée
#    d'instance, même convention que relay-run.sh / docs/.relay/receipts).
(
  LEDGER_DIR="docs/.relay"
  if mkdir -p "$LEDGER_DIR" 2>/dev/null; then
    [ -f "$LEDGER_DIR/.gitignore" ] || printf 'receipts/\ntoken-ledger.log\n' > "$LEDGER_DIR/.gitignore" 2>/dev/null
    grep -q '^token-ledger\.log$' "$LEDGER_DIR/.gitignore" 2>/dev/null \
      || printf 'token-ledger.log\n' >> "$LEDGER_DIR/.gitignore" 2>/dev/null
    printf '%s %s err=%s total=%s %s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$DECISION" "$ERR" "$TOTAL" "$FILE_PATH" \
      >> "$LEDGER_DIR/token-ledger.log" 2>/dev/null
  fi
) 2>/dev/null || true

printf '%s' "$TEXT" | "$PY" -c "$EMIT_PY" "$DECISION" 2>/dev/null
exit 0
