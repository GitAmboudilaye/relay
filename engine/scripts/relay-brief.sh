#!/usr/bin/env bash
# relay-brief.sh v1.0 — Senior Brief : contexte projet en 10 lignes, indépendant de CLAUDE.md
# RELAY Framework — Pilier 7
# Usage: ./docs/scripts/relay-brief.sh [--verbose]
#
# Lit : RELAY_PROJECT_DNA.md + SESSIONS_LOG.md + RELAY_METRICS.md
# Produit : 10 lignes lisibles par n'importe quel LLM en < 30 secondes

set -uo pipefail

VERBOSE=false
for arg in "$@"; do
  case "$arg" in
    --verbose) VERBOSE=true ;;
  esac
done

DNA="docs/context/RELAY_PROJECT_DNA.md"
LOG="docs/context/SESSIONS_LOG.md"
METRICS="docs/rules/RELAY_METRICS.md"
NS="NEXT_SESSION.md"
CHECK_SCRIPT="docs/scripts/relay-check.sh"

if [ ! -f "$DNA" ]; then
  echo "[relay-brief] ❌ $DNA introuvable — lancer relay-init.sh d'abord"
  exit 1
fi

# ── Extraction champs DNA ────────────────────────────────────────────────────

# Nom du projet depuis première ligne **Nom** de §Identité
PROJECT_LINE=$(grep -A3 "Identité du projet" "$DNA" 2>/dev/null \
  | grep '^\*\*' | head -1 | sed 's/\*\*\([^*]*\)\*\*.*/\1/' | sed 's/ est une solution.*//' \
  | tr -d '\r' | cut -c1-60 || echo "[projet]")
[ -z "$PROJECT_LINE" ] && PROJECT_LINE=$(basename "$(pwd)")

# Stack depuis la section §Identité uniquement (avant §Connaissance terrain)
IDENTITY_SECTION=$(awk '/## § Identité/{p=1} /## § Connaissance/{p=0} p' "$DNA" 2>/dev/null)
STACK=$(echo "$IDENTITY_SECTION" | grep -i "Stack\s*:" | head -1 \
  | sed 's/.*Stack\s*:\s*//' | sed 's/\s*|.*//' | sed 's/\*\*//g;s/`//g' | cut -c1-60 || echo "")
# Fallback: collecter les techno keywords dans §Identité uniquement
[ -z "$STACK" ] && STACK=$(echo "$IDENTITY_SECTION" \
  | grep -oE "ASP\.NET[^|,.<)]*|Flutter[^|,.<)]*|FastAPI[^|,.<)]*|Django[^|,.<)]*|Rails[^|,.<)]*" \
  | head -3 | tr '\n' ' + ' | sed 's/ + $//' | cut -c1-60 || echo "[stack non défini]")

# Acteurs (liste — une ligne par acteur avec **Acteur** : dans §Identité)
ACTORS=$(grep "^\- \*\*" "$DNA" 2>/dev/null \
  | sed 's/- \*\*\([^*]*\)\*\*.*/\1/' | tr '\n' ' / ' | sed 's/ \/ $//' \
  | cut -c1-70 || echo "[acteurs non définis]")

# Prochain cap (première ligne non-vide après le header §Prochain cap)
NEXT_CAP=$(awk '/## § Prochain cap/{found=1; next} found && /^[^#-]/ && NF{print; exit}' "$DNA" 2>/dev/null \
  | sed 's/\*\*//g;s/`//g' | sed 's/ =.*//' | cut -c1-80 || echo "[voir NEXT_SESSION.md]")

# Top règle terrain (première ligne DATA du tableau §Connaissance terrain — skip header et sep)
TOP_TERRAIN=$(awk '/§ Connaissance terrain/{t=1} t && /^\| /{print}' "$DNA" 2>/dev/null \
  | grep -v "Contexte terrain\|---|---" | head -1 \
  | awk -F'|' '{print $2}' | sed 's/^ //;s/ $//' | cut -c1-70 || echo "[voir DNA §Connaissance terrain]")

# Top invariant (première ligne DATA du tableau §Décisions invariantes — skip header et sep)
TOP_INVARIANT=$(awk '/§ Décisions invariantes/{t=1} t && /^\| /{print}' "$DNA" 2>/dev/null \
  | grep -v "Invariant\|---|Contexte\|---|---" | head -1 \
  | awk -F'|' '{gsub(/`/,"",$2); print $2}' | sed 's/^ //;s/ $//' | cut -c1-70 \
  || echo "[voir DNA §Décisions invariantes]")

# ── Extraction SESSIONS_LOG ──────────────────────────────────────────────────

LAST_SESSION="[aucune session enregistrée]"
if [ -f "$LOG" ]; then
  # Les sessions les plus récentes sont en TÊTE du fichier → head -1
  LAST_HEADER=$(grep "^## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" "$LOG" | head -1 | sed 's/^## //')
  if [ -n "$LAST_HEADER" ]; then
    # Extraire date + titre (tout ce qui est après la date)
    LAST_DATE=$(echo "$LAST_HEADER" | cut -d' ' -f1)
    LAST_TITLE=$(echo "$LAST_HEADER" | sed "s/^${LAST_DATE}[[:space:]]*—[[:space:]]*//" | cut -c1-60)
    LAST_SESSION="$LAST_DATE — $LAST_TITLE"
  fi
fi

# ── Extraction RELAY_METRICS ─────────────────────────────────────────────────

SESSIONS_COUNT="?"
FEATURES_AVOIDED="?"
REGRESSIONS="?"
if [ -f "$METRICS" ]; then
  SESSIONS_COUNT=$(grep "Sessions totales" "$METRICS" | grep -oE "[0-9]+" | head -1 || echo "?")
  FEATURES_AVOIDED=$(grep "Features déjà implémentées" "$METRICS" | grep -oE "[0-9]+" | head -1 || echo "?")
  REGRESSIONS=$(grep "Régressions majeures" "$METRICS" | grep -oE "[0-9]+" | head -1 || echo "?")
fi

# ── Extraction plan NEXT_SESSION ─────────────────────────────────────────────

NEXT_TASKS="[voir NEXT_SESSION.md §Plan]"
if [ -f "$NS" ]; then
  NEXT_TASKS=$(grep "TASK\[" "$NS" | grep "status=pending.*owner=session" \
    | head -2 | awk -F'] ' '{print $1"]"}' | tr '\n' ' ' | sed 's/TASK\[//g;s/\]/ /g' | cut -c1-60 \
    || echo "[voir NEXT_SESSION.md §Plan]")
fi

# ── Health Score ─────────────────────────────────────────────────────────────

HEALTH="[lancer relay-check.sh --score-only]"
if [ -f "$CHECK_SCRIPT" ]; then
  RAW_HEALTH=$("$CHECK_SCRIPT" --score-only 2>/dev/null || echo "?")
  # Extraire la ligne contenant le score (ex: "[RELAY] ── Health Score : 86/100 🟢 Sain ──")
  HEALTH=$(echo "$RAW_HEALTH" | grep -oE "[0-9]+/100[^|]*" | head -1 \
    || echo "$RAW_HEALTH" | grep "Health Score" | head -1 \
    || echo "$RAW_HEALTH" | head -1)
fi

TODAY=$(date +%Y-%m-%d)
PROJECT_NAME=$(basename "$(pwd)")

# ── Sortie Brief ─────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════════════════"
echo "  RELAY Senior Brief — $PROJECT_NAME — $TODAY"
echo "══════════════════════════════════════════════════════════════════"
echo " [1] Projet  : $PROJECT_LINE"
echo " [2] Stack   : $STACK"
echo " [3] Acteurs : $ACTORS"
echo " [4] Métriques RELAY : Sessions=$SESSIONS_COUNT | Features évitées=$FEATURES_AVOIDED | Régressions=$REGRESSIONS"
echo " [5] Dernière session : $LAST_SESSION"
echo " [6] Prochaines tâches : $NEXT_TASKS"
echo " [7] Cap projet : $NEXT_CAP"
echo " [8] Terrain  : $TOP_TERRAIN"
echo " [9] Invariant #1 : $TOP_INVARIANT"
echo "[10] Health Score : $HEALTH"
echo "══════════════════════════════════════════════════════════════════"
echo ""
echo "  Lire ensuite : NEXT_SESSION.md → CLAUDE.md → docs/rules/RELAY_PROTOCOL.md"
echo ""

if [ "$VERBOSE" = "true" ]; then
  echo "── Sources ──────────────────────────────────────────────────────"
  echo "  DNA      : $DNA"
  echo "  Log      : $LOG"
  echo "  Métriques: $METRICS"
  echo "  Plan     : $NS"
  echo ""
fi
