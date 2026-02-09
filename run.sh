#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Research-AI Interactive Dev Launcher (Linux/Mac)
# ============================================================================
# Double-click friendly — opens terminal with interactive menu.
# All containers communicate through localhost ports (like separate servers).
# All actions are logged to the logs/ directory for crash diagnostics.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Log setup ---
LOGDIR="$SCRIPT_DIR/logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/run_$(date '+%Y-%m-%d_%H%M%S').log"

# --- Container names ---
CADDY_CTR="research-ai-caddy-dev"
FRONTEND_CTR="research-ai-frontend-dev"
BACKEND_CTR="research-ai-backend-dev"
CADDY_IMG="research-ai-caddy-dev"
FRONTEND_IMG="research-ai-frontend-dev"
BACKEND_IMG="research-ai-backend-dev"

# --- Ports ---
CADDY_PORT=8080
FRONTEND_PORT=5173
BACKEND_PORT=8000

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Runtime detection variable ---
RT=""
KEEP_ALIVE=0
CLEANUP_DONE=0

# ============================================================================
# Logging
# ============================================================================

log() {
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  echo -e "  [${ts}] $1"
  # Strip ANSI color codes for the log file
  echo "[$ts] $(echo "$1" | sed 's/\x1b\[[0-9;]*m//g')" >> "$LOGFILE"
}

log_silent() {
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "[$ts] $1" >> "$LOGFILE"
}

log "=========================================="
log "Research-AI Dev Launcher started"
log "Log file: $LOGFILE"
log "=========================================="

# ============================================================================
# Utility functions
# ============================================================================

print_header() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "  ╔══════════════════════════════════════╗"
  echo "  ║        Research-AI Dev Launcher      ║"
  echo "  ╚══════════════════════════════════════╝"
  echo -e "${NC}"
}

print_status() {
  echo -e "${GREEN}[✓]${NC} $1"
}

print_warn() {
  echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
  echo -e "${RED}[✗]${NC} $1"
}

# ============================================================================
# Podman / Docker auto-install
# ============================================================================

detect_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "$ID"
  else
    echo "unknown"
  fi
}

install_podman() {
  local distro
  distro=$(detect_distro)

  echo ""
  print_warn "Podman is not installed. Attempting to install..."
  log_silent "Attempting to install podman on distro: $distro"
  echo ""

  case "$distro" in
    ubuntu|debian|linuxmint|pop)
      sudo apt-get update -qq && sudo apt-get install -y podman
      ;;
    arch|manjaro|endeavouros)
      sudo pacman -S --noconfirm podman
      ;;
    alpine)
      sudo apk add podman
      ;;
    fedora|centos|rhel|rocky|almalinux)
      sudo dnf install -y podman
      ;;
    opensuse*|sles)
      sudo zypper install -y podman
      ;;
    *)
      print_error "Unknown distro: $distro"
      log "ERROR: Unknown distro: $distro — cannot auto-install podman"
      print_warn "Please install podman manually, or press Enter to try docker instead."
      read -r
      return 1
      ;;
  esac

  if command -v podman &>/dev/null; then
    print_status "Podman installed successfully!"
    log_silent "Podman installed successfully"
    return 0
  else
    print_error "Podman installation failed."
    log "ERROR: Podman installation failed"
    return 1
  fi
}

ensure_runtime() {
  # Check podman first
  if command -v podman &>/dev/null; then
    RT=podman
    print_status "Using container runtime: podman"
    log_silent "Runtime detected: podman"
    return
  fi

  # Try to install podman
  if install_podman; then
    RT=podman
    return
  fi

  # Fallback to docker
  if command -v docker &>/dev/null; then
    RT=docker
    print_status "Using container runtime: docker"
    log_silent "Runtime detected: docker"
    return
  fi

  print_error "Neither podman nor docker could be found or installed."
  log "ERROR: No container runtime available"
  echo "Please install one manually and try again."
  echo ""
  echo "Press Enter to exit..."
  read -r
  exit 1
}

# ============================================================================
# Container management — each container runs independently on its own port
# ============================================================================

is_running() {
  $RT container inspect --format '{{.State.Running}}' "$1" 2>/dev/null | grep -q true
}

container_exists() {
  $RT container inspect "$1" &>/dev/null 2>&1
}

build_caddy() {
  echo ""
  echo -e "${CYAN}Building Caddy proxy image...${NC}"
  log_silent "Building Caddy proxy image..."
  if ! $RT build -t "$CADDY_IMG" \
    -f "$SCRIPT_DIR/dev/Containerfile.caddy" \
    "$SCRIPT_DIR" 2>> "$LOGFILE"; then
    log "ERROR: Caddy image build failed"
    print_error "Caddy image build failed! Check log: $LOGFILE"
    return 1
  fi
  log_silent "Caddy image built successfully"
}

build_backend() {
  echo ""
  echo -e "${CYAN}Building backend image...${NC}"
  log_silent "Building backend image..."
  if ! $RT build -t "$BACKEND_IMG" \
    -f "$SCRIPT_DIR/dev/Containerfile.backend" \
    "$SCRIPT_DIR" 2>> "$LOGFILE"; then
    log "ERROR: Backend image build failed"
    print_error "Backend image build failed! Check log: $LOGFILE"
    return 1
  fi
  log_silent "Backend image built successfully"
}

build_frontend() {
  echo ""
  echo -e "${CYAN}Building frontend image...${NC}"
  log_silent "Building frontend image..."
  if ! $RT build -t "$FRONTEND_IMG" \
    -f "$SCRIPT_DIR/dev/Containerfile.frontend" \
    "$SCRIPT_DIR" 2>> "$LOGFILE"; then
    log "ERROR: Frontend image build failed"
    print_error "Frontend image build failed! Check log: $LOGFILE"
    return 1
  fi
  log_silent "Frontend image built successfully"
}

start_caddy() {
  if is_running "$CADDY_CTR"; then
    print_status "Caddy proxy already running on port $CADDY_PORT"
    log_silent "Caddy proxy already running"
    return
  fi

  # Remove old container if exists
  if container_exists "$CADDY_CTR"; then
    $RT rm -f "$CADDY_CTR" &>/dev/null || true
  fi

  if ! build_caddy; then
    return 1
  fi

  log_silent "Starting Caddy proxy on port $CADDY_PORT..."
  echo "Starting Caddy proxy on port $CADDY_PORT..."
  if ! $RT run -d --name "$CADDY_CTR" \
    -p "$CADDY_PORT:80" \
    "$CADDY_IMG" >> "$LOGFILE" 2>&1; then
    log "ERROR: Failed to start Caddy container"
    print_error "Failed to start Caddy! Check log: $LOGFILE"
    return 1
  fi

  print_status "Caddy proxy running on http://localhost:$CADDY_PORT"
  log_silent "Caddy proxy running on http://localhost:$CADDY_PORT"
}

start_backend() {
  if is_running "$BACKEND_CTR"; then
    print_status "Backend already running on port $BACKEND_PORT"
    log_silent "Backend already running"
    return
  fi

  # Remove old container if exists
  if container_exists "$BACKEND_CTR"; then
    $RT rm -f "$BACKEND_CTR" &>/dev/null || true
  fi

  if ! build_backend; then
    return 1
  fi

  log_silent "Starting backend on port $BACKEND_PORT..."
  echo "Starting backend on port $BACKEND_PORT..."
  if ! $RT run -d --name "$BACKEND_CTR" \
    -p "$BACKEND_PORT:8000" \
    -e "CORS_ORIGINS=http://localhost:$CADDY_PORT,http://localhost:$FRONTEND_PORT" \
    -v "$SCRIPT_DIR/backend:/app:z" \
    "$BACKEND_IMG" >> "$LOGFILE" 2>&1; then
    log "ERROR: Failed to start backend container"
    print_error "Failed to start backend! Check log: $LOGFILE"
    return 1
  fi

  print_status "Backend running on http://localhost:$BACKEND_PORT"
  log_silent "Backend running on http://localhost:$BACKEND_PORT"
}

start_frontend() {
  if is_running "$FRONTEND_CTR"; then
    print_status "Frontend already running on port $FRONTEND_PORT"
    log_silent "Frontend already running"
    return
  fi

  # Remove old container if exists
  if container_exists "$FRONTEND_CTR"; then
    $RT rm -f "$FRONTEND_CTR" &>/dev/null || true
  fi

  if ! build_frontend; then
    return 1
  fi

  log_silent "Starting frontend on port $FRONTEND_PORT..."
  echo "Starting frontend on port $FRONTEND_PORT..."
  if ! $RT run -d --name "$FRONTEND_CTR" \
    -p "$FRONTEND_PORT:5173" \
    -v "$SCRIPT_DIR/frontend/src:/app/src:z" \
    -v "$SCRIPT_DIR/frontend/public:/app/public:z" \
    -v "$SCRIPT_DIR/frontend/index.html:/app/index.html:z" \
    -v "$SCRIPT_DIR/frontend/vite.config.ts:/app/vite.config.ts:z" \
    -v "$SCRIPT_DIR/frontend/tsconfig.json:/app/tsconfig.json:z" \
    -v "$SCRIPT_DIR/frontend/tsconfig.app.json:/app/tsconfig.app.json:z" \
    -v research-ai-node-modules:/app/node_modules \
    -e "VITE_API_URL=http://localhost:$CADDY_PORT/researchai-api" \
    -e "VITE_BASE=/researchai/" \
    "$FRONTEND_IMG" >> "$LOGFILE" 2>&1; then
    log "ERROR: Failed to start frontend container"
    print_error "Failed to start frontend! Check log: $LOGFILE"
    return 1
  fi

  print_status "Frontend running on http://localhost:$FRONTEND_PORT"
  log_silent "Frontend running on http://localhost:$FRONTEND_PORT"
}

stop_all() {
  echo ""
  echo "Stopping all dev containers..."
  log_silent "Stopping all dev containers..."
  for ctr in "$CADDY_CTR" "$FRONTEND_CTR" "$BACKEND_CTR"; do
    if container_exists "$ctr"; then
      $RT stop "$ctr" 2>/dev/null || true
      $RT rm "$ctr" 2>/dev/null || true
      print_status "Stopped $ctr"
      log_silent "Stopped $ctr"
    fi
  done
  echo ""
  print_status "All containers stopped."
  log_silent "All containers stopped"
}

resume_all() {
  echo ""
  echo "Resuming dev containers..."
  log_silent "Resuming dev containers..."
  for ctr in "$BACKEND_CTR" "$FRONTEND_CTR" "$CADDY_CTR"; do
    if container_exists "$ctr"; then
      $RT start "$ctr" 2>/dev/null || true
      print_status "Resumed $ctr"
      log_silent "Resumed $ctr"
    else
      print_warn "$ctr does not exist — run 'Both' first to create it."
      log_silent "WARN: $ctr does not exist"
    fi
  done
}

# ============================================================================
# Safe log viewer — Ctrl+C returns to dev panel instead of killing everything
# ============================================================================

view_container_logs() {
  local container="$1"
  # Temporarily ignore SIGINT in the parent so Ctrl+C only stops the logs
  # command (which runs in a subshell with default SIGINT handling).
  trap '' INT
  ( trap - INT; exec $RT logs -f "$container" 2>&1 ) || true
  # Restore the SIGINT trap
  if [ "$KEEP_ALIVE" = "1" ]; then
    trap 'true' INT
  else
    trap - INT
  fi
}

# ============================================================================
# Dev panel
# ============================================================================

dev_panel() {
  # Make Ctrl+C safe inside the dev panel loop (won't kill the script)
  trap 'true' INT

  while true; do
    echo ""
    echo -e "${CYAN}${BOLD}═══ Dev Panel ═══${NC}"
    echo ""
    echo -e "  ${BOLD}Access URLs:${NC}"
    echo -e "    App (via Caddy):  ${GREEN}http://localhost:$CADDY_PORT/researchai/${NC}"
    echo -e "    API (via Caddy):  ${GREEN}http://localhost:$CADDY_PORT/researchai-api/health${NC}"
    echo -e "    Frontend direct:  http://localhost:$FRONTEND_PORT"
    echo -e "    Backend direct:   http://localhost:$BACKEND_PORT"
    echo ""
    echo -e "  ${BOLD}Log file:${NC} $LOGFILE"
    echo ""
    echo -e "  ${BOLD}Commands:${NC}"
    echo "    [1] Show frontend logs"
    echo "    [2] Show backend logs"
    echo "    [3] Show caddy logs"
    echo "    [4] Restart frontend"
    echo "    [5] Restart backend"
    echo "    [6] Rebuild frontend (full image rebuild)"
    echo "    [7] Rebuild backend (full image rebuild)"
    echo "    [8] Show container status"
    echo "    [9] Open in browser"
    echo "    [0] Stop all & exit"
    echo ""
    echo -n "  Select option: "
    read -r choice

    log_silent "Dev panel selection: $choice"

    case "$choice" in
      1)
        echo -e "\n${CYAN}--- Frontend logs (Ctrl+C to return) ---${NC}"
        log_silent "Viewing frontend logs"
        view_container_logs "$FRONTEND_CTR"
        ;;
      2)
        echo -e "\n${CYAN}--- Backend logs (Ctrl+C to return) ---${NC}"
        log_silent "Viewing backend logs"
        view_container_logs "$BACKEND_CTR"
        ;;
      3)
        echo -e "\n${CYAN}--- Caddy logs (Ctrl+C to return) ---${NC}"
        log_silent "Viewing caddy logs"
        view_container_logs "$CADDY_CTR"
        ;;
      4)
        echo "Restarting frontend..."
        log_silent "Restarting frontend..."
        $RT restart "$FRONTEND_CTR" 2>/dev/null || true
        print_status "Frontend restarted."
        log_silent "Frontend restarted"
        ;;
      5)
        echo "Restarting backend..."
        log_silent "Restarting backend..."
        $RT restart "$BACKEND_CTR" 2>/dev/null || true
        print_status "Backend restarted."
        log_silent "Backend restarted"
        ;;
      6)
        echo "Rebuilding frontend..."
        log_silent "Rebuilding frontend (full rebuild)..."
        $RT rm -f "$FRONTEND_CTR" 2>/dev/null || true
        build_frontend
        start_frontend
        print_status "Frontend rebuilt and started."
        log_silent "Frontend rebuilt and started"
        ;;
      7)
        echo "Rebuilding backend..."
        log_silent "Rebuilding backend (full rebuild)..."
        $RT rm -f "$BACKEND_CTR" 2>/dev/null || true
        build_backend
        start_backend
        print_status "Backend rebuilt and started."
        log_silent "Backend rebuilt and started"
        ;;
      8)
        echo ""
        echo -e "${CYAN}Container status:${NC}"
        log_silent "Checking container status..."
        for ctr in "$CADDY_CTR" "$FRONTEND_CTR" "$BACKEND_CTR"; do
          if is_running "$ctr"; then
            echo -e "  ${GREEN}●${NC} $ctr — running"
            log_silent "Status: $ctr — running"
          elif container_exists "$ctr"; then
            echo -e "  ${YELLOW}●${NC} $ctr — stopped"
            log_silent "Status: $ctr — stopped"
          else
            echo -e "  ${RED}●${NC} $ctr — not created"
            log_silent "Status: $ctr — not created"
          fi
        done
        ;;
      9)
        local url="http://localhost:$CADDY_PORT/researchai/"
        echo "Opening $url ..."
        log_silent "Opening browser: $url"
        if command -v xdg-open &>/dev/null; then
          xdg-open "$url" 2>/dev/null &
        elif command -v open &>/dev/null; then
          open "$url" 2>/dev/null &
        else
          print_warn "Could not detect browser opener. Visit: $url"
        fi
        ;;
      0)
        log_silent "User requested stop all and exit"
        stop_all
        CLEANUP_DONE=1
        exit 0
        ;;
      *)
        print_warn "Invalid option: $choice"
        ;;
    esac
  done
}

# ============================================================================
# Lifetime menu
# ============================================================================

lifetime_menu() {
  echo ""
  echo -e "  ${BOLD}Container lifetime:${NC}"
  echo "    [1] Keep alive while this window is open"
  echo "    [2] Run indefinitely (survive after script closes)"
  echo ""
  echo -n "  Select option: "
  read -r lifetime_choice

  case "$lifetime_choice" in
    1)
      KEEP_ALIVE=1
      log_silent "Lifetime: Keep alive while window open"
      trap 'if [ "$CLEANUP_DONE" != "1" ]; then CLEANUP_DONE=1; echo ""; log "Window closing — stopping containers..."; stop_all; fi' EXIT
      ;;
    2)
      KEEP_ALIVE=0
      log_silent "Lifetime: Run indefinitely"
      ;;
    *)
      print_warn "Invalid choice, defaulting to 'keep alive while window open'"
      KEEP_ALIVE=1
      log_silent "Lifetime: Keep alive while window open (default)"
      trap 'if [ "$CLEANUP_DONE" != "1" ]; then CLEANUP_DONE=1; echo ""; log "Window closing — stopping containers..."; stop_all; fi' EXIT
      ;;
  esac
}

# ============================================================================
# Main menu
# ============================================================================

main_menu() {
  print_header
  ensure_runtime

  echo ""
  echo -e "  ${BOLD}What would you like to run?${NC}"
  echo "    [1] Frontend only"
  echo "    [2] Backend only"
  echo "    [3] Both (frontend + backend + Caddy proxy)"
  echo "    [4] Shut down all dev containers"
  echo "    [5] Resume existing containers"
  echo ""
  echo -n "  Select option: "
  read -r main_choice

  log_silent "Main menu selection: $main_choice"

  case "$main_choice" in
    1)
      log_silent "Mode: Frontend only"
      lifetime_menu
      start_frontend
      start_caddy
      dev_panel
      ;;
    2)
      log_silent "Mode: Backend only"
      lifetime_menu
      start_backend
      start_caddy
      dev_panel
      ;;
    3)
      log_silent "Mode: Both (frontend + backend + Caddy)"
      lifetime_menu
      start_backend
      start_frontend
      start_caddy
      dev_panel
      ;;
    4)
      log_silent "Mode: Shut down all"
      stop_all
      echo ""
      echo "Press Enter to exit..."
      read -r
      ;;
    5)
      log_silent "Mode: Resume existing"
      resume_all
      dev_panel
      ;;
    *)
      print_error "Invalid option: $main_choice"
      log "ERROR: Invalid main menu option: $main_choice"
      echo ""
      echo "Press Enter to exit..."
      read -r
      exit 1
      ;;
  esac
}

# Add final log entry on exit
trap 'log_silent "Script exiting"; log_silent "=========================================="' EXIT

# --- Entry point ---
main_menu
