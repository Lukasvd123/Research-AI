import logging

import httpx
from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse
from starlette.responses import StreamingResponse

from config import CHAT_URL

logger = logging.getLogger("ai.chat")

router = APIRouter()

CHAT_COMPLETIONS_URL = f"{CHAT_URL}/v1/chat/completions"

# --- Validation limits ---
MAX_MESSAGES = 50
MAX_MESSAGE_CHARS = 30_000  # per message content
MAX_BODY_BYTES = 512 * 1024  # 512 KB total payload
ALLOWED_PARAMS = {"messages", "stream", "temperature", "top_p", "max_tokens", "stop", "model"}
MAX_TOKENS_LIMIT = 8192
TEMPERATURE_RANGE = (0.0, 2.0)


def _validate_body(body: dict) -> str | None:
    """Return an error message if the body is invalid, else None."""
    if not isinstance(body.get("messages"), list):
        return "messages must be a list"
    if len(body["messages"]) > MAX_MESSAGES:
        return f"too many messages (max {MAX_MESSAGES})"
    for i, msg in enumerate(body["messages"]):
        if not isinstance(msg, dict):
            return f"messages[{i}] must be an object"
        content = msg.get("content", "")
        if isinstance(content, str) and len(content) > MAX_MESSAGE_CHARS:
            return f"messages[{i}].content exceeds {MAX_MESSAGE_CHARS} characters"
    if "max_tokens" in body:
        try:
            mt = int(body["max_tokens"])
        except (TypeError, ValueError):
            return "max_tokens must be an integer"
        if mt < 1 or mt > MAX_TOKENS_LIMIT:
            return f"max_tokens must be between 1 and {MAX_TOKENS_LIMIT}"
    if "temperature" in body:
        try:
            t = float(body["temperature"])
        except (TypeError, ValueError):
            return "temperature must be a number"
        if t < TEMPERATURE_RANGE[0] or t > TEMPERATURE_RANGE[1]:
            return f"temperature must be between {TEMPERATURE_RANGE[0]} and {TEMPERATURE_RANGE[1]}"
    # Strip unknown parameters before forwarding
    unknown = set(body.keys()) - ALLOWED_PARAMS
    for key in unknown:
        del body[key]
    return None


@router.post("/completions")
async def chat_completions(request: Request):
    # Check payload size
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

    stream = body.get("stream", False)

    try:
        if stream:
            return await _stream_response(body)
        return await _proxy_response(body)
    except httpx.ConnectError:
        logger.error("Cannot connect to llama-server at %s", CHAT_COMPLETIONS_URL)
        return JSONResponse(status_code=502, content={"error": "AI model is unavailable"})
    except httpx.TimeoutException:
        logger.error("Timeout waiting for llama-server")
        return JSONResponse(status_code=504, content={"error": "AI model timed out"})
    except Exception:
        logger.exception("Unexpected error proxying chat request")
        return JSONResponse(status_code=500, content={"error": "Internal AI service error"})


async def _proxy_response(body: dict):
    async with httpx.AsyncClient(timeout=120.0, verify=True) as client:
        resp = await client.post(CHAT_COMPLETIONS_URL, json=body)
        if resp.status_code != 200:
            return JSONResponse(
                status_code=502,
                content={"error": "AI model returned an error"},
            )
        return resp.json()


async def _stream_response(body: dict):
    async def event_generator():
        async with httpx.AsyncClient(timeout=120.0, verify=True) as client:
            async with client.stream("POST", CHAT_COMPLETIONS_URL, json=body) as resp:
                async for line in resp.aiter_lines():
                    if line:
                        yield f"{line}\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")
