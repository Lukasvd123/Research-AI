#!/bin/sh
set -e

log() { echo "$(date '+%H:%M:%S') - $1"; }

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

log "Server is running. Starting heartbeat (5m interval)."

# Heartbeat
while sleep 300; do
  curl -s -X POST "https://van-dee.nl/api_surf.php?action=heartbeat" -H "X-API-Token: $TOKEN"
  log "Heartbeat sent."
done