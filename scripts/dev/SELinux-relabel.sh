#!/usr/bin/env sh
set -eu

sudo chcon -R -t container_file_t -l s0 frontend .
sudo chcon -R -t container_file_t -l s0 api .
sudo chcon -t container_file_t -l s0 caddy/Caddyfile.dev
