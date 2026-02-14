.PHONY: check dev dev-down up down resume watch logs-api logs-ui logs-caddy logs-heartbeat \
       restart-api restart-ui rebuild status health open \
       backend frontend \
       ai-start ai-stop ai-deploy ai-status ai-logs \
       all all-down deploy deploy-logs clean

# ---------------------------------------------------------------------------
# Names
# ---------------------------------------------------------------------------
DEV_POD  := research-ai-dev
PROD_POD := research-ai-prod

# ---------------------------------------------------------------------------
# Production config (silently ignored when missing, i.e. on dev machines)
# ---------------------------------------------------------------------------
-include /opt/research-ai/config.env

BUNDLE_DEST := /etc/research-ai/bundle.yaml

# ===========================================================================
#  Dev targets
# ===========================================================================

check:
	@command -v podman >/dev/null 2>&1 || { echo "ERROR: podman not found in PATH"; exit 1; }
	@echo "podman $$(podman --version | awk '{print $$3}') is available"

dev: check
	@podman pod rm -f $(DEV_POD) 2>/dev/null || true
	@echo ""
	@echo "Building backend image..."
	@podman build -t research-ai-backend:dev -f backend/Containerfile .
	@mkdir -p .caddy/data .caddy/config
	@echo ""
	@echo "Starting dev pod..."
	@{ cat kube/env.yaml; echo "---"; cat kube/pod-dev.yaml; } | podman play kube -
	@echo ""
	@echo "Dev pod started.  http://localhost:8080/researchai/"

up: dev

dev-down:
	@-podman pod rm -f $(DEV_POD) 2>/dev/null
	@echo "Dev pod removed."

down: dev-down

resume:
	@podman pod start $(DEV_POD)
	@echo "Dev pod resumed."

watch:
	@podman pod logs -f $(DEV_POD)

logs-api:
	@podman logs -f $(DEV_POD)-api

logs-ui:
	@podman logs -f $(DEV_POD)-frontend

logs-caddy:
	@podman logs -f $(DEV_POD)-caddy

logs-heartbeat:
	@podman logs -f $(DEV_POD)-surf-heartbeat

restart-api:
	@podman restart $(DEV_POD)-api

restart-ui:
	@podman restart $(DEV_POD)-frontend

rebuild: dev-down
	@echo "Rebuilding backend image (no cache)..."
	@podman build -t research-ai-backend:dev --no-cache -f backend/Containerfile .
	@mkdir -p .caddy/data .caddy/config
	@echo ""
	@echo "Starting dev pod..."
	@{ cat kube/env.yaml; echo "---"; cat kube/pod-dev.yaml; } | podman play kube -
	@echo ""
	@echo "Rebuild complete."

status:
	@echo "=== Pod ==="
	@podman pod ps --filter name=$(DEV_POD) 2>/dev/null || true
	@echo ""
	@echo "=== Containers ==="
	@podman ps -a --filter pod=$(DEV_POD) 2>/dev/null || true

health:
	@printf "Frontend: "; curl -sf -o /dev/null -w '%{http_code}\n' http://localhost:8080/researchai/ 2>/dev/null || echo "FAIL"
	@printf "Backend:  "; curl -sf -o /dev/null -w '%{http_code}\n' http://localhost:8080/researchai-api/health 2>/dev/null || echo "FAIL"

open:
	xdg-open http://localhost:8080/researchai/

# ===========================================================================
#  Individual service targets
# ===========================================================================

backend: check
	@podman build -t research-ai-backend:dev -f backend/Containerfile .
	@echo "Backend image built."

frontend: check
	@podman build -t research-ai-frontend:dev -f frontend/Containerfile .
	@echo "Frontend image built."

# ===========================================================================
#  AI service targets (native systemd, not containerized)
# ===========================================================================

ai-start:
	@echo "Starting AI service..."
	@/home/lvandee/Research-AI/ai/scripts/start-ai.sh

ai-stop:
	@echo "Stopping AI service..."
	@/home/lvandee/Research-AI/ai/scripts/stop-ai.sh

ai-deploy:
	@echo "---- Installing AI systemd service ----"
	@sudo cp kube/research-ai-ai.service /etc/systemd/system/
	@sudo systemctl daemon-reload
	@sudo systemctl enable research-ai-ai.service
	@sudo systemctl start research-ai-ai.service
	@echo "AI service deployed and started."

ai-status:
	@printf "FastAPI:     "; curl -sf -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8090/health 2>/dev/null || echo "FAIL"
	@printf "Chat LLM:   "; curl -sf -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8081/health 2>/dev/null || echo "FAIL"
	@printf "Embed LLM:  "; curl -sf -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8082/health 2>/dev/null || echo "FAIL"

ai-logs:
	journalctl -fu research-ai-ai.service

# ===========================================================================
#  Production targets
# ===========================================================================

deploy: check
	@echo "---- Build images ----"
	@podman build -t research-ai-backend:prod -f backend/Containerfile .
	@podman build -t research-ai-frontend:prod \
		--build-arg VITE_API_URL=$(VITE_API_URL) \
		--build-arg VITE_BASE=$(VITE_BASE) \
		-f frontend/Containerfile .
	@echo ""
	@echo "---- Bundle manifest ----"
	@sudo mkdir -p /etc/research-ai
	@{ cat /opt/research-ai/env.yaml; echo "---"; cat kube/pod-prod.yaml; } | sudo tee $(BUNDLE_DEST) > /dev/null
	@echo ""
	@echo "---- Stop existing pod ----"
	@-podman pod rm -f $(PROD_POD) 2>/dev/null
	@echo ""
	@echo "---- Play ----"
	@podman play kube $(BUNDLE_DEST)
	@echo ""
	@echo "---- System Caddy ----"
	@sudo cp kube/Caddyfile.system /etc/caddy/Caddyfile
	@sudo systemctl reload caddy
	@echo ""
	@echo "---- Boot service ----"
	@sudo cp kube/research-ai-boot.service /etc/systemd/system/
	@sudo systemctl daemon-reload
	@sudo systemctl enable research-ai-boot.service
	@echo ""
	@echo "Production deploy complete."
	@echo "  Backend:  127.0.0.1:8000"
	@echo "  Frontend: 127.0.0.1:3000"

all: deploy ai-deploy
	@echo ""
	@echo "Full production stack deployed (pod + AI service)."

all-down:
	@-podman pod rm -f $(PROD_POD) 2>/dev/null
	@sudo systemctl stop research-ai-ai.service 2>/dev/null || true
	@echo "All services stopped."

deploy-logs:
	journalctl -fu research-ai-prod

clean:
	@-podman pod rm -f $(PROD_POD) 2>/dev/null
	@sudo rm -f $(BUNDLE_DEST)
	@echo "Production pod removed and bundle cleaned."
