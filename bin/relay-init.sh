#!/usr/bin/env bash
# relay-init.sh v3.0 — BOOTSTRAP RELAY dans un NOUVEAU projet (dérivé de relay-init v2.1)
# Repo canonique : engine/ (moteur portable) + templates/ (graines d'instance) + VERSION.
#
# Ce que fait le script, dans l'ordre :
#   1. Copie le MOTEUR : engine/scripts/* → docs/scripts/ , engine/rules/* → docs/rules/
#   2. Génère les fichiers d'INSTANCE depuis templates/ avec substitution des {{PLACEHOLDER}}
#      (jamais d'écrasement d'un fichier d'instance déjà présent).
#   3. Écrit docs/.relay-version (VERSION + URL source canonique + PROJECT=).
#   4. Installe le hook pre-commit RELAY (si dépôt git).
#
# Usage (lancé DEPUIS la racine du projet cible) :
#   /chemin/vers/relay/bin/relay-init.sh \
#     --project-name NAME --stack STACK --lang LANG --domain DOMAIN \
#     --actors a1,a2,admin --llm claude-code|gpt|gemini|generic \
#     [--canonical-url URL]   # URL/chemin canonique inscrit dans .relay-version (défaut = racine du repo canonique)

set -euo pipefail

PROJECT_NAME="MonProjet"
STACK="[à remplir]"
LANG="[à remplir]"
DOMAIN="[à remplir]"
ACTORS="acteur1,acteur2,admin"
LLM="claude-code"
CANONICAL_URL=""
TODAY=$(date +%Y-%m-%d)

for arg in "$@"; do
  case "$arg" in
    --project-name=*) PROJECT_NAME="${arg#--project-name=}" ;;
    --stack=*)        STACK="${arg#--stack=}" ;;
    --lang=*)         LANG="${arg#--lang=}" ;;
    --domain=*)       DOMAIN="${arg#--domain=}" ;;
    --actors=*)       ACTORS="${arg#--actors=}" ;;
    --llm=*)          LLM="${arg#--llm=}" ;;
    --canonical-url=*) CANONICAL_URL="${arg#--canonical-url=}" ;;
  esac
done

# ── Localisation du dépôt canonique (= parent de bin/) ───────────────────────
BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANON_ROOT="$(cd "$BIN_DIR/.." && pwd)"
ENGINE_SCRIPTS="$CANON_ROOT/engine/scripts"
ENGINE_RULES="$CANON_ROOT/engine/rules"
TEMPLATES="$CANON_ROOT/templates"
VERSION=$(grep -oE "[0-9]+\.[0-9]+\.[0-9]+" "$CANON_ROOT/VERSION" 2>/dev/null | head -1 || echo "0.0.0")
[ -z "$CANONICAL_URL" ] && CANONICAL_URL="$CANON_ROOT"

for d in "$ENGINE_SCRIPTS" "$ENGINE_RULES" "$TEMPLATES"; do
  [ -d "$d" ] || { echo "[RELAY-INIT] ❌ Dossier canonique manquant : $d"; exit 1; }
done

# ── Nom du fichier d'instructions LLM selon le moteur cible ──────────────────
case "$LLM" in
  claude-code) INSTR_FILE="CLAUDE.md"  ; INSTR_LABEL="Claude Code (CLAUDE.md)" ;;
  gpt)         INSTR_FILE="SYSTEM.md"  ; INSTR_LABEL="GPT / ChatGPT (SYSTEM.md)" ;;
  gemini)      INSTR_FILE="GEMINI.md"  ; INSTR_LABEL="Gemini (GEMINI.md)" ;;
  *)           INSTR_FILE="RELAY_INSTRUCTIONS.md" ; INSTR_LABEL="Generic LLM (RELAY_INSTRUCTIONS.md)" ;;
esac

# ── Liste d'acteurs (pour templates) ─────────────────────────────────────────
IFS=',' read -ra ACTOR_LIST <<< "$ACTORS"
ACTORS_PIPE=$(printf "%s / " "${ACTOR_LIST[@]}" | sed 's/ \/ $//')
ACTORS_DNA_LIST=$(for a in "${ACTOR_LIST[@]}"; do echo "- **$a** : [décrire le rôle terrain de $a]"; done)

echo "[RELAY-INIT] RELAY v$VERSION → projet : $PROJECT_NAME"
echo "[RELAY-INIT] Stack : $STACK | Domaine : $DOMAIN | LLM : $INSTR_LABEL"
echo "[RELAY-INIT] Acteurs : $ACTORS_PIPE"
echo "[RELAY-INIT] Canonique : $CANONICAL_URL"
echo ""

mkdir -p docs/scripts docs/context docs/rules

# ── 1. Copie du MOTEUR ────────────────────────────────────────────────────────
cp "$ENGINE_SCRIPTS"/*.sh docs/scripts/
# relay-update.sh (bin/) est aussi déposé dans docs/scripts/ pour que le projet puisse
# lancer `./docs/scripts/relay-update.sh` sans connaître le chemin du canonique.
[ -f "$CANON_ROOT/bin/relay-update.sh" ] && cp "$CANON_ROOT/bin/relay-update.sh" docs/scripts/relay-update.sh
chmod +x docs/scripts/*.sh 2>/dev/null || true
cp "$ENGINE_RULES"/*.md docs/rules/
echo "[RELAY-INIT] ✅ Moteur copié : docs/scripts/ ($(ls "$ENGINE_SCRIPTS" | wc -l | tr -d ' ') scripts + relay-update.sh) + docs/rules/ (règles RELAY)"

# ── 2. Substitution des placeholders (helper) ────────────────────────────────
# Rend un template vers une cible en remplaçant {{...}}. NE FAIT RIEN si la cible existe déjà.
render() {
  local tmpl="$1" dest="$2"
  if [ -f "$dest" ]; then
    echo "[RELAY-INIT] ⏭️  $dest existe déjà — NON écrasé (fichier d'instance)"
    return 0
  fi
  [ -f "$tmpl" ] || { echo "[RELAY-INIT] ⚠️  Template manquant : $tmpl"; return 0; }
  mkdir -p "$(dirname "$dest")"
  # Substitution via awk (gère le multi-ligne ACTORS_DNA_LIST en variable d'env)
  ACTORS_DNA_LIST="$ACTORS_DNA_LIST" \
  PROJECT_NAME="$PROJECT_NAME" STACK="$STACK" DOMAIN="$DOMAIN" ACTORS_PIPE="$ACTORS_PIPE" \
  INSTR_FILE="$INSTR_FILE" INSTR_LABEL="$INSTR_LABEL" TODAY="$TODAY" \
  awk '
    {
      gsub(/\{\{PROJECT_NAME\}\}/, ENVIRON["PROJECT_NAME"])
      gsub(/\{\{STACK\}\}/,        ENVIRON["STACK"])
      gsub(/\{\{DOMAIN\}\}/,       ENVIRON["DOMAIN"])
      gsub(/\{\{ACTORS_PIPE\}\}/,  ENVIRON["ACTORS_PIPE"])
      gsub(/\{\{INSTR_FILE\}\}/,   ENVIRON["INSTR_FILE"])
      gsub(/\{\{INSTR_LABEL\}\}/,  ENVIRON["INSTR_LABEL"])
      gsub(/\{\{TODAY\}\}/,        ENVIRON["TODAY"])
      if ($0 ~ /\{\{ACTORS_DNA_LIST\}\}/) { print ENVIRON["ACTORS_DNA_LIST"]; next }
      print
    }
  ' "$tmpl" > "$dest"
  echo "[RELAY-INIT] ✅ $dest généré"
}

render "$TEMPLATES/NEXT_SESSION.md"                    "NEXT_SESSION.md"
render "$TEMPLATES/INSTRUCTIONS.md"                    "$INSTR_FILE"
render "$TEMPLATES/docs/context/STATE.md"             "docs/context/STATE.md"
render "$TEMPLATES/docs/context/SESSIONS_LOG.md"      "docs/context/SESSIONS_LOG.md"
render "$TEMPLATES/docs/context/SESSIONS_ARCHIVE.md"  "docs/context/SESSIONS_ARCHIVE.md"
render "$TEMPLATES/docs/context/DECISIONS.md"         "docs/context/DECISIONS.md"
render "$TEMPLATES/docs/context/RELAY_PROJECT_DNA.md" "docs/context/RELAY_PROJECT_DNA.md"
render "$TEMPLATES/docs/rules/KNOWN_ISSUES.md"        "docs/rules/KNOWN_ISSUES.md"
# RELAY_METRICS (compteurs) + RELAY_RULE_POOL (registre human-gated) = données d'INSTANCE :
# seedées ici UNE fois, puis propriété du projet — relay-update.sh ne les réécrit JAMAIS.
render "$TEMPLATES/docs/rules/RELAY_METRICS.md"       "docs/rules/RELAY_METRICS.md"
render "$TEMPLATES/docs/rules/RELAY_RULE_POOL.md"     "docs/rules/RELAY_RULE_POOL.md"
# SECURITY_RULES.md = checklist d'ancrage sécu (Couche 2). Donnée d'instance, chargée
# SÉLECTIVEMENT (relay-check §9b la signale quand une surface sensible est touchée).
render "$TEMPLATES/docs/rules/SECURITY_RULES.md"      "docs/rules/SECURITY_RULES.md"
# rules.conf = règles d'instance du Regression Shield. Déposé commenté → Shield inactif
# tant que le projet n'a pas déclaré ses patterns. Donnée d'instance, jamais propagée.
render "$TEMPLATES/docs/.relay/rules.conf"            "docs/.relay/rules.conf"

# Workflow CI RELAY (SEC-3, Couche 3) : gate structure (relay-check --strict) + secrets (gitleaks).
# Générique (0 donnée projet) mais déposé à un chemin d'instance → copie-si-absente directe
# (PAS via render() : le YAML GitHub Actions contient ${{ }}, à ne pas faire passer dans awk).
CI_WORKFLOW=".github/workflows/relay-ci.yml"
if [ -f "$CI_WORKFLOW" ]; then
  echo "[RELAY-INIT] ⏭️  $CI_WORKFLOW existe déjà — NON écrasé (fichier d'instance)"
elif [ -f "$TEMPLATES/.github/workflows/relay-ci.yml" ]; then
  mkdir -p .github/workflows
  cp "$TEMPLATES/.github/workflows/relay-ci.yml" "$CI_WORKFLOW"
  echo "[RELAY-INIT] ✅ $CI_WORKFLOW généré (CI : relay-check --strict + gitleaks)"
fi

# ── 3. Manifeste docs/.relay-version ─────────────────────────────────────────
{
  echo "$VERSION"
  echo "PROJECT=$PROJECT_NAME"
  echo "CANONICAL_URL=$CANONICAL_URL"
  echo "INSTALLED=$TODAY"
} > docs/.relay-version
echo "[RELAY-INIT] ✅ docs/.relay-version écrit (v$VERSION ← $CANONICAL_URL)"

# ── 4. Hook pre-commit ────────────────────────────────────────────────────────
if [ -d ".git" ]; then
  cat > .git/hooks/pre-commit << 'HOOK'
#!/usr/bin/env bash
if git diff --cached --name-only | grep -qE '\.(cs|dart|py|ts|tsx|js|go|rs)$'; then
  if ! ./docs/scripts/relay-check.sh --strict 2>/dev/null; then
    echo ""
    echo "[RELAY] ⚠️  Fichiers code stagés mais NEXT_SESSION.md invalide. Continuer ? (y/N)"
    read -r answer </dev/tty
    [ "$answer" = "y" ] || exit 1
  fi
fi
exit 0
HOOK
  chmod +x .git/hooks/pre-commit
  echo "[RELAY-INIT] ✅ .git/hooks/pre-commit installé"
else
  echo "[RELAY-INIT] ℹ️  Pas de dépôt git — hook non installé (git init puis relancer)"
fi

echo ""
echo "[RELAY-INIT] ════════════════════════════════════════"
echo "[RELAY-INIT] ✅ $PROJECT_NAME — RELAY v$VERSION initialisé"
echo "[RELAY-INIT] Prochaines étapes :"
echo "[RELAY-INIT]   1. Remplir $INSTR_FILE §2 (env) + §3 (règles) + docs/context/RELAY_PROJECT_DNA.md"
echo "[RELAY-INIT]   2. Remplacer les TASK[SETUP-*] de NEXT_SESSION.md par les vraies tâches"
echo "[RELAY-INIT]   3. ./docs/scripts/relay-brief.sh  puis  ./docs/scripts/relay-check.sh"
echo "[RELAY-INIT] ════════════════════════════════════════"
