#!/usr/bin/env bash
set -euo pipefail

RUN_DIR="/run/user/$(id -u)/research-ai"

echo "[AI] Stopping AI services..."

for pidfile in "$RUN_DIR"/llama-chat.pid "$RUN_DIR"/llama-embed.pid "$RUN_DIR"/llama-fastapi.pid; do
    if [ -f "$pidfile" ]; then
        pid=$(cat "$pidfile")
        name=$(basename "$pidfile" .pid)
        # Verify the PID belongs to our process before killing
        if kill -0 "$pid" 2>/dev/null; then
            cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ' || true)
            if echo "$cmdline" | grep -qE 'llama-server|uvicorn'; then
                echo "  Stopping $name (PID $pid)"
                kill "$pid" 2>/dev/null || true
            else
                echo "  Skipping $name — PID $pid belongs to another process"
            fi
        fi
        rm -f "$pidfile"
    fi
done

echo "[AI] All services stopped."
