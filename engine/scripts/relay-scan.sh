#!/usr/bin/env bash
# relay-scan.sh v1.0 — Scan ciblé projet-wide (noyau RELAY « actif », contrat de sortie structuré)
# RELAY Framework — Outil noyau, 0 dépendance harnais (cf. docs/RELAY-CORE-ACTIF.md)
# Usage: relay-scan.sh <pattern> [--replace=<new>] [--json] [--fixed] [--top=N] [--path=<glob>]
#
# Émet un résumé STRUCTURÉ et BORNÉ (« contrat RELAY ») d'où un terme apparaît dans le projet,
# classé par surface (code/markup/style/config/docs/other) + top fichiers. Avec --replace : preview
# d'impact d'un renommage — occurrences EMBARQUÉES dans un identifiant/chemin (risquées en remplacement
# aveugle) vs STANDALONE (prose, probablement sûres). Exit 0 (informatif).
# Pensé token-négatif : un résumé en amont au lieu de N greps + lecture de dumps en aval.

set -uo pipefail

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

PATTERN=""
REPLACE=""
JSON_MODE=false
FIXED=false
TOP=10
PATHSPEC=""

for arg in "$@"; do
  case "$arg" in
    --json)       JSON_MODE=true ;;
    --fixed)      FIXED=true ;;
    --replace=*)  REPLACE="${arg#--replace=}" ;;
    --top=*)      TOP="${arg#--top=}" ;;
    --path=*)     PATHSPEC="${arg#--path=}" ;;
    --help|-h)    usage; exit 0 ;;
    -*)           echo "[RELAY] option inconnue : $arg" >&2; exit 2 ;;
    *)            if [ -z "$PATTERN" ]; then PATTERN="$arg"; else echo "[RELAY] un seul pattern attendu (reçu aussi « $arg »)" >&2; exit 2; fi ;;
  esac
done

if [ -z "$PATTERN" ]; then
  echo "[RELAY] usage : relay-scan.sh <pattern> [--replace=<new>] [--json] [--fixed] [--top=N] [--path=<glob>]" >&2
  exit 2
fi
case "$TOP" in (*[!0-9]*|'') TOP=10 ;; esac

in_git=false
git rev-parse --git-dir >/dev/null 2>&1 && in_git=true

# ── Recherche d'occurrences (file:match, une ligne par occurrence) ─────────────
# git grep = fichiers suivis seulement (respecte .gitignore, agnostique) ; sinon repli grep -r.
file_occ_search() {
  if $in_git; then
    if $FIXED; then
      git grep -oF -e "$PATTERN" -- "${PATHSPEC:-.}" 2>/dev/null
    else
      git grep -oE -e "$PATTERN" -- "${PATHSPEC:-.}" 2>/dev/null
    fi
  else
    local ex=(--exclude-dir=.git --exclude-dir=node_modules --exclude-dir=obj --exclude-dir=bin)
    if $FIXED; then
      grep -roF "${ex[@]}" -e "$PATTERN" "${PATHSPEC:-.}" 2>/dev/null
    else
      grep -roE "${ex[@]}" -e "$PATTERN" "${PATHSPEC:-.}" 2>/dev/null
    fi
  fi
}

OCC="$(file_occ_search || true)"           # lignes « file:match »
TOTAL=0
[ -n "$OCC" ] && TOTAL=$(printf '%s\n' "$OCC" | grep -c . )

if [ "$TOTAL" -eq 0 ]; then
  if $JSON_MODE; then
    printf '{"pattern":"%s","total":0,"files":0,"surfaces":{},"top":[]}\n' "$PATTERN"
  else
    echo "[RELAY] scan « $PATTERN » — 0 occurrence (fichiers suivis)."
  fi
  exit 0
fi

# Comptes par fichier : « <count> <file> »
PERFILE="$(printf '%s\n' "$OCC" | sed 's/:.*//' | sort | uniq -c | sort -rn)"
FILES=$(printf '%s\n' "$PERFILE" | grep -c . )

classify() {
  case "$1" in
    *.cs|*.dart|*.js|*.ts|*.jsx|*.tsx|*.java|*.py|*.go|*.rb|*.php|*.kt|*.swift|*.c|*.h|*.cpp|*.sh) echo code ;;
    *.cshtml|*.razor|*.html|*.htm|*.xml|*.xaml|*.vue|*.svg) echo markup ;;
    *.css|*.scss|*.sass|*.less) echo style ;;
    *.json|*.yml|*.yaml|*.toml|*.conf|*.ini|*.csproj|*.props|*.targets|*.gradle|*.config) echo config ;;
    *.md|*.txt|*.rst) echo docs ;;
    *) echo other ;;
  esac
}

s_code_o=0;   s_code_f=0
s_markup_o=0; s_markup_f=0
s_style_o=0;  s_style_f=0
s_config_o=0; s_config_f=0
s_docs_o=0;   s_docs_f=0
s_other_o=0;  s_other_f=0

while read -r cnt file; do
  [ -z "$cnt" ] && continue
  case "$(classify "$file")" in
    code)   s_code_o=$((s_code_o+cnt));     s_code_f=$((s_code_f+1)) ;;
    markup) s_markup_o=$((s_markup_o+cnt)); s_markup_f=$((s_markup_f+1)) ;;
    style)  s_style_o=$((s_style_o+cnt));   s_style_f=$((s_style_f+1)) ;;
    config) s_config_o=$((s_config_o+cnt)); s_config_f=$((s_config_f+1)) ;;
    docs)   s_docs_o=$((s_docs_o+cnt));     s_docs_f=$((s_docs_f+1)) ;;
    *)      s_other_o=$((s_other_o+cnt));   s_other_f=$((s_other_f+1)) ;;
  esac
done <<EOF
$PERFILE
EOF

# ── Preview de renommage (heuristique d'embarquement) ─────────────────────────
EMBEDDED=0; STANDALONE=0
if [ -n "$REPLACE" ] && ! $FIXED; then
  emb_search() {
    if $in_git; then
      git grep -hoE -e "[A-Za-z0-9_.]${PATTERN}|${PATTERN}[A-Za-z0-9_.]" -- "${PATHSPEC:-.}" 2>/dev/null
    else
      grep -rhoE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=obj --exclude-dir=bin \
        -e "[A-Za-z0-9_.]${PATTERN}|${PATTERN}[A-Za-z0-9_.]" "${PATHSPEC:-.}" 2>/dev/null
    fi
  }
  EMB_RAW="$(emb_search || true)"
  [ -n "$EMB_RAW" ] && EMBEDDED=$(printf '%s\n' "$EMB_RAW" | grep -c . )
  STANDALONE=$((TOTAL-EMBEDDED))
  [ "$STANDALONE" -lt 0 ] && STANDALONE=0
fi

# ── Sortie ────────────────────────────────────────────────────────────────────
TOPLIST="$(printf '%s\n' "$PERFILE" | head -n "$TOP")"

if $JSON_MODE; then
  printf '{"pattern":"%s","total":%d,"files":%d,' "$PATTERN" "$TOTAL" "$FILES"
  printf '"surfaces":{"code":[%d,%d],"markup":[%d,%d],"style":[%d,%d],"config":[%d,%d],"docs":[%d,%d],"other":[%d,%d]},' \
    "$s_code_o" "$s_code_f" "$s_markup_o" "$s_markup_f" "$s_style_o" "$s_style_f" \
    "$s_config_o" "$s_config_f" "$s_docs_o" "$s_docs_f" "$s_other_o" "$s_other_f"
  if [ -n "$REPLACE" ]; then
    printf '"replace":{"to":"%s","embedded":%d,"standalone":%d},' "$REPLACE" "$EMBEDDED" "$STANDALONE"
  fi
  printf '"top":['
  first=true
  while read -r cnt file; do
    [ -z "$cnt" ] && continue
    $first || printf ','
    printf '[%d,"%s"]' "$cnt" "$file"
    first=false
  done <<EOF
$TOPLIST
EOF
  printf ']}\n'
  exit 0
fi

echo "[RELAY] scan « $PATTERN » — $TOTAL occurrence(s) dans $FILES fichier(s) suivi(s)"
echo "[RELAY] par surface (occ / fichiers) :"
[ "$s_code_o"   -gt 0 ] && printf '[RELAY]   %-8s %5d / %d\n' "code"   "$s_code_o"   "$s_code_f"
[ "$s_markup_o" -gt 0 ] && printf '[RELAY]   %-8s %5d / %d\n' "markup" "$s_markup_o" "$s_markup_f"
[ "$s_style_o"  -gt 0 ] && printf '[RELAY]   %-8s %5d / %d\n' "style"  "$s_style_o"  "$s_style_f"
[ "$s_config_o" -gt 0 ] && printf '[RELAY]   %-8s %5d / %d\n' "config" "$s_config_o" "$s_config_f"
[ "$s_docs_o"   -gt 0 ] && printf '[RELAY]   %-8s %5d / %d\n' "docs"   "$s_docs_o"   "$s_docs_f"
[ "$s_other_o"  -gt 0 ] && printf '[RELAY]   %-8s %5d / %d\n' "other"  "$s_other_o"  "$s_other_f"

echo "[RELAY] top $TOP fichiers :"
while read -r cnt file; do
  [ -z "$cnt" ] && continue
  printf '[RELAY]   %5d  %s\n' "$cnt" "$file"
done <<EOF
$TOPLIST
EOF

if [ -n "$REPLACE" ]; then
  if $FIXED; then
    echo "[RELAY] renommage → « $REPLACE » : preview d'embarquement indisponible en --fixed (nécessite le mode regex)."
  else
    echo "[RELAY] renommage « $PATTERN » → « $REPLACE » (heuristique) :"
    printf '[RELAY]   %5d  EMBARQUÉES dans un identifiant/chemin (namespace, fichier, URL) → risquées en remplacement aveugle\n' "$EMBEDDED"
    printf '[RELAY]   %5d  STANDALONE (prose) → probablement sûres\n' "$STANDALONE"
    echo "[RELAY]   ⚠️ vérifier les embarquées une par une ; un sed/perl global confond les deux (cf. perl rename + cascade DS)."
  fi
fi

exit 0
