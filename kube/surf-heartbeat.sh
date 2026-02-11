#!/bin/sh
# 1. Install dependencies
if ! command -v curl >/dev/null || ! command -v jq >/dev/null; then
  apk add --no-cache curl jq
fi

echo "Logging in to retrieve SURF token..."

# Use -i to see headers if debugging, but here we capture the raw body
# We use a temporary file to inspect the response if it fails
LOGIN_RESPONSE=$(curl -s -X POST "https://van-dee.nl/api_login.php" \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"$VD_SURF_USER\", \"password\": \"$VD_SURF_PASS\"}")

# Debug: Print the raw response if jq fails
SURF_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r .token 2>/dev/null)

if [ -z "$SURF_TOKEN" ] || [ "$SURF_TOKEN" = "null" ]; then
  echo "--- LOGIN FAILED ---"
  echo "Raw Response from Server:"
  echo "$LOGIN_RESPONSE"
  echo "--------------------"
  echo "Check if VD_SURF_USER and VD_SURF_PASS are set correctly in the ConfigMap."
  exit 1
fi

echo "Token retrieved successfully."

# 2. Resume the server
echo "Resuming SURF server..."
curl -s -X POST "https://van-dee.nl/api_surf.php?action=resume" \
     -H "X-API-Token: $SURF_TOKEN"

# 3. Poll until status is 'running'
while true; do
  STATUS_JSON=$(curl -s -H "X-API-Token: $SURF_TOKEN" "https://van-dee.nl/api_surf.php?action=status")
  STATUS=$(echo "$STATUS_JSON" | jq -r .status)
  if [ "$STATUS" = "running" ]; then
    echo "Server is running!"
    break
  fi
  echo "Current status: $STATUS. Waiting 10s..."
  sleep 10
done

# 4. Heartbeat loop (every 5 minutes)
echo "Starting heartbeat loop..."
while true; do
  curl -s -X POST "https://van-dee.nl/api_surf.php?action=heartbeat" \
       -H "X-API-Token: $SURF_TOKEN"
  sleep 300
done