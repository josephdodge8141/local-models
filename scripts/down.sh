#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PID_FILE="$PROJECT_DIR/.ollama.pid"

# ── Stop via PID file (started by up.sh) ─────────────────────
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "==> Stopping Ollama (PID $PID)..."
        kill "$PID"
        # Wait for clean exit (up to 10s)
        for i in $(seq 1 10); do
            if ! kill -0 "$PID" 2>/dev/null; then
                break
            fi
            sleep 1
        done
        if kill -0 "$PID" 2>/dev/null; then
            echo "    Process still alive, sending SIGKILL..."
            kill -9 "$PID" 2>/dev/null || true
        fi
        echo "==> Ollama stopped."
    else
        echo "==> Stale PID file (process $PID already exited). Cleaning up."
    fi
    rm -f "$PID_FILE"
    exit 0
fi

# ── Fallback: find any running ollama serve ──────────────────
if pgrep -f "ollama serve" >/dev/null 2>&1; then
    echo "==> Ollama is running but was not started by these scripts."
    echo ""
    echo "    To stop it manually:"
    echo "      pkill -f 'ollama serve'"
    echo ""
    echo "    If started via brew:"
    echo "      brew services stop ollama"
    exit 1
fi

echo "==> Ollama is not running."
