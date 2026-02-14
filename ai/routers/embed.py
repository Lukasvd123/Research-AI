import logging

import httpx
from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

from config import EMBED_URL

logger = logging.getLogger("ai.embed")

router = APIRouter()

EMBEDDINGS_URL = f"{EMBED_URL}/v1/embeddings"

MAX_INPUT_CHARS = 30_000
MAX_BODY_BYTES = 256 * 1024  # 256 KB


def _validate_body(body: dict) -> str | None:
    """Return an error message if invalid, else None."""
    inp = body.get("input")
    if inp is None:
        return "input is required"
    if isinstance(inp, str):
        if len(inp) > MAX_INPUT_CHARS:
            return f"input exceeds {MAX_INPUT_CHARS} characters"
    elif isinstance(inp, list):
        for i, item in enumerate(inp):
            if not isinstance(item, str):
                return f"input[{i}] must be a string"
            if len(item) > MAX_INPUT_CHARS:
                return f"input[{i}] exceeds {MAX_INPUT_CHARS} characters"
    else:
        return "input must be a string or list of strings"
    return None


@router.post("/embed")
async def embed(request: Request):
    content_length = request.headers.get("content-length")
    if content_length and int(content_length) > MAX_BODY_BYTES:
        return JSONResponse(status_code=413, content={"error": "Payload too large"})

    try:
        body = await request.json()
    except Exception:
        return JSONResponse(status_code=400, content={"error": "Invalid JSON body"})

    error = _validate_body(body)
    if error:
        return JSONResponse(status_code=422, content={"error": error})

    try:
        # verify=True ensures TLS cert validation if EMBED_URL uses HTTPS.
        # Do not set verify=False — it would allow MITM attacks.
        async with httpx.AsyncClient(timeout=60.0, verify=True) as client:
            resp = await client.post(EMBEDDINGS_URL, json=body)
            if resp.status_code != 200:
                return JSONResponse(
                    status_code=502,
                    content={"error": "Embedding model returned an error"},
                )
            return resp.json()
    except httpx.ConnectError:
        logger.error("Cannot connect to embedding server at %s", EMBEDDINGS_URL)
        return JSONResponse(status_code=502, content={"error": "Embedding model is unavailable"})
    except httpx.TimeoutException:
        logger.error("Timeout waiting for embedding server")
        return JSONResponse(status_code=504, content={"error": "Embedding model timed out"})
    except Exception:
        logger.exception("Unexpected error proxying embed request")
        return JSONResponse(status_code=500, content={"error": "Internal AI service error"})
