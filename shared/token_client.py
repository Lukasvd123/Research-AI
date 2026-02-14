"""Client for obtaining and caching JWTs from remote servers."""

import time

import httpx


class TokenClient:
    """Authenticates against a remote server's /auth/token endpoint.

    Each instance caches its own token independently, so holding multiple
    TokenClient instances (one per remote server) never causes collisions.
    """

    def __init__(self, name: str, auth_url: str, username: str, password: str):
        self.name = name
        self.auth_url = auth_url.rstrip("/")
        self.username = username
        self.password = password
        self._access_token: str | None = None
        self._refresh_token: str | None = None
        self._expires_at: float = 0.0

    def _is_expired(self) -> bool:
        # Refresh 60 seconds before actual expiry
        return time.time() >= (self._expires_at - 60)

    async def get_token(self) -> str:
        """Return a valid access token, fetching or refreshing as needed."""
        if self._access_token and not self._is_expired():
            return self._access_token

        if self._refresh_token:
            try:
                return await self._refresh()
            except Exception:
                pass  # Fall through to full auth

        return await self._authenticate()

    async def _authenticate(self) -> str:
        """Full client_credentials grant against the remote server."""
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"{self.auth_url}/auth/token",
                json={
                    "grant_type": "client_credentials",
                    "username": self.username,
                    "password": self.password,
                },
                timeout=10,
            )
            resp.raise_for_status()
            data = resp.json()

        self._access_token = data["access_token"]
        self._refresh_token = data["refresh_token"]
        self._expires_at = time.time() + data.get("expires_in", 86400)
        return self._access_token

    async def _refresh(self) -> str:
        """Use refresh_token grant to get a new access token."""
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"{self.auth_url}/auth/token",
                json={
                    "grant_type": "refresh_token",
                    "refresh_token": self._refresh_token,
                },
                timeout=10,
            )
            resp.raise_for_status()
            data = resp.json()

        self._access_token = data["access_token"]
        self._refresh_token = data["refresh_token"]
        self._expires_at = time.time() + data.get("expires_in", 86400)
        return self._access_token

    async def auth_header(self) -> dict[str, str]:
        """Return an Authorization header dict ready for use with httpx."""
        token = await self.get_token()
        return {"Authorization": f"Bearer {token}"}
