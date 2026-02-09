#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
POD_NAME="research-ai-dev"
FRONTEND_CTR="research-ai-frontend-dev"
BACKEND_CTR="research-ai-backend-dev"
FRONTEND_IMG="research-ai-frontend-dev"
BACKEND_IMG="research-ai-backend-dev"
FRONTEND_PORT=5173
BACKEND_PORT=8000

# --- Auto-detect container runtime ---
USE_POD=0
if command -v podman &>/dev/null; then
  RT=podman
  USE_POD=1
elif command -v docker &>/dev/null; then
  RT=docker
else
  echo "Error: neither podman nor docker found in PATH" >&2
  exit 1
fi
echo "Using container runtime: $RT"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VITE_API_URL="${VITE_API_URL:-http://localhost:$BACKEND_PORT}"

# --- Helper functions ---

ensure_pod() {
  if [ "$USE_POD" = "1" ]; then
    if ! $RT pod exists "$POD_NAME" 2>/dev/null; then
      echo "Creating pod: $POD_NAME"
      $RT pod create --name "$POD_NAME" \
        -p "$FRONTEND_PORT:$FRONTEND_PORT" \
        -p "$BACKEND_PORT:$BACKEND_PORT"
    else
      echo "Pod $POD_NAME already exists."
      $RT pod start "$POD_NAME" 2>/dev/null || true
    fi
  else
    if ! $RT network inspect "$POD_NAME" &>/dev/null; then
      echo "Creating network: $POD_NAME"
      $RT network create "$POD_NAME"
    fi
  fi
}

ensure_backend() {
  echo "Building backend image..."
  $RT build -t "$BACKEND_IMG" \
    -f "$SCRIPT_DIR/dev/Containerfile.backend" \
    "$SCRIPT_DIR"

  if $RT container inspect "$BACKEND_CTR" &>/dev/null; then
    echo "Starting existing backend container..."
    $RT start "$BACKEND_CTR" 2>/dev/null || true
  else
    echo "Creating backend container..."
    if [ "$USE_POD" = "1" ]; then
      $RT run -d --name "$BACKEND_CTR" \
        --pod "$POD_NAME" \
        -v "$SCRIPT_DIR/backend:/app:z" \
        "$BACKEND_IMG"
    else
      $RT run -d --name "$BACKEND_CTR" \
        --network "$POD_NAME" \
        -p "$BACKEND_PORT:$BACKEND_PORT" \
        -v "$SCRIPT_DIR/backend:/app:z" \
        "$BACKEND_IMG"
    fi
  fi
  echo "Backend running at http://localhost:$BACKEND_PORT"
}

ensure_frontend() {
  echo "Building frontend image..."
  $RT build -t "$FRONTEND_IMG" \
    -f "$SCRIPT_DIR/dev/Containerfile.frontend" \
    "$SCRIPT_DIR"

  if $RT container inspect "$FRONTEND_CTR" &>/dev/null; then
    echo "Starting existing frontend container..."
    $RT start "$FRONTEND_CTR" 2>/dev/null || true
  else
    echo "Creating frontend container..."
    if [ "$USE_POD" = "1" ]; then
      $RT run -d --name "$FRONTEND_CTR" \
        --pod "$POD_NAME" \
        -v "$SCRIPT_DIR/frontend/src:/app/src:z" \
        -v "$SCRIPT_DIR/frontend/public:/app/public:z" \
        -v "$SCRIPT_DIR/frontend/index.html:/app/index.html:z" \
        -v "$SCRIPT_DIR/frontend/vite.config.ts:/app/vite.config.ts:z" \
        -v "$SCRIPT_DIR/frontend/tsconfig.json:/app/tsconfig.json:z" \
        -v "$SCRIPT_DIR/frontend/tsconfig.app.json:/app/tsconfig.app.json:z" \
        -v research-ai-node-modules:/app/node_modules \
        -e "VITE_API_URL=$VITE_API_URL" \
        "$FRONTEND_IMG"
    else
      $RT run -d --name "$FRONTEND_CTR" \
        --network "$POD_NAME" \
        -p "$FRONTEND_PORT:$FRONTEND_PORT" \
        -v "$SCRIPT_DIR/frontend/src:/app/src:z" \
        -v "$SCRIPT_DIR/frontend/public:/app/public:z" \
        -v "$SCRIPT_DIR/frontend/index.html:/app/index.html:z" \
        -v "$SCRIPT_DIR/frontend/vite.config.ts:/app/vite.config.ts:z" \
        -v "$SCRIPT_DIR/frontend/tsconfig.json:/app/tsconfig.json:z" \
        -v "$SCRIPT_DIR/frontend/tsconfig.app.json:/app/tsconfig.app.json:z" \
        -v research-ai-node-modules:/app/node_modules \
        -e "VITE_API_URL=$VITE_API_URL" \
        "$FRONTEND_IMG"
    fi
  fi
  echo "Frontend running at http://localhost:$FRONTEND_PORT"
}

stop_all() {
  echo "Stopping pod $POD_NAME..."
  if [ "$USE_POD" = "1" ]; then
    $RT pod stop "$POD_NAME" 2>/dev/null || true
    echo "Pod stopped."
  else
    $RT stop "$FRONTEND_CTR" 2>/dev/null || true
    $RT stop "$BACKEND_CTR" 2>/dev/null || true
    echo "Containers stopped."
  fi
}

rebuild_all() {
  echo "Tearing down pod and containers for a clean rebuild..."
  if [ "$USE_POD" = "1" ]; then
    $RT pod rm -f "$POD_NAME" 2>/dev/null || true
  else
    $RT rm -f "$FRONTEND_CTR" 2>/dev/null || true
    $RT rm -f "$BACKEND_CTR" 2>/dev/null || true
    $RT network rm "$POD_NAME" 2>/dev/null || true
  fi
  echo "Done. Run the script again with backend or frontend to rebuild."
}

# --- Main ---
usage() {
  echo "Usage: $0 <backend|frontend|stop|rebuild>"
  echo ""
  echo "  backend   - Start BOTH frontend and backend in a pod"
  echo "  frontend  - Start ONLY the frontend in a pod"
  echo "  stop      - Stop the running pod/containers"
  echo "  rebuild   - Remove pod and containers, then re-run to recreate"
  exit 1
}

if [ $# -ne 1 ]; then
  usage
fi

case "$1" in
  backend)
    ensure_pod
    ensure_backend
    ensure_frontend
    echo ""
    echo "Both services running in pod $POD_NAME:"
    echo "  Frontend: http://localhost:$FRONTEND_PORT"
    echo "  Backend:  http://localhost:$BACKEND_PORT"
    ;;
  frontend)
    ensure_pod
    ensure_frontend
    ;;
  stop)
    stop_all
    ;;
  rebuild)
    rebuild_all
    ;;
  *)
    usage
    ;;
esac
