from pydantic import BaseModel


class TokenRequest(BaseModel):
    grant_type: str
    username: str | None = None
    password: str | None = None
    refresh_token: str | None = None


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
