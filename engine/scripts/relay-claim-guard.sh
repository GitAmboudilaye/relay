#!/usr/bin/env bash
# relay-claim-guard.sh v1.0 — Garde « déclaré-vs-committé » (R1bis)
# RELAY Framework — auditeur de claims, complément de relay-uncommitted-guard.sh (R1)
# Usage: ./docs/scripts/relay-claim-guard.sh [--strict] [--json] [--source=<fichier>]
#   (défaut)   : signal-only — liste les claims non committés mais exit 0 (heuristique → adoption sûre)
#   --strict   : un claim non committé → exit 1 (BLOQUE le job CI / la clôture)
#   --json     : sortie machine ({clean, finding_count, findings[]}), exit code inchangé
#   --source=F : override du fichier de claims (défaut : NEXT_SESSION.md auto-localisé)
#
# Pourquoi (RELAY-CORE-ACTIF §3, VISION §12 — R1bis) : R1 (relay-uncommitted-guard) ferme le trou
# « produit hors-git » en LOCAL, mais PAS en CI — un checkout GitHub Actions est TOUJOURS propre
# (`git status --porcelain` vide), donc R1 en CI = faux-vert. Le travail jamais committé reste local et
# n'atteint jamais GitHub. R1bis opère sur l'arbre COMMITTÉ (HEAD) : il lit ce que NEXT_SESSION déclare
# « fait/livré » et asserte via `git ls-files` que chaque chemin déclaré existe dans l'arbre committé.
# Absent = « déclaré fait, jamais committé ». Indépendant de l'arbre de travail → marche en CI, ferme
# vraiment le trou DeepSeek (cas réel observé : un répertoire déclaré « créé » mais `git ls-files` vide).
#
# Source des claims (décision user) : NEXT_SESSION.md SEUL (là où vit le smoking gun ; surface réduite =
# moins de faux-rouge ; extensible plus tard aux logs trackés).
#
# « Chemin déclaré » (décision user — coeur anti-faux-rouge) : token entre backticks, sur une ligne
# portant un marqueur DONE (✅ / ~~barré~~ / status=done / fait / livré / DONE), qui ressemble à un
# chemin (contient « / » OU une extension de code) ET n'est PAS une forme ref-git / URL / version
# (origin/…, feature/…, http…, ://, vX.Y.Z, ranges « .. »). Calibration ÉTROITE : le but est d'attraper
# un livrable jamais committé sans noyer la prose légitime (noms de branches, hashes, URLs prod).
#
# Sévérité (décision user) : --warn par DÉFAUT (signal-only). À la différence de R1 (déterministe donc
# bloquant), R1bis est HEURISTIQUE → un faux-rouge ne doit pas casser une CI légitime tant que la
# calibration n'est pas éprouvée sur N projets. --strict pour opt-in bloquant.
# FAIL-OPEN absolu sur l'OUTILLAGE (hors repo git, git absent, pas de NEXT_SESSION) → exit 0 : le garde
# ne casse jamais un environnement qui n'a pas de quoi le faire tourner. Offline-safe (lecture locale).
#
# LIMITE INHÉRENTE (documentée) : R1bis suppose que NEXT_SESSION décrit le repo où il VIT. Un chemin qui
# appartient à un AUTRE repo (ex. un NEXT_SESSION « hôte » qui pilote du travail committé ailleurs) est
# indistinguable, token par token, d'un livrable jamais committé : les deux sont « absents de l'arbre ».
# C'est exactement pourquoi (a) la CIBLE de câblage est le repo dont le NEXT_SESSION décrit SON propre
# travail (cas réel observé sur un consommateur : N claims absents = trou réel), et (b) la sévérité défaut
# --warn. Filtres anti-bruit appliqués : globs (motif ≠ livrable), .git/ (jamais suivi), gitignorés
# (non-committés PAR DESIGN), refs/branches/URLs/versions, et tokens « word/word » sans extension ni
# slash final (prose ambiguë). Un livrable = RÉPERTOIRE (slash final) OU FICHIER (extension de code).

set -uo pipefail

STRICT=false
JSON_MODE=false
SOURCE_OVERRIDE=""
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=true ;;
    --json) JSON_MODE=true ;;
    --source=*) SOURCE_OVERRIDE="${arg#--source=}" ;;
  esac
done

PROJECT_NAME=$(basename "$(pwd)")
TODAY=$(date +%Y-%m-%d 2>/dev/null || echo "")

emit_open() {
  # Sortie fail-open uniforme (toujours exit 0).
  local reason="$1"
  if [ "$JSON_MODE" = "true" ]; then
    echo "{ \"project\": \"$PROJECT_NAME\", \"date\": \"$TODAY\", \"applicable\": false, \"reason\": \"$reason\", \"clean\": true, \"finding_count\": 0, \"findings\": [] }"
  else
    echo "[RELAY] ⚠️  $reason — garde de claims inapplicable (fail-open, exit 0)."
  fi
  exit 0
}

# ── 0. Fail-open outillage : pas de git OU pas dans un repo ────────────────────────────────────────
if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  emit_open "Pas de dépôt git détecté"
fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

# ── 1. Localisation du fichier de claims (NEXT_SESSION.md) ─────────────────────────────────────────
NS=""
if [ -n "$SOURCE_OVERRIDE" ]; then
  [ -f "$SOURCE_OVERRIDE" ] && NS="$SOURCE_OVERRIDE"
else
  for cand in "${ROOT:+$ROOT/NEXT_SESSION.md}" "${ROOT:+$ROOT/docs/context/NEXT_SESSION.md}" "NEXT_SESSION.md" "docs/context/NEXT_SESSION.md"; do
    [ -n "$cand" ] && [ -f "$cand" ] && NS="$cand" && break
  done
fi
[ -z "$NS" ] && emit_open "Aucun NEXT_SESSION.md trouvé"

# ── 2. Heuristique de classification d'un token backtick en « chemin déclaré » ────────────────────
# Renvoie 0 si le token est un chemin candidat (à vérifier en git), 1 sinon (prose/ref/url/version).
CODE_EXT_RE='\.(cs|razor|dart|sh|bash|ts|tsx|js|jsx|mjs|py|rb|go|rs|java|kt|swift|php|cshtml|csproj|sln|sql|conf|cfg|ini|toml|ya?ml|json|md|markdown|txt|rst|adoc|html?|css|scss|xml|csv|proto|gradle|dockerfile)$'
is_declared_path() {
  local t="$1"
  # Vide / trop court → non.
  [ ${#t} -lt 3 ] && return 1
  # Espaces internes → ce n'est pas un chemin (prose entre backticks).
  case "$t" in *" "*) return 1 ;; esac
  # Glob (motif, pas un livrable littéral : engine/scripts/*.sh, Public/*) ; .git interne (jamais suivi).
  case "$t" in *"*"*|*"?"*|.git/*) return 1 ;; esac
  # Exclusions ref-git / URL — formes qui contiennent « / » sans être des fichiers.
  case "$t" in
    http*|*://*) return 1 ;;                            # URL
    origin/*|upstream/*|refs/*|HEAD*) return 1 ;;       # ref distante / révision
    main/*|master/*|develop/*) return 1 ;;             # branche
  esac
  # Range git (origin/main...HEAD, a..b).
  case "$t" in *".."*) return 1 ;; esac
  # Version pure (v1.2.3 / 1.24.0) — pas un chemin.
  printf '%s' "$t" | grep -qE '^v?[0-9]+\.[0-9]+(\.[0-9]+)?([-.][0-9A-Za-z]+)?$' && return 1
  # Branche feature/bugfix/etc. SANS extension de code = ref, pas un fichier livrable.
  case "$t" in
    feature/*|bugfix/*|hotfix/*|chore/*|fix/*|release/*)
      printf '%s' "$t" | grep -qiE "$CODE_EXT_RE" || return 1 ;;
  esac
  # Acceptation ÉTROITE (anti-prose) : un livrable est soit un RÉPERTOIRE (se termine par « / »),
  # soit un FICHIER (porte une extension de code). Un token « word/word » SANS extension et SANS slash
  # final est de la prose ambiguë (security/decision, relay/main, isValidé/isApprouvé) → rejet. Ce
  # resserrement n'affecte pas le cas réel (noms de fichiers avec extension + répertoire déclaré).
  case "$t" in */) return 0 ;; esac
  printf '%s' "$t" | grep -qiE "$CODE_EXT_RE" && return 0
  return 1
}

# ── 3. Le chemin déclaré existe-t-il dans l'arbre COMMITTÉ (HEAD / index) ? ────────────────────────
# 0 = présent (committé), 1 = absent. git ls-files reflète l'arbre suivi (≠ working tree non committé).
path_committed() {
  local p="${1%/}"   # retire un éventuel slash final
  case "$1" in
    */) git ls-files --error-unmatch -- "$p/*" >/dev/null 2>&1 ;;   # répertoire déclaré
    */*) git ls-files --error-unmatch -- "$p" >/dev/null 2>&1 || git ls-files --error-unmatch -- "$p/*" >/dev/null 2>&1 ;;
    *)  git ls-files --error-unmatch -- "*$p" >/dev/null 2>&1 ;;     # nom de fichier nu → match en fin de chemin
  esac
}

DONE_MARKER_RE='✅|~~|status=done|[Dd][Oo][Nn][Ee]|[Ff]ait|[Ll]ivré'

FINDINGS=()          # "chemin\tnuméro de ligne"
SEEN=" "             # dédup des chemins déjà signalés

while IFS= read -r entry; do
  lineno="${entry%%:*}"
  line="${entry#*:}"
  # La ligne doit porter un marqueur DONE.
  printf '%s' "$line" | grep -qE "$DONE_MARKER_RE" || continue
  # Extraire chaque token entre backticks de la ligne.
  rest="$line"
  while [ "$rest" != "${rest#*\`}" ]; do
    rest="${rest#*\`}"          # consomme jusqu'au backtick ouvrant
    tok="${rest%%\`*}"          # token jusqu'au backtick fermant
    rest="${rest#*\`}"          # consomme le backtick fermant pour la suite
    [ -z "$tok" ] && continue
    is_declared_path "$tok" || continue
    git check-ignore -q -- "$tok" 2>/dev/null && continue  # gitignoré = non-committé PAR DESIGN (ledger, interne)
    path_committed "$tok" && continue                 # présent dans l'arbre committé → OK
    case "$SEEN" in *" $tok "*) continue ;; esac      # déjà signalé
    SEEN="$SEEN$tok "
    FINDINGS+=("$tok	$lineno")
  done
done < <(grep -nE "$DONE_MARKER_RE" "$NS" 2>/dev/null || true)

COUNT=${#FINDINGS[@]}

# ── 4. Sortie ─────────────────────────────────────────────────────────────────────────────────────
if [ "$JSON_MODE" = "true" ]; then
  arr=""
  for f in "${FINDINGS[@]}"; do
    p="${f%%	*}"; ln="${f##*	}"
    esc=$(printf '%s' "$p" | sed 's/\\/\\\\/g; s/"/\\"/g')
    item="{ \"path\": \"$esc\", \"line\": $ln }"
    if [ -z "$arr" ]; then arr="$item"; else arr="$arr, $item"; fi
  done
  clean=$([ "$COUNT" -eq 0 ] && echo true || echo false)
  echo "{ \"project\": \"$PROJECT_NAME\", \"date\": \"$TODAY\", \"applicable\": true, \"source\": \"$NS\", \"clean\": $clean, \"finding_count\": $COUNT, \"findings\": [ $arr ] }"
  { [ "$COUNT" -gt 0 ] && [ "$STRICT" = "true" ]; } && exit 1 || exit 0
fi

if [ "$COUNT" -eq 0 ]; then
  echo "[RELAY] ✅ Claims cohérents — chaque chemin déclaré « fait » dans $(basename "$NS") existe dans l'arbre committé."
  exit 0
fi

echo ""
echo "══════════════════════════════════════════════════════════════════"
echo "  RELAY Claim Guard (R1bis) — $PROJECT_NAME — $TODAY"
echo "══════════════════════════════════════════════════════════════════"
echo ""
echo "[RELAY] ❌ $COUNT chemin(s) déclaré(s) « fait/livré » mais ABSENT(s) de l'arbre committé :"
echo "        (source : $NS — assertion git ls-files sur HEAD)"
echo ""
for f in "${FINDINGS[@]}"; do
  p="${f%%	*}"; ln="${f##*	}"
  printf '        L%-5s  %s\n' "$ln" "$p"
done
echo ""
echo "        → soit le livrable n'a jamais été committé (trou « produit hors-git »),"
echo "          soit le claim est obsolète (chemin renommé/supprimé) — committer ou corriger la ligne."
echo "══════════════════════════════════════════════════════════════════"

if [ "$STRICT" = "true" ]; then
  exit 1
fi
echo ""
echo "(défaut : signal-only — n'altère pas l'exit code ; --strict pour bloquer)"
exit 0
