from fastapi import APIRouter, Header, Request, Response
from fastapi.responses import JSONResponse

from auth.config import ACCESS_TOKEN_EXPIRE_SECONDS, OAUTH_CREDENTIALS
from auth.jwt_handler import create_access_token, create_refresh_token, decode_token
from auth.models import TokenResponse

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/token", response_model=TokenResponse)
async def token(request: Request):
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
        if expected is None or expected != password:
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
        return Response(status_code=401)

    token_str = authorization[len("Bearer "):]
    try:
        payload = decode_token(token_str)
        if payload.get("type") != "access":
            return Response(status_code=401)
    except Exception:
        return Response(status_code=401)

    return Response(
        status_code=200,
        headers={
            "X-Auth-User": payload.get("sub", ""),
            "X-Auth-Scope": "authenticated",
        },
    )
