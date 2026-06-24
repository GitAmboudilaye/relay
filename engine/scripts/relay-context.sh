#!/usr/bin/env bash
# relay-context.sh v1.0 — Contexte/règle pertinent pour UN chemin (noyau RELAY « actif », shift-left)
# RELAY Framework — Outil noyau, 0 dépendance harnais (cf. docs/RELAY-CORE-ACTIF.md §1.2/§1.3)
# Usage: relay-context.sh --path=<fichier> [--stdin] [--json] [--top=N] [--strict]
#
# Émet — AVANT l'écriture — la règle pertinente d'un fichier en grepant SON CONTENU (et non le
# diff stagé : c'est le rôle a posteriori de relay-check). Source de vérité = docs/.relay/rules.conf
# (MÊME fichier d'instance que relay-check ; 0 règle dans le moteur). Déclenché par CONTENU (§1.3) :
# ne signale QUE les patterns réellement présents → SILENCE si rien (token-négatif). --stdin lit le
# contenu PROPOSÉ sur stdin (le hook PreToolUse pipera l'édition à venir, --path servant au typage).
# Exit 0 (informatif) ; --strict → exit 3 si ≥1 hit de sévérité ERROR (pour un gate, jamais imposé).

set -uo pipefail

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }

PATH_ARG=""
USE_STDIN=false
JSON_MODE=false
STRICT=false
TOP=12

for arg in "$@"; do
  case "$arg" in
    --path=*)  PATH_ARG="${arg#--path=}" ;;
    --stdin)   USE_STDIN=true ;;
    --json)    JSON_MODE=true ;;
    --strict)  STRICT=true ;;
    --top=*)   TOP="${arg#--top=}" ;;
    --help|-h) usage; exit 0 ;;
    -*)        echo "[RELAY] option inconnue : $arg" >&2; exit 2 ;;
    *)         echo "[RELAY] argument positionnel inattendu : $arg (utiliser --path=)" >&2; exit 2 ;;
  esac
done

case "$TOP" in (*[!0-9]*|'') TOP=12 ;; esac

if [ -z "$PATH_ARG" ] && ! $USE_STDIN; then
  echo "[RELAY] usage : relay-context.sh --path=<fichier> [--stdin] [--json] [--top=N] [--strict]" >&2
  exit 2
fi

# ── Résolution de rules.conf (racine git → repli CWD-relatif, comme relay-check) ───────────────
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
RULES_CONF=""
for cand in "${ROOT:+$ROOT/docs/.relay/rules.conf}" "docs/.relay/rules.conf"; do
  [ -n "$cand" ] && [ -f "$cand" ] && { RULES_CONF="$cand"; break; }
done

# ── Source du contenu à scanner : stdin (contenu proposé) sinon le fichier sur disque ──────────
CONTENT=""
if $USE_STDIN; then
  CONTENT="$(cat)"                         # contenu PROPOSÉ par le hook (édition à venir)
elif [ -f "$PATH_ARG" ]; then
  CONTENT="$(cat -- "$PATH_ARG" 2>/dev/null || true)"
else
  # --path sans --stdin et fichier absent (création pure) : 0 contenu = rien à grep → silence honnête.
  CONTENT=""
fi

emit_empty() {
  if $JSON_MODE; then
    printf '{"path":"%s","rules_conf":%s,"total":0,"hits":[]}\n' \
      "$PATH_ARG" "$( [ -n "$RULES_CONF" ] && echo '"present"' || echo 'null' )"
  fi
  # mode humain : SILENCE total (aucune ligne) = contrat §1.3
  exit 0
}

# rules.conf absent → rien à émettre (un avertissement permanent = bruit ; relay-check le signale déjà à la clôture).
[ -z "$RULES_CONF" ] && emit_empty
[ -z "$CONTENT" ] && emit_empty

# ── Sections applicables selon le TYPE du fichier (--path) ─────────────────────────────────────
# Universelles : s'appliquent à tout fichier. Design : scopées par extension (comme relay-check §8).
# Format émis : « <section> <severity> ».
applicable_sections() {
  # universelles (ordre = ordre d'affichage : ERROR d'abord)
  printf '%s\n' \
    "security_forbidden ERROR" \
    "forbidden_patterns ERROR" \
    "regression_warn WARN" \
    "security_warn WARN" \
    "security_surface INFO" \
    "decision_surface INFO"
  case "$PATH_ARG" in
    *.dart)            printf '%s\n' "design_warn_flutter WARN" ;;
    *.css|*.cshtml)    printf '%s\n' "design_warn_css WARN" ;;
  esac
}

# ── Parseur d'une section de rules.conf (byte-fidèle à relay-check parse_security_section) ──────
# Remplit SEC_PAT / SEC_MSG / SEC_EXCL / SEC_EXCLPATH pour la section demandée.
SEC_PAT=(); SEC_MSG=(); SEC_EXCL=(); SEC_EXCLPATH=()
parse_section() {
  local section="$1" line in_section=0 pat rest token msg excl exclpath
  SEC_PAT=(); SEC_MSG=(); SEC_EXCL=(); SEC_EXCLPATH=()
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"                     # ltrim
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac                       # commentaire
    if [[ "$line" =~ ^\[[a-z_]+\]$ ]]; then
      [ "$line" = "[$section]" ] && in_section=1 || in_section=0
      continue
    fi
    [ "$in_section" = "1" ] || continue
    pat="${line%%' | '*}"
    msg=""; excl=""; exclpath=""
    if [[ "$line" == *' | '* ]]; then
      rest="${line#*' | '}"
      while [ -n "$rest" ]; do
        if [[ "$rest" == *' | '* ]]; then
          token="${rest%%' | '*}"; rest="${rest#*' | '}"
        else
          token="$rest"; rest=""
        fi
        case "$token" in
          msg=*)          msg="${token#msg=}" ;;
          exclude=*)      excl="${token#exclude=}" ;;
          exclude-path=*) exclpath="${token#exclude-path=}" ;;
        esac
      done
    fi
    pat="${pat%"${pat##*[![:space:]]}"}"                        # rtrim regex
    [ -z "$pat" ] && continue
    SEC_PAT+=("$pat"); SEC_MSG+=("$msg"); SEC_EXCL+=("$excl"); SEC_EXCLPATH+=("$exclpath")
  done < "$RULES_CONF"
}

# ── Collecte des hits : grep le CONTENU (≠ diff). Honore exclude= (contenu) + exclude-path= (chemin) ──
HIT_SEV=(); HIT_SEC=(); HIT_PAT=(); HIT_MSG=(); HIT_CNT=()
ERROR_HITS=0

while read -r section severity; do
  [ -z "$section" ] && continue
  parse_section "$section"
  [ "${#SEC_PAT[@]}" -eq 0 ] && continue
  for i in "${!SEC_PAT[@]}"; do
    pattern="${SEC_PAT[$i]}"; msg="${SEC_MSG[$i]}"; excl="${SEC_EXCL[$i]}"; exclpath="${SEC_EXCLPATH[$i]}"
    [ -n "$exclpath" ] && [ -n "$PATH_ARG" ] && [[ "$PATH_ARG" == *"$exclpath"* ]] && continue
    matched="$(printf '%s\n' "$CONTENT" | grep -E -e "$pattern" 2>/dev/null || true)"
    if [ -n "$excl" ] && [ -n "$matched" ]; then
      matched="$(printf '%s\n' "$matched" | grep -vE -e "$excl" 2>/dev/null || true)"
    fi
    cnt=0
    [ -n "$matched" ] && cnt=$(printf '%s\n' "$matched" | grep -c . )
    if [ "$cnt" -gt 0 ]; then
      HIT_SEV+=("$severity"); HIT_SEC+=("$section"); HIT_PAT+=("$pattern"); HIT_MSG+=("$msg"); HIT_CNT+=("$cnt")
      [ "$severity" = "ERROR" ] && ERROR_HITS=$((ERROR_HITS + 1))
    fi
  done
done <<EOF
$(applicable_sections)
EOF

TOTAL="${#HIT_SEV[@]}"
[ "$TOTAL" -eq 0 ] && emit_empty            # SILENCE si rien (§1.3)

# ── Sortie bornée (top-N ; les sections sont déjà ordonnées ERROR→INFO) ────────────────────────
if $JSON_MODE; then
  printf '{"path":"%s","rules_conf":"present","total":%d,"hits":[' "$PATH_ARG" "$TOTAL"
  first=true; shown=0
  for i in "${!HIT_SEV[@]}"; do
    [ "$shown" -ge "$TOP" ] && break
    $first || printf ','
    # échappe les guillemets/backslash des champs libres (msg, pattern) pour un JSON valide
    esc_pat="${HIT_PAT[$i]//\\/\\\\}"; esc_pat="${esc_pat//\"/\\\"}"
    esc_msg="${HIT_MSG[$i]//\\/\\\\}"; esc_msg="${esc_msg//\"/\\\"}"
    printf '{"section":"%s","severity":"%s","pattern":"%s","msg":"%s","matches":%d}' \
      "${HIT_SEC[$i]}" "${HIT_SEV[$i]}" "$esc_pat" "$esc_msg" "${HIT_CNT[$i]}"
    first=false; shown=$((shown + 1))
  done
  printf '],"truncated":%s,"error_hits":%d}\n' "$( [ "$TOTAL" -gt "$TOP" ] && echo true || echo false )" "$ERROR_HITS"
  $STRICT && [ "$ERROR_HITS" -gt 0 ] && exit 3
  exit 0
fi

echo "[RELAY] contexte « ${PATH_ARG:-<stdin>} » — $TOTAL règle(s) pertinente(s) (déclenché par contenu)"
shown=0
for i in "${!HIT_SEV[@]}"; do
  [ "$shown" -ge "$TOP" ] && break
  case "${HIT_SEV[$i]}" in
    ERROR) icon="⛔" ;;
    WARN)  icon="⚠️ " ;;
    *)     icon="ℹ️ " ;;
  esac
  printf '[RELAY]   %s %-6s %-18s %s\n' "$icon" "${HIT_SEV[$i]}" "[${HIT_SEC[$i]}]" "${HIT_MSG[$i]:-${HIT_PAT[$i]}}"
  shown=$((shown + 1))
done
[ "$TOTAL" -gt "$TOP" ] && printf '[RELAY]   … +%d autre(s) (--top=%d pour élargir)\n' "$((TOTAL - TOP))" "$TOP"
[ "$ERROR_HITS" -gt 0 ] && echo "[RELAY]   ⛔ $ERROR_HITS pattern(s) PROSCRIT(s) présent(s) — corriger AVANT d'écrire (sinon réécriture = tokens)."

$STRICT && [ "$ERROR_HITS" -gt 0 ] && exit 3
exit 0
