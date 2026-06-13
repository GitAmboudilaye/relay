#!/usr/bin/env bash
# relay-split.sh v1.0 — Fractionnement NEXT_SESSION.md en NEXT_SESSION/<feature>.md
# Usage: ./docs/scripts/relay-split.sh [--dry-run] [--list]
#
# Déclencher quand NEXT_SESSION.md > 150 lignes avec 5+ features actives.
# Crée un répertoire NEXT_SESSION/ avec un fichier par feature + index central.
# Le format TASK[FEATURE-*] est utilisé pour regrouper automatiquement.
#
# Après split, relay-check.sh valide NEXT_SESSION.md (index) comme avant.
# Chaque NEXT_SESSION/<feature>.md suit le même format TASK[] + niveaux MRS.

set -euo pipefail

FILE="NEXT_SESSION.md"
DIR="NEXT_SESSION"
DRY_RUN=false
LIST_ONLY=false

for arg in "$@"; do
  [ "$arg" = "--dry-run" ] && DRY_RUN=true
  [ "$arg" = "--list"    ] && LIST_ONLY=true
done

if [ ! -f "$FILE" ]; then
  echo "[RELAY-SPLIT] ❌ $FILE introuvable"
  exit 1
fi

LINES=$(wc -l < "$FILE")
echo "[RELAY-SPLIT] $FILE : $LINES lignes"

# ── Mode --list : montrer le regroupement détecté ──────────────────────────
if $LIST_ONLY; then
  echo ""
  echo "── Features détectées (préfixes TASK[]) ──"
  grep -E "^TASK\[|~~TASK\[" "$FILE" 2>/dev/null \
    | grep -oE 'TASK\[[A-Z0-9_-]+\]' \
    | sed 's/TASK\[\([A-Z0-9_]*\)-.*/\1/' \
    | sort -u \
    | while read -r prefix; do
        COUNT=$(grep -cE "TASK\[${prefix}" "$FILE" 2>/dev/null || true)
        echo "  $prefix — $COUNT tâche(s)"
      done
  echo ""
  echo "Pour fractionner : ./docs/scripts/relay-split.sh --dry-run"
  exit 0
fi

# ── Vérification seuil ────────────────────────────────────────────────────
if [ "$LINES" -le 150 ]; then
  echo "[RELAY-SPLIT] ℹ️  $LINES lignes ≤ 150 — fractionnement non nécessaire."
  echo "             Déclencher quand > 150 lignes avec 5+ features actives."
  exit 0
fi

# ── Détection des prefixes de features ────────────────────────────────────
FEATURES=$(grep -E "^TASK\[|~~TASK\[" "$FILE" 2>/dev/null \
  | grep -oE 'TASK\[[A-Z0-9_-]+\]' \
  | sed 's/TASK\[\([A-Z0-9_]*\)-.*/\1/' \
  | sort -u || true)

FEATURE_COUNT=$(echo "$FEATURES" | grep -c "." 2>/dev/null || true)
echo "[RELAY-SPLIT] $FEATURE_COUNT préfixe(s) de features détecté(s) : $(echo $FEATURES | tr '\n' ' ')"

if [ "$FEATURE_COUNT" -lt 3 ]; then
  echo "[RELAY-SPLIT] ⚠️  Moins de 3 features distinctes — fractionnement non recommandé."
  echo "             Préférer archiver les tâches ✅ dans SESSIONS_ARCHIVE.md."
  exit 0
fi

# ── Mode dry-run : afficher le plan ─────────────────────────────────────
if $DRY_RUN; then
  echo ""
  echo "── Plan de fractionnement (dry-run) ──"
  echo "  Répertoire : $DIR/"
  echo "  Fichier index : $FILE (conservé, allégé)"
  echo ""
  while IFS= read -r feature; do
    [ -z "$feature" ] && continue
    COUNT=$(grep -cE "TASK\[${feature}" "$FILE" 2>/dev/null || true)
    echo "  → $DIR/${feature,,}.md  ($COUNT tâche(s) TASK[${feature}-*])"
  done <<< "$FEATURES"
  echo ""
  echo "  Format $FILE après split :"
  echo "  > Index — pointer vers NEXT_SESSION/<feature>.md"
  echo "  > §Plan session suivante — liste compacte des tâches retenues"
  echo "  > §Retour expérience — inchangé"
  echo ""
  echo "Pour exécuter : ./docs/scripts/relay-split.sh"
  exit 0
fi

# ── Exécution : créer $DIR/ et écrire les fichiers feature ───────────────
echo ""
echo "[RELAY-SPLIT] Création de $DIR/ ..."
mkdir -p "$DIR"

while IFS= read -r feature; do
  [ -z "$feature" ] && continue
  FEATURE_FILE="$DIR/${feature,,}.md"

  {
    echo "# NEXT_SESSION/${feature,,}.md — Feature ${feature}"
    echo ""
    echo "> Extrait de NEXT_SESSION.md par relay-split.sh — $(date +%Y-%m-%d)"
    echo "> Format TASK[] identique — relay-check.sh valide uniquement NEXT_SESSION.md (index)"
    echo ""
    echo "## Tâches"
    echo ""
    # Extraire les blocs TASK[FEATURE-*] avec leurs commentaires (jusqu'à la prochaine ligne vide ou TASK)
    grep -A5 "TASK\[${feature}" "$FILE" 2>/dev/null || true
  } > "$FEATURE_FILE"

  echo "[RELAY-SPLIT] ✅ $FEATURE_FILE créé"
done <<< "$FEATURES"

echo ""
echo "[RELAY-SPLIT] ✅ Fractionnement terminé."
echo "             Prochaine étape : alléger NEXT_SESSION.md → ne garder que l'index + §Plan."
echo "             relay-check.sh continue à valider NEXT_SESSION.md (index)."
