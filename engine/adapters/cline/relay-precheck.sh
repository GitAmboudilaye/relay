#!/usr/bin/env bash
# relay-precheck.sh — Adaptateur Cline (hook PreToolUse) du noyau RELAY « actif »  [RELAY-CLINE]
# RELAY Framework — couche ADAPTATEUR, propre au harnais Cline (cf. docs/RELAY-CORE-ACTIF.md §1.2/§3).
#
# 2ᵉ ADAPTATEUR du framework (après Claude Code). Câblé via le système de hooks de Cline (v3.36+) :
# le fichier .clinerules/hooks/PreToolUse (nommé EXACTEMENT ainsi, sans extension, exécutable) doit
# pointer ICI (symlink ou wrapper — voir README). Reçoit le JSON PreToolUse de Cline sur stdin
# (toolName + parameters{path,content|diff}), appelle relay-context.sh --path=<édité> --stdin sur le
# contenu PROPOSÉ (shift-left : la règle AVANT l'écriture), et traduit la sortie du noyau en décision
# de hook Cline :
#   • ≥1 pattern ERROR (proscrit) → {"cancel": true,  "errorMessage": …}    → BLOQUE ; l'agent voit la
#                                    raison et corrige AVANT d'écrire → réécriture aval évitée = tokens.
#   • seulement WARN/INFO         → {"cancel": false, "contextModification": …} → non-bloquant, injecté.
#   • rien / défaillance          → {"cancel": false}  → ALLOW explicite (Cline attend un JSON valide).
#
# DIFFÉRENCE avec l'adaptateur Claude Code (relay-hook.sh) : ici le « silence » n'est PAS l'absence de
# sortie mais un ALLOW explicite {"cancel": false} — c'est le contrat Cline (le hook renvoie toujours un
# JSON). Le schéma JSON d'ENTRÉE diffère aussi (toolName/parameters vs tool_name/tool_input). Le NOYAU,
# lui, est rigoureusement le même relay-context.sh.
#
# FAIL-OPEN absolu : toute défaillance de l'adaptateur (python3 absent, JSON illisible, noyau
# introuvable, contenu vide, outil non-écriture) → {"cancel": false} / exit 0 = l'édition n'est JAMAIS
# bloquée par un bug d'outillage. Un garde-fou qui casse l'éditeur est pire que pas de garde-fou.
#
# 0 couplage du noyau : TOUTE la spécificité Cline vit ICI ; relay-context.sh reste agnostique.

set -uo pipefail

allow() { printf '{"cancel": false}\n'; exit 0; }   # ALLOW explicite = contrat hook Cline

# ── ANTI-FREEZE : un hook PreToolUse ne doit JAMAIS geler l'éditeur. La lecture stdin (`cat` jusqu'à EOF)
#    et les appels au noyau sont bornés par un timeout DUR ; tout dépassement → fail-open (allow). Vecteur
#    observé : un harnais qui n'envoie/ne ferme pas stdin pour certains outils → `cat` attend l'EOF
#    indéfiniment → éditeur figé. « Un garde-fou qui casse l'éditeur est pire que pas de garde-fou. »
#    Surchargeable via RELAY_HOOK_TIMEOUT (secondes, défaut 4). `timeout` absent → exécution non bornée
#    (repli : on ne dégrade pas un env qui n'a pas l'outil, mais l'immense majorité des systèmes l'ont).
TIMEOUT_BIN="$(command -v timeout 2>/dev/null || true)"
HOOK_TIMEOUT="${RELAY_HOOK_TIMEOUT:-4}"
run_bounded() {   # run_bounded <cmd...> sous timeout si dispo ; stdin/redirection hérités tels quels
  if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" "$HOOK_TIMEOUT" "$@"; else "$@"; fi
}

# ── 0. python3 requis pour les 2 frontières JSON (parse stdin + emit décision). Absent → fail-open ──
PY="$(command -v python3 2>/dev/null || true)"
[ -z "$PY" ] && allow

# ── 1. Localiser le noyau relay-context.sh ─────────────────────────────────────────────────────
# SYMLINK-SAFE : Cline impose un fichier nommé « PreToolUse » dans .clinerules/hooks/ ; il pointe ICI
# par symlink/wrapper. readlink -f résout le VRAI emplacement de ce script (sinon ../../scripts casse
# quand on est appelé via le symlink). + repli git-root (consommateur docs/scripts, canonique engine/scripts).
SELF_SRC="${BASH_SOURCE[0]}"
SELF_REAL="$(readlink -f "$SELF_SRC" 2>/dev/null || echo "$SELF_SRC")"
SELF=""
if SELF_DIR="$(cd "$(dirname "$SELF_REAL")" 2>/dev/null && pwd)"; then SELF="$SELF_DIR"; fi
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
CONTEXT_BIN=""
for cand in "${RELAY_CONTEXT_BIN:-}" \
            "${SELF:-}/../../scripts/relay-context.sh" \
            "${ROOT:+$ROOT/docs/scripts/relay-context.sh}" \
            "${ROOT:+$ROOT/engine/scripts/relay-context.sh}" \
            "$(command -v relay-context.sh 2>/dev/null || true)"; do
  if [ -n "$cand" ] && [ -x "$cand" ]; then CONTEXT_BIN="$cand"; break; fi
done
[ -z "$CONTEXT_BIN" ] && allow

# ── Helpers python3 (script via -c → stdin reste libre pour les DONNÉES) ────────────────────────
PARSE_PY='
import sys, json
out = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)                      # JSON illisible -> file_path vide -> fail-open en aval
tool = data.get("toolName") or ""
params = data.get("parameters") or {}
# Seuls les outils dECRITURE de fichier portent un contenu a analyser. Tout le reste -> allow direct.
if tool not in ("write_to_file", "replace_in_file", "new_file", "edit_file"):
    sys.exit(0)
fp = params.get("path") or params.get("file_path") or ""
# Contenu PROPOSE selon loutil : write_to_file=content, replace_in_file=diff (+ alias defensifs)
parts = []
for k in ("content", "diff", "file_text", "new_string"):
    v = params.get(k)
    if isinstance(v, str):
        parts.append(v)
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
if decision == "deny":
    print(json.dumps({"cancel": True, "errorMessage": text}))
else:
    print(json.dumps({"cancel": False, "contextModification": text}))
'

# ── 2. Parser le stdin PreToolUse → file_path (stdout) + contenu proposé (fichier) via python3 ──
#    Robuste aux échappements JSON (\n, \", \\, unicode) que le bash pur gère mal.
# Lecture stdin BORNÉE (LE vecteur de freeze) : timeout sur `cat` → au pire vide après HOOK_TIMEOUT → allow.
STDIN_JSON="$(run_bounded cat 2>/dev/null || true)"
[ -z "$STDIN_JSON" ] && allow
TMP_CONTENT="$(mktemp 2>/dev/null)" || allow
trap 'rm -f "$TMP_CONTENT"' EXIT

FILE_PATH="$(printf '%s' "$STDIN_JSON" | "$PY" -c "$PARSE_PY" "$TMP_CONTENT" 2>/dev/null)"

[ -z "$FILE_PATH" ] && allow
[ ! -s "$TMP_CONTENT" ] && allow         # aucun contenu proposé → rien à analyser → allow

# ── 3. Interroger le noyau sur le CONTENU PROPOSÉ — décision via sa sortie --json (déterministe) ──
JSON_OUT="$(run_bounded "$CONTEXT_BIN" --path="$FILE_PATH" --stdin --json < "$TMP_CONTENT" 2>/dev/null || true)"
[ -z "$JSON_OUT" ] && allow

TOTAL="$(printf '%s' "$JSON_OUT" | grep -o '"total":[0-9]\{1,\}' | head -1 | grep -o '[0-9]\{1,\}')"
ERR="$(printf '%s' "$JSON_OUT"   | grep -o '"error_hits":[0-9]\{1,\}' | head -1 | grep -o '[0-9]\{1,\}')"
TOTAL="${TOTAL:-0}"; ERR="${ERR:-0}"
[ "$TOTAL" -eq 0 ] && allow               # ALLOW (§1.3) — aucun pattern présent = token-négatif

# ── 4. Texte terse à montrer à l'agent = mode humain du noyau (déjà formaté « [RELAY] … ») ──────
TEXT="$(run_bounded "$CONTEXT_BIN" --path="$FILE_PATH" --stdin < "$TMP_CONTENT" 2>/dev/null || true)"
[ -z "$TEXT" ] && allow

# ── 5. Décision : ERROR → cancel(deny) ; sinon contextModification (non-bloquant) ───────────────
if [ "$ERR" -gt 0 ]; then DECISION="deny"; else DECISION="context"; fi

# ── 5b. Ledger d'instance (token-saved) — 1 ligne par firing, lue par relay-tokens.sh ───────────
#    deny = réécriture aval évitée (token-saved) ; context = injection amont (token-in). MÊME format de
#    ligne que l'adaptateur Claude Code → relay-tokens.sh agrège les deux harnais sans changement.
#    FAIL-OPEN absolu : un échec d'écriture du ledger ne doit JAMAIS bloquer l'édition (sous-shell,
#    erreurs avalées). Gitignoré (donnée d'instance, même convention que relay-run.sh).
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

# ── 6. Émettre la décision de hook Cline (python3 pour un JSON valide, texte échappé) ───────────
printf '%s' "$TEXT" | "$PY" -c "$EMIT_PY" "$DECISION" 2>/dev/null || allow
exit 0
