import httpx
from fastapi import APIRouter, Request

from config import EMBED_URL

router = APIRouter()

EMBEDDINGS_URL = f"{EMBED_URL}/v1/embeddings"


@router.post("/embed")
async def embed(request: Request):
    body = await request.json()
    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.post(EMBEDDINGS_URL, json=body)
        return resp.json()
