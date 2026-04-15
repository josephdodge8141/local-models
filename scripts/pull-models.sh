#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/models.conf"

OLLAMA_URL="http://127.0.0.1:${OLLAMA_PORT:-11434}"

# ── Pre-flight ───────────────────────────────────────────────
if ! curl -sf "$OLLAMA_URL/" >/dev/null 2>&1; then
    echo "ERROR: Ollama is not running at $OLLAMA_URL"
    echo "       Run ./scripts/up.sh first."
    exit 1
fi

# ── Pull each model ──────────────────────────────────────────
FAILED=()
SUCCEEDED=()

for model in "${MODELS[@]}"; do
    echo ""
    echo "==========================================="
    echo "  Pulling: $model"
    echo "==========================================="
    if ollama pull "$model"; then
        SUCCEEDED+=("$model")
        echo "    -> $model pulled successfully"
    else
        echo ""
        echo "    -> FAILED to pull $model"
        echo "       The tag may not exist in the Ollama registry."
        echo "       Check available tags: https://ollama.com/library"
        FAILED+=("$model")
    fi
done

# ── Summary ──────────────────────────────────────────────────
echo ""
echo "==========================================="
echo "  Pull Summary"
echo "==========================================="

if [ ${#SUCCEEDED[@]} -gt 0 ]; then
    echo "  Succeeded (${#SUCCEEDED[@]}):"
    for m in "${SUCCEEDED[@]}"; do echo "    + $m"; done
fi

if [ ${#FAILED[@]} -gt 0 ]; then
    echo "  Failed (${#FAILED[@]}):"
    for m in "${FAILED[@]}"; do echo "    - $m"; done
fi

echo ""
echo "Installed models:"
ollama list

if [ ${#FAILED[@]} -gt 0 ]; then
    exit 1
fi
