# n8n AI Sandbox Setup

**One-script setup for the n8n self-hosted AI sandbox** — generates certs, secrets, and Docker Compose stack, starts it, and prints the 4 env vars you need to paste into your n8n instance.

> Part of the SNBD Host n8n tutorial series.  
> Previous video: *How to connect DeepSeek to n8n*

---

## What it does

```
Step 1 — Check prerequisites  (Docker, Compose, openssl, curl)
Step 2 — Create ~/n8n-sandbox/ directory
Step 3 — Generate secrets      (API key, registration token, runner key)
Step 4 — Generate mTLS certs   (CA + sandbox-api + sandbox-runner-1)
Step 5 — Write docker-compose.yml
Step 6 — Pull n8n sandbox images
Step 7 — Start the stack       (docker compose up -d)
Step 8 — Wait for health check (GET /healthz → {"status":"ok"})
Step 9 — Print PROOF banner
Step 10 — Print the 4 env vars to paste into n8n
```

## Requirements

| Tool | Notes |
|------|-------|
| Docker Engine ≥ 24 | [Install](https://docs.docker.com/get-docker/) |
| Docker Compose v2 | Bundled with Docker Desktop; `apt install docker-compose-plugin` on Linux |
| openssl | Pre-installed on most Linux/macOS |
| curl | Pre-installed on most Linux/macOS |

The sandbox containers need access to the Docker socket (`/var/run/docker.sock`).  
The runner container runs **privileged** (required for Docker-in-Docker).

---

## Quick start

```bash
# Download
curl -O https://raw.githubusercontent.com/pussycoder99/n8n-sandbox-setup/main/n8n-sandbox-setup.sh
chmod +x n8n-sandbox-setup.sh

# Run on the same server as your n8n instance
bash n8n-sandbox-setup.sh
```

At the end the script prints:

```
N8N_INSTANCE_AI_SANDBOX_ENABLED=true
N8N_INSTANCE_AI_SANDBOX_PROVIDER=n8n-sandbox
N8N_SANDBOX_SERVICE_URL=http://sandbox-api:8080
N8N_SANDBOX_SERVICE_API_KEY=<generated-key>
```

Paste these into your n8n environment and restart n8n.

---

## All commands

```bash
bash n8n-sandbox-setup.sh              # Full setup (default)
bash n8n-sandbox-setup.sh --verify     # Health check only
bash n8n-sandbox-setup.sh --show-env   # Print n8n env vars again
bash n8n-sandbox-setup.sh --teardown   # Stop and remove the stack
```

### Environment variables (override defaults)

```bash
SANDBOX_DIR=/opt/n8n-sandbox \
SANDBOX_API_PORT=8080 \
bash n8n-sandbox-setup.sh
```

| Variable | Default | Description |
|----------|---------|-------------|
| `SANDBOX_DIR` | `~/n8n-sandbox` | Where certs, .env, and docker-compose.yml are stored |
| `SANDBOX_API_PORT` | `8080` | Host port the sandbox API listens on |
| `SANDBOX_API_IMAGE` | `docker.n8n.io/n8nio/n8n-sandbox-service:latest` | Sandbox API image |
| `SANDBOX_RUNNER_IMAGE` | `docker.n8n.io/n8nio/n8n-sandbox-runner:latest` | Runner image |

---

## Where to run this

### Same VPS as n8n (recommended)

```bash
ssh root@your-vps
bash n8n-sandbox-setup.sh
```

n8n and the sandbox share the same Docker host, so the hostname `sandbox-api` resolves automatically inside Docker.

### Local Mac + ngrok (quick demo)

```bash
bash n8n-sandbox-setup.sh     # runs sandbox on localhost:8080
ngrok http 8080               # exposes it publicly
```

Then set `N8N_SANDBOX_SERVICE_URL=https://abc123.ngrok-free.app` in your cloud n8n.

> Not recommended for production — ngrok URL changes on restart.

---

## What gets created

```
~/n8n-sandbox/
├── .env                    # secrets (chmod 600, never commit)
├── docker-compose.yml      # sandbox stack definition
└── certs/
    ├── ca.key / ca.crt     # self-signed CA
    ├── sandbox-api.key / sandbox-api.crt
    └── sandbox-runner.key / sandbox-runner.crt
```

Secrets are re-used across runs. Delete `~/n8n-sandbox/.env` to rotate keys,  
or delete `~/n8n-sandbox/certs/` to regenerate certificates.

---

## Verify it's working

```bash
curl http://localhost:8080/healthz
# Expected: {"status":"ok"}
```

Or use the built-in check:

```bash
bash n8n-sandbox-setup.sh --verify
```

---

## n8n docs reference

- [Set up n8n Assistant — Setup 2: Self-host the sandbox manually](https://docs.n8n.io/deploy/host-n8n/configure-n8n/set-up-n8n-assistant/#setup-2)
- [Docker Compose guide](https://docs.n8n.io/deploy/host-n8n/install-options/install-using-docker-compose)
- [Choose a model provider](https://docs.n8n.io/deploy/host-n8n/configure-n8n/set-up-n8n-assistant/#choose-a-model-provider)

---

## Troubleshooting

**Image pull fails (`docker.n8n.io` unauthorized)**  
The n8n sandbox images require n8n Enterprise access.  
```bash
docker login docker.n8n.io
docker pull docker.n8n.io/n8nio/n8n-sandbox-service:latest
```

**Health check times out**  
```bash
docker compose -p n8n-sandbox logs sandbox-api
docker compose -p n8n-sandbox logs sandbox-runner-1
```

**n8n can't reach sandbox-api**  
Make sure n8n and the sandbox are on the same Docker network, or use the host IP instead of `sandbox-api` as the hostname.

**Regenerate certs / rotate secrets**  
```bash
bash n8n-sandbox-setup.sh --teardown
rm -rf ~/n8n-sandbox
bash n8n-sandbox-setup.sh
```

---

## License

MIT — free to use and modify.

---

*By [SNBD Host](https://snbdhost.com)*
