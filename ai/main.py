from datetime import datetime

from fastapi import FastAPI

from routers import chat, embed
from shared.auth.router import router as auth_router

app = FastAPI(title="Research-AI AI Service")

app.include_router(auth_router)
app.include_router(chat.router, prefix="/chat")
app.include_router(embed.router)


@app.get("/health")
def health():
    return {
        "status": "ok",
        "service": "Research-AI AI",
        "time": datetime.now().isoformat(),
    }
