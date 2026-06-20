#!/usr/bin/env bash
# relay-forecast.sh v1.0 — Projection de fin de backlog (Scrum Master / Chef de projet)
# RELAY Framework — Outil complémentaire, pair de relay-stats.sh
# Usage: ./docs/scripts/relay-forecast.sh [--json] [--window=N] [--drift-threshold=X]
#
# Prolongement TEMPOREL de SCOPE-1 (relay-check §10 mécanise la règle 70% sur la session
# COURANTE ; le forecast projette le RYTHME sur les sessions à venir).
#
# Produit :
#   - Points restants    = somme effort des TASK[] RETENABLES (pending + owner=session +
#                          depends=[]) au barème SCOPE-1 S=0.5/M=1/L=2 — MÊME filtre, MÊME unité.
#   - Vélocité           = points DONE récents ÷ nb de sessions récentes (points/session, PAS commit).
#   - Projection         = ceil(restants / vélocité), en FOURCHETTE (min–max) — jamais un faux point précis.
#   - Alerte de dérive   = sur la fenêtre, points AJOUTÉS au backlog vs points FERMÉS (git diff) :
#                          le backlog grossit-il plus vite qu'il ne se vide ? (VISION §116, scope-creep tendanciel).
#
# Honnêteté de calibration : < 2 sessions d'historique ou 0 tâche done → « historique insuffisant »,
# JAMAIS un chiffre inventé. Backlog retenable vide → « 0 session ».
#
# INFORMATIF PUR : exit 0 TOUJOURS — ne bloque ni n'alourdit aucun commit (cohérent relay-stats,
# n'est PAS un gate). Offline-safe (git local uniquement, aucune dépendance réseau).

set -uo pipefail

JSON_MODE=false
WINDOW="${RELAY_FORECAST_WINDOW:-5}"
DRIFT_THRESHOLD="${RELAY_FORECAST_DRIFT_THRESHOLD:-0}"
for arg in "$@"; do
  case "$arg" in
    --json) JSON_MODE=true ;;
    --window=*) WINDOW="${arg#--window=}" ;;
    --drift-threshold=*) DRIFT_THRESHOLD="${arg#--drift-threshold=}" ;;
  esac
done
# Gardes : paramètres non numériques → repli sur défaut (ne jamais crasher sur un env mal réglé)
case "$WINDOW" in ''|*[!0-9]*) WINDOW=5 ;; esac
case "$DRIFT_THRESHOLD" in ''|*[!0-9.]*) DRIFT_THRESHOLD=0 ;; esac
[ "$WINDOW" -lt 1 ] && WINDOW=1

TODAY=$(date +%Y-%m-%d)
PROJECT_NAME=$(basename "$(pwd)")
BACKLOG_FILE="NEXT_SESSION.md"
ARCHIVE_FILE="docs/context/SESSIONS_ARCHIVE.md"

# ── helpers ────────────────────────────────────────────────────────────────────

# Barème SCOPE-1 appliqué à un flux de lignes TASK[] passé sur stdin (filtre fourni par l'appelant).
points_of_lines() {
  awk '{
    if ($0 ~ /effort=S/) s += 0.5
    else if ($0 ~ /effort=M/) s += 1
    else if ($0 ~ /effort=L/) s += 2
  } END { printf "%.1f", s + 0 }'
}

# ceil(n / d) ; d<=0 → "NaN"
ceil_div() {
  awk -v n="$1" -v d="$2" 'BEGIN {
    if (d <= 0) { print "NaN"; exit }
    v = n / d; print (v == int(v)) ? v : int(v) + 1
  }'
}

# ── 1. Points restants — filtre + barème SCOPE-1 À L'IDENTIQUE (relay-check §10) ──
# pending + owner=session + depends=[]  →  on ne projette QUE le backlog RETENABLE (non bloqué),
# même unité que la règle 70% : deux « points 70% » divergents dans le moteur seraient une erreur.
REMAINING=$(awk '
  /TASK\[/ && /status=pending/ && /owner=session/ && /depends=\[\]/ {
    if ($0 ~ /effort=S/) s += 0.5
    else if ($0 ~ /effort=M/) s += 1
    else if ($0 ~ /effort=L/) s += 2
  } END { printf "%.1f", s + 0 }
' "$BACKLOG_FILE" 2>/dev/null || echo 0)
REMAINING=${REMAINING:-0.0}

# ── 2. Fenêtre de sessions récentes ──────────────────────────────────────────────
# Dénominateur de la vélocité = nb de SESSIONS (pas de commits). Source (décision 3.1) :
#   - canonique : fichiers docs/session_logs/*.md (1 par session) ;
#   - instance  : à défaut, dates distinctes des tâches done (NEXT_SESSION + SESSIONS_ARCHIVE).
SESSION_DATES=""
if compgen -G "docs/session_logs/*.md" > /dev/null 2>&1; then
  SESSION_DATES=$(ls docs/session_logs/*.md 2>/dev/null \
    | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort -u)
fi
if [ -z "$SESSION_DATES" ]; then
  SESSION_DATES=$(for f in "$BACKLOG_FILE" "$ARCHIVE_FILE"; do
      [ -f "$f" ] && grep "status=done" "$f"
    done | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort -u)
fi

WINDOW_DATES=$(echo "$SESSION_DATES" | grep -vE '^$' | sort -ru | head -n "$WINDOW")
NB_SESSIONS=$(echo "$WINDOW_DATES" | grep -cvE '^$')
SINCE=$(echo "$WINDOW_DATES" | grep -vE '^$' | tail -1)

# ── 3. Points done sur la fenêtre + série par session (pour la fourchette) ────────
# Une tâche done est datée en fin de ligne (~~TASK[X] … status=done effort=S~~ ✅ <commit> <date>).
DONE_BY_DATE=$(for f in "$BACKLOG_FILE" "$ARCHIVE_FILE"; do
    [ -f "$f" ] && grep "status=done" "$f"
  done | awk -v since="$SINCE" '
    {
      d = ""
      if (match($0, /[0-9]{4}-[0-9]{2}-[0-9]{2}/)) d = substr($0, RSTART, RLENGTH)
      if (d == "" || (since != "" && d < since)) next
      p = 0
      if ($0 ~ /effort=S/) p = 0.5; else if ($0 ~ /effort=M/) p = 1; else if ($0 ~ /effort=L/) p = 2
      agg[d] += p
    }
    END { for (k in agg) printf "%s %.1f\n", k, agg[k] }
  ')

RECENT_DONE_PTS=$(echo "$DONE_BY_DATE" | awk '{ s += $2 } END { printf "%.1f", s + 0 }')
RECENT_DONE_PTS=${RECENT_DONE_PTS:-0.0}

# Débit par session (parmi celles ayant produit) → variance honnête pour la fourchette
V_MAX=$(echo "$DONE_BY_DATE" | awk 'NF{ if ($2 > m) m = $2 } END { printf "%.1f", m + 0 }')
V_MIN_POS=$(echo "$DONE_BY_DATE" | awk 'NF && $2 > 0 { if (m == "" || $2 < m) m = $2 } END { printf "%.1f", (m == "" ? 0 : m) }')
NB_PRODUCTIVE=$(echo "$DONE_BY_DATE" | awk 'NF && $2 > 0' | grep -cvE '^$')

# Vélocité moyenne (points/session) sur la fenêtre
VELOCITY=$(awk -v p="$RECENT_DONE_PTS" -v n="$NB_SESSIONS" 'BEGIN { printf "%.2f", (n > 0 ? p / n : 0) }')

# ── 4. Projection ────────────────────────────────────────────────────────────────
# Honnêteté : < 2 sessions OU 0 point done → insuffisant ; backlog vide → 0 session.
PROJ_STATUS="ok"; PROJ_CENTRAL=""; PROJ_MIN=""; PROJ_MAX=""
if awk "BEGIN { exit !($REMAINING == 0) }"; then
  PROJ_STATUS="empty"
elif [ "$NB_SESSIONS" -lt 2 ] || awk "BEGIN { exit !($RECENT_DONE_PTS == 0) }"; then
  PROJ_STATUS="insufficient"
else
  PROJ_CENTRAL=$(ceil_div "$REMAINING" "$VELOCITY")
  if [ "$NB_PRODUCTIVE" -ge 2 ] && awk "BEGIN { exit !($V_MAX > 0 && $V_MIN_POS > 0) }"; then
    PROJ_MIN=$(ceil_div "$REMAINING" "$V_MAX")       # optimiste : meilleur débit observé
    PROJ_MAX=$(ceil_div "$REMAINING" "$V_MIN_POS")   # pessimiste : plus faible débit non nul
  fi
fi

# ── 5. Alerte de dérive (scope-creep tendanciel) — git diff sur la fenêtre ────────
# Points AJOUTÉS au backlog (nouvelles TASK[] pending) vs points FERMÉS (passées done) depuis
# le début de la fenêtre. added > closed (+ seuil) → le backlog grossit plus vite qu'il ne se vide.
DRIFT_STATUS="insufficient"; DRIFT_ADDED="0.0"; DRIFT_CLOSED="0.0"; DRIFT_NET="0.0"
if [ -n "$SINCE" ] && git rev-parse --git-dir > /dev/null 2>&1; then
  BASE=$(git rev-list -1 --before="$SINCE 00:00:00" HEAD 2>/dev/null || true)
  if [ -n "$BASE" ]; then
    DIFF=$(git diff "$BASE" HEAD -- "$BACKLOG_FILE" "$ARCHIVE_FILE" 2>/dev/null || true)
    DRIFT_ADDED=$(echo "$DIFF" | grep -E '^\+[^+]' | sed 's/^\+//' \
      | awk '/TASK\[/ && /status=pending/ && !/~~/' | points_of_lines)
    DRIFT_CLOSED=$(echo "$DIFF" | grep -E '^\+[^+]' | sed 's/^\+//' \
      | awk '/TASK\[/ && /status=done/' | points_of_lines)
    DRIFT_ADDED=${DRIFT_ADDED:-0.0}; DRIFT_CLOSED=${DRIFT_CLOSED:-0.0}
    DRIFT_NET=$(awk -v a="$DRIFT_ADDED" -v c="$DRIFT_CLOSED" 'BEGIN { printf "%.1f", a - c }')
    if awk "BEGIN { exit !($DRIFT_NET > $DRIFT_THRESHOLD) }"; then
      DRIFT_STATUS="drift"
    else
      DRIFT_STATUS="ok"
    fi
  fi
fi

# ── Output ────────────────────────────────────────────────────────────────────────

if [ "$JSON_MODE" = "true" ]; then
  echo "{"
  echo "  \"project\": \"$PROJECT_NAME\","
  echo "  \"date\": \"$TODAY\","
  echo "  \"remaining_points\": $REMAINING,"
  echo "  \"window_sessions\": $NB_SESSIONS,"
  echo "  \"recent_done_points\": $RECENT_DONE_PTS,"
  echo "  \"velocity_pts_per_session\": $VELOCITY,"
  echo "  \"projection\": {"
  echo "    \"status\": \"$PROJ_STATUS\","
  echo "    \"central_sessions\": \"${PROJ_CENTRAL}\","
  echo "    \"min_sessions\": \"${PROJ_MIN}\","
  echo "    \"max_sessions\": \"${PROJ_MAX}\""
  echo "  },"
  echo "  \"drift\": {"
  echo "    \"status\": \"$DRIFT_STATUS\","
  echo "    \"added_points\": $DRIFT_ADDED,"
  echo "    \"closed_points\": $DRIFT_CLOSED,"
  echo "    \"net_points\": $DRIFT_NET"
  echo "  }"
  echo "}"
  exit 0
fi

echo ""
echo "══════════════════════════════════════════════════════════════════"
echo "  RELAY Forecast — $PROJECT_NAME — $TODAY"
echo "══════════════════════════════════════════════════════════════════"
echo ""
echo "── Backlog retenable (barème SCOPE-1 : pending · owner=session · depends=[]) ──"
echo "  Points restants : $REMAINING pt(s)   (S=0.5 / M=1 / L=2)"
echo ""
echo "── Vélocité (points/session, fenêtre = $NB_SESSIONS dernière(s) session(s)) ──"
echo "  Sessions récentes : $NB_SESSIONS"
echo "  Points done       : $RECENT_DONE_PTS pt(s)"
echo "  Vélocité moyenne  : ~$VELOCITY pt/session"
echo ""
echo "── Projection (à ce rythme, pour vider le backlog retenable) ──"
case "$PROJ_STATUS" in
  empty)
    echo "  ✅ Backlog retenable vidé → 0 session." ;;
  insufficient)
    echo "  ⚠️  Historique insuffisant pour projeter (< 2 sessions ou 0 tâche done)."
    echo "      → pas de chiffre inventé ; accumule de l'historique." ;;
  ok)
    if [ -n "$PROJ_MIN" ] && [ -n "$PROJ_MAX" ]; then
      echo "  ⏳ ~$PROJ_MIN à $PROJ_MAX session(s)  (central ~$PROJ_CENTRAL)"
      echo "     fourchette = meilleur débit ($V_MAX pt) → plus faible débit non nul ($V_MIN_POS pt)"
    else
      echo "  ⏳ ~$PROJ_CENTRAL session(s)  (variance indisponible : < 2 sessions productives)"
    fi ;;
esac
echo ""
echo "── Alerte de dérive (scope-creep tendanciel — git, sur la fenêtre) ──"
case "$DRIFT_STATUS" in
  insufficient)
    echo "  ⚠️  Historique git insuffisant pour mesurer la dérive (pas de commit avant la fenêtre)." ;;
  drift)
    echo "  ⚠️  Dérive : $DRIFT_ADDED pt(s) ajoutés vs $DRIFT_CLOSED pt(s) fermés (net +$DRIFT_NET)"
    echo "      → le backlog grossit plus vite qu'il ne se vide (seuil $DRIFT_THRESHOLD)." ;;
  ok)
    echo "  ✅ Pas de dérive : $DRIFT_ADDED pt(s) ajoutés vs $DRIFT_CLOSED pt(s) fermés (net $DRIFT_NET)." ;;
esac
echo "══════════════════════════════════════════════════════════════════"
echo ""
echo "(informatif — n'altère jamais l'exit ; surcharges : RELAY_FORECAST_WINDOW, RELAY_FORECAST_DRIFT_THRESHOLD)"
exit 0
