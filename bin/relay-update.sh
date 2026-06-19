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

# ── 2b. Migration rules.conf (≥ v1.3.0) — externalisation des patterns interdits ─────
# Depuis v1.3.0, le moteur ne contient PLUS de patterns interdits codés en dur : ils
# vivent dans docs/.relay/rules.conf (instance). Pour ne RIEN perdre, si le projet n'a
# pas encore de rules.conf, on le seede avec l'ancienne liste codée en dur → le
# Regression Shield conserve EXACTEMENT ses patterns (zéro assouplissement silencieux).
# Idempotent : ne touche jamais un rules.conf déjà présent (fichier d'instance).
RULES_CONF="docs/.relay/rules.conf"
SEEDED_RULES=0
if [ ! -f "$RULES_CONF" ]; then
  mkdir -p "$(dirname "$RULES_CONF")"
  cat > "$RULES_CONF" <<'RULESCONF'
# RELAY — règles d'instance du Regression Shield
# Seedé par relay-update (migration v1.3.0) à partir des patterns auparavant codés en dur
# dans le moteur. Fichier d'INSTANCE : committé, jamais écrasé par un futur relay-update.
# Format : une regex (ERE, grep -E) par ligne sous [forbidden_patterns] ; exclusion inline
# optionnelle « <regex> | exclude=<regex> » ; « # » et lignes vides ignorées.
# → Élaguez/adaptez cette liste à VOTRE stack ; ajoutez vos propres anti-patterns.
[forbidden_patterns]
\.Result\b              | exclude=\.Result[[:space:]]*=
\.Wait()
\.Include\(.*\)\.Select
\.Select.*\.Include
localhost:7285
localhost:5000
isValidé
isApprouvé
logout.*GET
RULESCONF
  SEEDED_RULES=1
fi

# ── 2c. Migration Design System (≥ v1.4.0) — externalisation des règles DS ───────────
# Depuis v1.4.0, le Design System Shield (§8 du moteur) ne contient PLUS de patterns/
# messages/chemins codés en dur : ils vivent dans rules.conf, sections [design_warn_*].
# Idempotent AU NIVEAU SECTION : on AJOUTE les sections DS si elles sont absentes, même
# si rules.conf existe déjà (cas d'un projet migré en v1.3.0 → ne RIEN perdre = on doit
# l'enrichir, pas le recréer). Si déjà présentes → on n'y touche pas (données d'instance).
SEEDED_DS=0
if [ -f "$RULES_CONF" ] && ! grep -qE '^\[design_warn_flutter\]' "$RULES_CONF" 2>/dev/null; then
  cat >> "$RULES_CONF" <<'DSCONF'

# ── Design System Shield (seedé par relay-update v1.4.0) ─────────────────────
# Anciens patterns/messages/exclusions auparavant codés en dur dans le moteur (§8).
# Format : <regex> | msg=<texte de remédiation> | exclude-path=<fragment-de-chemin>
# Sévérité = WARNING (ne bloque pas le commit). Section absente → shield DS inactif.
# → Adaptez à VOTRE design system (ou supprimez la section si non pertinent).
[design_warn_flutter]
Colors\.green\b   | msg=utiliser AppColors.* à la place | exclude-path=core/theme/
Colors\.blue\b    | msg=utiliser AppColors.* à la place | exclude-path=core/theme/
Colors\.red\b     | msg=utiliser AppColors.* à la place | exclude-path=core/theme/
Colors\.grey\b    | msg=utiliser AppColors.* à la place | exclude-path=core/theme/
Colors\.orange\b  | msg=utiliser AppColors.* à la place | exclude-path=core/theme/
Colors\.purple\b  | msg=utiliser AppColors.* à la place | exclude-path=core/theme/
Colors\.yellow\b  | msg=utiliser AppColors.* à la place | exclude-path=core/theme/
Colors\.black\b   | msg=utiliser AppColors.* à la place | exclude-path=core/theme/

[design_warn_css]
(color|background|border)[^:]*:[^;]*#[0-9a-fA-F]{3,6}   | msg=couleur hex hardcodée — utiliser var(--ac-*) | exclude-path=design-system
DSCONF
  SEEDED_DS=1
fi

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
if [ "$SEEDED_RULES" -eq 1 ]; then
  echo "[RELAY-UPDATE] 🌱 Migration v1.3.0 : $RULES_CONF seedé avec les anciens patterns codés en dur"
  echo "[RELAY-UPDATE]    (Regression Shield préservé à l'identique — relisez/adaptez cette liste à votre stack)."
fi
if [ "$SEEDED_DS" -eq 1 ]; then
  echo "[RELAY-UPDATE] 🌱 Migration v1.4.0 : sections [design_warn_*] ajoutées à $RULES_CONF (Design System Shield préservé à l'identique)"
  echo "[RELAY-UPDATE]    (relisez/adaptez à votre design system, ou supprimez ces sections si non pertinent)."
fi
echo "[RELAY-UPDATE] ℹ️  Aucun autre fichier d'instance touché (NEXT_SESSION.md, docs/context/*, KNOWN_ISSUES.md…)."
echo "[RELAY-UPDATE] ════════════════════════════════════════"
