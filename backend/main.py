import os
from datetime import datetime
import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List

from auth.router import router as auth_router

class Fruit(BaseModel):
    name: str

class Fruits(BaseModel):
    fruits: List[Fruit]

app = FastAPI(debug=os.environ.get("FASTAPI_DEBUG", "").lower() in ("1", "true"))

cors_env = os.environ.get("CORS_ORIGINS", "http://localhost:5173,http://localhost:3000")
origins = [o.strip() for o in cors_env.split(",")]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router)

memory_db = {"fruits": []}

@app.get("/health")
def health():
    return {
        "status": "ok",
        "service": "ResearchAI Backend",
        "time": datetime.now().isoformat(),
        "fruit_count": len(memory_db["fruits"]),
    }

@app.get("/fruits", response_model=Fruits)
def get_fruits():
    return Fruits(fruits=memory_db["fruits"])

@app.post("/fruits")
def add_fruit(fruit: Fruit):
    memory_db["fruits"].append(fruit)
    return {"name": fruit.name, "total": len(memory_db["fruits"])}

@app.delete("/fruits")
def clear_fruits():
    memory_db["fruits"].clear()
    return {"status": "cleared"}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
