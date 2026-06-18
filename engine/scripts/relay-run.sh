#!/usr/bin/env bash
# relay-run.sh v1.0 — Wrapper de preuve : exécute une commande et émet un REÇU
# Capture cmd/cwd/timestamps/stdout/stderr/exit-code dans docs/.relay/receipts/<hash>.log,
# repasse le code de sortie tel quel (wrapper transparent), et imprime le hash à CITER
# dans NEXT_SESSION.md sous la forme [verified-run:<hash>].
#
# C'est le socle d'intégrité de `[verified-run]` : relay-check.sh exige qu'un
# `[verified-run:<hash>]` pointe vers un reçu existant (sinon ERREUR = preuve falsifiée).
#
# Usage:
#   ./docs/scripts/relay-run.sh "<commande>"
#   ./docs/scripts/relay-run.sh dotnet build
#   ./docs/scripts/relay-run.sh "flutter test && echo done"
#
# Reçus : docs/.relay/receipts/<hash>.log (gitignorés — preuve locale, données d'instance).
# Rétrocompat : opt-in. `[verified-run]` nu (sans hash) reste valide ; le reçu n'est requis
# que pour REVENDIQUER la preuve. `[verified-build]` / `[assumed]` ne sont jamais concernés.

set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "[RELAY] ❌ usage: relay-run.sh \"<commande>\"" >&2
  exit 2
fi

CMD="$*"

RECEIPT_DIR="docs/.relay/receipts"
mkdir -p "$RECEIPT_DIR"

# Auto-ignore : les reçus sont des données d'instance, jamais committées.
# Le script dépose lui-même le .gitignore → aucun fichier d'instance à éditer à la main.
GITIGNORE="docs/.relay/.gitignore"
if [ ! -f "$GITIGNORE" ]; then
  printf 'receipts/\n' > "$GITIGNORE"
fi

# Hash court, unique par run (cmd + horodatage + pid + aléa). Portable : sha1sum (Linux)
# ou shasum (macOS/BSD).
hash_input="${CMD}|$(date +%s 2>/dev/null || true)|$$|${RANDOM:-0}${RANDOM:-0}"
if command -v sha1sum >/dev/null 2>&1; then
  HASH=$(printf '%s' "$hash_input" | sha1sum | cut -c1-12)
elif command -v shasum >/dev/null 2>&1; then
  HASH=$(printf '%s' "$hash_input" | shasum | cut -c1-12)
else
  echo "[RELAY] ❌ ni sha1sum ni shasum disponibles — impossible d'émettre un reçu" >&2
  exit 2
fi

RECEIPT="$RECEIPT_DIR/$HASH.log"
STARTED=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date 2>/dev/null || echo "?")

echo "[RELAY] ▶ relay-run : $CMD"
echo "[RELAY]   reçu → $RECEIPT"
echo ""

# Exécution : sortie combinée (stdout+stderr) streamée à la console ET capturée.
# PIPESTATUS[0] = code de sortie de la commande, pas de tee.
OUTPUT_TMP=$(mktemp 2>/dev/null || echo "/tmp/relay-run.$$.tmp")
set +e
bash -c "$CMD" 2>&1 | tee "$OUTPUT_TMP"
EXIT_CODE=${PIPESTATUS[0]}
set -e

FINISHED=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date 2>/dev/null || echo "?")

{
  echo "# RELAY receipt"
  echo "hash: $HASH"
  echo "cmd: $CMD"
  echo "cwd: $(pwd)"
  echo "started: $STARTED"
  echo "finished: $FINISHED"
  echo "exit: $EXIT_CODE"
  echo "--- output ---"
  cat "$OUTPUT_TMP" 2>/dev/null || true
} > "$RECEIPT"

rm -f "$OUTPUT_TMP" 2>/dev/null || true

echo ""
if [ "$EXIT_CODE" -eq 0 ]; then
  echo "[RELAY] ✅ exit 0 — cite cette preuve dans NEXT_SESSION.md : [verified-run:$HASH]"
else
  echo "[RELAY] ⚠️  exit $EXIT_CODE — la commande a ÉCHOUÉ. Ne pas revendiquer [verified-run] sur un run rouge."
  echo "[RELAY]    (reçu conservé pour audit : exit=$EXIT_CODE)"
fi

# Wrapper transparent : repasse le code de sortie de la commande encapsulée.
exit "$EXIT_CODE"
