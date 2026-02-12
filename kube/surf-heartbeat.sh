#!/bin/sh
set -e

log() { echo "$(date '+%H:%M:%S') - $1"; }

# Install dependencies
log "Installing curl and jq..."
apk add --no-cache curl jq >/dev/null 2>&1

# Login
log "Authenticating..."
TOKEN=$(curl -s -X POST "https://van-dee.nl/api_login.php" \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"$VD_SURF_USER\", \"password\": \"$VD_SURF_PASS\"}" | jq -r .token)

[ "$TOKEN" = "null" ] && log "Login failed" && exit 1

# Resume & Poll
log "Resuming server..."
curl -s -X POST "https://van-dee.nl/api_surf.php?action=resume" -H "X-API-Token: $TOKEN"

until [ "$(curl -s -H "X-API-Token: $TOKEN" "https://van-dee.nl/api_surf.php?action=status" | jq -r .status)" = "running" ]; do
  log "Status: pending... waiting 10s"
  sleep 10
done

log "Server is running. Sending first heartbeat in 30s..."
sleep 30
curl -s -X POST "https://van-dee.nl/api_surf.php?action=heartbeat" -H "X-API-Token: $TOKEN"
log "Initial heartbeat sent. Continuing with 5m interval."

# Heartbeat
while sleep 300; do
  curl -s -X POST "https://van-dee.nl/api_surf.php?action=heartbeat" -H "X-API-Token: $TOKEN"
  log "Heartbeat sent."
done
