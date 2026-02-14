import httpx
from fastapi import APIRouter, Request
from starlette.responses import StreamingResponse

from config import CHAT_URL

router = APIRouter()

CHAT_COMPLETIONS_URL = f"{CHAT_URL}/v1/chat/completions"


@router.post("/completions")
async def chat_completions(request: Request):
    body = await request.json()
    stream = body.get("stream", False)

    if stream:
        return await _stream_response(body)
    return await _proxy_response(body)


async def _proxy_response(body: dict):
    async with httpx.AsyncClient(timeout=120.0) as client:
        resp = await client.post(CHAT_COMPLETIONS_URL, json=body)
        return resp.json()


async def _stream_response(body: dict):
    async def event_generator():
        async with httpx.AsyncClient(timeout=120.0) as client:
            async with client.stream("POST", CHAT_COMPLETIONS_URL, json=body) as resp:
                async for line in resp.aiter_lines():
                    if line:
                        yield f"{line}\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")
