#!/bin/sh
# Authenticate server-side at container start — credentials never reach the browser.
# Only the resulting JWT tokens are written to runtime-config.js.

AUTH_USER="${VITE_AUTH_USER:-${SERVER_AUTH_USER:-}}"
AUTH_PASS="${VITE_AUTH_PASS:-${SERVER_AUTH_PASS:-}}"
API_URL="${VITE_API_URL:-http://127.0.0.1:8000}"

fetch_token() {
  curl -sf -X POST "${API_URL}/auth/token" \
    -H "Content-Type: application/json" \
    -d "{\"grant_type\":\"client_credentials\",\"username\":\"${AUTH_USER}\",\"password\":\"${AUTH_PASS}\"}"
}

write_config() {
  _resp="$1"
  _access=$(echo "$_resp" | jq -r '.access_token')
  _refresh=$(echo "$_resp" | jq -r '.refresh_token')
  cat > /srv/runtime-config.js <<JSEOF
window.__RUNTIME_CONFIG__ = {
  VITE_API_URL: "${VITE_API_URL:-}",
  VITE_AUTH_TOKEN: "${_access}",
  VITE_REFRESH_TOKEN: "${_refresh}"
};
JSEOF
}

# Write a config with no tokens (fallback if auth is not configured or fails)
write_empty_config() {
  cat > /srv/runtime-config.js <<JSEOF
window.__RUNTIME_CONFIG__ = {
  VITE_API_URL: "${VITE_API_URL:-}"
};
JSEOF
}

if [ -n "$AUTH_USER" ] && [ -n "$AUTH_PASS" ]; then
  echo "[frontend] Authenticating against ${API_URL}..."
  TOKEN_RESP=""
  for i in $(seq 1 30); do
    TOKEN_RESP=$(fetch_token) && break
    TOKEN_RESP=""
    echo "[frontend] Backend not ready, retrying ($i/30)..."
    sleep 2
  done

  if [ -n "$TOKEN_RESP" ]; then
    write_config "$TOKEN_RESP"
    echo "[frontend] Token obtained — credentials kept server-side."

    # Background: refresh token every 20 hours (tokens last 24h)
    (
      while true; do
        sleep 72000
        echo "[frontend] Refreshing token..."
        NEW_RESP=$(fetch_token) || continue
        write_config "$NEW_RESP"
        echo "[frontend] Token refreshed."
      done
    ) &
  else
    echo "[frontend] WARNING: Could not authenticate after 30 attempts."
    write_empty_config
  fi
else
  write_empty_config
fi

exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
