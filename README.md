# Project Setup

## Configuration

This project requires a local environment configuration file that is not tracked in git for security reasons.

To set this up:

1.  **Copy the example file:**
    ```bash
    cp kube/env.yaml.example kube/env.yaml
    ```
2.  **Add credentials:** Open the newly created `kube/env.yaml` and fill in your specific values/credentials.

## Makefile Usage

Use `make` to manage the application lifecycle.

| Command | Description |
| --- | --- |
| **Development** |  |
| `make up` | Builds images and starts the local Podman pod. |
| `make down` | Stops the local pod. |
| `make watch` | Tails logs for the whole pod (use `wapi` / `wui` for specific logs). |
| `make labelSELinux` | Fixes SELinux context labels for volumes (only when developing on a Security-Enhanced Linux kernel). |
| **Production** |  |
| `make deploy` | Builds prod images and installs the Systemd Quadlet service. |
| `make logs` | Tails the systemd journal for the service. |

## Gitignore Policy

**Do not clutter the project `.gitignore` with personal tooling configurations.**

This repository maintains a strict, minimal `.gitignore` focused only on project-specific artifacts and security. If your specific tools or OS generate files (e.g., `.vscode/`, `.idea/`, `.DS_Store`, `venv/`), you must add them to your **Global Gitignore**.

* *Learn how to set up a global gitignore [here](https://docs.github.com/en/get-started/getting-started-with-git/ignoring-files#configuring-ignored-files-for-all-repositories-on-your-computer).*