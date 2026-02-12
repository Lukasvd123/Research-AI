.PHONY: check up down resume watch logs-api logs-ui logs-caddy logs-heartbeat \
       restart-api restart-ui rebuild status health open \
       deploy deploy-logs clean

# ---------------------------------------------------------------------------
# Names
# ---------------------------------------------------------------------------
DEV_POD  := research-ai-dev
PROD_POD := research-ai-prod

# ---------------------------------------------------------------------------
# Production config (silently ignored when missing, i.e. on dev machines)
# ---------------------------------------------------------------------------
-include /opt/research-ai/config.env

CERT_DIR    := /etc/letsencrypt/live/reserachaiub.researchai.src.surf-hosted.nl
BUNDLE_DEST := /etc/research-ai/bundle.yaml

# ===========================================================================
#  Dev targets
# ===========================================================================

check:
	@command -v podman >/dev/null 2>&1 || { echo "ERROR: podman not found in PATH"; exit 1; }
	@echo "podman $$(podman --version | awk '{print $$3}') is available"

up: check
	podman build -t research-ai-backend:dev -f backend/Containerfile .
	mkdir -p .caddy/data .caddy/config
	-podman volume create research-ai-modules-pvc 2>/dev/null
	{ cat kube/env.yaml; echo "---"; cat kube/pod-dev.yaml; } | podman play kube -
	@echo ""
	@echo "Dev pod started.  http://localhost:8080/researchai/"

down:
	-podman pod rm -f $(DEV_POD) 2>/dev/null
	@echo "Dev pod removed."

resume:
	podman pod start $(DEV_POD)
	@echo "Dev pod resumed."

watch:
	podman pod logs -f $(DEV_POD)

logs-api:
	podman logs -f $(DEV_POD)-api

logs-ui:
	podman logs -f $(DEV_POD)-frontend

logs-caddy:
	podman logs -f $(DEV_POD)-caddy

logs-heartbeat:
	podman logs -f $(DEV_POD)-surf-heartbeat

restart-api:
	podman restart $(DEV_POD)-api

restart-ui:
	podman restart $(DEV_POD)-frontend

rebuild: down
	podman build -t research-ai-backend:dev --no-cache -f backend/Containerfile .
	mkdir -p .caddy/data .caddy/config
	-podman volume create research-ai-modules-pvc 2>/dev/null
	{ cat kube/env.yaml; echo "---"; cat kube/pod-dev.yaml; } | podman play kube -
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
#  Production targets
# ===========================================================================

define SYSTEM_CADDYFILE
reserachaiub.researchai.src.surf-hosted.nl {
	tls $(CERT_DIR)/fullchain.pem $(CERT_DIR)/privkey.pem

	# Heartbeat endpoint for watchdog
	handle /heartbeat {
		reverse_proxy 127.0.0.1:9100
	}

	# GitHub webhook
	handle /github-webhook* {
		reverse_proxy 127.0.0.1:9000
	}

	# Backend API - strip /researchai-api prefix
	handle_path /researchai-api/* {
		reverse_proxy 127.0.0.1:8000
	}

	# Frontend - strip /researchai prefix
	handle_path /researchai/* {
		reverse_proxy 127.0.0.1:3000
	}

	# Redirect /researchai to /researchai/
	redir /researchai /researchai/ permanent
}
endef
export SYSTEM_CADDYFILE

deploy: check
	# ---- Build images ----
	podman build -t research-ai-backend:prod -f backend/Containerfile .
	podman build -t research-ai-frontend:prod \
		--build-arg VITE_API_URL=$(VITE_API_URL) \
		--build-arg VITE_BASE=$(VITE_BASE) \
		-f frontend/Containerfile .
	# ---- Bundle manifest ----
	sudo mkdir -p /etc/research-ai
	{ cat /opt/research-ai/env.yaml; echo "---"; cat kube/pod-prod.yaml; } | sudo tee $(BUNDLE_DEST) > /dev/null
	# ---- Stop existing pod ----
	-podman pod rm -f $(PROD_POD) 2>/dev/null
	# ---- Play ----
	podman play kube $(BUNDLE_DEST)
	# ---- System Caddy ----
	echo "$$SYSTEM_CADDYFILE" | sudo tee /etc/caddy/Caddyfile > /dev/null
	sudo systemctl reload caddy
	# ---- Heartbeat receiver ----
	sudo systemctl start heartbeat-receiver.service 2>/dev/null || true
	sudo systemctl enable heartbeat-receiver.service 2>/dev/null || true
	@echo ""
	@echo "Production deploy complete."
	@echo "  Backend:  127.0.0.1:8000"
	@echo "  Frontend: 127.0.0.1:3000"

deploy-logs:
	journalctl -fu research-ai-prod

clean:
	-podman pod rm -f $(PROD_POD) 2>/dev/null
	sudo rm -f $(BUNDLE_DEST)
	@echo "Production pod removed and bundle cleaned."
