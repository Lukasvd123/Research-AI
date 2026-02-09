#!/usr/bin/env bash
set -euo pipefail

# --- Auto-detect container runtime ---
if command -v podman &>/dev/null; then
  RT=podman
elif command -v docker &>/dev/null; then
  RT=docker
else
  echo "Error: neither podman nor docker found in PATH" >&2
  exit 1
fi
echo "Using container runtime: $RT"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VITE_API_URL="${VITE_API_URL:-http://localhost:8000}"

# --- Helper functions ---
stop_container() {
  local name="$1"
  if $RT container exists "$name" 2>/dev/null; then
    echo "Stopping and removing existing container: $name"
    $RT stop "$name" 2>/dev/null || true
    $RT rm "$name" 2>/dev/null || true
  fi
}

start_frontend() {
  local name="research-ai-frontend-dev"
  stop_container "$name"

  echo "Building frontend dev image..."
  $RT build -t research-ai-frontend-dev \
    -f "$SCRIPT_DIR/dev/Containerfile.frontend" \
    "$SCRIPT_DIR"

  echo "Starting frontend dev container on port 5173..."
  $RT run -d --name "$name" \
    -p 5173:5173 \
    -v "$SCRIPT_DIR/frontend/src:/app/src:z" \
    -v "$SCRIPT_DIR/frontend/public:/app/public:z" \
    -v "$SCRIPT_DIR/frontend/index.html:/app/index.html:z" \
    -v "$SCRIPT_DIR/frontend/vite.config.ts:/app/vite.config.ts:z" \
    -v "$SCRIPT_DIR/frontend/tsconfig.json:/app/tsconfig.json:z" \
    -v "$SCRIPT_DIR/frontend/tsconfig.app.json:/app/tsconfig.app.json:z" \
    -v research-ai-node-modules:/app/node_modules \
    -e "VITE_API_URL=$VITE_API_URL" \
    research-ai-frontend-dev

  echo "Frontend running at http://localhost:5173"
}

start_backend() {
  local name="research-ai-backend-dev"
  stop_container "$name"

  echo "Building backend dev image..."
  $RT build -t research-ai-backend-dev \
    -f "$SCRIPT_DIR/dev/Containerfile.backend" \
    "$SCRIPT_DIR"

  echo "Starting backend dev container on port 8000..."
  $RT run -d --name "$name" \
    -p 8000:8000 \
    -v "$SCRIPT_DIR/backend:/app:z" \
    research-ai-backend-dev

  echo "Backend running at http://localhost:8000"
}

# --- Main ---
usage() {
  echo "Usage: $0 <backend|frontend>"
  echo ""
  echo "  backend   - Start BOTH frontend and backend containers"
  echo "  frontend  - Start ONLY the frontend container"
  exit 1
}

if [ $# -ne 1 ]; then
  usage
fi

case "$1" in
  backend)
    start_backend
    start_frontend
    echo ""
    echo "Both services running:"
    echo "  Frontend: http://localhost:5173"
    echo "  Backend:  http://localhost:8000"
    ;;
  frontend)
    start_frontend
    ;;
  *)
    usage
    ;;
esac
