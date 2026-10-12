#!/usr/bin/env sh
# ============================================================
#  SNBD Host — n8n Sandbox Bootstrap
#  Works on a completely fresh server with nothing installed.
#  Installs curl → then downloads and runs the full setup.
#
#  One-liner:
#    bash <(wget -qO- https://raw.githubusercontent.com/yeaminlabs/n8n-sandbox-setup/main/bootstrap.sh)
# ============================================================

SCRIPT_URL="https://raw.githubusercontent.com/yeaminlabs/n8n-sandbox-setup/main/n8n-sandbox-setup.sh"

# ── colours ───────────────────────────────────────────────────
if [ -t 1 ]; then
  GRN='\033[0;32m'; YEL='\033[0;33m'; RED='\033[0;31m'
  CYN='\033[0;36m'; BLD='\033[1m'; RST='\033[0m'
else
  GRN=''; YEL=''; RED=''; CYN=''; BLD=''; RST=''
fi

ok()   { printf "  ${GRN}✔${RST}  %s\n" "$*"; }
warn() { printf "  ${YEL}⚠${RST}  %s\n" "$*"; }
fail() { printf "  ${RED}✘${RST}  %s\n" "$*"; }
info() { printf "  ${CYN}→${RST}  %s\n" "$*"; }

printf "\n${BLD}${CYN}  SNBD Host — n8n Sandbox Bootstrap${RST}\n\n"

# ── Step 1: figure out package manager ───────────────────────
PKG_MGR=""
if command -v apt-get >/dev/null 2>&1; then
  PKG_MGR="apt-get"
elif command -v dnf >/dev/null 2>&1; then
  PKG_MGR="dnf"
elif command -v yum >/dev/null 2>&1; then
  PKG_MGR="yum"
elif command -v brew >/dev/null 2>&1; then
  PKG_MGR="brew"
fi

install_pkg() {
  pkg="$1"
  info "Installing $pkg via ${PKG_MGR:-unknown} ..."
  case "$PKG_MGR" in
    apt-get)
      apt-get update -qq 2>/dev/null
      apt-get install -y "$pkg" 2>/dev/null
      ;;
    dnf|yum)
      $PKG_MGR install -y "$pkg" 2>/dev/null
      ;;
    brew)
      brew install "$pkg" 2>/dev/null
      ;;
    *)
      fail "No known package manager found. Install $pkg manually."
      exit 1
      ;;
  esac
}

# ── Step 2: ensure curl ───────────────────────────────────────
if command -v curl >/dev/null 2>&1; then
  ok "curl already installed: $(curl --version 2>/dev/null | head -n1)"
else
  warn "curl not found — installing now ..."
  install_pkg curl
  if command -v curl >/dev/null 2>&1; then
    ok "curl installed."
  else
    # Last resort: try wget to download curl's binary directly
    fail "curl install failed via package manager."
    if command -v wget >/dev/null 2>&1; then
      warn "Falling back to wget to download the setup script ..."
      wget -qO /tmp/n8n-sandbox-setup.sh "$SCRIPT_URL" && \
        chmod +x /tmp/n8n-sandbox-setup.sh && \
        bash /tmp/n8n-sandbox-setup.sh
      exit $?
    fi
    fail "Neither curl nor wget available. Please run:"
    fail "  apt-get install -y curl   OR   yum install -y curl"
    exit 1
  fi
fi

# ── Step 3: download and run the main setup script ───────────
info "Downloading n8n-sandbox-setup.sh ..."
curl -fsSL "$SCRIPT_URL" -o /tmp/n8n-sandbox-setup.sh
chmod +x /tmp/n8n-sandbox-setup.sh
ok "Downloaded. Starting setup ...\n"

bash /tmp/n8n-sandbox-setup.sh
