import os


CHAT_URL = os.environ.get("LLAMA_CHAT_URL", "http://127.0.0.1:8081")
EMBED_URL = os.environ.get("LLAMA_EMBED_URL", "http://127.0.0.1:8082")
AI_PORT = int(os.environ.get("AI_PORT", "8090"))
