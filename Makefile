.PHONY: up down watch watchui watchapi

ifeq ($(OS),Windows_NT)
  MKDIR_P = powershell -NoProfile -Command "New-Item -ItemType Directory -Force -Path"
else
  MKDIR_P = mkdir -p
endif

up:
	podman build -t research-ai-api:dev -f ./api/Containerfile .
	$(MKDIR_P) .caddy/data .caddy/config
	podman kube play kube/env.yaml kube/pod-dev.yaml

down:
	podman kube down kube/pod-dev.yaml

watch:
	podman pod logs -f research-ai-dev

watchapi:
	podman pod logs -f -c research-ai-dev-api research-ai-dev

watchui:
	podman pod logs -f -c research-ai-dev-frontend research-ai-dev
