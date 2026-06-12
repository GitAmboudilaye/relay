#!/usr/bin/env bash
# stale-detector.sh — Détecte les tâches [assumed] non modifiées depuis N commits
# Usage: ./docs/scripts/stale-detector.sh [--sessions N] [--auto-mark]
# --sessions N : seuil (défaut 2)
# --auto-mark  : réécrire NEXT_SESSION.md avec les tâches promues [stale?]

set -uo pipefail

FILE="NEXT_SESSION.md"
THRESHOLD=2
AUTO_MARK=false

for arg in "$@"; do
  case "$arg" in
    --sessions=*) THRESHOLD="${arg#--sessions=}" ;;
    --auto-mark)  AUTO_MARK=true ;;
  esac
done

if [ ! -f "$FILE" ]; then
  echo "[STALE] ❌ $FILE introuvable" && exit 1
fi
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "[STALE] ❌ Pas un dépôt git" && exit 1
fi

echo "[STALE] Analyse des tâches [assumed] (seuil : $THRESHOLD commits)"
echo ""

# Commits qui touchent le fichier
mapfile -t COMMITS < <(git log --format="%H" -- "$FILE" 2>/dev/null | head -n "$((THRESHOLD + 2))")
COMMIT_COUNT=${#COMMITS[@]}

if [ "$COMMIT_COUNT" -lt 2 ]; then
  echo "[STALE] ℹ️  Moins de 2 commits sur $FILE — pas assez d'historique"
  exit 0
fi

# Tâches [assumed] actuelles (TASK[] lines uniquement)
mapfile -t ASSUMED_TASKS < <(grep -E "^TASK\[" "$FILE" | grep -F "[assumed]" || true)

if [ "${#ASSUMED_TASKS[@]}" -eq 0 ]; then
  echo "[STALE] ✅ Aucune tâche [assumed] dans $FILE"
  exit 0
fi

echo "[STALE] ${#ASSUMED_TASKS[@]} tâche(s) [assumed] trouvée(s)"
echo ""

STALE_IDS=()

for task_line in "${ASSUMED_TASKS[@]}"; do
  TASK_ID=$(echo "$task_line" | grep -oE "TASK\[[A-Z0-9_-]+\]" | head -1 || true)
  [ -z "$TASK_ID" ] && continue

  # Compter dans combien de commits précédents cette tâche était déjà [assumed]
  FOUND_IN_HISTORY=0
  for i in "${!COMMITS[@]}"; do
    [ "$i" -eq 0 ] && continue  # skip HEAD
    commit="${COMMITS[$i]}"
    if git show "$commit:$FILE" 2>/dev/null | grep -F "$TASK_ID" | grep -qF "[assumed]"; then
      FOUND_IN_HISTORY=$((FOUND_IN_HISTORY + 1))
    fi
  done

  if [ "$FOUND_IN_HISTORY" -ge "$((THRESHOLD - 1))" ]; then
    echo "[STALE] ⚠️  $TASK_ID → devrait être [stale?] (assumed depuis $((FOUND_IN_HISTORY + 1)) commits)"
    STALE_IDS+=("$TASK_ID")
  else
    echo "[STALE] ✅ $TASK_ID → [assumed] récent (ok)"
  fi
done

echo ""

if [ "${#STALE_IDS[@]}" -eq 0 ]; then
  echo "[STALE] ✅ Aucune tâche à promouvoir [stale?]"
  exit 0
fi

echo "[STALE] ${#STALE_IDS[@]} tâche(s) candidate(s) pour [stale?]"

if $AUTO_MARK; then
  cp "$FILE" "${FILE}.bak"
  for task_id in "${STALE_IDS[@]}"; do
    # Escape brackets pour sed
    ESCAPED=$(echo "$task_id" | sed 's/\[/\\[/g; s/\]/\\]/g')
    sed -i "s/\(TASK${ESCAPED}[^\n]*\)\[assumed\]/\1[stale?]/" "$FILE"
    echo "[STALE] ✍️  $task_id : [assumed] → [stale?]"
  done
  echo ""
  echo "[STALE] Backup : ${FILE}.bak"
  echo "[STALE] ✅ Terminé — relancer relay-check.sh pour vérifier"
else
  echo "[STALE] → Relancer avec --auto-mark pour appliquer"
fi
