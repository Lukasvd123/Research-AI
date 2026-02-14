import os
import sys

_DEFAULT_SECRET = "change-me-in-production"

JWT_SECRET = os.environ.get("JWT_SECRET", _DEFAULT_SECRET)
if JWT_SECRET == _DEFAULT_SECRET:
    print(
        "WARNING: JWT_SECRET is not set or uses the default value. "
        "Tokens are insecure. Set JWT_SECRET in env.yaml.",
        file=sys.stderr,
    )

JWT_ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_SECONDS = 86400      # 1 day
REFRESH_TOKEN_EXPIRE_SECONDS = 604800    # 7 days

# This server's credential (incoming auth)
OAUTH_CREDENTIALS = {}

_server_user = os.environ.get("SERVER_AUTH_USER", "")
_server_pass = os.environ.get("SERVER_AUTH_PASS", "")
if _server_user and _server_pass:
    OAUTH_CREDENTIALS[_server_user] = _server_pass

# Auto-discover remote servers: REMOTE_<NAME>_URL / _USER / _PASS
REMOTE_SERVERS: dict[str, dict[str, str]] = {}

_seen_prefixes: set[str] = set()
for key in os.environ:
    if key.startswith("REMOTE_") and key.endswith("_URL"):
        name = key[len("REMOTE_"):-len("_URL")]  # e.g. "AI", "NEO4J"
        if name in _seen_prefixes:
            continue
        _seen_prefixes.add(name)
        url = os.environ.get(f"REMOTE_{name}_URL", "")
        user = os.environ.get(f"REMOTE_{name}_USER", "")
        password = os.environ.get(f"REMOTE_{name}_PASS", "")
        if url and user and password:
            REMOTE_SERVERS[name.lower()] = {
                "url": url,
                "user": user,
                "pass": password,
            }
