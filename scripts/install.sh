#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing Ollama..."
echo ""

# ── Check Homebrew ───────────────────────────────────────────
if ! command -v brew &>/dev/null; then
    echo "ERROR: Homebrew is not installed."
    echo "       Install it first: https://brew.sh"
    exit 1
fi

# ── Install or upgrade Ollama ────────────────────────────────
if command -v ollama &>/dev/null; then
    CURRENT=$(ollama --version 2>/dev/null || echo "unknown")
    echo "    Ollama is already installed ($CURRENT)."
    echo "    Upgrading to latest..."
    brew upgrade ollama 2>/dev/null || echo "    Already up to date."
else
    brew install ollama
fi

# ── Verify ───────────────────────────────────────────────────
echo ""
if command -v ollama &>/dev/null; then
    echo "==> Ollama installed successfully."
    ollama --version
    echo ""
    echo "    Metal GPU acceleration: enabled (Apple Silicon native)"
    echo "    Model storage: ~/.ollama"
    echo ""
    echo "    Next steps:"
    echo "      ./scripts/up.sh            # start the server"
    echo "      ./scripts/pull-models.sh   # download models"
    echo "      ./scripts/test-models.sh   # verify everything works"
else
    echo "ERROR: Installation failed. Check brew output above."
    exit 1
fi
