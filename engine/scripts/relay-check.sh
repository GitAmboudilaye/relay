#!/usr/bin/env bash
# relay-check.sh v3.8 — Validation structure + contenu + commits + clôture NEXT_SESSION.md
# + Security Shield (piloté par rules.conf, sections [security_forbidden] BLOQUANT / [security_warn] — v1.8.0)
# + Security Surface Trigger (ancrage sécu sélectif — section [security_surface], WARNING signal-only — v1.10.0)
# + Security Pattern Memory (auto-feed SECURITY_RULES.md : fix sécu KNOWN_ISSUES ✅ RÉSOLU sans pattern appris — v1.11.0)
# + Scope-Creep Alert (mécanise la règle 70% : somme effort des TASK[] retenables > budget → WARNING — v1.12.0)
# + Decision Trigger (trace décision archi : marqueur [decision_surface] touché sans entrée ## DEC- ajoutée — WARNING signal-only — v1.13.0)
# + Porte de reçu (v1.2.0) : `[verified-run:<hash>]` exige un reçu relay-run.sh existant (sinon ERREUR)
# + Skew check (signal-only) : alerte si moteur d'instance < canonique localisable
# + Design System Shield (piloté par rules.conf, sections [design_warn_*] — v1.4.0)
# + Branch Guard (avertissement si commit direct sur main/develop avec .cs/.dart)
# + Jauge de densité anti-inflation (Pilier 11 — signal-only, ne modifie pas le Health Score)
# Usage: ./docs/scripts/relay-check.sh [--strict] [--score-only] [--density] [--companion-repo=<path>]
# --strict              : exit 1 si erreur (pour hook pre-commit)
# --score-only          : affiche uniquement le Health Score
# --density             : affiche la jauge de densité + liste des règles dormantes (candidates consolidation)
# --companion-repo=PATH : vérifie les hash commits dans un second repo git (ex: repo Flutter)

set -euo pipefail

FILE="NEXT_SESSION.md"
STRICT=false
SCORE_ONLY=false
DENSITY_ONLY=false
COMPANION_REPO=""

for arg in "$@"; do
  [ "$arg" = "--strict" ]        && STRICT=true
  [ "$arg" = "--score-only" ]    && SCORE_ONLY=true
  [ "$arg" = "--density" ]       && DENSITY_ONLY=true
  [[ "$arg" == --companion-repo=* ]] && COMPANION_REPO="${arg#--companion-repo=}"
done

if [ ! -f "$FILE" ]; then
  echo "[RELAY] ❌ $FILE introuvable (lancer depuis la racine du projet)"
  $STRICT && exit 1 || exit 0
fi

LINES=$(wc -l < "$FILE")
ERRORS=0
WARNINGS=0

count_pattern() { grep -cE "$1" "$FILE" 2>/dev/null || true; }
has_pattern()   { grep -qE "$1" "$FILE" 2>/dev/null; }

# ── Jauge de densité (Pilier 11 — anti-inflation, signal-only) ───────────────
# Mesure l'enflure du jeu de règles versionnées vN.N. Calculée depuis les artefacts
# existants (§Retour/§Suggestion nomment déjà leur version) → zéro instrumentation nouvelle.
# N'affecte JAMAIS le Health Score 0-100 : l'enflure du ruleset est orthogonale à la
# qualité du NEXT_SESSION.md courant et ne doit pas bloquer un commit.
DENS_ARCHIVE="docs/context/SESSIONS_ARCHIVE.md"
DENS_LOG="docs/context/SESSIONS_LOG.md"
DENS_PROTO="docs/rules/RELAY_PROTOCOL.md"
DENS_POOL="docs/rules/RELAY_RULE_POOL.md"

# ── Pool anti-inflation (TASK[RELAY-ANTIINFLATION-POOL]) ─────────────────────
# Détecte une règle vN.N présente dans le RULESET ACTIF (formalisée dans le corps
# de RELAY_PROTOCOL.md §1-§8) SANS entrée `statut=promue` dans le pool. Warning
# signal-only (exit 0) : la promotion candidate→ruleset est human-gated (§7.1).
DENS_UNPROMOTED=""
compute_pool_warnings() {
  [ -f "$DENS_PROTO" ] || return 0
  [ -f "$DENS_POOL" ]  || return 0
  # Versions citées dans le RULESET ACTIF = règles formalisées du protocole (§1-§6, §8).
  # On EXCLUT (a) la section §7 (anti-inflation) qui *décrit* le mécanisme de pool, et
  # (b) toute ligne qui parle explicitement du pool/candidate/promue (méta-discussion :
  # une vN.N y est citée comme exemple, pas formalisée comme règle active). Ce qui reste
  # = une vN.N réellement formalisée comme règle ⇒ doit avoir une entrée `promue` au pool.
  local ruleset promoted v proto_active
  proto_active=$(awk '
    /^## 7\. /      { skip=1 }
    /^## 8\. /      { skip=0 }
    skip            { next }
    /candidate|promue|pool|§7\.1/ { next }   # méta-discussion du pool : citation, pas règle
    { print }
  ' "$DENS_PROTO" 2>/dev/null || true)
  ruleset=$(echo "$proto_active" | grep -oE "v[0-9]+\.[0-9]+" | sort -u || true)
  # Versions marquées promue dans le pool (ligne de table contenant `promue`)
  promoted=$(grep -E "\| *promue *\|" "$DENS_POOL" 2>/dev/null \
    | grep -oE "v[0-9]+\.[0-9]+" | sort -u || true)
  for v in $ruleset; do
    if ! echo "$promoted" | grep -qx "$v"; then
      DENS_UNPROMOTED="$DENS_UNPROMOTED $v"
    fi
  done
  DENS_UNPROMOTED=$(echo "$DENS_UNPROMOTED" | sed 's/^ *//; s/ *$//')
}

DENS_UNIVERSE_N=0; DENS_RECENT_N=0; DENS_DORMANT=""; DENS_RATIO="n/a"; DENS_ICON="⚪"
compute_density() {
  [ -f "$DENS_ARCHIVE" ] || return 0
  local universe recent
  # Univers = versions vN.N citées all-time (archive + log + NEXT_SESSION + protocole)
  universe=$(cat "$DENS_ARCHIVE" "$DENS_LOG" "$FILE" "$DENS_PROTO" 2>/dev/null \
    | grep -oE "v[0-9]+\.[0-9]+" | sort -u || true)
  # Fenêtre récente = NEXT_SESSION + 10 premiers blocs §Retour/§Suggestion de l'archive (newest-first)
  # (|| true : grep sans match renvoie 1 → ne pas faire planter le script sous set -e + pipefail)
  local boundary
  boundary=$(grep -nE "^#{2,3} .*(Retour|Suggestion)" "$DENS_ARCHIVE" 2>/dev/null | sed -n '10p' | cut -d: -f1 || true)
  boundary=${boundary:-140}
  recent=$( { cat "$FILE"; head -n "$boundary" "$DENS_ARCHIVE"; } 2>/dev/null \
    | grep -oE "v[0-9]+\.[0-9]+" | sort -u || true)
  DENS_UNIVERSE_N=$(echo "$universe" | grep -c . || true)
  DENS_RECENT_N=$(echo "$recent"  | grep -c . || true)
  DENS_DORMANT=$(comm -23 <(echo "$universe") <(echo "$recent") | tr '\n' ' ' | sed 's/ *$//')
  if [ "$DENS_RECENT_N" -gt 0 ]; then
    # ratio = univers / récent (×100 pour l'arithmétique entière bash)
    local r=$(( DENS_UNIVERSE_N * 100 / DENS_RECENT_N ))
    DENS_RATIO=$(printf '%d.%02d' $((r/100)) $((r%100)))
    if   [ "$r" -le 130 ]; then DENS_ICON="🟢"
    elif [ "$r" -le 180 ]; then DENS_ICON="🟡"
    else                        DENS_ICON="🔴"; fi
  fi
}

# Mode standalone --density : rapport détaillé + sortie
if $DENSITY_ONLY; then
  compute_density
  compute_pool_warnings
  echo "[RELAY] ── Densité du jeu de règles (Pilier 11 — anti-inflation) ──"
  echo "[RELAY]    univers=$DENS_UNIVERSE_N règles vN.N | référencées ~10 sessions=$DENS_RECENT_N | ratio=$DENS_RATIO $DENS_ICON"
  echo "[RELAY]    Dormantes (candidates à consolidation — décision humaine, jamais auto) :"
  echo "[RELAY]      $DENS_DORMANT"
  echo "[RELAY]    ⚠️  Une dormante peut être un garde-fou silencieux (toujours respecté → à GARDER)"
  echo "[RELAY]        OU une règle situationnelle oubliée (→ candidate au retrait). Classer avant d'agir."
  echo "[RELAY] ── Pool candidat (§7.1 — promotion human-gated sur 2ᵉ déclencheur) ──"
  if [ -n "$DENS_UNPROMOTED" ]; then
    echo "[RELAY] ⚠️  Règle(s) du ruleset actif sans entrée \`promue\` dans le pool : $DENS_UNPROMOTED"
    echo "[RELAY]        → confirmer 2ᵉ déclencheur + validation humaine, ou retirer du ruleset (RELAY_RULE_POOL.md)."
  else
    echo "[RELAY] ✅ Toute règle vN.N du ruleset actif a une entrée \`promue\` dans le pool."
  fi
  exit 0
fi

# ── Score components ────────────────────────────────────────────────────────
SCORE_SECTIONS=0   # max 35
SCORE_SIZE=0       # max 15
SCORE_TRUST=0      # max 35
SCORE_COMMITS=0    # max 15

check_section() {
  local pattern="$1" label="$2"
  if has_pattern "$pattern"; then
    $SCORE_ONLY || echo "[RELAY] ✅ Section présente : $label"
    SCORE_SECTIONS=$((SCORE_SECTIONS + 9))
  else
    $SCORE_ONLY || echo "[RELAY] ❌ Section manquante : $label"
    ERRORS=$((ERRORS + 1))
  fi
}

check_content() {
  local pattern="$1" label="$2"
  if has_pattern "$pattern"; then
    $SCORE_ONLY || echo "[RELAY] ✅ Contenu vérifié : $label"
  else
    $SCORE_ONLY || echo "[RELAY] ⚠️  Contenu manquant : $label"
    WARNINGS=$((WARNINGS + 1))
  fi
}

$SCORE_ONLY || echo "[RELAY] Validation $FILE ($LINES lignes)"
[ -n "$COMPANION_REPO" ] && { $SCORE_ONLY || echo "[RELAY] Companion repo : $COMPANION_REPO"; }
$SCORE_ONLY || echo ""

# ── 1. Sections obligatoires (35 pts = 4×9, cap à 35) ────────────────────
$SCORE_ONLY || echo "── Sections ──"
check_section "^## .*Plan session suivante"  '"## ⚡ Plan session suivante"'
check_section "^### Ce qui reste"            '"### Ce qui reste ❌"'
check_section "^## Retour expérience"        '"## Retour expérience"'
check_section "^## Règles absolues rappel"   '"## Règles absolues rappel"'
[ "$SCORE_SECTIONS" -gt 35 ] && SCORE_SECTIONS=35

# ── 2. Contenu minimal ──────────────────────────────────────────────────────
$SCORE_ONLY || echo ""
$SCORE_ONLY || echo "── Contenu ──"
check_content "^TASK\[" \
  "au moins un TASK[] dans §Ce qui reste ❌"
check_content "TASK\[.*\].*pending.*owner=session" \
  "au moins une tâche owner=session status=pending"
check_content "\[verified(-build|-run)?\]|\[assumed\]|\[stale\?\]|\[external\]" \
  "niveaux de confiance MRS présents"

# Budget tracker — vérifier présence dans §Plan
if has_pattern "BUDGET SESSION"; then
  BUDGET_PTS=$(grep -E "BUDGET SESSION" "$FILE" 2>/dev/null | head -1 || true)
  $SCORE_ONLY || echo "[RELAY] ✅ Budget tracker : $BUDGET_PTS"
else
  $SCORE_ONLY || echo "[RELAY] ⚠️  Pas de BUDGET SESSION dans §Plan session suivante (recommandé)"
  WARNINGS=$((WARNINGS + 1))
fi

# ── 3. Taille (15 pts) ──────────────────────────────────────────────────────
$SCORE_ONLY || echo ""
$SCORE_ONLY || echo "── Taille ──"
if [ "$LINES" -gt 200 ]; then
  $SCORE_ONLY || echo "[RELAY] ❌ Taille : $LINES lignes (> 200 — archiver dans SESSIONS_ARCHIVE.md)"
  ERRORS=$((ERRORS + 1))
  SCORE_SIZE=0
elif [ "$LINES" -gt 150 ]; then
  $SCORE_ONLY || echo "[RELAY] ⚠️  Taille : $LINES lignes (> 150 — envisager relay-split.sh)"
  WARNINGS=$((WARNINGS + 1))
  SCORE_SIZE=8
elif [ "$LINES" -gt 130 ]; then
  $SCORE_ONLY || echo "[RELAY] ℹ️  Taille : $LINES lignes (130-150 — zone de vigilance)"
  SCORE_SIZE=12
else
  $SCORE_ONLY || echo "[RELAY] ✅ Taille : $LINES lignes (≤ 130 — optimal)"
  SCORE_SIZE=15
fi

# ── 3b. Ancrage métier — BLOQUANT si mots-clés métier détectés sans ANCRAGE: ─
# Mots-clés qui indiquent une logique métier (acteur terrain, permissions, workflow)
BUSINESS_KEYWORDS="ANCRAGE:|acteur=|permissions=|conforme=|cas_limite="
META_KEYWORDS="acteur|superviseur|agent\b|permissions|valide|approuve|workflow|rôle|autorisation"

SESSION_TASKS=$(grep -E "^TASK\[" "$FILE" | grep "owner=session" | grep "status=pending" || true)
if [ -n "$SESSION_TASKS" ]; then
  TASK_COUNT=$(echo "$SESSION_TASKS" | grep -c "." 2>/dev/null || true)
  ANCHORED=0
  BUSINESS_MISSING=0

  while IFS= read -r task_line; do
    [ -z "$task_line" ] && continue
    TASK_ID=$(echo "$task_line" | grep -oE "TASK\[[A-Z0-9_-]+\]" | head -1 || true)
    [ -z "$TASK_ID" ] && continue
    ESCAPED=$(echo "$TASK_ID" | sed 's/\[/\\[/g; s/\]/\\]/g')

    # Récupérer le corps de la tâche (15 lignes après l'ID)
    TASK_BODY=$(awk "/^${ESCAPED}/{found=1; count=0} found && count<=15{print; count++} count>15{exit}" "$FILE" 2>/dev/null || true)

    HAS_ANCHOR=$(echo "$TASK_BODY" | grep -cE "ANCRAGE:" 2>/dev/null || true)
    HAS_BUSINESS=$(echo "$TASK_BODY" | grep -ciE "$META_KEYWORDS" 2>/dev/null || true)
    # Tâche bloquée = depends=[X] non vide → ancrage peut attendre
    IS_BLOCKED=$(echo "$task_line" | grep -oE "depends=\[[^]]+\]" | grep -v "depends=\[\]" | head -1 || true)

    if [ "$HAS_ANCHOR" -gt 0 ]; then
      ANCHORED=$((ANCHORED + 1))
      $SCORE_ONLY || echo "[RELAY] ✅ Ancrage : $TASK_ID — ANCRAGE: présent"
    elif [ "$HAS_BUSINESS" -gt 0 ] && [ -z "$IS_BLOCKED" ]; then
      # Tâche métier débloquée sans ancrage = ERREUR BLOQUANTE
      $SCORE_ONLY || echo "[RELAY] ❌ ANCRAGE: obligatoire — $TASK_ID (tâche débloquée, mots-clés métier détectés)"
      ERRORS=$((ERRORS + 1))
      BUSINESS_MISSING=$((BUSINESS_MISSING + 1))
    elif [ "$HAS_BUSINESS" -gt 0 ] && [ -n "$IS_BLOCKED" ]; then
      # Tâche métier bloquée → warning (sera traité quand débloquée)
      $SCORE_ONLY || echo "[RELAY] ⚠️  Ancrage : $TASK_ID bloquée ($IS_BLOCKED) — ANCRAGE: à ajouter avant déblocage"
      WARNINGS=$((WARNINGS + 1))
    else
      # Tâche technique sans ancrage = warning seulement
      $SCORE_ONLY || echo "[RELAY] ⚠️  Ancrage : $TASK_ID — technique, ANCRAGE: si logique métier présente"
      WARNINGS=$((WARNINGS + 1))
    fi
  done <<< "$SESSION_TASKS"

  if [ "$BUSINESS_MISSING" -gt 0 ]; then
    $SCORE_ONLY || echo "[RELAY]    → $BUSINESS_MISSING tâche(s) métier sans ANCRAGE: — ajouter avant de committer"
  elif [ "$TASK_COUNT" -gt 0 ]; then
    $SCORE_ONLY || echo "[RELAY]    Ancrage : $ANCHORED/$TASK_COUNT tâche(s) ancrées"
  fi
fi

# ── 3c. ESCALADE_METIER — bloquant si question posée sans réponse humaine ────
# Pilier 9 : LLM s'arrête sur nuance métier → ESCALADE_METIER: documente la question
# → REPONSE_HUMAINE: documente la réponse — le commit est bloqué jusqu'à réponse
if [ -n "$SESSION_TASKS" ]; then
  ESCALADE_ERRORS=0

  while IFS= read -r task_line; do
    [ -z "$task_line" ] && continue
    TASK_ID=$(echo "$task_line" | grep -oE "TASK\[[A-Z0-9_-]+\]" | head -1 || true)
    [ -z "$TASK_ID" ] && continue
    ESCAPED=$(echo "$TASK_ID" | sed 's/\[/\\[/g; s/\]/\\]/g')
    # TASK[RELAY-ESCALADE-PARSER] : borner le corps de la tâche au PROCHAIN en-tête de
    # tâche (`TASK[`, éventuellement préfixé `~~`/`**`) ou EOF, PLUTÔT qu'à un compteur
    # fixe de 15 lignes (la fenêtre fixe débordait sur la tâche suivante et captait son
    # ESCALADE_METIER → faux négatif d'attribution). Borne dynamique.
    TASK_BODY=$(awk "
      # Ligne d'en-tête de la tâche cible → démarre la capture (et la marque pour ne pas
      # la confondre avec une borne de fin au tour suivant).
      !found && /^(~~)?(\\*\\*)?${ESCAPED}/ { found=1; print; next }
      # Une fois démarré, le corps se ferme au prochain en-tête de tâche (TASK[),
      # OU à un séparateur de section (---) / titre (## …) — bornes naturelles de fin.
      found && /^(~~)?(\\*\\*)?TASK\\[/ { exit }
      found && /^---[[:space:]]*\$/     { exit }
      found && /^## /                   { exit }
      found { print }
    " "$FILE" 2>/dev/null || true)

    # Regex tolérante au colon décalé (TASK[RELAY-ESCALADE-PARSER]) : accepter un court
    # texte (parenthèse de provenance) entre le mot-clé et le `:` — p.ex.
    # `# REPONSE_HUMAINE (user, 2026-06-12) : …` doit compter comme réponse présente.
    # ANTI sur-assouplissement : on ANCRE sur le marqueur `#` (les vraies lignes
    # ESCALADE/REPONSE sont `> # MOTCLÉ…:`) → la prose libre qui mentionne
    # « 0 ESCALADE_METIER » sans marqueur `#` ni `:` collé ne matche PAS.
    HAS_ESCALADE=$(echo "$TASK_BODY" | grep -cE "#[[:space:]]*ESCALADE_METIER[^:]*:" 2>/dev/null || true)
    HAS_REPONSE=$(echo "$TASK_BODY" | grep -cE "#[[:space:]]*REPONSE_HUMAINE[^:]*:" 2>/dev/null || true)

    if [ "$HAS_ESCALADE" -gt 0 ] && [ "$HAS_REPONSE" -eq 0 ]; then
      $SCORE_ONLY || echo "[RELAY] ❌ REPONSE_HUMAINE: manquante — $TASK_ID (ESCALADE_METIER sans réponse → commit bloqué)"
      ERRORS=$((ERRORS + 1))
      ESCALADE_ERRORS=$((ESCALADE_ERRORS + 1))
    elif [ "$HAS_ESCALADE" -gt 0 ] && [ "$HAS_REPONSE" -gt 0 ]; then
      $SCORE_ONLY || echo "[RELAY] ✅ Escalade : $TASK_ID — ESCALADE_METIER + REPONSE_HUMAINE documentés"
    fi
  done <<< "$SESSION_TASKS"

  if [ "$ESCALADE_ERRORS" -gt 0 ]; then
    $SCORE_ONLY || echo "[RELAY]    → $ESCALADE_ERRORS tâche(s) bloquée(s) : obtenir REPONSE_HUMAINE: avant de committer"
  fi
fi

# ── 4. Ratio confiance MRS (35 pts) ─────────────────────────────────────────
# TASK[RELAY-VERIFY-RUN] : `[verified]` est scindé en `[verified-build]` (statique)
# et `[verified-run]` (runtime/test). Les deux comptent comme « vérifié » au numérateur
# du ratio confiance ; `[verified]` legacy = alias de `[verified-run]` (rétro-compat).
TOTAL_TASKS=$(count_pattern "^TASK\[")
TASK_LINES=$(grep -E "^TASK\[" "$FILE" 2>/dev/null || true)
# Legacy exact : `[verified]` (sans suffixe -build/-run)
VERIFIED_LEGACY=$(echo "$TASK_LINES" | grep -cF "[verified]" 2>/dev/null || true)
VERIFIED_BUILD=$(echo "$TASK_LINES" | grep -cF "[verified-build]" 2>/dev/null || true)
# Compte les deux formes : `[verified-run]` nu ET `[verified-run:<hash>]` adossé à un reçu.
VERIFIED_RUN=$(echo "$TASK_LINES" | grep -cE "\[verified-run(:[a-f0-9]+)?\]" 2>/dev/null || true)
ASSUMED=$(echo  "$TASK_LINES" | grep -cF "[assumed]"  2>/dev/null || true)
STALE=$(echo   "$TASK_LINES" | grep -cF "[stale?]"   2>/dev/null || true)

TOTAL_TASKS=${TOTAL_TASKS:-0}
VERIFIED_LEGACY=${VERIFIED_LEGACY:-0}
VERIFIED_BUILD=${VERIFIED_BUILD:-0}
VERIFIED_RUN=${VERIFIED_RUN:-0}
ASSUMED=${ASSUMED:-0}
STALE=${STALE:-0}
# Numérateur confiance = tout ce qui est vérifié (legacy + build + run).
VERIFIED=$(( VERIFIED_LEGACY + VERIFIED_BUILD + VERIFIED_RUN ))

# ── 4a. Porte de reçu (TASK[RELAY-RUN-RECEIPT], v1.2.0) ──────────────────────
# `[verified-run:<hash>]` = revendication de preuve ADOSSÉE à un reçu relay-run.sh.
#   → le reçu docs/.relay/receipts/<hash>.log DOIT exister, sinon ERREUR (preuve falsifiée).
# `[verified-run]` nu (sans hash) = legacy/opt-in : toléré, warning signal-only « non adossé ».
# Rétrocompat : une instance sans aucun reçu (que des run nus) PASSE — le reçu n'est requis
# que pour les claims qui CITENT explicitement un hash.
RECEIPT_DIR="docs/.relay/receipts"
CITED_RUNS=$(echo "$TASK_LINES" | grep -oE "\[verified-run:[a-f0-9]+\]" 2>/dev/null || true)
BARE_RUNS=$(echo "$TASK_LINES" | grep -cE "\[verified-run\]" 2>/dev/null || true)
BARE_RUNS=${BARE_RUNS:-0}
if [ -n "$CITED_RUNS" ]; then
  while IFS= read -r cited; do
    [ -z "$cited" ] && continue
    rhash=$(echo "$cited" | sed -E 's/\[verified-run:([a-f0-9]+)\]/\1/')
    if [ -f "$RECEIPT_DIR/$rhash.log" ]; then
      $SCORE_ONLY || echo "[RELAY] ✅ [verified-run:$rhash] adossé à un reçu"
    else
      $SCORE_ONLY || echo "[RELAY] ❌ [verified-run:$rhash] cite un reçu INTROUVABLE ($RECEIPT_DIR/$rhash.log) — preuve falsifiée ou reçu non committé/perdu"
      ERRORS=$((ERRORS + 1))
    fi
  done <<< "$CITED_RUNS"
fi
if [ "$BARE_RUNS" -gt 0 ]; then
  $SCORE_ONLY || echo "[RELAY] ⚠️  $BARE_RUNS [verified-run] nu(s) (sans :hash) — non adossé(s) à un reçu relay-run.sh ; preuve revendiquée mais non prouvable (signal-only)"
  WARNINGS=$((WARNINGS + 1))
fi

if [ "$TOTAL_TASKS" -gt 0 ]; then
  TRUST_DENOM=$(( VERIFIED + ASSUMED + STALE ))
  if [ "$TRUST_DENOM" -gt 0 ]; then
    SCORE_TRUST=$(( (VERIFIED * 35) / TRUST_DENOM ))
    STALE_PENALTY=$(( STALE * 5 ))
    SCORE_TRUST=$(( SCORE_TRUST > STALE_PENALTY ? SCORE_TRUST - STALE_PENALTY : 0 ))
  else
    SCORE_TRUST=18
  fi
  if [ "$STALE" -gt 0 ]; then
    $SCORE_ONLY || echo "[RELAY] ⚠️  $STALE tâche(s) [stale?] — exécuter stale-detector.sh"
    WARNINGS=$((WARNINGS + 1))
  fi
else
  SCORE_TRUST=18
fi

$SCORE_ONLY || echo ""
$SCORE_ONLY || echo "── MRS ──"
$SCORE_ONLY || echo "[RELAY]    TASK[]: $TOTAL_TASKS | [verified]: $VERIFIED (legacy=$VERIFIED_LEGACY · build=$VERIFIED_BUILD · run=$VERIFIED_RUN) | [assumed]: $ASSUMED | [stale?]: $STALE"

# ── 4b. Sécurité « build-only » — fix KI marqué corrigé sans preuve runtime ──
# TASK[RELAY-VERIFY-RUN] : une tâche de fix sécurité (réf. KI-xxx + verbe « fix/corrig »)
# étiquetée `[verified-build]` n'est PAS prouvée par exécution (l'attaque n'a pas été jouée).
# Warning signal-only (n'ajoute pas d'erreur, n'altère pas l'exit code).
SECURITY_FIX_LINES=$(echo "$TASK_LINES" | grep -iE "KI-?[0-9]" | grep -F "[verified-build]" 2>/dev/null || true)
if [ -n "$SECURITY_FIX_LINES" ]; then
  while IFS= read -r sline; do
    [ -z "$sline" ] && continue
    SID=$(echo "$sline" | grep -oE "TASK\[[A-Z0-9_-]+\]" | head -1 || true)
    $SCORE_ONLY || echo "[RELAY] ⚠️  build-only : $SID référence un KI sécurité en \`[verified-build]\` — prouvé par build, PAS par run (jouer l'attaque pour \`[verified-run]\`)"
    WARNINGS=$((WARNINGS + 1))
  done <<< "$SECURITY_FIX_LINES"
fi

# ── 5. Vérification commits des tâches done (15 pts) ────────────────────────
# v3.0 : vérifie d'abord dans ce repo, puis dans --companion-repo si fourni
$SCORE_ONLY || echo ""
$SCORE_ONLY || echo "── Commits ──"
[ -n "$COMPANION_REPO" ] && { $SCORE_ONLY || echo "[RELAY]    (companion-repo actif : hash vérifiés dans les 2 repos)"; }

DONE_LINES=$(grep -E "~~TASK\[" "$FILE" 2>/dev/null || true)

if [ -z "$DONE_LINES" ]; then
  $SCORE_ONLY || echo "[RELAY] ℹ️  Aucune tâche ~~done~~ à vérifier"
  SCORE_COMMITS=15
else
  DONE_COUNT=0
  HASH_FOUND=0
  HASH_VALID=0

  while IFS= read -r done_line; do
    [ -z "$done_line" ] && continue
    DONE_COUNT=$((DONE_COUNT + 1))

    COMMIT_HASH=$(echo "$done_line" | grep -oE '`[0-9a-f]{7,12}`' | head -1 | tr -d '`' 2>/dev/null || true)

    if [ -z "$COMMIT_HASH" ]; then
      TASK_ID=$(echo "$done_line" | grep -oE 'TASK\[[A-Z0-9_-]+\]' | head -1 || true)
      $SCORE_ONLY || echo "[RELAY] ⚠️  $TASK_ID — hash commit absent (convention: \`<hash7>\` après ✅)"
      WARNINGS=$((WARNINGS + 1))
    else
      HASH_FOUND=$((HASH_FOUND + 1))
      # Vérifier dans le repo courant
      COMMIT_TYPE=$(git cat-file -t "$COMMIT_HASH" 2>/dev/null || true)
      FOUND_IN="repo courant"

      # Si pas trouvé et companion-repo fourni → vérifier là-bas
      if [ "$COMMIT_TYPE" != "commit" ] && [ -n "$COMPANION_REPO" ] && [ -d "$COMPANION_REPO" ]; then
        COMMIT_TYPE=$(git -C "$COMPANION_REPO" cat-file -t "$COMMIT_HASH" 2>/dev/null || true)
        FOUND_IN="companion-repo"
      fi

      if [ "$COMMIT_TYPE" = "commit" ]; then
        HASH_VALID=$((HASH_VALID + 1))
        $SCORE_ONLY || echo "[RELAY] ✅ Commit \`$COMMIT_HASH\` vérifié ($FOUND_IN)"
      else
        TASK_ID=$(echo "$done_line" | grep -oE 'TASK\[[A-Z0-9_-]+\]' | head -1 || true)
        $SCORE_ONLY || echo "[RELAY] ❌ Commit \`$COMMIT_HASH\` introuvable dans les 2 repos ($TASK_ID)"
        ERRORS=$((ERRORS + 1))
      fi
    fi
  done <<< "$DONE_LINES"

  $SCORE_ONLY || echo "[RELAY]    Done: $DONE_COUNT | hash présent: $HASH_FOUND | hash valide: $HASH_VALID"

  if [ "$DONE_COUNT" -gt 0 ]; then
    SCORE_COMMITS=$(( (HASH_VALID * 15) / DONE_COUNT ))
  else
    SCORE_COMMITS=15
  fi
fi

# ── 6. Clôture de session — présence entrée today ────────────────────────────
$SCORE_ONLY || echo ""
$SCORE_ONLY || echo "── Clôture ──"
TODAY=$(date +%Y-%m-%d)

SESSIONS_LOG="docs/context/SESSIONS_LOG.md"
if [ -f "$SESSIONS_LOG" ]; then
  if grep -qE "^## $TODAY" "$SESSIONS_LOG" 2>/dev/null; then
    $SCORE_ONLY || echo "[RELAY] ✅ SESSIONS_LOG.md : entrée $TODAY présente"
  else
    $SCORE_ONLY || echo "[RELAY] ⚠️  SESSIONS_LOG.md : aucune entrée $TODAY — □7 checklist non complété ?"
    WARNINGS=$((WARNINGS + 1))
  fi
fi

if grep -qE "^## Retour expérience.*$TODAY" "$FILE" 2>/dev/null; then
  $SCORE_ONLY || echo "[RELAY] ✅ §Retour expérience : session $TODAY documentée"
else
  $SCORE_ONLY || echo "[RELAY] ⚠️  §Retour expérience : aucune entrée datée $TODAY — □8 checklist non complété ?"
  WARNINGS=$((WARNINGS + 1))
fi

# ── 7. Regression Shield — patterns interdits déclarés par le PROJET ─────────
# Source de vérité = docs/.relay/rules.conf (fichier d'INSTANCE, committé, jamais écrasé
# par relay-update). AUCUN pattern projet n'est codé en dur dans le moteur : chaque projet
# déclare SES règles d'archi/sécurité ; un projet sans config voit le Shield INACTIF avec un
# avertissement explicite — jamais un assouplissement muet. Les anciens patterns codés en dur
# sont seedés dans rules.conf par relay-update.sh au 1ᵉʳ update (zéro perte de garde).
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null | grep -E '\.(cs|dart|py|ts|tsx|js|jsx|go|rs|java|kt|rb|php)$' || true)
RULES_CONF="docs/.relay/rules.conf"

if [ -n "$STAGED_FILES" ]; then
  # Parse rules.conf → FORBIDDEN_PATTERNS (+ PATTERN_EXCLUDE optionnel). Format plat :
  # une regex (ERE, grep -E) par ligne sous [forbidden_patterns] ; exclusion inline
  # optionnelle « <regex> | exclude=<regex> » ; lignes vides et « # » = ignorées.
  FORBIDDEN_PATTERNS=()
  declare -A PATTERN_EXCLUDE=()
  RS_IN=0
  if [ -f "$RULES_CONF" ]; then
    while IFS= read -r rs_line || [ -n "$rs_line" ]; do
      rs_line="${rs_line#"${rs_line%%[![:space:]]*}"}"          # ltrim
      [ -z "$rs_line" ] && continue
      case "$rs_line" in \#*) continue ;; esac                  # commentaire
      if [[ "$rs_line" =~ ^\[[a-z_]+\]$ ]]; then                # en-tête de section
        [ "$rs_line" = "[forbidden_patterns]" ] && RS_IN=1 || RS_IN=0
        continue
      fi
      [ "$RS_IN" = "1" ] || continue
      if [[ "$rs_line" == *" | exclude="* ]]; then
        rs_pat="${rs_line%% | exclude=*}"
        rs_exc="${rs_line##* | exclude=}"
      else
        rs_pat="$rs_line"; rs_exc=""
      fi
      rs_pat="${rs_pat%"${rs_pat##*[![:space:]]}"}"             # rtrim pattern
      rs_exc="${rs_exc#"${rs_exc%%[![:space:]]*}"}"; rs_exc="${rs_exc%"${rs_exc##*[![:space:]]}"}"
      [ -z "$rs_pat" ] && continue
      FORBIDDEN_PATTERNS+=("$rs_pat")
      [ -n "$rs_exc" ] && PATTERN_EXCLUDE["$rs_pat"]="$rs_exc"
    done < "$RULES_CONF"
  fi

  $SCORE_ONLY || echo ""
  $SCORE_ONLY || echo "── Regression Shield ──"

  if [ "${#FORBIDDEN_PATTERNS[@]}" -eq 0 ]; then
    # Fallback EXPLICITE (jamais muet) : aucune règle déclarée → Shield inactif + warning.
    if [ -f "$RULES_CONF" ]; then
      $SCORE_ONLY || echo "[RELAY] ⚠️  Regression Shield inactif : 0 pattern déclaré dans $RULES_CONF (section [forbidden_patterns] vide)."
    else
      $SCORE_ONLY || echo "[RELAY] ⚠️  Regression Shield inactif : $RULES_CONF absent — ce projet n'a déclaré aucune règle (relay-init dépose un modèle ; relay-update seede les anciens patterns)."
    fi
    WARNINGS=$((WARNINGS + 1))
  else
    SHIELD_ERRORS=0
    for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
      EXCLUDE="${PATTERN_EXCLUDE[$pattern]:-}"
      while IFS= read -r staged_file; do
        [ ! -f "$staged_file" ] && continue
        ADDED=$(git diff --cached -- "$staged_file" 2>/dev/null | grep "^+" | grep -vE "^\+\+\+" | grep -E "$pattern" 2>/dev/null || true)
        # Retirer les lignes correspondant à l'exclusion (affectation légitime) avant de compter
        if [ -n "$EXCLUDE" ] && [ -n "$ADDED" ]; then
          ADDED=$(echo "$ADDED" | grep -vE "$EXCLUDE" 2>/dev/null || true)
        fi
        MATCHES=$(echo "$ADDED" | grep -cE "$pattern" 2>/dev/null || true)
        [ -z "$ADDED" ] && MATCHES=0
        if [ "$MATCHES" -gt 0 ]; then
          $SCORE_ONLY || echo "[RELAY] ❌ Regression Shield : pattern interdit \`$pattern\` détecté dans $staged_file (+$MATCHES lignes)"
          ERRORS=$((ERRORS + 1))
          SHIELD_ERRORS=$((SHIELD_ERRORS + 1))
        fi
      done <<< "$STAGED_FILES"
    done

    if [ "$SHIELD_ERRORS" -eq 0 ]; then
      FILE_COUNT=$(echo "$STAGED_FILES" | grep -c "." 2>/dev/null || true)
      $SCORE_ONLY || echo "[RELAY] ✅ Regression Shield : $FILE_COUNT fichier(s) vérifié(s) — 0 pattern interdit (${#FORBIDDEN_PATTERNS[@]} règle(s) active(s))"
    fi
  fi
fi

# ── 8. Design System Shield — piloté par docs/.relay/rules.conf (v1.4.0) ──────
# Les patterns/messages/exclusions du Design System vivent dans rules.conf (instance),
# sections [design_warn_flutter] (fichiers .dart) et [design_warn_css] (.css/.cshtml).
# Sévérité = WARNING (ne bloque JAMAIS le commit). Section absente/vide → shield DS
# inactif pour ce type de fichier, ANNONCÉ (jamais muet). Zéro donnée projet dans le moteur.

# Parse une section DS de rules.conf → remplit les tableaux globaux DS_PAT/DS_MSG/DS_EXCL.
# Format de ligne : <regex> | msg=<texte> | exclude-path=<fragment-de-chemin>
# (msg et exclude-path optionnels ; champs séparés par « | », ordre libre).
parse_design_section() {
  local section="$1" line in_section=0 pat rest token
  DS_PAT=(); DS_MSG=(); DS_EXCL=()
  [ -f "$RULES_CONF" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"                   # ltrim
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac                     # commentaire
    if [[ "$line" =~ ^\[[a-z_]+\]$ ]]; then                   # en-tête de section
      [ "$line" = "[$section]" ] && in_section=1 || in_section=0
      continue
    fi
    [ "$in_section" = "1" ] || continue
    pat="${line%%' | '*}"                                     # regex = avant le 1er « | »
    local msg="" excl=""
    if [[ "$line" == *' | '* ]]; then
      rest="${line#*' | '}"
      while [ -n "$rest" ]; do                                # champs key=value
        if [[ "$rest" == *' | '* ]]; then
          token="${rest%%' | '*}"; rest="${rest#*' | '}"
        else
          token="$rest"; rest=""
        fi
        case "$token" in
          msg=*)          msg="${token#msg=}" ;;
          exclude-path=*) excl="${token#exclude-path=}" ;;
        esac
      done
    fi
    pat="${pat%"${pat##*[![:space:]]}"}"                      # rtrim regex
    [ -z "$pat" ] && continue
    DS_PAT+=("$pat"); DS_MSG+=("$msg"); DS_EXCL+=("$excl")
  done < "$RULES_CONF"
}

# Scanne les fichiers stagés d'un type contre une section DS. Sévérité WARNING.
# $1=fichiers stagés  $2=section  $3=label  $4=regex de strip-commentaire (langage)
scan_design_section() {
  local staged="$1" section="$2" label="$3" comment_strip="$4"
  local f pattern msg excl i matches
  [ -z "$staged" ] && return 0
  parse_design_section "$section"
  if [ "${#DS_PAT[@]}" -eq 0 ]; then
    $SCORE_ONLY || echo "[RELAY] ⚠️  Design System Shield ($label) inactif : section [$section] absente/vide dans $RULES_CONF"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi
  DS_SECTIONS_ACTIVE=$((DS_SECTIONS_ACTIVE + 1))
  for i in "${!DS_PAT[@]}"; do
    pattern="${DS_PAT[$i]}"; msg="${DS_MSG[$i]}"; excl="${DS_EXCL[$i]}"
    while IFS= read -r f; do
      [ ! -f "$f" ] && continue
      [ -n "$excl" ] && [[ "$f" == *"$excl"* ]] && continue   # exclusion de chemin (déclarée par l'instance)
      matches=$(git diff --cached -- "$f" 2>/dev/null | grep "^+" | grep -vE "^\+\+\+|$comment_strip" | grep -cE "$pattern" 2>/dev/null || true)
      if [ "$matches" -gt 0 ]; then
        $SCORE_ONLY || echo "[RELAY] ⚠️  Design System $label : \`$pattern\` dans $f — ${msg:-violation Design System} (+$matches lignes)"
        WARNINGS=$((WARNINGS + 1))
        DS_WARNINGS=$((DS_WARNINGS + 1))
      fi
    done <<< "$staged"
  done
}

# Sélection des fichiers par type (extension = niveau langage, pas donnée projet) ;
# l'exclusion de chemin projet (emplacement où le design system est défini) est dans rules.conf.
DART_STAGED=$(git diff --cached --name-only 2>/dev/null | grep -E '\.dart$' || true)
CSS_STAGED=$(git diff --cached --name-only 2>/dev/null | grep -E '\.(css|cshtml)$' || true)

DS_WARNINGS=0
DS_SECTIONS_ACTIVE=0

if [ -n "$DART_STAGED" ] || [ -n "$CSS_STAGED" ]; then
  $SCORE_ONLY || echo ""
  $SCORE_ONLY || echo "── Design System Shield ──"

  scan_design_section "$DART_STAGED" "design_warn_flutter" "Flutter" '//.*$'
  scan_design_section "$CSS_STAGED"  "design_warn_css"     "CSS"     '/\*'

  if [ "$DS_SECTIONS_ACTIVE" -gt 0 ] && [ "$DS_WARNINGS" -eq 0 ]; then
    $SCORE_ONLY || echo "[RELAY] ✅ Design System Shield : aucune violation détectée"
  fi
fi

# ── 9. Security Shield — piloté par docs/.relay/rules.conf (v1.8.0) ───────────
# Patterns de sécurité dangereux dans le diff stagé (code ET config). Deux sections :
#   [security_forbidden] = ERREUR (bloque) ; [security_warn] = WARNING (ne bloque pas).
# Format ligne : <regex ERE> | msg=<remédiation> | exclude=<regex contenu> | exclude-path=<fragment>
# Zéro donnée projet dans le moteur : le mécanisme est ici, les patterns vivent dans rules.conf.
# LUCIDITÉ : gate commit/CI, PAS un IDS/WAF runtime — ne remplace pas un pentest.

# Parse une section sécu → SEC_PAT/SEC_MSG/SEC_EXCL/SEC_EXCLPATH (miroir parse_design_section + exclude contenu).
parse_security_section() {
  local section="$1" line in_section=0 pat rest token
  SEC_PAT=(); SEC_MSG=(); SEC_EXCL=(); SEC_EXCLPATH=()
  [ -f "$RULES_CONF" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"                   # ltrim
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac                     # commentaire
    if [[ "$line" =~ ^\[[a-z_]+\]$ ]]; then                   # en-tête de section
      [ "$line" = "[$section]" ] && in_section=1 || in_section=0
      continue
    fi
    [ "$in_section" = "1" ] || continue
    pat="${line%%' | '*}"                                     # regex = avant le 1er « | »
    local msg="" excl="" exclpath=""
    if [[ "$line" == *' | '* ]]; then
      rest="${line#*' | '}"
      while [ -n "$rest" ]; do                                # champs key=value séparés par « | »
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
    pat="${pat%"${pat##*[![:space:]]}"}"                      # rtrim regex
    [ -z "$pat" ] && continue
    SEC_PAT+=("$pat"); SEC_MSG+=("$msg"); SEC_EXCL+=("$excl"); SEC_EXCLPATH+=("$exclpath")
  done < "$RULES_CONF"
}

# Scanne les fichiers stagés contre une section sécu. $1=stagés $2=section $3=severity(error|warn).
scan_security_section() {
  local staged="$1" section="$2" severity="$3"
  local f pattern msg excl exclpath i added matches
  [ -z "$staged" ] && return 0
  parse_security_section "$section"
  if [ "${#SEC_PAT[@]}" -eq 0 ]; then
    $SCORE_ONLY || echo "[RELAY] ⚠️  Security Shield [$section] inactif : section absente/vide dans $RULES_CONF"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi
  SEC_SECTIONS_ACTIVE=$((SEC_SECTIONS_ACTIVE + 1))
  for i in "${!SEC_PAT[@]}"; do
    pattern="${SEC_PAT[$i]}"; msg="${SEC_MSG[$i]}"; excl="${SEC_EXCL[$i]}"; exclpath="${SEC_EXCLPATH[$i]}"
    while IFS= read -r f; do
      [ ! -f "$f" ] && continue
      [ -n "$exclpath" ] && [[ "$f" == *"$exclpath"* ]] && continue   # exclusion de chemin (instance)
      # -e "$pattern" : un pattern peut commencer par « - » (ex. clé privée -----BEGIN…) → sinon grep le lit comme options
      added=$(git diff --cached -- "$f" 2>/dev/null | grep "^+" | grep -vE "^\+\+\+" | grep -E -e "$pattern" 2>/dev/null || true)
      if [ -n "$excl" ] && [ -n "$added" ]; then                      # exclusion de contenu (faux positif légitime)
        added=$(echo "$added" | grep -vE -e "$excl" 2>/dev/null || true)
      fi
      matches=$(echo "$added" | grep -cE -e "$pattern" 2>/dev/null || true)
      [ -z "$added" ] && matches=0
      if [ "$matches" -gt 0 ]; then
        if [ "$severity" = "error" ]; then
          $SCORE_ONLY || echo "[RELAY] ❌ Security Shield : \`$pattern\` dans $f — ${msg:-pattern de sécurité interdit} (+$matches lignes)"
          ERRORS=$((ERRORS + 1)); SEC_ERRORS=$((SEC_ERRORS + 1))
        else
          $SCORE_ONLY || echo "[RELAY] ⚠️  Security Shield : \`$pattern\` dans $f — ${msg:-vérifier (sécurité)} (+$matches lignes)"
          WARNINGS=$((WARNINGS + 1)); SEC_WARNINGS=$((SEC_WARNINGS + 1))
        fi
      fi
    done <<< "$staged"
  done
}

# Code ET config (un secret vit souvent en config). rules.conf est EXCLU (il contient des patterns par nature).
SEC_STAGED=$(git diff --cached --name-only 2>/dev/null | grep -E '\.(cs|dart|py|ts|tsx|js|jsx|go|rs|java|kt|rb|php|json|ya?ml|env|xml|properties|toml|ini|config|sh)$' | grep -vE 'docs/\.relay/rules\.conf' || true)

SEC_ERRORS=0
SEC_WARNINGS=0
SEC_SECTIONS_ACTIVE=0

if [ -n "$SEC_STAGED" ]; then
  $SCORE_ONLY || echo ""
  $SCORE_ONLY || echo "── Security Shield ──"
  scan_security_section "$SEC_STAGED" "security_forbidden" "error"
  scan_security_section "$SEC_STAGED" "security_warn"      "warn"
  if [ "$SEC_SECTIONS_ACTIVE" -gt 0 ] && [ "$SEC_ERRORS" -eq 0 ] && [ "$SEC_WARNINGS" -eq 0 ]; then
    $SCORE_ONLY || echo "[RELAY] ✅ Security Shield : aucun pattern de sécurité détecté"
  fi
fi

# ── 9b. Security Surface Trigger — ancrage sécu SÉLECTIF (Couche 2, v1.10.0) ──
# Réutilise le grep déterministe de la Couche 1 (parse_security_section) sur une 3ᵉ section,
# [security_surface], dont les patterns sont des MARQUEURS de zone sensible (auth, secrets,
# crypto, IDOR…) — PAS des dangers. Si le diff stagé en touche un → UN avertissement
# « ancrer SECURITY_RULES.md » : c'est le déclencheur qui rend l'ancrage sécu sélectif
# (checklist chargée seulement si surface touchée → token-négatif, VISION.md §4).
# Sévérité = WARNING signal-only (n'altère JAMAIS l'exit code) : le grep de surface est
# heuristique (faux positifs assumés) → guider, jamais bloquer. Le verdict reste humain.
# LUCIDITÉ : gate commit/CI, PAS un IDS/WAF runtime — ne remplace pas un pentest.
if [ -n "$SEC_STAGED" ]; then
  parse_security_section "security_surface"
  $SCORE_ONLY || echo ""
  $SCORE_ONLY || echo "── Security Surface Trigger ──"
  if [ "${#SEC_PAT[@]}" -eq 0 ]; then
    $SCORE_ONLY || echo "[RELAY] ⚠️  Security Surface Trigger inactif : section [security_surface] absente/vide dans $RULES_CONF"
    WARNINGS=$((WARNINGS + 1))
  else
    SURFACE_HITS=""
    for i in "${!SEC_PAT[@]}"; do
      pattern="${SEC_PAT[$i]}"; cat_label="${SEC_MSG[$i]}"; excl="${SEC_EXCL[$i]}"; exclpath="${SEC_EXCLPATH[$i]}"
      while IFS= read -r f; do
        [ ! -f "$f" ] && continue
        [ -n "$exclpath" ] && [[ "$f" == *"$exclpath"* ]] && continue
        added=$(git diff --cached -- "$f" 2>/dev/null | grep "^+" | grep -vE "^\+\+\+" | grep -E -e "$pattern" 2>/dev/null || true)
        if [ -n "$excl" ] && [ -n "$added" ]; then
          added=$(echo "$added" | grep -vE -e "$excl" 2>/dev/null || true)
        fi
        [ -n "$added" ] && SURFACE_HITS="$SURFACE_HITS${cat_label:-surface sensible}"$'\n'
      done <<< "$SEC_STAGED"
    done
    SURFACE_CATS=$(printf '%s' "$SURFACE_HITS" | grep -v '^$' | sort -u | paste -sd', ' - 2>/dev/null || true)
    if [ -n "$SURFACE_CATS" ]; then
      $SCORE_ONLY || echo "[RELAY] ⚠️  Surface sensible touchée ($SURFACE_CATS)"
      $SCORE_ONLY || echo "[RELAY]    → ancrer la checklist docs/rules/SECURITY_RULES.md (Couche 2) + écrire SECURITY_ANCHOR: dans le TASK[]"
      $SCORE_ONLY || echo "[RELAY]    (signal-only — n'altère pas l'exit ; heuristique, gate commit/CI ≠ pentest)"
      WARNINGS=$((WARNINGS + 1))
    else
      $SCORE_ONLY || echo "[RELAY] ✅ Security Surface Trigger : aucune surface sensible dans le diff stagé (${#SEC_PAT[@]} marqueur(s) actif(s))"
    fi
  fi
fi

# ── 9c. Security Pattern Memory — auto-feed de SECURITY_RULES.md (Couche 4, v1.11.0) ──
# Miroir du Regression Shield transposé à la sécurité. Quand une CORRECTION de sécurité atterrit
# (un finding de KNOWN_ISSUES.md passe ✅ RÉSOLU dans le diff stagé ET le diff porte un marqueur
# [security_surface]) SANS qu'un « pattern appris » soit enregistré dans SECURITY_RULES.md
# (§Patterns appris) → UN avertissement signal-only invitant à l'enregistrer, pour que la session
# suivante ne réintroduise pas le bug corrigé.
# Le LLM est la couche faible : le DÉCLENCHEUR est déterministe (grep, réutilise le vocabulaire
# d'instance [security_surface] → moteur vierge, comme §9b), la PUCE reste CURATÉE par l'humain
# (on n'auto-écrit jamais de la sécurité). Token-NEUTRE (1 puce ciblée, soumise à la jauge densité).
# Sévérité = WARNING signal-only (n'altère JAMAIS l'exit). LUCIDITÉ : gate commit/CI ≠ pentest.
KI_ADDED=$(git diff --cached -- "docs/rules/KNOWN_ISSUES.md" 2>/dev/null | grep "^+" | grep -vE "^\+\+\+" || true)
if [ -n "$KI_ADDED" ] && printf '%s\n' "$KI_ADDED" | grep -qE "✅ RÉSOLU" 2>/dev/null; then
  $SCORE_ONLY || echo ""
  $SCORE_ONLY || echo "── Security Pattern Memory ──"
  parse_security_section "security_surface"
  SEC_FIX_MATCH=""
  for i in "${!SEC_PAT[@]}"; do
    if printf '%s\n' "$KI_ADDED" | grep -qE -e "${SEC_PAT[$i]}" 2>/dev/null; then
      SEC_FIX_MATCH=1; break
    fi
  done
  if [ -n "$SEC_FIX_MATCH" ]; then
    # Un pattern appris a-t-il été ajouté à SECURITY_RULES.md (puce de prose, PAS une checkbox) ?
    PATTERN_ADDED=$(git diff --cached -- "docs/rules/SECURITY_RULES.md" 2>/dev/null \
      | grep -E "^\+" | grep -vE "^\+\+\+" \
      | grep -E "^\+[[:space:]]*-[[:space:]]+" | grep -vE "^\+[[:space:]]*-[[:space:]]+\[ \]" || true)
    if [ -z "$PATTERN_ADDED" ]; then
      $SCORE_ONLY || echo "[RELAY] ⚠️  Fix sécu détecté (finding KNOWN_ISSUES ✅ RÉSOLU) sans pattern appris enregistré"
      $SCORE_ONLY || echo "[RELAY]    → ajoute un pattern concret dans docs/rules/SECURITY_RULES.md (§Patterns appris, Couche 4) pour que la prochaine session ne le réintroduise pas"
      $SCORE_ONLY || echo "[RELAY]    (signal-only — n'altère pas l'exit ; soumis à la jauge densité anti-inflation)"
      WARNINGS=$((WARNINGS + 1))
    else
      $SCORE_ONLY || echo "[RELAY] ✅ Security Pattern Memory : fix sécu + pattern appris enregistré dans SECURITY_RULES.md"
    fi
  else
    $SCORE_ONLY || echo "[RELAY] ✅ Security Pattern Memory : finding résolu non-sécu (aucun marqueur [security_surface]) — rien à enregistrer"
  fi
fi

# ── 9. Branch Guard — pas de commit direct sur main/develop avec du code ─────
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
CODE_STAGED=$(git diff --cached --name-only 2>/dev/null | grep -E '\.(cs|dart)$' || true)

if [ -n "$CODE_STAGED" ] && { [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "develop" ]; }; then
  $SCORE_ONLY || echo ""
  $SCORE_ONLY || echo "── Branch Guard ──"
  $SCORE_ONLY || echo "[RELAY] ⚠️  Commit de code (.cs/.dart) directement sur \`$CURRENT_BRANCH\` — préférer une feature branch puis merger"
  WARNINGS=$((WARNINGS + 1))
fi

# ── 10. Scope-Creep Alert — mécanise la règle 70% du protocole §2 (Chef de projet, v1.12.0) ──
# La règle des 70% existait en PROSE (§2 étape 4) mais n'était jamais MÉCANISÉE : le LLM est la couche
# faible (il s'auto-déclare « ça tient »). Ici relay-check somme l'effort des TASK[] RETENABLES cette
# session — pending + owner=session + depends=[] (NON bloquées) — au barème protocole S=0.5/M=1/L=2.
# Si la somme dépasse le budget 70% (défaut 3.5 pts, surchargeable RELAY_SCOPE_BUDGET) → UN avertissement
# signal-only « scope-creep : retenir un sous-ensemble, reporter le reste ». N'altère JAMAIS l'exit code
# (heuristique → guide, cohérent SEC-2/SEC-4 ; l'arbitrage de périmètre reste humain). Token-négatif
# (réutilise le format TASK[] déjà parsé l.176-181, 0 nouveau vocabulaire d'instance). On ne compte QUE
# les tâches non bloquées (depends=[]) → un gros backlog majoritairement bloqué ne déclenche pas (≠ creep).
SCOPE_BUDGET="${RELAY_SCOPE_BUDGET:-3.5}"
# Garde : budget non numérique → repli sur le défaut protocole (ne jamais crasher sur un env mal réglé)
case "$SCOPE_BUDGET" in ''|*[!0-9.]*) SCOPE_BUDGET=3.5 ;; esac
SCOPE_SUM=$(awk '
  /TASK\[/ && /status=pending/ && /owner=session/ && /depends=\[\]/ {
    if      ($0 ~ /effort=S/) sum += 0.5
    else if ($0 ~ /effort=M/) sum += 1
    else if ($0 ~ /effort=L/) sum += 2
  }
  END { printf "%.1f", sum + 0 }
' "$FILE" 2>/dev/null || echo 0)
SCOPE_SUM=${SCOPE_SUM:-0.0}
$SCORE_ONLY || echo ""
$SCORE_ONLY || echo "── Scope-Creep Alert ──"
# Comparaison flottante via awk (le test bash [ ] ne compare pas les décimaux)
if awk "BEGIN { exit !($SCOPE_SUM > $SCOPE_BUDGET) }" 2>/dev/null; then
  $SCORE_ONLY || echo "[RELAY] ⚠️  Scope-creep : $SCOPE_SUM pts retenables (pending · owner=session · depends=[]) > budget 70% ($SCOPE_BUDGET pts)"
  $SCORE_ONLY || echo "[RELAY]    → retiens un sous-ensemble ≤ $SCOPE_BUDGET pts, reporte le reste (protocole §2) ; barème S=0.5/M=1/L=2"
  $SCORE_ONLY || echo "[RELAY]    (signal-only — n'altère pas l'exit ; surcharge RELAY_SCOPE_BUDGET)"
  WARNINGS=$((WARNINGS + 1))
else
  $SCORE_ONLY || echo "[RELAY] ✅ Scope-Creep Alert : $SCOPE_SUM pts retenables ≤ budget 70% ($SCOPE_BUDGET pts)"
fi

# ── 11. Decision Trigger — trace des décisions architecturales (Architecte connaissance, v1.13.0) ──
# Une décision archi (dépendance, projet, interface Domain, câblage DI…) est souvent prise
# IMPLICITEMENT dans un commit, sans être tracée dans docs/context/DECISIONS.md → la connaissance
# se perd (pourquoi ce choix ? quelles alternatives rejetées ? sous quelle condition réviser ?).
# Miroir EXACT de la famille §9b (scan de surface) + §9c (événement détecté SANS contre-trace → rappel) :
# réutilise parse_security_section sur une section [decision_surface] (MARQUEURS structurels, moteur
# vierge — vocabulaire en instance). Si le diff stagé en touche un ET qu'aucune entrée « ## DEC- » n'a
# été ajoutée à DECISIONS.md dans le même commit stagé → UN avertissement « trace cette décision ».
# Sévérité = WARNING signal-only (n'altère JAMAIS l'exit) : l'architecture est un jugement, le LLM est
# la couche faible — le déterministe RAPPELLE, l'humain DÉCIDE (on ne le fait pas auto-classer « ceci est
# une décision » de façon bloquante). Token-négatif (grep, 0 token LLM). On NE remplit JAMAIS la décision.
DEC_STAGED=$(git diff --cached --name-only 2>/dev/null | grep -E '\.(cs|dart|py|ts|tsx|js|jsx|go|rs|java|kt|rb|php|json|ya?ml|xml|toml|gradle|csproj|sln|fsproj|vbproj)$' | grep -vE 'docs/\.relay/rules\.conf' || true)
if [ -n "$DEC_STAGED" ]; then
  parse_security_section "decision_surface"
  $SCORE_ONLY || echo ""
  $SCORE_ONLY || echo "── Decision Trigger ──"
  if [ "${#SEC_PAT[@]}" -eq 0 ]; then
    $SCORE_ONLY || echo "[RELAY] ⚠️  Decision Trigger inactif : section [decision_surface] absente/vide dans $RULES_CONF"
    WARNINGS=$((WARNINGS + 1))
  else
    DEC_HITS=""
    for i in "${!SEC_PAT[@]}"; do
      pattern="${SEC_PAT[$i]}"; cat_label="${SEC_MSG[$i]}"; excl="${SEC_EXCL[$i]}"; exclpath="${SEC_EXCLPATH[$i]}"
      while IFS= read -r f; do
        [ ! -f "$f" ] && continue
        [ -n "$exclpath" ] && [[ "$f" == *"$exclpath"* ]] && continue
        added=$(git diff --cached -- "$f" 2>/dev/null | grep "^+" | grep -vE "^\+\+\+" | grep -E -e "$pattern" 2>/dev/null || true)
        if [ -n "$excl" ] && [ -n "$added" ]; then
          added=$(echo "$added" | grep -vE -e "$excl" 2>/dev/null || true)
        fi
        [ -n "$added" ] && DEC_HITS="$DEC_HITS${cat_label:-changement structurel}"$'\n'
      done <<< "$DEC_STAGED"
    done
    DEC_CATS=$(printf '%s' "$DEC_HITS" | grep -v '^$' | sort -u | paste -sd', ' - 2>/dev/null || true)
    if [ -n "$DEC_CATS" ]; then
      # Une entrée « ## DEC- » a-t-elle été ajoutée à DECISIONS.md dans le même commit stagé ?
      DEC_ENTRY_ADDED=$(git diff --cached -- "docs/context/DECISIONS.md" 2>/dev/null \
        | grep -E "^\+" | grep -vE "^\+\+\+" | grep -E "^\+##[[:space:]]*DEC-" || true)
      if [ -z "$DEC_ENTRY_ADDED" ]; then
        $SCORE_ONLY || echo "[RELAY] ⚠️  Changement structurel détecté ($DEC_CATS) sans décision tracée"
        $SCORE_ONLY || echo "[RELAY]    → ajoute une entrée ## DEC-XXX dans docs/context/DECISIONS.md (choix / alternatives rejetées / condition de révision)"
        $SCORE_ONLY || echo "[RELAY]    (signal-only — n'altère pas l'exit ; heuristique, marqueurs [decision_surface] — l'humain décide)"
        WARNINGS=$((WARNINGS + 1))
      else
        $SCORE_ONLY || echo "[RELAY] ✅ Decision Trigger : changement structurel + décision tracée (## DEC-) dans DECISIONS.md"
      fi
    else
      $SCORE_ONLY || echo "[RELAY] ✅ Decision Trigger : aucun changement structurel dans le diff stagé (${#SEC_PAT[@]} marqueur(s) actif(s))"
    fi
  fi
fi

# ── Gating sécurité du LABEL (TASK[RELAY-SCORE-HONEST]) ──────────────────────
# Le LABEL « 🟢 Sain » ne doit pas s'afficher tant qu'un finding P0/P1 reste OUVERT
# dans KNOWN_ISSUES.md. On gate UNIQUEMENT le label affiché — le score numérique
# d'hygiène (sections/taille/confiance/commits) reste calculé à l'identique (cf.
# RELAY_METRICS §1, séparation handoff/produit volontaire).
# « P0/P1 ouvert » = toute entrée `### KI-xxx` sous une section `## … P0` / `## … P1`
# dont le titre ne contient PAS `✅ RÉSOLU`. Les 🟡 (partiels) comptent OUVERTS.
# Détection tolérante : KNOWN_ISSUES absent / 0 finding → label inchangé (ne crashe pas).
KNOWN_ISSUES_FILE="docs/rules/KNOWN_ISSUES.md"
count_open_p0p1() {
  [ -f "$KNOWN_ISSUES_FILE" ] || { echo 0; return 0; }
  awk '
    /^## / {
      # Nouvelle section : active uniquement si titre mentionne P0 ou P1
      if ($0 ~ /P0/ || $0 ~ /P1/) { active=1 } else { active=0 }
      next
    }
    active && /^### KI-/ {
      if ($0 !~ /✅ RÉSOLU/) open++
    }
    END { print open+0 }
  ' "$KNOWN_ISSUES_FILE" 2>/dev/null || echo 0
}
OPEN_P0P1=$(count_open_p0p1)
OPEN_P0P1=${OPEN_P0P1:-0}

# ── Skew check (signal-only) — moteur d'instance en retard sur le canonique ───
# TASK[RELAY-PORTABILITY] : compare la version moteur de CE projet (docs/.relay-version)
# à la VERSION du dépôt canonique localisable. N'altère NI le score NI l'exit code :
# pur avertissement « lance relay-update.sh ». No-op gracieux si l'un des deux manque.
# Localisation du canonique (même ordre de priorité que relay-update.sh) :
#   1. $RELAY_CANONICAL (env)   2. cache ~/.relay/canonical   3. introuvable → silencieux.
SKEW_MSG=""
compute_skew() {
  local instver canver canroot
  [ -f "docs/.relay-version" ] || return 0
  # Version moteur installée = 1ʳᵉ chaîne X.Y.Z du manifeste d'instance
  instver=$(grep -oE "[0-9]+\.[0-9]+\.[0-9]+" "docs/.relay-version" 2>/dev/null | head -1 || true)
  [ -z "$instver" ] && return 0
  # Localiser la racine canonique (même ordre que relay-update.sh, + CANONICAL_URL local)
  local canurl
  canurl=$(grep -E "^CANONICAL_URL=" "docs/.relay-version" 2>/dev/null | head -1 | cut -d= -f2- || true)
  if [ -n "${RELAY_CANONICAL:-}" ] && [ -f "${RELAY_CANONICAL}/VERSION" ]; then
    canroot="$RELAY_CANONICAL"
  elif [ -f "$HOME/.relay/canonical/VERSION" ]; then
    canroot="$HOME/.relay/canonical"
  elif [ -n "$canurl" ] && [ -f "${canurl}/VERSION" ]; then
    canroot="$canurl"   # chemin local du canonique inscrit au manifeste
  else
    return 0   # canonique introuvable → no-op gracieux
  fi
  canver=$(grep -oE "[0-9]+\.[0-9]+\.[0-9]+" "$canroot/VERSION" 2>/dev/null | head -1 || true)
  [ -z "$canver" ] && return 0
  # Comparaison sémantique X.Y.Z purement numérique (tri version)
  if [ "$instver" != "$canver" ]; then
    local lower
    lower=$(printf '%s\n%s\n' "$instver" "$canver" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)
    if [ "$lower" = "$instver" ]; then
      SKEW_MSG="moteur v$instver en retard sur canonique v$canver → lance relay-update.sh"
    fi
  fi
}
compute_skew

# ── Health Score ─────────────────────────────────────────────────────────────
HEALTH=$(( SCORE_SECTIONS + SCORE_SIZE + SCORE_TRUST + SCORE_COMMITS ))
[ "$HEALTH" -gt 100 ] && HEALTH=100

if [ "$HEALTH" -ge 80 ]; then
  HEALTH_LABEL="🟢 Sain"
elif [ "$HEALTH" -ge 60 ]; then
  HEALTH_LABEL="🟡 Attention"
else
  HEALTH_LABEL="🔴 Dégradé"
fi

# Gating : tant qu'un P0/P1 est ouvert, le label « Sain » s'éteint et signale
# le nombre de findings ouverts. Score numérique inchangé.
if [ "$OPEN_P0P1" -gt 0 ] && [ "$HEALTH" -ge 80 ]; then
  HEALTH_LABEL="⚠️ $OPEN_P0P1 P0/P1 ouvert(s)"
fi

compute_density

$SCORE_ONLY || echo ""
echo "[RELAY] ── Health Score : $HEALTH/100 $HEALTH_LABEL ──"
echo "[RELAY]    sections=$SCORE_SECTIONS/35  taille=$SCORE_SIZE/15  confiance=$SCORE_TRUST/35  commits=$SCORE_COMMITS/15"
echo "[RELAY] ── Densité ruleset : $DENS_RATIO $DENS_ICON (univers=$DENS_UNIVERSE_N / récent=$DENS_RECENT_N · jauge anti-inflation, n'affecte pas le score) ──"
[ -n "$DENS_DORMANT" ] && { $SCORE_ONLY || echo "[RELAY]    dormantes (→ --density pour le détail) : $DENS_DORMANT"; }
[ -n "$SKEW_MSG" ] && echo "[RELAY] ⚠️  Skew moteur : $SKEW_MSG (signal-only, n'affecte ni le score ni l'exit code)"
$SCORE_ONLY && exit 0

echo ""
PRESENT=$(( SCORE_SECTIONS / 9 ))
[ "$PRESENT" -gt 4 ] && PRESENT=4

if [ "$ERRORS" -gt 0 ]; then
  echo "[RELAY] ❌ $ERRORS erreur(s), $WARNINGS warning(s) — $PRESENT/4 sections présentes"
  $STRICT && exit 1 || exit 0
else
  echo "[RELAY] ✅ NEXT_SESSION.md — structure valide ($LINES lignes, $WARNINGS warning(s))"
  exit 0
fi
