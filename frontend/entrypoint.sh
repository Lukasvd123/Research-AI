#!/bin/sh
# Generate runtime config from environment variables before starting Caddy.
# This allows VITE_AUTH_USER/PASS to be set at deploy time, not build time.
cat > /srv/runtime-config.js <<EOF
window.__RUNTIME_CONFIG__ = {
  VITE_API_URL: "${VITE_API_URL:-}",
  VITE_AUTH_USER: "${VITE_AUTH_USER:-}",
  VITE_AUTH_PASS: "${VITE_AUTH_PASS:-}"
};
EOF

exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
