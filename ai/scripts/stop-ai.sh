#!/usr/bin/env bash
set -euo pipefail

echo "[AI] Stopping AI services..."

for pidfile in /tmp/llama-chat.pid /tmp/llama-embed.pid /tmp/llama-fastapi.pid; do
    if [ -f "$pidfile" ]; then
        pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
            echo "  Killing PID $pid ($pidfile)"
            kill "$pid" 2>/dev/null || true
        fi
        rm -f "$pidfile"
    fi
done

echo "[AI] All services stopped."
