.PHONY: up down watch wui wapi clear deploy logs clean

# Where the final combined YAML will be written
BUNDLE_DEST  := /etc/research-ai/bundle.yaml

# Where the systemd unit file will be written
UNIT_DEST    := /etc/containers/systemd/research-ai.kube

# dev rules:
up:
	podman build -t research-ai-api:dev -f ./api/Containerfile .
	mkdir -p .caddy/data .caddy/config
	podman kube play kube/env.yaml kube/pod-dev.yaml

down:
	podman kube down kube/pod-dev.yaml

labelSELinux:
	sudo chcon -R -t container_file_t -l s0 frontend .
	sudo chcon -R -t container_file_t -l s0 api .
	sudo chcon -t container_file_t -l s0 caddy/Caddyfile.dev

watch:
	podman pod logs -f research-ai-dev

wapi:
	podman logs -f research-ai-dev-api

wui:
	podman logs -f research-ai-dev-

clear:
	podman rm -f -a
	podman pod rm -f -a
	podman volume rm -f -a
	podman rmi -f -a


# prod rules:
deploy:
# build
	podman build -t research-ai-api:prod -f ./api/Containerfile .
	podman build -t research-ai-frontend:prod -f ./frontend/Containerfile .
# move and bundle manifest.yaml 
	sudo mkdir -p /etc/research-ai
	(cat k8s/env.yaml; echo "---"; cat k8s/pod.prod.yaml) | sudo tee $(BUNDLE_DEST) > /dev/null
# move quadlet .kube yaml
	sudo cp kube/research-ai.kube $(UNIT_DEST)
# (re)start quadlet service
	sudo systemctl daemon-reload
	sudo systemctl restart research-ai

logs:
	journalctl -fu research-ai

clean:
	sudo rm -f $(UNIT_DEST)
	sudo systemctl daemon-reload
	rm -f $(BUNDLE_DEST)
