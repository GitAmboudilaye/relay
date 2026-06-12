#!/usr/bin/env bash
# relay-update.sh v1.0 — PROPAGATION du moteur RELAY dans un projet consommateur.
# Cœur du chantier de portabilité : met à jour UNIQUEMENT les fichiers moteur,
# ne touche AUCUN fichier d'instance, et rafraîchit docs/.relay-version.
#
# Localisation du canonique (ordre de priorité) :
#   1. $RELAY_CANONICAL (env)                      → racine d'un repo canonique local
#   2. cache ~/.relay/canonical                    → clone/pull depuis CANONICAL_URL (docs/.relay-version)
#   3. CANONICAL_URL = chemin local existant       → utilisé directement
#   4. sinon                                        → erreur explicite
#
# Usage (DEPUIS la racine du projet consommateur) :
#   ./docs/scripts/relay-update.sh            # ou  /chemin/relay/bin/relay-update.sh
#   RELAY_CANONICAL=/home/me/projects/relay ./docs/scripts/relay-update.sh
#
# Fichiers MOTEUR propagés (et EUX SEULS) :
#   engine/scripts/* → docs/scripts/    engine/rules/{RELAY_PROTOCOL,RELAY_METRICS,RELAY_RULE_POOL}.md → docs/rules/
# Fichiers d'INSTANCE jamais touchés :
#   NEXT_SESSION.md, CLAUDE.md, docs/context/*, docs/rules/{KNOWN_ISSUES,*_ARCHITECTURE,...}.md

set -euo pipefail

VERSION_FILE="docs/.relay-version"
[ -f "$VERSION_FILE" ] || { echo "[RELAY-UPDATE] ❌ $VERSION_FILE introuvable — lancer depuis la racine d'un projet initialisé RELAY"; exit 1; }

OLD_VERSION=$(grep -oE "[0-9]+\.[0-9]+\.[0-9]+" "$VERSION_FILE" 2>/dev/null | head -1 || echo "0.0.0")
CANONICAL_URL=$(grep -E "^CANONICAL_URL=" "$VERSION_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true)
PROJECT_NAME=$(grep -E "^PROJECT=" "$VERSION_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true)

# ── 1. Localiser la racine canonique ─────────────────────────────────────────
CANON_ROOT=""
locate_canonical() {
  # (1) env explicite
  if [ -n "${RELAY_CANONICAL:-}" ] && [ -f "${RELAY_CANONICAL}/VERSION" ]; then
    CANON_ROOT="$RELAY_CANONICAL"; echo "[RELAY-UPDATE] Canonique via \$RELAY_CANONICAL : $CANON_ROOT"; return 0
  fi
  # (2) CANONICAL_URL est un chemin local déjà présent
  if [ -n "$CANONICAL_URL" ] && [ -f "${CANONICAL_URL}/VERSION" ]; then
    CANON_ROOT="$CANONICAL_URL"; echo "[RELAY-UPDATE] Canonique via chemin local : $CANON_ROOT"; return 0
  fi
  # (3) cache ~/.relay/canonical (clone/pull si URL git)
  local cache="$HOME/.relay/canonical"
  if [ -f "$cache/VERSION" ]; then
    if [ -d "$cache/.git" ] && [ -n "$CANONICAL_URL" ]; then
      echo "[RELAY-UPDATE] Pull du cache canonique ($cache)…"
      git -C "$cache" pull --ff-only >/dev/null 2>&1 || echo "[RELAY-UPDATE] ⚠️  pull échoué — usage du cache existant"
    fi
    CANON_ROOT="$cache"; echo "[RELAY-UPDATE] Canonique via cache : $CANON_ROOT"; return 0
  fi
  # clone si URL git fournie
  if [ -n "$CANONICAL_URL" ] && echo "$CANONICAL_URL" | grep -qE '^(https?://|git@|ssh://)'; then
    echo "[RELAY-UPDATE] Clone du canonique depuis $CANONICAL_URL → $cache"
    mkdir -p "$HOME/.relay"
    if git clone --depth 1 "$CANONICAL_URL" "$cache" >/dev/null 2>&1 && [ -f "$cache/VERSION" ]; then
      CANON_ROOT="$cache"; return 0
    fi
  fi
  return 1
}

if ! locate_canonical; then
  echo "[RELAY-UPDATE] ❌ Canonique RELAY introuvable."
  echo "[RELAY-UPDATE]    Essaye l'une de ces options :"
  echo "[RELAY-UPDATE]      • export RELAY_CANONICAL=/chemin/vers/relay   (repo canonique local)"
  echo "[RELAY-UPDATE]      • renseigne CANONICAL_URL dans $VERSION_FILE   (chemin local ou URL git)"
  exit 1
fi

NEW_VERSION=$(grep -oE "[0-9]+\.[0-9]+\.[0-9]+" "$CANON_ROOT/VERSION" 2>/dev/null | head -1 || echo "0.0.0")
ENGINE_SCRIPTS="$CANON_ROOT/engine/scripts"
ENGINE_RULES="$CANON_ROOT/engine/rules"
for d in "$ENGINE_SCRIPTS" "$ENGINE_RULES"; do
  [ -d "$d" ] || { echo "[RELAY-UPDATE] ❌ Canonique incomplet : $d manquant"; exit 1; }
done

# ── 2. Copier UNIQUEMENT les fichiers moteur (avec rapport de changement) ─────
CHANGED=()
copy_engine_file() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ ! -f "$dest" ] || ! cmp -s "$src" "$dest"; then
    cp "$src" "$dest"
    CHANGED+=("$dest")
  fi
}

# Scripts moteur
for f in "$ENGINE_SCRIPTS"/*.sh; do
  copy_engine_file "$f" "docs/scripts/$(basename "$f")"
done
chmod +x docs/scripts/*.sh 2>/dev/null || true

# Règle moteur propagée = RELAY_PROTOCOL.md SEUL (§0-§7 portables ; §8 = pointeur statique).
# RELAY_METRICS.md (compteurs) et RELAY_RULE_POOL.md (registre human-gated) sont des données
# d'INSTANCE seedées par relay-init — on ne les propage JAMAIS (sinon écrasement de données projet).
# Idem KNOWN_ISSUES.md / *_ARCHITECTURE.md.
for r in RELAY_PROTOCOL.md; do
  [ -f "$ENGINE_RULES/$r" ] && copy_engine_file "$ENGINE_RULES/$r" "docs/rules/$r"
done

# ── 3. Mettre à jour docs/.relay-version (conserve PROJECT/CANONICAL_URL d'instance) ─
{
  echo "$NEW_VERSION"
  echo "PROJECT=$PROJECT_NAME"
  echo "CANONICAL_URL=$CANONICAL_URL"
  echo "UPDATED=$(date +%Y-%m-%d)"
} > "$VERSION_FILE"

# ── 4. Résumé ─────────────────────────────────────────────────────────────────
echo ""
echo "[RELAY-UPDATE] ════════════════════════════════════════"
echo "[RELAY-UPDATE] Projet : ${PROJECT_NAME:-?} | Version : $OLD_VERSION → $NEW_VERSION"
if [ "${#CHANGED[@]}" -eq 0 ]; then
  echo "[RELAY-UPDATE] ✅ Moteur déjà à jour — 0 fichier modifié"
else
  echo "[RELAY-UPDATE] ✅ ${#CHANGED[@]} fichier(s) moteur mis à jour :"
  for c in "${CHANGED[@]}"; do echo "[RELAY-UPDATE]    • $c"; done
fi
echo "[RELAY-UPDATE] ℹ️  Aucun fichier d'instance touché (NEXT_SESSION.md, docs/context/*, KNOWN_ISSUES.md…)."
echo "[RELAY-UPDATE] ════════════════════════════════════════"
