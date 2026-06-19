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

# ── 0. Arguments (AVANT le garde projet : --help/--check doivent marcher partout) ─
#   --check : dry-run en LECTURE SEULE — localise le canonique, compare les versions et,
#             si retard, affiche les entrées CHANGELOG entre les deux. N'écrit AUCUN
#             fichier d'instance, sort 0. Scriptable, offline-safe (la détection distante
#             vit ICI, jamais dans relay-check : chemin de commit rapide + 2G terrain).
CHECK_ONLY=false
ASSUME_YES=false   # T6-3 : bypass du prompt accept/décline (CI/hook/pipeline)
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=true ;;
    -y|--yes|--non-interactive) ASSUME_YES=true ;;
    -h|--help)
      echo "Usage: relay-update.sh [--check] [--yes|--non-interactive]"
      echo "  (sans option)        : propage le moteur canonique dans ce projet (écrit)."
      echo "                         Si une mise à jour est dispo et qu'on est en terminal (TTY),"
      echo "                         affiche le changelog et demande confirmation [o/N]."
      echo "  --check              : dry-run lecture seule — affiche la mise à jour dispo + le changelog."
      echo "  --yes, -y,           : applique sans demander (pour CI/hooks/pipelines). Implicite aussi"
      echo "  --non-interactive      quand l'entrée n'est pas un terminal (auto-détection [ -t 0 ])."
      exit 0 ;;
    *) echo "[RELAY-UPDATE] ⚠️  option inconnue : $arg (ignorée)" ;;
  esac
done

VERSION_FILE="docs/.relay-version"
[ -f "$VERSION_FILE" ] || { echo "[RELAY-UPDATE] ❌ $VERSION_FILE introuvable — lancer depuis la racine d'un projet initialisé RELAY"; exit 1; }

OLD_VERSION=$(grep -oE "[0-9]+\.[0-9]+\.[0-9]+" "$VERSION_FILE" 2>/dev/null | head -1 || echo "0.0.0")
CANONICAL_URL=$(grep -E "^CANONICAL_URL=" "$VERSION_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true)
PROJECT_NAME=$(grep -E "^PROJECT=" "$VERSION_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true)

# ── Helpers de version & changelog (utilisés par --check) ─────────────────────
# Comparaison sémantique X.Y.Z purement numérique (même tri que compute_skew de relay-check).
ver_gt() {  # ver_gt A B → vrai (0) ssi A > B
  [ "$1" = "$2" ] && return 1
  local lower
  lower=$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)
  [ "$lower" = "$2" ]   # B est la plus basse → A > B
}

print_changelog_section() {  # fichier, version → imprime le bloc "## [version] …"
  awk -v v="$2" '
    $0 ~ "^## \\[" v "\\]" { inblk=1; print; next }
    inblk && /^## \[/ { exit }
    inblk { print }
  ' "$1"
}

print_changelog_delta() {  # fichier, from, to → imprime les sections from < v <= to
  local file="$1" from="$2" to="$3" v shown=0
  [ -f "$file" ] || { echo "  (CHANGELOG.md absent du canonique — pas de détail des améliorations)"; return 0; }
  while read -r v; do
    if ver_gt "$v" "$from" && ! ver_gt "$v" "$to"; then
      print_changelog_section "$file" "$v"
      echo ""
      shown=1
    fi
  done < <(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$file" \
            | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
            | sort -t. -k1,1n -k2,2n -k3,3n -r)
  [ "$shown" -eq 0 ] && echo "  (aucune entrée de changelog entre v$from et v$to)"
  return 0
}

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

# ── 1b. Mode --check : dry-run LECTURE SEULE (ne copie rien, n'écrit pas .relay-version) ─
if $CHECK_ONLY; then
  echo ""
  echo "[RELAY-UPDATE] ════════════════════════════════════════"
  if [ "$OLD_VERSION" = "$NEW_VERSION" ]; then
    echo "[RELAY-UPDATE] ✅ À jour — moteur v$OLD_VERSION = canonique v$NEW_VERSION (rien à faire)."
  elif ver_gt "$NEW_VERSION" "$OLD_VERSION"; then
    echo "[RELAY-UPDATE] ⬆️  Mise à jour disponible : v$OLD_VERSION → v$NEW_VERSION"
    echo "[RELAY-UPDATE] ── Améliorations apportées (CHANGELOG) ──"
    print_changelog_delta "$CANON_ROOT/CHANGELOG.md" "$OLD_VERSION" "$NEW_VERSION"
    echo "[RELAY-UPDATE] ▶ Pour appliquer : relancer SANS --check."
  else
    echo "[RELAY-UPDATE] ℹ️  Moteur local v$OLD_VERSION en avance sur le canonique v$NEW_VERSION (rien à faire)."
  fi
  echo "[RELAY-UPDATE] (dry-run — aucun fichier modifié)"
  echo "[RELAY-UPDATE] ════════════════════════════════════════"
  exit 0
fi

# ── 1b2. Prompt accept/décline (T6-3) — run normal, AVANT toute écriture ───────
# Décision user (2026-06-18, escalade §3) : DÉFAUT TTY interactif + BYPASS CI.
# On réutilise print_changelog_delta (déjà écrit pour --check) pour montrer les
# améliorations AVANT d'appliquer, puis on attend [o/N]. Placé AVANT le self-update
# §1c → AUCUN fichier (pas même relay-update.sh lui-même) n'est touché sans « oui ».
#   • Sauté si pas de mise à jour (OLD == NEW, ou local en avance) : rien à confirmer.
#   • Sauté en non-interactif : --yes/--non-interactive OU pas de TTY ([ ! -t 0 ] :
#     hook/pipeline/CI) → application automatique, jamais bloquante.
#   • Idempotent à travers le re-exec du self-update : la confirmation est propagée
#     en stage 2 via RELAY_UPDATE_CONFIRMED=1 → JAMAIS de double prompt.
CONFIRMED_FOR_REEXEC="${RELAY_UPDATE_CONFIRMED:-0}"
if [ "$CONFIRMED_FOR_REEXEC" != "1" ] && ver_gt "$NEW_VERSION" "$OLD_VERSION"; then
  echo ""
  echo "[RELAY-UPDATE] ⬆️  Mise à jour disponible : v$OLD_VERSION → v$NEW_VERSION"
  echo "[RELAY-UPDATE] ── Améliorations apportées (CHANGELOG) ──"
  print_changelog_delta "$CANON_ROOT/CHANGELOG.md" "$OLD_VERSION" "$NEW_VERSION"
  if $ASSUME_YES; then
    echo "[RELAY-UPDATE] ✔ --yes / non-interactif demandé : application sans confirmation."
  elif [ ! -t 0 ]; then
    echo "[RELAY-UPDATE] ✔ Entrée non interactive (pas de TTY) : application automatique (CI/hook)."
  else
    printf "[RELAY-UPDATE] Appliquer cette mise à jour ? [o/N] "
    read -r _reply || _reply=""   # EOF (Ctrl-D) sous set -e → traité comme « non »
    case "$_reply" in
      o|O|oui|OUI|y|Y|yes|YES) echo "[RELAY-UPDATE] ▶ Application…" ;;
      *) echo "[RELAY-UPDATE] ✖ Mise à jour refusée — aucun fichier modifié. (relancez quand vous voulez)"; exit 0 ;;
    esac
  fi
  CONFIRMED_FOR_REEXEC=1
fi

# ── 1c. Self-update bootstrapping (§1b) — stage 1 → re-exec stage 2 ────────────
# relay-update.sh vit dans bin/ (canonique) et docs/scripts/ (consommateur, déposé
# par relay-init). La boucle de copie (§2) ne propage QUE engine/scripts/*.sh →
# relay-update ne se met PAS à jour lui-même. Sans ce correctif, un consommateur
# lance son ANCIEN docs/scripts/relay-update.sh : il copie bien le moteur récent,
# mais exécute son ancienne logique de migration (rules.conf non seedé, etc.).
# Correctif (décision user 2026-06-18 : « self-update stage 1 → re-exec stage 2 ») :
# stage 1 copie le nouveau relay-update SUR le script courant, puis re-exec stage 2
# qui rejoue la migration AVEC la logique à jour → correct en UN seul run.
#   • Sauté en --check (déjà sorti plus haut — lecture seule).
#   • Jamais quand on tourne DEPUIS le canonique (bin/) : on n'écrase pas la source.
#   • Idempotent : si le script courant == canonique (cmp -s) → rien (pas de boucle).
#   • Garde anti-boucle : RELAY_SELFUPDATE_STAGE2=1 sur le re-exec → un seul saut.
# Ce bloc est un compound command unique : bash l'a entièrement parsé avant de
# l'exécuter, donc réécrire $0 puis exec immédiatement est sûr (rien n'est relu
# depuis le fichier modifié après le exec qui remplace le process).
RUNNING_SCRIPT="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
CANON_UPDATE="$CANON_ROOT/bin/relay-update.sh"
if [ "${RELAY_SELFUPDATE_STAGE2:-0}" != "1" ] \
   && [ -f "$CANON_UPDATE" ] \
   && [ "$RUNNING_SCRIPT" != "$CANON_UPDATE" ] \
   && ! cmp -s "$CANON_UPDATE" "$RUNNING_SCRIPT"; then
  echo "[RELAY-UPDATE] 🔄 Self-update : relay-update.sh est obsolète → copie de la version"
  echo "[RELAY-UPDATE]    canonique puis relance avec la logique de migration à jour."
  cp "$CANON_UPDATE" "$RUNNING_SCRIPT"
  chmod +x "$RUNNING_SCRIPT" 2>/dev/null || true
  # T6-3 : propager le consentement déjà obtenu (§1b2) → stage 2 ne re-demande pas.
  RELAY_SELFUPDATE_STAGE2=1 RELAY_UPDATE_CONFIRMED="$CONFIRMED_FOR_REEXEC" exec "$RUNNING_SCRIPT" "$@"
fi

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

# ── 2d. Migration Security Shield (≥ v1.8.0) — gate déterministe sécu ────────────────
# Depuis v1.8.0, le Security Shield (§9 du moteur) lit ses patterns dans rules.conf,
# sections [security_forbidden] (ERREUR/bloque) et [security_warn] (WARNING). Idempotent
# AU NIVEAU SECTION : on AJOUTE les sections si absentes (projet init avant v1.8.0 → ne
# RIEN perdre = enrichir, pas recréer). Si déjà présentes → on n'y touche pas (instance).
SEEDED_SEC=0
if [ -f "$RULES_CONF" ] && ! grep -qE '^\[security_forbidden\]' "$RULES_CONF" 2>/dev/null; then
  cat >> "$RULES_CONF" <<'SECCONF'

# ── Security Shield (seedé par relay-update v1.8.0) ──────────────────────────
# Patterns de sécurité dangereux dans le diff stagé (code ET config). Deux sections :
#   [security_forbidden] = ERREUR (bloque le commit) ; [security_warn] = WARNING.
# Format : <regex> | msg=<remédiation> | exclude=<regex contenu> | exclude-path=<fragment>
# LUCIDITÉ : gate commit/CI, PAS un IDS/WAF runtime — ne remplace pas un pentest.
[security_forbidden]
-----BEGIN ([A-Z]+ )?PRIVATE KEY-----   | msg=clé privée en clair commitée — révoquer + déplacer vers un secret store
AKIA[0-9A-Z]{16}                        | msg=clé d'accès AWS en clair — révoquer immédiatement + secret store
# Per-stack (décommenter selon VOTRE stack) :
# password\s*=\s*["'][^"'$]{6,}["']                      | msg=mot de passe codé en dur — var d'env/secret store | exclude=(getenv|process\.env|Environment\.|GetValue)
# (SELECT|INSERT|UPDATE|DELETE)\b.*"\s*\+                 | msg=SQL concaténé (injection) — requête paramétrée
# pickle\.loads                                          | msg=désérialisation pickle non sûre (RCE)
# dangerouslySetInnerHTML                                | msg=injection HTML (XSS) — assainir l'entrée

[security_warn]
\b(MD5|md5|Md5|SHA1|sha1|Sha1)\b                         | msg=hash faible — SHA-256+/bcrypt/argon2 pour un secret | exclude=(checksum|etag|cache.?key|content.?hash)
(api[_-]?key|secret|token|passwd)\s*[:=]\s*["'][^"']{8,}["']   | msg=secret potentiel en clair — variable d'env ? | exclude=(getenv|process\.env|Environment\.|example|placeholder|xxxx|changeme|your[_-])
[?&](id|user_?id|account_?id)=                           | msg=identifiant en query string — vérifier l'autorisation (risque IDOR)
SECCONF
  SEEDED_SEC=1
fi

# ── 2e. Migration CI RELAY (≥ v1.9.0) — workflow GitHub Actions (SEC-3, Couche 3) ────
# Depuis v1.9.0, relay-init dépose .github/workflows/relay-ci.yml (gate structure
# relay-check --strict + secrets gitleaks). Un projet initialisé AVANT v1.9.0 n'a pas
# ce workflow → on le seede ici depuis le template canonique. Idempotent : ne touche
# JAMAIS un workflow déjà présent (fichier d'instance que le projet a pu personnaliser).
# Source = templates/ (pas engine/) : c'est un fichier d'instance, pas un fichier moteur.
CI_WORKFLOW=".github/workflows/relay-ci.yml"
CI_TEMPLATE="$CANON_ROOT/templates/.github/workflows/relay-ci.yml"
SEEDED_CI=0
if [ ! -f "$CI_WORKFLOW" ] && [ -f "$CI_TEMPLATE" ]; then
  mkdir -p .github/workflows
  cp "$CI_TEMPLATE" "$CI_WORKFLOW"
  SEEDED_CI=1
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
if [ "$SEEDED_SEC" -eq 1 ]; then
  echo "[RELAY-UPDATE] 🌱 Migration v1.8.0 : sections [security_*] ajoutées à $RULES_CONF (Security Shield activé — patterns universels)"
  echo "[RELAY-UPDATE]    (relisez/adaptez à votre stack ; décommentez les patterns per-stack pertinents). Gate commit/CI, pas un pentest."
fi
if [ "$SEEDED_CI" -eq 1 ]; then
  echo "[RELAY-UPDATE] 🌱 Migration v1.9.0 : $CI_WORKFLOW déposé (CI : relay-check --strict + gitleaks — SEC-3, Couche 3)"
  echo "[RELAY-UPDATE]    (fichier d'instance : adaptez-le ; gitleaks-action nécessite GITLEAKS_LICENSE pour une organisation)."
fi
echo "[RELAY-UPDATE] ℹ️  Aucun autre fichier d'instance touché (NEXT_SESSION.md, docs/context/*, KNOWN_ISSUES.md…)."
echo "[RELAY-UPDATE] ════════════════════════════════════════"
