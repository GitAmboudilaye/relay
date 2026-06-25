#!/usr/bin/env bash
# relay-uncommitted-guard.sh v1.0 — Garde de clôture d'état-git (R1)
# RELAY Framework — gate de clôture, pair de relay-check.sh (couche passive)
# Usage: ./docs/scripts/relay-uncommitted-guard.sh [--warn] [--json]
#   (défaut)  : arbre de travail SALE → exit 1 (BLOQUE la clôture / le job CI)
#   --warn    : signal-only — liste les fichiers mais exit 0 (adoption progressive, brownfield)
#   --json    : sortie machine ({clean, dirty_count, files[]}), exit code inchangé
#
# Pourquoi (RELAY-CORE-ACTIF §3, VISION §12 — R1) : l'examen cross-LLM DeepSeek a révélé un trou de la
# couche PASSIVE — un LLM peut déclarer une tâche « faite » en laissant le produit HORS-GIT (fichiers
# untracked jamais `git add`és). Le gate relay-check ne mord qu'au commit → rendu INERTE par omission.
# Ce garde impose la règle inverse : « `git status --porcelain` vide = condition de clôture ». Lançable
# aussi en CI → ferme le trou sans dépendre de la discipline du LLM.
#
# Portée (décision user) : porcelain LITTÉRAL — untracked + modifiés + stagés non committés déclenchent
# tous. La clôture = absolument tout committé. Les fichiers gitignorés (ex. docs/session_logs/ internes)
# sont nativement exclus par porcelain → pas de faux positif sur l'interne.
#
# Sémantique (décision user) : BLOQUANT par défaut (c'est un gate), --warn pour signal-only.
# FAIL-OPEN absolu sur l'OUTILLAGE (hors d'un repo git, git absent) → exit 0 : le garde ne doit jamais
# casser un environnement qui n'a simplement pas de quoi le faire tourner. FAIL-CLOSED sur le FINDING
# (arbre sale) → exit 1. Offline-safe (lecture locale, aucun réseau).

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

# ── 0. Fail-open outillage : pas de git OU pas dans un repo → ne jamais bloquer ────────────────────
if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ "$JSON_MODE" = "true" ]; then
    echo "{ \"project\": \"$PROJECT_NAME\", \"date\": \"$TODAY\", \"git\": false, \"clean\": true, \"dirty_count\": 0, \"files\": [] }"
  else
    echo "[RELAY] ⚠️  Pas de dépôt git détecté — garde d'état-git inapplicable (fail-open, exit 0)."
  fi
  exit 0
fi

# ── 1. État porcelain (untracked + modifiés + stagés ; gitignorés exclus nativement) ──────────────
STATUS=$(git status --porcelain 2>/dev/null || true)

if [ -z "$STATUS" ]; then
  # Arbre propre → condition de clôture remplie.
  if [ "$JSON_MODE" = "true" ]; then
    echo "{ \"project\": \"$PROJECT_NAME\", \"date\": \"$TODAY\", \"git\": true, \"clean\": true, \"dirty_count\": 0, \"files\": [] }"
  else
    echo "[RELAY] ✅ Arbre de travail propre — condition de clôture d'état-git remplie."
  fi
  exit 0
fi

# ── 2. Arbre SALE → finding ───────────────────────────────────────────────────────────────────────
DIRTY_COUNT=$(printf '%s\n' "$STATUS" | grep -c '' 2>/dev/null || echo 0)

if [ "$JSON_MODE" = "true" ]; then
  # Construit le tableau JSON des chemins (XY + chemin) ; échappe guillemets et backslashes.
  FILES_JSON=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    esc=$(printf '%s' "$line" | sed 's/\\/\\\\/g; s/"/\\"/g')
    if [ -z "$FILES_JSON" ]; then FILES_JSON="\"$esc\""; else FILES_JSON="$FILES_JSON, \"$esc\""; fi
  done <<EOF
$STATUS
EOF
  echo "{ \"project\": \"$PROJECT_NAME\", \"date\": \"$TODAY\", \"git\": true, \"clean\": false, \"dirty_count\": $DIRTY_COUNT, \"files\": [ $FILES_JSON ] }"
  [ "$WARN" = "true" ] && exit 0 || exit 1
fi

echo ""
echo "══════════════════════════════════════════════════════════════════"
echo "  RELAY Uncommitted Guard — $PROJECT_NAME — $TODAY"
echo "══════════════════════════════════════════════════════════════════"
echo ""
echo "[RELAY] ❌ Arbre de travail SALE : $DIRTY_COUNT entrée(s) non committée(s)."
echo "        La clôture exige « git status --porcelain » vide (tout committé)."
echo ""
printf '%s\n' "$STATUS" | sed 's/^/        /'
echo ""
echo "        → committe (ou stash) ces fichiers avant de déclarer la tâche faite,"
echo "          puis relance ce garde. (gitignorés déjà exclus — interne préservé.)"
echo "══════════════════════════════════════════════════════════════════"

if [ "$WARN" = "true" ]; then
  echo ""
  echo "(--warn : signal-only — n'altère pas l'exit code)"
  exit 0
fi
exit 1
