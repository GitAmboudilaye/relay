#!/usr/bin/env bash
# docs/scripts/audit.sh — Audit code project-agnostic (RELAY engine)
# Usage : ./docs/scripts/audit.sh [backend|web|all]
#
# PORTABILITÉ (TASK[RELAY-PORTABILITY]) : zéro identité de projet en dur.
#   - Nom du projet : dérivé de docs/.relay-version (PROJECT=) → sinon basename du repo git.
#   - Racine        : racine du dépôt git courant.
#   - Cibles scan   : auto-découvertes (dossiers Controllers/ et Services/ trouvés sous la racine),
#                     plus un override possible via le manifeste docs/.relay-version :
#                       AUDIT_BACKEND_GLOBS="rel/path1 rel/path2"   (dossiers à scanner)
#                       AUDIT_WEB_GLOBS="rel/path"
#   Aucun chemin AgriConnect.* / cookie projet en dur : la version driftée est neutralisée.

set -uo pipefail
TARGET=${1:-all}
ERRORS=0
WARNINGS=0

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
VERSION_FILE="$ROOT/docs/.relay-version"

# ── Nom du projet (agnostique) ───────────────────────────────────────────────
PROJECT_NAME=""
if [ -f "$VERSION_FILE" ]; then
  PROJECT_NAME=$(grep -E "^PROJECT=" "$VERSION_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r' || true)
fi
[ -z "$PROJECT_NAME" ] && PROJECT_NAME=$(basename "$ROOT")

# ── Cibles de scan (override manifeste sinon auto-découverte) ─────────────────
BACKEND_GLOBS=""
WEB_GLOBS=""
if [ -f "$VERSION_FILE" ]; then
  BACKEND_GLOBS=$(grep -E "^AUDIT_BACKEND_GLOBS=" "$VERSION_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' || true)
  WEB_GLOBS=$(grep -E "^AUDIT_WEB_GLOBS=" "$VERSION_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' || true)
fi

# Auto-découverte si pas d'override : tous les dossiers Controllers/ et Services/ du repo
resolve_backend_dirs() {
  if [ -n "$BACKEND_GLOBS" ]; then
    for g in $BACKEND_GLOBS; do [ -d "$ROOT/$g" ] && echo "$ROOT/$g"; done
  else
    find "$ROOT" -type d \( -name Controllers -o -name Services \) \
      -not -path '*/bin/*' -not -path '*/obj/*' -not -path '*/node_modules/*' 2>/dev/null
  fi
}
resolve_web_dirs() {
  if [ -n "$WEB_GLOBS" ]; then
    for g in $WEB_GLOBS; do [ -d "$ROOT/$g" ] && echo "$ROOT/$g"; done
  else
    find "$ROOT" -type d \( -iname '*web*' -o -iname '*.web' \) \
      -not -path '*/bin/*' -not -path '*/obj/*' -not -path '*/node_modules/*' 2>/dev/null
  fi
}

mapfile -t BACKEND_DIRS < <(resolve_backend_dirs)
mapfile -t WEB_DIRS < <(resolve_web_dirs)

echo ""
echo "╔══════════════════════════════════════════╗"
printf "║   %-38s ║\n" "$PROJECT_NAME — Audit"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── BACKEND ──────────────────────────────────────────────────────────────────
if [[ "$TARGET" == "backend" || "$TARGET" == "all" ]]; then
  echo "▶ Backend"
  echo "─────────────────────────────"

  if [ "${#BACKEND_DIRS[@]}" -eq 0 ]; then
    echo "ℹ️  Aucun dossier Controllers/ ou Services/ détecté (override AUDIT_BACKEND_GLOBS dans docs/.relay-version)"
  else
    # 1. .Result / .Wait() bloquant (deadlock async)
    BLOCKING=$(grep -rn "\.Result\b\|\.Wait()" "${BACKEND_DIRS[@]}" 2>/dev/null || true)
    if [ -n "$BLOCKING" ]; then
      echo "❌ .Result / .Wait() bloquant :"; echo "$BLOCKING"; ERRORS=$((ERRORS+1))
    else
      echo "✅ Async/await → OK"
    fi

    # 2. DTO défini inline dans un controller
    CTRL_DIRS=$(printf '%s\n' "${BACKEND_DIRS[@]}" | grep -i Controllers || true)
    if [ -n "$CTRL_DIRS" ]; then
      INLINE_DTO=$(echo "$CTRL_DIRS" | while IFS= read -r d; do
        [ -d "$d" ] && grep -rn "record.*Request\|record.*Response\|class.*Dto" "$d" 2>/dev/null || true
      done)
      if [ -n "$INLINE_DTO" ]; then
        echo "❌ DTO potentiellement inline dans controller :"; echo "$INLINE_DTO"; ERRORS=$((ERRORS+1))
      else
        echo "✅ DTOs → pas dans les controllers"
      fi
    fi

    # 3. Console.WriteLine résiduel (utiliser un logger)
    CONSOLE=$(grep -rn "Console\.WriteLine" "${BACKEND_DIRS[@]}" 2>/dev/null || true)
    if [ -n "$CONSOLE" ]; then
      echo "⚠️  Console.WriteLine (utiliser un logger) :"; echo "$CONSOLE"; WARNINGS=$((WARNINGS+1))
    else
      echo "✅ Logging → OK"
    fi
  fi

  # 4. appsettings.Development.json dans .gitignore (si appsettings présent)
  if [ -f "$ROOT/.gitignore" ] && find "$ROOT" -name 'appsettings*.json' -not -path '*/bin/*' 2>/dev/null | grep -q .; then
    if ! grep -q "appsettings.Development.json" "$ROOT/.gitignore"; then
      echo "❌ appsettings.Development.json absent du .gitignore"; ERRORS=$((ERRORS+1))
    else
      echo "✅ .gitignore → OK"
    fi
  fi

  # 5. Clé secrète hardcodée (tous .cs hors appsettings/IConfiguration)
  JWT_HARD=$(grep -rn --include='*.cs' "SecretKey\s*=\s*\"" "$ROOT" 2>/dev/null \
    | grep -v "appsettings\|IConfiguration\|options\.\|/bin/\|/obj/" || true)
  if [ -n "$JWT_HARD" ]; then
    echo "❌ Clé secrète potentiellement hardcodée :"; echo "$JWT_HARD"; ERRORS=$((ERRORS+1))
  else
    echo "✅ Secrets → OK"
  fi
fi

# ── WEB ──────────────────────────────────────────────────────────────────────
if [[ "$TARGET" == "web" || "$TARGET" == "all" ]]; then
  echo ""
  echo "▶ Web"
  echo "─────────────────────────────"

  # Vérifier que le build passe (auto-détection du système de build)
  if find "$ROOT" -maxdepth 2 \( -name '*.sln' -o -name '*.csproj' \) 2>/dev/null | grep -q . && command -v dotnet >/dev/null 2>&1; then
    echo "  → dotnet build (silencieux)..."
    BUILD_OUT=$(cd "$ROOT" && dotnet build --no-restore -q 2>&1 | grep -E "^.*error" || true)
    if [ -n "$BUILD_OUT" ]; then
      echo "❌ Build errors :"; echo "$BUILD_OUT"; ERRORS=$((ERRORS+1))
    else
      echo "✅ dotnet build → OK"
    fi
  elif [ -f "$ROOT/package.json" ] && command -v npm >/dev/null 2>&1; then
    echo "ℹ️  package.json détecté — lancer 'npm run build' manuellement (audit ne build pas le front auto)"
  else
    echo "ℹ️  Aucun système de build auto-détecté (sln/csproj/package.json)"
  fi
fi

echo ""
echo "╔══════════════════════════════════════════╗"
if [ $ERRORS -gt 0 ]; then
  printf "║  ❌ %-2s erreur(s) — commit BLOQUÉ          ║\n" "$ERRORS"
else
  echo "║  ✅ 0 erreur                              ║"
fi
if [ $WARNINGS -gt 0 ]; then
  printf "║  ⚠️  %-2s avertissement(s)                  ║\n" "$WARNINGS"
fi
echo "╚══════════════════════════════════════════╝"
echo ""

[ $ERRORS -gt 0 ] && exit 1 || exit 0
