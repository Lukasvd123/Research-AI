.PHONY: up down watch

up:
	podman build -t research-ai-api:dev -f ./api/Containerfile .
	mkdir -p .cache/node_modules .caddy/data .caddy/config
	podman kube play kube/env.yaml kube/pod-dev.yaml

down:
	podman kube down kube/pod-dev.yaml || true

watch:
	podman pod logs -f research-ai-dev
