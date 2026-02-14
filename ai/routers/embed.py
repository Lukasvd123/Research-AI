import logging

import httpx
from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

from config import EMBED_URL

logger = logging.getLogger("ai.embed")

router = APIRouter()

EMBEDDINGS_URL = f"{EMBED_URL}/v1/embeddings"


@router.post("/embed")
async def embed(request: Request):
    try:
        body = await request.json()
    except Exception:
        return JSONResponse(status_code=400, content={"error": "Invalid JSON body"})

    try:
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
