#!/usr/bin/env bash
# relay-precommit.sh — Adaptateur SANS-AGENT (git pre-commit / CI) du noyau RELAY « actif »  [RELAY-NOAGENT]
# RELAY Framework — couche ADAPTATEUR, scénario DÉGRADÉ (cf. docs/RELAY-CORE-ACTIF.md §1.1/§1.2/§3).
#
# 3ᵉ ADAPTATEUR du framework (après Claude Code et Cline). Cible le scénario où il n'y a PAS d'agent :
# un dev qui code sans LLM, ou la CI. §1.1 : sans agent, il n'existe AUCUN contexte LLM où injecter la
# règle « avant l'écriture » → le canal y est DÉGRADÉ. La seule barrière possible est en aval, au
# COMMIT (pre-commit) ou dans la CI, et le canal d'enforcement n'est plus un JSON de décision (comme les
# hooks d'agent) mais le CODE DE SORTIE + un texte lisible humain/CI.
#
# Appelle le MÊME noyau agnostique relay-context.sh --path=<fichier> --stdin --strict sur le contenu
# PROPOSÉ de chaque fichier touché, et traduit sa sortie :
#   • ≥1 pattern ERROR (proscrit, exit 3 du noyau) → accumulé → exit 1 final  → BLOQUE le commit / le job.
#   • seulement WARN/INFO                          → texte affiché, non-bloquant (advisory).
#   • rien (silence du noyau)                      → rien (token-négatif, §1.3).
#
# DEUX modes (un seul script) :
#   • pre-commit (défaut) : fichiers STAGÉS (git diff --cached) ; contenu = blob d'INDEX (git show :file)
#                           → on valide ce qui va être committé, pas l'arbre de travail.
#   • CI / range : RELAY_RANGE défini (ex. origin/main...HEAD) → fichiers du diff ; contenu = arbre courant
#                  (en CI le checkout est sur la pointe).
#
# DIFFÉRENCE STRUCTURANTE vs les adaptateurs d'AGENT (relay-hook.sh / relay-precheck.sh) :
#   FAIL-OPEN sur l'OUTILLAGE, FAIL-CLOSED sur le FINDING. Les adaptateurs agent sont PUREMENT fail-open
#   (un hook cassé ne bloque jamais une édition). Ici le BUT MÊME est de bloquer sur un pattern proscrit :
#     - bug d'outillage (git absent, hors dépôt, rules.conf/noyau introuvable) → exit 0 = ne JAMAIS coincer
#       un commit pour un bug d'outil ;
#     - vrai pattern PROSCRIT dans le contenu → exit 1 = on BLOQUE.
#   Échappatoire explicite : RELAY_SKIP=1 (ou git commit --no-verify, qui court-circuite tout pre-commit).
#
# PAS de ledger token-saved (volontaire). La métrique relay-tokens modélise l'économie de RÉÉCRITURE LLM ;
# un commit humain bloqué n'est PAS une réécriture LLM évitée → l'y inscrire CORROMPRAIT la métrique. Même
# discipline que « token-saved = contrefactuel, jamais inventé ». Cet adaptateur ne touche pas le ledger.
#
# Pur Bash, 0 python3 (aucune frontière JSON : git fournit la liste de fichiers, le noyau fournit
# texte + exit code). 0 couplage du noyau : TOUTE la spécificité sans-agent vit ICI ; relay-context.sh
# reste agnostique.

set -uo pipefail

# ── Échappatoire explicite (git --no-verify court-circuite aussi tout hook pre-commit) ─────────────
case "${RELAY_SKIP:-}" in 1|true|yes|on) exit 0 ;; esac

# ── 0. git requis ; absent ou hors dépôt → fail-open (bug d'outillage ne bloque jamais un commit) ──
command -v git >/dev/null 2>&1 || exit 0
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$ROOT" ] && exit 0

# ── 1. Localiser le noyau relay-context.sh (résolution symlink-safe, comme l'adaptateur Cline) ─────
SELF_SRC="${BASH_SOURCE[0]}"
SELF_REAL="$(readlink -f "$SELF_SRC" 2>/dev/null || echo "$SELF_SRC")"
SELF=""
if SELF_DIR="$(cd "$(dirname "$SELF_REAL")" 2>/dev/null && pwd)"; then SELF="$SELF_DIR"; fi
CONTEXT_BIN=""
for cand in "${RELAY_CONTEXT_BIN:-}" \
            "${SELF:-}/../../scripts/relay-context.sh" \
            "${ROOT:+$ROOT/docs/scripts/relay-context.sh}" \
            "${ROOT:+$ROOT/engine/scripts/relay-context.sh}" \
            "$(command -v relay-context.sh 2>/dev/null || true)"; do
  if [ -n "$cand" ] && [ -x "$cand" ]; then CONTEXT_BIN="$cand"; break; fi
done
[ -z "$CONTEXT_BIN" ] && exit 0   # noyau introuvable = bug d'outillage → fail-open

# ── 2. Mode + liste des fichiers à vérifier ────────────────────────────────────────────────────────
#    --diff-filter=ACMR : Ajout/Copie/Modif/Renommage (jamais D : rien à scanner sur une suppression).
if [ -n "${RELAY_RANGE:-}" ]; then
  MODE="range"
  FILES="$(git diff --name-only --diff-filter=ACMR "$RELAY_RANGE" 2>/dev/null || true)"
else
  MODE="precommit"
  FILES="$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)"
fi
[ -z "$FILES" ] && exit 0   # rien à vérifier

# ── 3. Pour chaque fichier : piper le contenu PROPOSÉ au noyau (--strict) et agréger ───────────────
ERR_FILES=0
ADVISORY=""
ERRORS=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  # Source du contenu PROPOSÉ selon le mode
  if [ "$MODE" = "range" ]; then
    [ -f "$ROOT/$f" ] || continue
    CONTENT="$(cat -- "$ROOT/$f" 2>/dev/null || true)"
  else
    CONTENT="$(git show ":$f" 2>/dev/null || true)"   # blob d'index = ce qui va être committé
  fi
  [ -z "$CONTENT" ] && continue
  # Interroger le noyau : --strict → exit 3 si ≥1 ERROR ; sortie humaine = texte terse « [RELAY] … ».
  TEXT="$(printf '%s' "$CONTENT" | "$CONTEXT_BIN" --path="$f" --stdin --strict 2>/dev/null)"
  rc=$?
  [ -z "$TEXT" ] && continue   # silence = aucun pattern présent (token-négatif, §1.3)
  if [ "$rc" -eq 3 ]; then
    ERR_FILES=$((ERR_FILES + 1))
    ERRORS="${ERRORS}${TEXT}"$'\n'
  else
    ADVISORY="${ADVISORY}${TEXT}"$'\n'
  fi
done <<EOF
$FILES
EOF

# ── 4. Émettre — advisory non-bloquant d'abord, puis erreurs (bloquantes) ──────────────────────────
[ -n "$ADVISORY" ] && printf '%s' "$ADVISORY"

if [ "$ERR_FILES" -gt 0 ]; then
  printf '%s' "$ERRORS"
  echo "[RELAY] ⛔ commit bloqué — $ERR_FILES fichier(s) avec un pattern PROSCRIT (corriger AVANT de committer)."
  echo "[RELAY]    Contournement explicite : RELAY_SKIP=1 git commit …  (ou git commit --no-verify) — à vos risques."
  exit 1
fi
exit 0
