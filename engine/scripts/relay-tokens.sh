#!/usr/bin/env bash
# relay-tokens.sh v1.0 — Métrique token-saved du RELAY « actif » (économie chiffrée du shift-left)
# RELAY Framework — outil informatif, pair de relay-stats.sh / relay-forecast.sh
# Usage: ./docs/scripts/relay-tokens.sh [--json] [--ledger=CHEMIN]
#
# Matérialise l'angle produit de RELAY (VISION §4, RELAY-CORE-ACTIF §0/§1.4) : le hook PreToolUse
# (RELAY-3) injecte un rappel ciblé EN AMONT (~token-in) pour éviter une réécriture EN AVAL (~token-saved).
# Ce script lit le LEDGER d'instance que le hook dépose (docs/.relay/token-ledger.log, 1 ligne/firing)
# et chiffre le bilan.
#
# Modèle (RELAY-CORE-ACTIF §0) — token-saved est CONTREFACTUEL (la réécriture évitée n'a, par définition,
# jamais eu lieu) → il est MODÉLISÉ, jamais « mesuré ». Étiqueté comme estimation, constantes overridables :
#   token-in    = chaque firing (deny OU context) injecte un rappel amont      ~RELAY_TOKEN_IN    (déf. 40)
#   token-saved = chaque deny évite une réécriture aval (deny seulement, conservateur) ~RELAY_TOKEN_SAVED (déf. 2000)
#   net         = token-saved − token-in
#
# Honnêteté : ledger absent/vide → « pas encore de données », JAMAIS un chiffre inventé (cohérent forecast).
# INFORMATIF PUR : exit 0 TOUJOURS — ne bloque ni n'alourdit aucun commit. Offline-safe (lecture locale).

set -uo pipefail

JSON_MODE=false
LEDGER="docs/.relay/token-ledger.log"
TOKEN_IN="${RELAY_TOKEN_IN:-40}"
TOKEN_SAVED="${RELAY_TOKEN_SAVED:-2000}"
for arg in "$@"; do
  case "$arg" in
    --json) JSON_MODE=true ;;
    --ledger=*) LEDGER="${arg#--ledger=}" ;;
  esac
done
# Gardes : constantes non numériques → repli sur défaut (ne jamais crasher sur un env mal réglé)
case "$TOKEN_IN" in ''|*[!0-9]*) TOKEN_IN=40 ;; esac
case "$TOKEN_SAVED" in ''|*[!0-9]*) TOKEN_SAVED=2000 ;; esac

TODAY=$(date +%Y-%m-%d 2>/dev/null)
PROJECT_NAME=$(basename "$(pwd)")

# ── 1. Décompte des firings depuis le ledger ($2 = décision : deny | context) ─────────────────────
DENY=0; CONTEXT=0
if [ -f "$LEDGER" ]; then
  DENY=$(awk '$2 == "deny" { n++ } END { print n + 0 }' "$LEDGER" 2>/dev/null || echo 0)
  CONTEXT=$(awk '$2 == "context" { n++ } END { print n + 0 }' "$LEDGER" 2>/dev/null || echo 0)
fi
DENY=${DENY:-0}; CONTEXT=${CONTEXT:-0}
FIRINGS=$((DENY + CONTEXT))

# ── 2. Modèle économique ──────────────────────────────────────────────────────────────────────────
TOK_IN_TOTAL=$((FIRINGS * TOKEN_IN))      # toute injection (deny OU context) coûte ~token-in en amont
TOK_SAVED_TOTAL=$((DENY * TOKEN_SAVED))    # seul un deny évite une réécriture aval (conservateur)
NET=$((TOK_SAVED_TOTAL - TOK_IN_TOTAL))

# ── 3. Sortie ───────────────────────────────────────────────────────────────────────────────────
if [ "$JSON_MODE" = "true" ]; then
  echo "{"
  echo "  \"project\": \"$PROJECT_NAME\","
  echo "  \"date\": \"$TODAY\","
  echo "  \"ledger\": \"$LEDGER\","
  echo "  \"firings\": $FIRINGS,"
  echo "  \"deny\": $DENY,"
  echo "  \"context\": $CONTEXT,"
  echo "  \"token_in\": $TOK_IN_TOTAL,"
  echo "  \"token_saved\": $TOK_SAVED_TOTAL,"
  echo "  \"net\": $NET,"
  echo "  \"model\": { \"token_in_per_firing\": $TOKEN_IN, \"token_saved_per_deny\": $TOKEN_SAVED }"
  echo "}"
  exit 0
fi

echo ""
echo "══════════════════════════════════════════════════════════════════"
echo "  RELAY Tokens — $PROJECT_NAME — $TODAY"
echo "══════════════════════════════════════════════════════════════════"
echo ""
if [ ! -f "$LEDGER" ] || [ "$FIRINGS" -eq 0 ]; then
  echo "  ⚠️  Pas encore de données ($LEDGER absent ou vide)."
  echo "      Le hook PreToolUse (RELAY-3) n'a pas encore tiré sur ce projet —"
  echo "      → pas de chiffre inventé ; câble l'adaptateur puis édite du code."
  echo "══════════════════════════════════════════════════════════════════"
  echo ""
  echo "(informatif — n'altère jamais l'exit)"
  exit 0
fi
echo "── Firings du hook (shift-left, ledger d'instance) ──"
echo "  Total : $FIRINGS   (deny $DENY · context $CONTEXT)"
echo ""
echo "── Bilan token (modèle estimé — token-saved est contrefactuel) ──"
echo "  token-in    : ~$TOK_IN_TOTAL tok   (injection amont, ~$TOKEN_IN/firing)"
echo "  token-saved : ~$TOK_SAVED_TOTAL tok   (réécriture aval évitée, ~$TOKEN_SAVED/deny)"
echo "  net         : ~$NET tok économisés"
echo "══════════════════════════════════════════════════════════════════"
echo ""
echo "(informatif — n'altère jamais l'exit ; modèle overridable : RELAY_TOKEN_IN, RELAY_TOKEN_SAVED)"
exit 0
