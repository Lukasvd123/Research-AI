import os

JWT_SECRET = os.environ.get("JWT_SECRET", "change-me-in-production")
JWT_ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_SECONDS = 86400      # 1 day
REFRESH_TOKEN_EXPIRE_SECONDS = 604800    # 7 days

# OAuth2 client credentials (loaded from env)
OAUTH_CREDENTIALS = {}

for key, val in os.environ.items():
    if key.startswith("OAUTH_") and key.endswith("_USER"):
        prefix = key[: -len("_USER")]  # e.g. "OAUTH_BACKEND"
        pass_key = f"{prefix}_PASS"
        password = os.environ.get(pass_key, "")
        if val and password:
            OAUTH_CREDENTIALS[val] = password
