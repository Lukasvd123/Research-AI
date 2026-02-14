#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AI_DIR="$(dirname "$SCRIPT_DIR")"
LLAMA_BIN="${LLAMA_BIN:-/home/lvandee/llama.cpp/build/bin}"
MODEL_DIR="${MODEL_DIR:-/home/lvandee/models}"

export LD_LIBRARY_PATH="${LLAMA_BIN}:${LD_LIBRARY_PATH:-}"

CHAT_MODEL="${MODEL_DIR}/qwen3/Qwen3-8B-Q4_K_M.gguf"
EMBED_MODEL="${MODEL_DIR}/qwen3/Qwen3-Embedding-8B-Q4_K_M.gguf"

echo "[AI] Starting chat llama-server on port 8081..."
"${LLAMA_BIN}/llama-server" \
    --model "$CHAT_MODEL" \
    --port 8081 \
    --host 127.0.0.1 \
    --n-gpu-layers 99 \
    &
echo $! > /tmp/llama-chat.pid

echo "[AI] Starting embedding llama-server on port 8082..."
"${LLAMA_BIN}/llama-server" \
    --model "$EMBED_MODEL" \
    --port 8082 \
    --host 127.0.0.1 \
    --n-gpu-layers 99 \
    --embedding \
    &
echo $! > /tmp/llama-embed.pid

echo "[AI] Waiting for llama-servers to initialize..."
sleep 5

echo "[AI] Starting FastAPI wrapper on port 8090..."
cd "$AI_DIR"
uvicorn main:app --host 127.0.0.1 --port 8090 &
echo $! > /tmp/llama-fastapi.pid

echo "[AI] All services started."
echo "  Chat:  PID $(cat /tmp/llama-chat.pid)   -> 127.0.0.1:8081"
echo "  Embed: PID $(cat /tmp/llama-embed.pid)   -> 127.0.0.1:8082"
echo "  API:   PID $(cat /tmp/llama-fastapi.pid) -> 127.0.0.1:8090"

# Keep the script running so systemd sees it as active
wait
