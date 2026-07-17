#!/usr/bin/env bash
# relay-branch-guard.sh v1.0 — Garde de discipline de branche (R2)
# RELAY Framework — gate de commit, pair de relay-uncommitted-guard.sh (R1) / relay-claim-guard.sh (R1bis)
# Usage: ./docs/scripts/relay-branch-guard.sh [--warn] [--json]
#   (défaut)  : HEAD sur une branche PROTÉGÉE → exit 1 (BLOQUE le commit direct)
#   --warn    : signal-only — annonce mais exit 0 (adoption progressive, brownfield)
#   --json    : sortie machine ({branch, protected, clean}), exit code inchangé
#
# Pourquoi (GitFlow allégé, VISION §12) : un modèle main=prod / develop=intégration / feature-hotfix
# ne tient que si l'on ne committe JAMAIS de travail directement sur main/develop (règle « nouveau module =
# nouvelle feature »). Cette règle est identique quel que soit le stack → généralisable (N>1), d'où sa place
# comme garde RELAY portable plutôt que discipline projet répétée à la main.
#
# Câblage : pre-commit (le hook pre-commit NE se déclenche PAS sur un merge — git utilise pre-merge-commit —
# donc un « git merge --no-ff feature/x » qui atterrit sur develop N'est PAS bloqué). Belt-and-suspenders :
# si un merge/rebase/cherry-pick est EN COURS, le garde fail-open (opération legit sur branche protégée).
#
# Branches protégées : défaut « main develop master » ; override via l'env RELAY_PROTECTED_BRANCHES
# (liste séparée par espaces ou virgules), ex. RELAY_PROTECTED_BRANCHES="main develop release".
#
# Sémantique : BLOQUANT par défaut (gate déterministe — la branche courante est un FAIT, pas une heuristique ;
# aligné sur relay-uncommitted-guard), --warn pour signal-only. FAIL-OPEN absolu sur l'OUTILLAGE (hors repo
# git, git absent, HEAD détachée, aucune branche, merge en cours) → exit 0 : ne jamais casser un environnement
# qui n'a pas de quoi le faire tourner, ni une opération git legit. Offline-safe (lecture locale).

set -uo pipefail

WARN=false
JSON_MODE=false
for arg in "$@"; do
  case "$arg" in
    --warn) WARN=true ;;
    --json) JSON_MODE=true ;;
  esac
done

PROJECT_NAME=$(basename "$(pwd)")
TODAY=$(date +%Y-%m-%d 2>/dev/null || echo "")

emit_open() {
  # Sortie fail-open uniforme (toujours exit 0).
  local reason="$1"
  if [ "$JSON_MODE" = "true" ]; then
    echo "{ \"project\": \"$PROJECT_NAME\", \"date\": \"$TODAY\", \"applicable\": false, \"reason\": \"$reason\", \"clean\": true }"
  else
    echo "[RELAY] ⚠️  $reason — garde de branche inapplicable (fail-open, exit 0)."
  fi
  exit 0
}

# ── 0. Fail-open outillage : pas de git OU pas dans un repo ────────────────────────────────────────
if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  emit_open "Pas de dépôt git détecté"
fi

GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || echo ".git")

# ── 1. Opération git en cours (merge/rebase/cherry-pick/revert) → legit sur branche protégée ───────
if [ -f "$GIT_DIR/MERGE_HEAD" ] || [ -f "$GIT_DIR/CHERRY_PICK_HEAD" ] || [ -f "$GIT_DIR/REVERT_HEAD" ] \
   || [ -d "$GIT_DIR/rebase-merge" ] || [ -d "$GIT_DIR/rebase-apply" ]; then
  emit_open "Opération git en cours (merge/rebase/cherry-pick)"
fi

# ── 2. Branche courante (HEAD détachée → fail-open) ────────────────────────────────────────────────
BRANCH=$(git symbolic-ref --short -q HEAD 2>/dev/null || echo "")
[ -z "$BRANCH" ] && emit_open "HEAD détachée (aucune branche courante)"

# ── 3. Ensemble des branches protégées (env override, sinon défaut) ────────────────────────────────
PROTECTED_RAW="${RELAY_PROTECTED_BRANCHES:-main develop master}"
PROTECTED_RAW="${PROTECTED_RAW//,/ }"   # virgules → espaces
IS_PROTECTED=false
for pb in $PROTECTED_RAW; do
  [ "$BRANCH" = "$pb" ] && IS_PROTECTED=true && break
done

# ── 4. Sortie ─────────────────────────────────────────────────────────────────────────────────────
if [ "$IS_PROTECTED" = "false" ]; then
  if [ "$JSON_MODE" = "true" ]; then
    echo "{ \"project\": \"$PROJECT_NAME\", \"date\": \"$TODAY\", \"applicable\": true, \"branch\": \"$BRANCH\", \"protected\": false, \"clean\": true }"
  else
    echo "[RELAY] ✅ Branche « $BRANCH » — commit autorisé (hors branches protégées : $PROTECTED_RAW)."
  fi
  exit 0
fi

# Branche protégée → finding.
if [ "$JSON_MODE" = "true" ]; then
  clean=$([ "$WARN" = "true" ] && echo true || echo false)
  echo "{ \"project\": \"$PROJECT_NAME\", \"date\": \"$TODAY\", \"applicable\": true, \"branch\": \"$BRANCH\", \"protected\": true, \"clean\": $clean }"
  [ "$WARN" = "true" ] && exit 0 || exit 1
fi

echo ""
echo "══════════════════════════════════════════════════════════════════"
echo "  RELAY Branch Guard (R2) — $PROJECT_NAME — $TODAY"
echo "══════════════════════════════════════════════════════════════════"
echo ""
echo "[RELAY] ❌ Commit direct sur la branche protégée « $BRANCH »."
echo "        Modèle GitFlow : main=prod / develop=intégration ne reçoivent que des merges."
echo ""
echo "        → travailler sur une branche dédiée :"
echo "            git checkout -b feature/<module>   (nouveau module / feature)"
echo "            git checkout -b fix/<bug>          (correctif non urgent)"
echo "            git checkout -b hotfix/<bug>       (correctif prod urgent, depuis main)"
echo "          puis merger : git checkout $BRANCH && git merge --no-ff <branche>"
echo ""
echo "        (branches protégées : $PROTECTED_RAW — override via RELAY_PROTECTED_BRANCHES)"
echo "══════════════════════════════════════════════════════════════════"

if [ "$WARN" = "true" ]; then
  echo ""
  echo "(--warn : signal-only — n'altère pas l'exit code)"
  exit 0
fi
exit 1
