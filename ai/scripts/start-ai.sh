#!/usr/bin/env bash
set -euo pipefail

# All paths are configured via environment variables.
# The systemd unit or env.yaml must set these — there are no hardcoded defaults.
: "${LLAMA_BIN:?ERROR: LLAMA_BIN not set (path to llama.cpp build/bin directory)}"
: "${MODEL_DIR:?ERROR: MODEL_DIR not set (path to model files directory)}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AI_DIR="$(dirname "$SCRIPT_DIR")"
REPO_DIR="$(dirname "$AI_DIR")"
export PYTHONPATH="${REPO_DIR}:${PYTHONPATH:-}"
RUN_DIR="/run/user/$(id -u)/research-ai"
mkdir -p "$RUN_DIR"

export LD_LIBRARY_PATH="${LLAMA_BIN}:${LD_LIBRARY_PATH:-}"

CHAT_MODEL="${CHAT_MODEL:-${MODEL_DIR}/qwen3/Qwen3-8B-Q4_K_M.gguf}"
EMBED_MODEL="${EMBED_MODEL:-${MODEL_DIR}/qwen3/Qwen3-Embedding-8B-Q4_K_M.gguf}"
GPU_LAYERS="${N_GPU_LAYERS:-99}"

# Cleanup child processes on exit
cleanup() {
    echo "[AI] Shutting down..."
    kill 0 2>/dev/null || true
    rm -f "$RUN_DIR"/llama-*.pid
    wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "[AI] Starting chat llama-server on port 8081..."
"${LLAMA_BIN}/llama-server" \
    --model "$CHAT_MODEL" \
    --port 8081 \
    --host 127.0.0.1 \
    --n-gpu-layers "$GPU_LAYERS" \
    &
CHAT_PID=$!
echo "$CHAT_PID" > "$RUN_DIR/llama-chat.pid"

echo "[AI] Starting embedding llama-server on port 8082..."
"${LLAMA_BIN}/llama-server" \
    --model "$EMBED_MODEL" \
    --port 8082 \
    --host 127.0.0.1 \
    --n-gpu-layers "$GPU_LAYERS" \
    --embedding \
    &
EMBED_PID=$!
echo "$EMBED_PID" > "$RUN_DIR/llama-embed.pid"

echo "[AI] Waiting for llama-servers to initialize..."
sleep 5

echo "[AI] Starting FastAPI wrapper on port 8090..."
cd "$AI_DIR"
uvicorn main:app --host 127.0.0.1 --port 8090 &
API_PID=$!
echo "$API_PID" > "$RUN_DIR/llama-fastapi.pid"

echo "[AI] All services started."
echo "  Chat:  PID $CHAT_PID  -> 127.0.0.1:8081"
echo "  Embed: PID $EMBED_PID  -> 127.0.0.1:8082"
echo "  API:   PID $API_PID   -> 127.0.0.1:8090"

# Keep running — if any child dies, exit (systemd will restart)
wait -n
echo "[AI] A child process exited, shutting down."
exit 1
