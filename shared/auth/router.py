import secrets
import time
from collections import defaultdict

from fastapi import APIRouter, Header, Request
from fastapi.responses import JSONResponse

from shared.auth.config import ACCESS_TOKEN_EXPIRE_SECONDS, OAUTH_CREDENTIALS
from shared.auth.jwt_handler import create_access_token, create_refresh_token, decode_token
from shared.auth.models import TokenResponse

router = APIRouter(prefix="/auth", tags=["auth"])

# --- Simple in-memory rate limiter for /auth/token ---
_rate_window = 60  # seconds
_rate_max = 10  # max attempts per window per IP
_rate_store: dict[str, list[float]] = defaultdict(list)
_rate_last_cleanup = 0.0
_rate_cleanup_interval = 300  # full cleanup every 5 minutes


def _is_rate_limited(client_ip: str) -> bool:
    global _rate_last_cleanup
    now = time.monotonic()

    # Periodic full cleanup to prevent unbounded memory growth
    if now - _rate_last_cleanup > _rate_cleanup_interval:
        _rate_last_cleanup = now
        stale = [ip for ip, ts in _rate_store.items() if not ts or now - ts[-1] > _rate_window]
        for ip in stale:
            del _rate_store[ip]

    # Prune expired entries for this IP
    _rate_store[client_ip] = [t for t in _rate_store[client_ip] if now - t < _rate_window]
    if len(_rate_store[client_ip]) >= _rate_max:
        return True
    _rate_store[client_ip].append(now)
    return False


@router.post("/token", response_model=TokenResponse)
async def token(request: Request):
    client_ip = request.client.host if request.client else "unknown"
    if _is_rate_limited(client_ip):
        return JSONResponse(
            status_code=429,
            content={"error": "too_many_requests", "error_description": "Rate limit exceeded"},
        )

    # Support both JSON and form-encoded bodies
    content_type = request.headers.get("content-type", "")
    if "application/json" in content_type:
        data = await request.json()
    else:
        form = await request.form()
        data = dict(form)

    grant_type = data.get("grant_type")

    if grant_type == "client_credentials":
        username = data.get("username", "")
        password = data.get("password", "")

        expected = OAUTH_CREDENTIALS.get(username)
        if expected is None or not secrets.compare_digest(expected, password):
            return JSONResponse(
                status_code=401,
                content={"error": "invalid_client", "error_description": "Bad credentials"},
            )

        return TokenResponse(
            access_token=create_access_token(username),
            refresh_token=create_refresh_token(username),
            expires_in=ACCESS_TOKEN_EXPIRE_SECONDS,
        )

    if grant_type == "refresh_token":
        refresh = data.get("refresh_token", "")
        try:
            payload = decode_token(refresh)
            if payload.get("type") != "refresh":
                raise ValueError("not a refresh token")
            subject = payload["sub"]
        except Exception:
            return JSONResponse(
                status_code=401,
                content={"error": "invalid_grant", "error_description": "Invalid refresh token"},
            )

        return TokenResponse(
            access_token=create_access_token(subject),
            refresh_token=create_refresh_token(subject),
            expires_in=ACCESS_TOKEN_EXPIRE_SECONDS,
        )

    return JSONResponse(
        status_code=400,
        content={"error": "unsupported_grant_type"},
    )


@router.get("/validate")
async def validate(authorization: str = Header(default="")):
    if not authorization.startswith("Bearer "):
        return JSONResponse(
            status_code=401,
            content={"error": "invalid_token", "error_description": "Missing or malformed Authorization header"},
        )

    token_str = authorization[len("Bearer "):]
    try:
        payload = decode_token(token_str)
        if payload.get("type") != "access":
            raise ValueError("not an access token")
    except Exception:
        return JSONResponse(
            status_code=401,
            content={"error": "invalid_token", "error_description": "Token is invalid or expired"},
        )

    return JSONResponse(
        status_code=200,
        content={"status": "valid"},
        headers={
            "X-Auth-User": payload.get("sub", ""),
            "X-Auth-Scope": "authenticated",
        },
    )
