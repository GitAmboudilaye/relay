#!/usr/bin/env bash
# relay-stats.sh v1.0 — Métriques automatiques depuis git log
# RELAY Framework — Outil complémentaire
# Usage: ./docs/scripts/relay-stats.sh [--json] [--weeks=N]
#
# Produit :
#   - Vélocité : commits par semaine
#   - Sessions par feature (groupe par type de commit)
#   - Ratio effort : S/M/L depuis les tâches done dans NEXT_SESSION.md + SESSIONS_ARCHIVE.md

set -uo pipefail

JSON_MODE=false
WEEKS=8
for arg in "$@"; do
  case "$arg" in
    --json) JSON_MODE=true ;;
    --weeks=*) WEEKS="${arg#--weeks=}" ;;
  esac
done

TODAY=$(date +%Y-%m-%d)
PROJECT_NAME=$(basename "$(pwd)")

# ── Vélocité ─────────────────────────────────────────────────────────────────

# Total commits (hors merges)
TOTAL_COMMITS=$(git log --no-merges --oneline 2>/dev/null | wc -l | tr -d ' ')

# Commits sur les N dernières semaines
SINCE_DATE=$(date -d "$WEEKS weeks ago" +%Y-%m-%d 2>/dev/null \
  || date -v-"${WEEKS}w" +%Y-%m-%d 2>/dev/null \
  || echo "2026-01-01")
RECENT_COMMITS=$(git log --no-merges --oneline --since="$SINCE_DATE" 2>/dev/null | wc -l | tr -d ' ')
VELOCITY=$(( RECENT_COMMITS / (WEEKS > 0 ? WEEKS : 1) ))

# Première date de commit
FIRST_COMMIT_DATE=$(git log --no-merges --format="%ci" 2>/dev/null | tail -1 | cut -d' ' -f1 || echo "?")

# ── Sessions par feature ──────────────────────────────────────────────────────

# Compter les types de commits (feat/fix/docs/refactor)
FEAT_COUNT=$(git log --no-merges --format="%s" 2>/dev/null | grep -cE '^feat(\(|:)' || echo 0)
FIX_COUNT=$(git log --no-merges --format="%s" 2>/dev/null | grep -cE '^fix(\(|:)' || echo 0)
DOCS_COUNT=$(git log --no-merges --format="%s" 2>/dev/null | grep -cE '^docs(\(|:)' || echo 0)
REFACTOR_COUNT=$(git log --no-merges --format="%s" 2>/dev/null | grep -cE '^refactor(\(|:)' || echo 0)

# Top scopes (feat(X) + fix(X))
TOP_SCOPES=$(git log --no-merges --format="%s" 2>/dev/null \
  | grep -oE '\(([^)]+)\)' | tr -d '()' \
  | sort | uniq -c | sort -rn | head -5 || echo "")

# ── Effort TASK depuis NEXT_SESSION + SESSIONS_ARCHIVE ───────────────────────

TASKS_DONE_S=0; TASKS_DONE_M=0; TASKS_DONE_L=0
TASKS_PENDING_S=0; TASKS_PENDING_M=0; TASKS_PENDING_L=0

for file in NEXT_SESSION.md docs/context/SESSIONS_ARCHIVE.md; do
  [ -f "$file" ] || continue
  while IFS= read -r line; do
    if echo "$line" | grep -q "status=done"; then
      effort=$(echo "$line" | grep -oE 'effort=[SML]' | cut -d= -f2)
      case "$effort" in
        S) TASKS_DONE_S=$((TASKS_DONE_S+1)) ;;
        M) TASKS_DONE_M=$((TASKS_DONE_M+1)) ;;
        L) TASKS_DONE_L=$((TASKS_DONE_L+1)) ;;
      esac
    elif echo "$line" | grep -q "status=pending"; then
      effort=$(echo "$line" | grep -oE 'effort=[SML]' | cut -d= -f2)
      case "$effort" in
        S) TASKS_PENDING_S=$((TASKS_PENDING_S+1)) ;;
        M) TASKS_PENDING_M=$((TASKS_PENDING_M+1)) ;;
        L) TASKS_PENDING_L=$((TASKS_PENDING_L+1)) ;;
      esac
    fi
  done < "$file"
done

TASKS_DONE_TOTAL=$((TASKS_DONE_S + TASKS_DONE_M + TASKS_DONE_L))
TASKS_PENDING_TOTAL=$((TASKS_PENDING_S + TASKS_PENDING_M + TASKS_PENDING_L))

# ── (ratio calculé depuis les variables déjà définies ci-dessus) ─────────────

# ── Health Score courant ──────────────────────────────────────────────────────

HEALTH="[lancer relay-check.sh]"
if [ -f "docs/scripts/relay-check.sh" ]; then
  HEALTH=$(./docs/scripts/relay-check.sh --score-only 2>/dev/null \
    | grep -oE "[0-9]+/100[^|]*" | head -1 \
    || ./docs/scripts/relay-check.sh --score-only 2>/dev/null | head -1 \
    || echo "?")
fi

# ── Output ────────────────────────────────────────────────────────────────────

if [ "$JSON_MODE" = "true" ]; then
  echo "{"
  echo "  \"project\": \"$PROJECT_NAME\","
  echo "  \"date\": \"$TODAY\","
  echo "  \"velocity\": {"
  echo "    \"total_commits\": $TOTAL_COMMITS,"
  echo "    \"recent_commits_${WEEKS}w\": $RECENT_COMMITS,"
  echo "    \"commits_per_week\": $VELOCITY,"
  echo "    \"first_commit\": \"$FIRST_COMMIT_DATE\""
  echo "  },"
  echo "  \"commit_types\": {\"feat\": $FEAT_COUNT, \"fix\": $FIX_COUNT, \"docs\": $DOCS_COUNT, \"refactor\": $REFACTOR_COUNT},"
  echo "  \"tasks\": {"
  echo "    \"done\": {\"S\": $TASKS_DONE_S, \"M\": $TASKS_DONE_M, \"L\": $TASKS_DONE_L, \"total\": $TASKS_DONE_TOTAL},"
  echo "    \"pending\": {\"S\": $TASKS_PENDING_S, \"M\": $TASKS_PENDING_M, \"L\": $TASKS_PENDING_L, \"total\": $TASKS_PENDING_TOTAL}"
  echo "  },"
  echo "  \"health_score\": \"$HEALTH\""
  echo "}"
else
  echo ""
  echo "══════════════════════════════════════════════════════════════════"
  echo "  RELAY Stats — $PROJECT_NAME — $TODAY"
  echo "══════════════════════════════════════════════════════════════════"
  echo ""
  echo "── Vélocité (git log) ───────────────────────────────────────────"
  echo "  Premier commit  : $FIRST_COMMIT_DATE"
  echo "  Total commits   : $TOTAL_COMMITS (hors merges)"
  echo "  Derniers ${WEEKS} sem : $RECENT_COMMITS commits"
  echo "  Moyenne         : ~$VELOCITY commit(s)/semaine"
  echo ""
  echo "── Types de commits ─────────────────────────────────────────────"
  echo "  feat     : $FEAT_COUNT"
  echo "  fix      : $FIX_COUNT"
  echo "  docs     : $DOCS_COUNT"
  echo "  refactor : $REFACTOR_COUNT"
  if [ "$((FEAT_COUNT + FIX_COUNT))" -gt 0 ]; then
    echo "  ratio fix/feat : $(( FIX_COUNT * 100 / (FEAT_COUNT + FIX_COUNT) ))% de fix vs feat"
  fi
  echo ""
  echo "── Scopes les plus actifs (top 5) ──────────────────────────────"
  echo "$TOP_SCOPES" | while read -r count scope; do
    echo "  $scope : $count commit(s)"
  done
  echo ""
  echo "── Effort tâches (NEXT_SESSION.md + SESSIONS_ARCHIVE.md) ───────"
  echo "  Terminées  : $TASKS_DONE_TOTAL (S=$TASKS_DONE_S / M=$TASKS_DONE_M / L=$TASKS_DONE_L)"
  echo "  En attente : $TASKS_PENDING_TOTAL (S=$TASKS_PENDING_S / M=$TASKS_PENDING_M / L=$TASKS_PENDING_L)"
  [ $TASKS_DONE_TOTAL -gt 0 ] && \
    echo "  Poids L terminées : $(( TASKS_DONE_L * 100 / TASKS_DONE_TOTAL ))% (indicateur dette tech)"
  echo ""
  echo "── Health Score actuel ──────────────────────────────────────────"
  echo "  $HEALTH"
  echo "══════════════════════════════════════════════════════════════════"
  echo ""
fi
