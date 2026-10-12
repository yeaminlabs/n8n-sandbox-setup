#!/usr/bin/env bash
# ============================================================
#  SNBD Host — n8n AI Sandbox Setup Script
#  Sets up the self-hosted n8n sandbox stack (sandbox-api +
#  sandbox-runner) locally, verifies it, then prints the exact
#  env vars to paste into your n8n instance.
#
#  Usage:
#    bash n8n-sandbox-setup.sh              # full setup
#    bash n8n-sandbox-setup.sh --verify     # healthcheck only
#    bash n8n-sandbox-setup.sh --teardown   # stop & remove stack
#    bash n8n-sandbox-setup.sh --show-env   # print env vars only
#
#  Requirements: Docker, Docker Compose v2, openssl, curl
#  Run this on the same machine (or same Docker network) as n8n.
# ============================================================

set -euo pipefail

# ── constants ─────────────────────────────────────────────────────────────────
SANDBOX_DIR="${SANDBOX_DIR:-$HOME/n8n-sandbox}"
SANDBOX_API_PORT="${SANDBOX_API_PORT:-8080}"
COMPOSE_PROJECT="n8n-sandbox"

# n8n sandbox Docker images (official n8n registry)
# See: https://docs.n8n.io/deploy/host-n8n/install-options/install-using-docker-compose
SANDBOX_API_IMAGE="${SANDBOX_API_IMAGE:-docker.n8n.io/n8nio/n8n-sandbox-service:latest}"
SANDBOX_RUNNER_IMAGE="${SANDBOX_RUNNER_IMAGE:-docker.n8n.io/n8nio/n8n-sandbox-runner:latest}"

# ── mode flags ────────────────────────────────────────────────────────────────
MODE="setup"
for arg in "$@"; do
  case "$arg" in
    --verify)   MODE="verify" ;;
    --teardown) MODE="teardown" ;;
    --show-env) MODE="show-env" ;;
    -h|--help)
      sed -n '2,11p' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

STAMP=$(date +%Y%m%d-%H%M)
LOG_FILE="$HOME/n8n-sandbox-setup-$STAMP.log"
exec > >(tee "$LOG_FILE") 2>&1

# ── colours ───────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  GRN='\033[0;32m'; YEL='\033[0;33m'; RED='\033[0;31m'
  CYN='\033[0;36m'; MAG='\033[0;35m'; BLD='\033[1m'; DIM='\033[2m'; RST='\033[0m'
else
  GRN=''; YEL=''; RED=''; CYN=''; MAG=''; BLD=''; DIM=''; RST=''
fi

# ── helpers ───────────────────────────────────────────────────────────────────
have()   { command -v "$1" >/dev/null 2>&1; }
ok()     { printf "  ${GRN}✔${RST}  %s\n" "$*"; }
warn()   { printf "  ${YEL}⚠${RST}  %s\n" "$*"; }
fail()   { printf "  ${RED}✘${RST}  %s\n" "$*"; }
info()   { printf "  ${CYN}→${RST}  %s\n" "$*"; }
step()   { printf "\n${BLD}${MAG}▶ %s${RST}\n" "$*"; }
banner() {
  echo
  printf "${BLD}${CYN}%s${RST}\n" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  printf "${BLD}  %s${RST}\n" "$*"
  printf "${BLD}${CYN}%s${RST}\n" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo
}

gen_secret() {
  # Generate a 32-byte hex secret without python/openssl rand dependency
  LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 64 2>/dev/null || \
    openssl rand -hex 32 2>/dev/null || \
    date +%s%N | sha256sum | head -c 64
}

wait_for_health() {
  local url="$1" max="${2:-60}" i=0
  while [ $i -lt $max ]; do
    if curl -sf "$url" 2>/dev/null | grep -q '"ok"'; then
      return 0
    fi
    sleep 2
    ((i+=2))
    printf "."
  done
  return 1
}

# ── header ────────────────────────────────────────────────────────────────────
clear 2>/dev/null || true
printf "${BLD}${CYN}"
cat <<'LOGO'

  ███████╗███╗   ██╗██████╗ ██████╗     ██╗  ██╗ ██████╗ ███████╗████████╗
  ██╔════╝████╗  ██║██╔══██╗██╔══██╗    ██║  ██║██╔═══██╗██╔════╝╚══██╔══╝
  ███████╗██╔██╗ ██║██████╔╝██║  ██║    ███████║██║   ██║███████╗   ██║
  ╚════██║██║╚██╗██║██╔══██╗██║  ██║    ██╔══██║██║   ██║╚════██║   ██║
  ███████║██║ ╚████║██████╔╝██████╔╝    ██║  ██║╚██████╔╝███████║   ██║
  ╚══════╝╚═╝  ╚═══╝╚═════╝ ╚═════╝     ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝

LOGO
printf "${RST}"
printf "  ${BLD}n8n AI Sandbox Setup — Self-Hosted${RST}   %s\n" "$(date '+%Y-%m-%d %H:%M')"
printf "  Mode: ${BLD}${MODE}${RST}   Dir: ${DIM}%s${RST}\n\n" "$SANDBOX_DIR"

# auto-detect compose command (used in all modes)
if docker compose version >/dev/null 2>&1; then
  DC="docker compose"
elif have docker-compose; then
  DC="docker-compose"
else
  DC="docker compose"  # will fail gracefully later with a better message
fi

# ══════════════════════════════════════════════════════════════════════════════
#  MODE: show-env — just print the vars from an existing setup
# ══════════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "show-env" ]; then
  ENV_FILE="$SANDBOX_DIR/.env"
  if [ ! -f "$ENV_FILE" ]; then
    fail ".env not found at $ENV_FILE — run setup first."
    exit 1
  fi
  banner "n8n Environment Variables"
  source "$ENV_FILE"
  printf "${BLD}Add these to your n8n instance (environment or .env file):${RST}\n\n"
  printf "  ${GRN}N8N_INSTANCE_AI_SANDBOX_ENABLED${RST}=true\n"
  printf "  ${GRN}N8N_INSTANCE_AI_SANDBOX_PROVIDER${RST}=n8n-sandbox\n"
  printf "  ${GRN}N8N_SANDBOX_SERVICE_URL${RST}=http://sandbox-api:%s\n" "$SANDBOX_API_PORT"
  printf "  ${GRN}N8N_SANDBOX_SERVICE_API_KEY${RST}=%s\n\n" "${SANDBOX_API_KEY:-<run setup first>}"
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
#  MODE: teardown
# ══════════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "teardown" ]; then
  banner "Tearing Down Sandbox Stack"
  if [ -f "$SANDBOX_DIR/docker-compose.yml" ]; then
    cd "$SANDBOX_DIR"
    $DC -p "$COMPOSE_PROJECT" down -v --remove-orphans && ok "Stack removed." || warn "docker compose down exited non-zero."
  else
    warn "No docker-compose.yml found at $SANDBOX_DIR — nothing to tear down."
  fi
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
#  MODE: verify — healthcheck against running stack
# ══════════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "verify" ]; then
  banner "Sandbox Health Verification"
  HEALTH_URL="http://localhost:${SANDBOX_API_PORT}/healthz"
  info "Checking $HEALTH_URL ..."
  RESP=$(curl -sf "$HEALTH_URL" 2>/dev/null || echo "")
  if echo "$RESP" | grep -q '"ok"'; then
    ok "Sandbox API is healthy: $RESP"
  else
    fail "Health check failed. Response: '${RESP:-no response}'"
    info "Is the stack running?  docker compose -p $COMPOSE_PROJECT ps  (or docker-compose)"
    exit 1
  fi
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
#  MODE: setup (default)
# ══════════════════════════════════════════════════════════════════════════════

# ── STEP 1: Prerequisites — auto-install anything missing ────────────────────
banner "Step 1 — Prerequisites"

# Detect OS
OS_TYPE=""
PKG_MGR=""
if [[ "$OSTYPE" == "darwin"* ]]; then
  OS_TYPE="macos"
elif [ -f /etc/os-release ]; then
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian|linuxmint) OS_TYPE="debian"; PKG_MGR="apt-get" ;;
    centos|rhel|rocky|almalinux)
      OS_TYPE="rhel"
      have dnf && PKG_MGR="dnf" || PKG_MGR="yum"
      ;;
    fedora) OS_TYPE="rhel"; PKG_MGR="dnf" ;;
    *) OS_TYPE="linux-unknown" ;;
  esac
fi
info "Detected OS: ${OS_TYPE} ${PRETTY_NAME:-}"

# ── auto-install helper ───────────────────────────────────────────────────────
pkg_install() {
  local pkg="$1" label="${2:-$1}"
  info "Installing $label ..."
  case "$OS_TYPE" in
    macos)
      if ! have brew; then
        info "Homebrew not found — installing Homebrew first ..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      fi
      brew install "$pkg" 2>&1 | tail -5
      ;;
    debian)
      apt-get update -qq 2>/dev/null
      apt-get install -y "$pkg" 2>&1 | tail -5
      ;;
    rhel)
      $PKG_MGR install -y "$pkg" 2>&1 | tail -5
      ;;
    *)
      fail "Cannot auto-install on this OS. Please install $label manually."
      return 1
      ;;
  esac
}

install_docker() {
  case "$OS_TYPE" in
    macos)
      warn "Docker Desktop is required on macOS."
      warn "Download from: https://www.docker.com/products/docker-desktop/"
      warn "Or install via Homebrew: brew install --cask docker"
      if have brew; then
        info "Installing Docker Desktop via Homebrew ..."
        brew install --cask docker 2>&1 | tail -5
        info "Launch Docker Desktop from Applications, then re-run this script."
      fi
      exit 1
      ;;
    debian)
      info "Installing Docker Engine via official script ..."
      curl -fsSL https://get.docker.com | sh
      systemctl enable docker --now 2>/dev/null || true
      ;;
    rhel)
      info "Installing Docker Engine via official script ..."
      curl -fsSL https://get.docker.com | sh
      systemctl enable docker --now 2>/dev/null || true
      ;;
    *)
      fail "Cannot auto-install Docker on this OS. See https://docs.docker.com/get-docker/"
      exit 1
      ;;
  esac
}

install_docker_compose() {
  case "$OS_TYPE" in
    debian)
      apt-get update -qq 2>/dev/null
      apt-get install -y docker-compose-plugin 2>&1 | tail -5
      ;;
    rhel)
      $PKG_MGR install -y docker-compose-plugin 2>&1 | tail -5 || \
      $PKG_MGR install -y docker-compose 2>&1 | tail -5
      ;;
    macos)
      # Docker Desktop installs the compose plugin but it only activates once
      # the daemon is running. Check if the plugin binary already exists.
      COMPOSE_PLUGIN_PATHS=(
        "$HOME/.docker/cli-plugins/docker-compose"
        "/usr/local/lib/docker/cli-plugins/docker-compose"
        "/usr/local/libexec/docker/cli-plugins/docker-compose"
        "/Applications/Docker.app/Contents/Resources/cli-plugins/docker-compose"
      )
      for p in "${COMPOSE_PLUGIN_PATHS[@]}"; do
        if [ -x "$p" ]; then
          # Wire it up as a standalone binary so we can call it without daemon
          ln -sf "$p" /usr/local/bin/docker-compose 2>/dev/null || true
          info "Linked Docker Compose plugin from $p"
          return 0
        fi
      done
      info "Docker Compose not found on disk. Install Docker Desktop to get it:"
      info "  brew install --cask docker   OR   https://www.docker.com/products/docker-desktop/"
      warn "Start Docker Desktop, then re-run this script."
      exit 1
      ;;
    *)
      info "Trying standalone docker-compose install ..."
      COMPOSE_VER=$(curl -s https://api.github.com/repos/docker/compose/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
      curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
      chmod +x /usr/local/bin/docker-compose
      ;;
  esac
}

# ── curl ─────────────────────────────────────────────────────────────────────
if have curl; then
  ok "curl found: $(curl --version 2>/dev/null | head -n1)"
else
  warn "curl not found — installing ..."
  case "$OS_TYPE" in
    macos)   pkg_install curl ;;
    debian)  pkg_install curl ;;
    rhel)    pkg_install curl ;;
    *)       fail "Install curl manually then re-run."; exit 1 ;;
  esac
  have curl && ok "curl installed." || { fail "curl install failed."; exit 1; }
fi

# ── openssl ───────────────────────────────────────────────────────────────────
if have openssl; then
  ok "openssl found: $(openssl version 2>/dev/null)"
else
  warn "openssl not found — installing ..."
  case "$OS_TYPE" in
    macos)   pkg_install openssl ;;
    debian)  pkg_install openssl ;;
    rhel)    pkg_install openssl ;;
    *)       fail "Install openssl manually then re-run."; exit 1 ;;
  esac
  have openssl && ok "openssl installed." || { fail "openssl install failed."; exit 1; }
fi

# ── Docker ────────────────────────────────────────────────────────────────────
if have docker; then
  ok "Docker found: $(docker --version 2>/dev/null)"
else
  warn "Docker not found — installing ..."
  install_docker
  have docker && ok "Docker installed: $(docker --version 2>/dev/null)" || { fail "Docker install failed."; exit 1; }
fi

# ── Docker Compose ────────────────────────────────────────────────────────────
if docker compose version >/dev/null 2>&1; then
  DC="docker compose"
  ok "Docker Compose (plugin) found: $(docker compose version 2>/dev/null | head -n1)"
elif have docker-compose; then
  DC="docker-compose"
  ok "docker-compose found: $(docker-compose --version 2>/dev/null)"
  warn "docker-compose v1 detected — Compose v2 is recommended."
else
  warn "Docker Compose not found — installing ..."
  install_docker_compose
  if docker compose version >/dev/null 2>&1; then
    DC="docker compose"
    ok "Docker Compose installed: $(docker compose version 2>/dev/null | head -n1)"
  elif have docker-compose; then
    DC="docker-compose"
    ok "docker-compose installed: $(docker-compose --version 2>/dev/null)"
  else
    fail "Docker Compose install failed. Install manually: https://docs.docker.com/compose/install/"
    exit 1
  fi
fi

# ── Docker daemon ─────────────────────────────────────────────────────────────
if ! docker info >/dev/null 2>&1; then
  warn "Docker daemon not running — attempting to start ..."
  if have systemctl; then
    systemctl start docker 2>/dev/null && sleep 3
  elif have service; then
    service docker start 2>/dev/null && sleep 3
  fi
  if docker info >/dev/null 2>&1; then
    ok "Docker daemon started."
  else
    fail "Docker daemon is not running."
    fail "On macOS: open Docker Desktop app."
    fail "On Linux: sudo systemctl start docker"
    exit 1
  fi
else
  ok "Docker daemon is running."
fi

# ── STEP 2: Create directory structure ────────────────────────────────────────
banner "Step 2 — Create Sandbox Directory"

mkdir -p "$SANDBOX_DIR/certs"
ok "Directory ready: $SANDBOX_DIR"

# ── STEP 3: Generate secrets ──────────────────────────────────────────────────
banner "Step 3 — Generate Secrets"

ENV_FILE="$SANDBOX_DIR/.env"

if [ -f "$ENV_FILE" ]; then
  warn ".env already exists — reusing existing secrets."
  source "$ENV_FILE"
else
  info "Generating new secrets ..."
  SANDBOX_API_KEY=$(gen_secret)
  SANDBOX_REGISTRATION_TOKEN=$(gen_secret)
  SANDBOX_RUNNER_KEY=$(gen_secret)

  cat > "$ENV_FILE" <<EOF
# n8n Sandbox secrets — generated $(date '+%Y-%m-%d %H:%M')
# Keep this file private. Never commit to git.
SANDBOX_API_KEY=${SANDBOX_API_KEY}
SANDBOX_REGISTRATION_TOKEN=${SANDBOX_REGISTRATION_TOKEN}
SANDBOX_RUNNER_KEY=${SANDBOX_RUNNER_KEY}
SANDBOX_API_PORT=${SANDBOX_API_PORT}
EOF
  chmod 600 "$ENV_FILE"
  ok "Secrets written to $ENV_FILE"
fi

ok "  SANDBOX_API_KEY              = ${SANDBOX_API_KEY:0:8}...${SANDBOX_API_KEY: -4} (${#SANDBOX_API_KEY} chars)"
ok "  SANDBOX_REGISTRATION_TOKEN   = ${SANDBOX_REGISTRATION_TOKEN:0:8}...${SANDBOX_REGISTRATION_TOKEN: -4}"
ok "  SANDBOX_RUNNER_KEY           = ${SANDBOX_RUNNER_KEY:0:8}...${SANDBOX_RUNNER_KEY: -4}"

# ── STEP 4: Generate mTLS certificates ───────────────────────────────────────
banner "Step 4 — Generate mTLS Certificates"

CERT_DIR="$SANDBOX_DIR/certs"
CA_KEY="$CERT_DIR/ca.key"
CA_CERT="$CERT_DIR/ca.crt"
API_KEY="$CERT_DIR/sandbox-api.key"
API_CERT="$CERT_DIR/sandbox-api.crt"
RUNNER_KEY="$CERT_DIR/sandbox-runner.key"
RUNNER_CERT="$CERT_DIR/sandbox-runner.crt"

if [ -f "$CA_CERT" ] && [ -f "$API_CERT" ] && [ -f "$RUNNER_CERT" ]; then
  warn "Certificates already exist — skipping generation. Delete $CERT_DIR to regenerate."
else
  info "Generating CA key and self-signed certificate ..."
  openssl genrsa -out "$CA_KEY" 4096 2>/dev/null
  openssl req -x509 -new -nodes -key "$CA_KEY" \
    -sha256 -days 3650 \
    -subj "/CN=n8n-sandbox-ca/O=SNBD Host/C=BD" \
    -out "$CA_CERT" 2>/dev/null
  ok "CA certificate: $CA_CERT"

  # sandbox-api server certificate
  info "Generating sandbox-api certificate (CN=sandbox-api) ..."
  openssl genrsa -out "$API_KEY" 4096 2>/dev/null
  openssl req -new -key "$API_KEY" \
    -subj "/CN=sandbox-api/O=SNBD Host/C=BD" \
    -out "$CERT_DIR/sandbox-api.csr" 2>/dev/null
  openssl x509 -req -in "$CERT_DIR/sandbox-api.csr" \
    -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
    -out "$API_CERT" -days 3650 -sha256 \
    -extfile <(printf "subjectAltName=DNS:sandbox-api,DNS:localhost,IP:127.0.0.1\n") 2>/dev/null
  rm -f "$CERT_DIR/sandbox-api.csr"
  ok "sandbox-api certificate: $API_CERT"

  # sandbox-runner-1 client certificate
  info "Generating sandbox-runner-1 certificate (CN=sandbox-runner-1) ..."
  openssl genrsa -out "$RUNNER_KEY" 4096 2>/dev/null
  openssl req -new -key "$RUNNER_KEY" \
    -subj "/CN=sandbox-runner-1/O=SNBD Host/C=BD" \
    -out "$CERT_DIR/sandbox-runner.csr" 2>/dev/null
  openssl x509 -req -in "$CERT_DIR/sandbox-runner.csr" \
    -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
    -out "$RUNNER_CERT" -days 3650 -sha256 2>/dev/null
  rm -f "$CERT_DIR/sandbox-runner.csr"
  ok "sandbox-runner-1 certificate: $RUNNER_CERT"
fi

# Verify cert chain
if openssl verify -CAfile "$CA_CERT" "$API_CERT" >/dev/null 2>&1; then
  ok "Certificate chain verified ✓"
else
  warn "Certificate chain verification failed — regenerate by deleting $CERT_DIR and re-running."
fi

# ── STEP 5: Write docker-compose.yml ─────────────────────────────────────────
banner "Step 5 — Write Docker Compose Stack"

COMPOSE_FILE="$SANDBOX_DIR/docker-compose.yml"

cat > "$COMPOSE_FILE" <<COMPOSE
# n8n Self-Hosted Sandbox Stack
# Generated by SNBD Host n8n-sandbox-setup.sh — $(date '+%Y-%m-%d %H:%M')
# Docs: https://docs.n8n.io/deploy/host-n8n/configure-n8n/set-up-n8n-assistant/#setup-2

name: n8n-sandbox

services:

  sandbox-api:
    image: ${SANDBOX_API_IMAGE}
    container_name: sandbox-api
    restart: unless-stopped
    ports:
      - "${SANDBOX_API_PORT}:8080"
    environment:
      SANDBOX_API_KEYS: "\${SANDBOX_API_KEY}"
      REGISTRATION_TOKEN: "\${SANDBOX_REGISTRATION_TOKEN}"
      TLS_CA_CERT: /certs/ca.crt
      TLS_SERVER_CERT: /certs/sandbox-api.crt
      TLS_SERVER_KEY: /certs/sandbox-api.key
    volumes:
      - ./certs:/certs:ro
    networks:
      - sandbox-net
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:8080/healthz"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 15s

  sandbox-runner-1:
    image: ${SANDBOX_RUNNER_IMAGE}
    container_name: sandbox-runner-1
    restart: unless-stopped
    privileged: true
    environment:
      SANDBOX_API_URL: http://sandbox-api:8080
      REGISTRATION_TOKEN: "\${SANDBOX_REGISTRATION_TOKEN}"
      RUNNER_KEY: "\${SANDBOX_RUNNER_KEY}"
      RUNNER_NAME: sandbox-runner-1
      TLS_CA_CERT: /certs/ca.crt
      TLS_CLIENT_CERT: /certs/sandbox-runner.crt
      TLS_CLIENT_KEY: /certs/sandbox-runner.key
    volumes:
      - ./certs:/certs:ro
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - sandbox-net
    depends_on:
      sandbox-api:
        condition: service_healthy

networks:
  sandbox-net:
    driver: bridge
COMPOSE

ok "docker-compose.yml written to $COMPOSE_FILE"

# ── STEP 6: Pull images ───────────────────────────────────────────────────────
banner "Step 6 — Pull Docker Images"

N8N_REGISTRY="docker.n8n.io"

# Check if already logged in to n8n registry
REGISTRY_AUTH_FILE="${DOCKER_CONFIG:-$HOME/.docker}/config.json"
ALREADY_LOGGED_IN=0
if [ -f "$REGISTRY_AUTH_FILE" ] && grep -q "$N8N_REGISTRY" "$REGISTRY_AUTH_FILE" 2>/dev/null; then
  ALREADY_LOGGED_IN=1
fi

# Try pulling without login first (in case credentials are cached)
if docker pull "$SANDBOX_API_IMAGE" >/dev/null 2>&1; then
  ALREADY_LOGGED_IN=1
fi

if [ "$ALREADY_LOGGED_IN" = "0" ]; then
  echo
  printf "  ${BLD}${CYN}The n8n sandbox images are in a private registry.${RST}\n"
  printf "  ${BLD}You need an n8n account to pull them.${RST}\n"
  printf "  ${DIM}Sign up free at: https://app.n8n.cloud/register${RST}\n\n"
  printf "  ${BLD}Log in to docker.n8n.io now:${RST}\n"
  printf "  ${DIM}(Enter your n8n.io email and password)${RST}\n\n"
  docker login "$N8N_REGISTRY"
  LOGIN_EXIT=$?
  if [ $LOGIN_EXIT -ne 0 ]; then
    fail "Login failed. Cannot pull sandbox images without n8n registry access."
    echo
    info "If you don't have an n8n account, sign up at https://app.n8n.cloud/register"
    info "Then re-run this script."
    exit 1
  fi
  ok "Logged in to $N8N_REGISTRY"
fi

info "Pulling $SANDBOX_API_IMAGE ..."
if docker pull "$SANDBOX_API_IMAGE" 2>&1 | tail -n3; then
  ok "sandbox-api image ready."
else
  fail "Pull failed even after login."
  info "Make sure your n8n account has access to the sandbox images."
  info "Check: https://docs.n8n.io/deploy/host-n8n/configure-n8n/set-up-n8n-assistant/"
  exit 1
fi

info "Pulling $SANDBOX_RUNNER_IMAGE ..."
if docker pull "$SANDBOX_RUNNER_IMAGE" 2>&1 | tail -n3; then
  ok "sandbox-runner image ready."
else
  fail "Pull failed for runner image."
  exit 1
fi

# ── STEP 7: Start the stack ───────────────────────────────────────────────────
banner "Step 7 — Start Sandbox Stack"

cd "$SANDBOX_DIR"
source "$ENV_FILE"

info "Starting stack with docker compose ..."
# docker-compose v1 reads .env automatically; v2 uses --env-file
if [ "$DC" = "docker compose" ]; then
  $DC -p "$COMPOSE_PROJECT" --env-file "$ENV_FILE" up -d
else
  $DC -p "$COMPOSE_PROJECT" up -d
fi

ok "Containers started."
echo
$DC -p "$COMPOSE_PROJECT" ps
echo

# ── STEP 8: Wait for health ───────────────────────────────────────────────────
banner "Step 8 — Health Check"

HEALTH_URL="http://localhost:${SANDBOX_API_PORT}/healthz"
info "Waiting for sandbox-api to be healthy ($HEALTH_URL) ..."
printf "  "

if wait_for_health "$HEALTH_URL" 90; then
  printf "\n"
  RESP=$(curl -sf "$HEALTH_URL" 2>/dev/null)
  ok "Health check PASSED: $RESP"
else
  printf "\n"
  fail "Health check timed out after 90s."
  echo
  warn "Container logs (sandbox-api):"
  $DC -p "$COMPOSE_PROJECT" logs --tail=30 sandbox-api 2>/dev/null || true
  echo
  warn "Check that the n8n sandbox images are available to you."
  warn "If using docker.n8n.io images, ensure you have n8n Enterprise access:"
  warn "  https://docs.n8n.io/deploy/host-n8n/install-options/install-using-docker-compose"
  exit 1
fi

# ── STEP 9: Proof output ──────────────────────────────────────────────────────
banner "✅  SANDBOX RUNNING — PROOF"

echo
printf "  ${GRN}${BLD}curl http://localhost:%s/healthz${RST}\n" "$SANDBOX_API_PORT"
FINAL_RESP=$(curl -sf "http://localhost:${SANDBOX_API_PORT}/healthz" 2>/dev/null || echo '{"status":"unreachable"}')
printf "  ${GRN}Response: %s${RST}\n" "$FINAL_RESP"
echo

printf "  ${BLD}Container status:${RST}\n"
$DC -p "$COMPOSE_PROJECT" ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || \
  $DC -p "$COMPOSE_PROJECT" ps
echo

# ── STEP 10: n8n env vars ─────────────────────────────────────────────────────
banner "Step 10 — n8n Environment Variables"

printf "${BLD}Add these to your n8n instance (environment, .env, or docker-compose.yml):${RST}\n\n"

source "$ENV_FILE"

printf "  ${BLD}${GRN}N8N_INSTANCE_AI_SANDBOX_ENABLED${RST}=${GRN}true${RST}\n"
printf "  ${BLD}${GRN}N8N_INSTANCE_AI_SANDBOX_PROVIDER${RST}=${GRN}n8n-sandbox${RST}\n"
printf "  ${BLD}${GRN}N8N_SANDBOX_SERVICE_URL${RST}=${GRN}http://sandbox-api:%s${RST}\n" "$SANDBOX_API_PORT"
printf "  ${BLD}${GRN}N8N_SANDBOX_SERVICE_API_KEY${RST}=${GRN}%s${RST}\n\n" "${SANDBOX_API_KEY}"

echo "# ── Copy-paste block ────────────────────────────────────────────────────────"
echo "N8N_INSTANCE_AI_SANDBOX_ENABLED=true"
echo "N8N_INSTANCE_AI_SANDBOX_PROVIDER=n8n-sandbox"
printf "N8N_SANDBOX_SERVICE_URL=http://sandbox-api:%s\n" "$SANDBOX_API_PORT"
printf "N8N_SANDBOX_SERVICE_API_KEY=%s\n" "${SANDBOX_API_KEY}"
echo "# ────────────────────────────────────────────────────────────────────────────"
echo

info "If n8n runs in the same Docker network as sandbox-api,"
info "use the service name: http://sandbox-api:${SANDBOX_API_PORT}"
info "If n8n runs on the host directly, use: http://localhost:${SANDBOX_API_PORT}"
echo

# ── Final summary ─────────────────────────────────────────────────────────────
banner "Summary"

ok "Sandbox stack is running."
ok "API key generated and stored in $ENV_FILE"
ok "mTLS certificates in $SANDBOX_DIR/certs/"
ok "Health check passed: $FINAL_RESP"
echo
printf "  ${BLD}Useful commands:${RST}\n"
printf "  ${DIM}bash n8n-sandbox-setup.sh --verify${RST}          # re-check health\n"
printf "  ${DIM}bash n8n-sandbox-setup.sh --show-env${RST}        # print n8n env vars\n"
printf "  ${DIM}bash n8n-sandbox-setup.sh --teardown${RST}        # stop & remove stack\n"
printf "  ${DIM}docker compose -p n8n-sandbox logs -f${RST}       # follow live logs\n"
printf "  ${DIM}curl http://localhost:%s/healthz${RST}          # manual health check\n" "$SANDBOX_API_PORT"
echo
printf "  ${DIM}Log saved: %s${RST}\n" "$LOG_FILE"
echo
printf "  ${BLD}${CYN}SNBD Host — snbdhost.com${RST}\n"
echo
