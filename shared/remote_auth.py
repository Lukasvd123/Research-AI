"""Registry of TokenClient instances for remote servers.

Auto-discovers REMOTE_<NAME>_URL/USER/PASS from shared.auth.config
and creates one TokenClient per remote server.

Usage:
    from shared.remote_auth import get_remote_client
    client = get_remote_client("ai")
    headers = await client.auth_header()
"""

from shared.auth.config import REMOTE_SERVERS
from shared.token_client import TokenClient

_clients: dict[str, TokenClient] = {}

for _name, _cfg in REMOTE_SERVERS.items():
    _clients[_name] = TokenClient(
        name=_name,
        auth_url=_cfg["url"],
        username=_cfg["user"],
        password=_cfg["pass"],
    )


def get_remote_client(name: str) -> TokenClient:
    """Return the TokenClient for the named remote server.

    Raises KeyError if no REMOTE_<NAME>_* env vars were configured.
    """
    key = name.lower()
    if key not in _clients:
        available = ", ".join(sorted(_clients)) or "(none)"
        raise KeyError(
            f"No remote server '{name}' configured. Available: {available}"
        )
    return _clients[key]


def list_remote_servers() -> list[str]:
    """Return names of all configured remote servers."""
    return sorted(_clients)
