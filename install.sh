#!/usr/bin/env bash
set -euo pipefail

REPO="akitaonrails/easy-subtitle"
BINARY="easy-subtitle"

# Prefer ~/.local/bin if it's in PATH, otherwise /usr/local/bin
if echo "$PATH" | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
  INSTALL_DIR="$HOME/.local/bin"
else
  INSTALL_DIR="/usr/local/bin"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# Detect platform
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Linux)
    case "$ARCH" in
      x86_64) ASSET="easy-subtitle-linux-x86_64.tar.gz" ;;
      aarch64|arm64) ASSET="easy-subtitle-linux-arm64.tar.gz" ;;
      *) error "Unsupported Linux architecture: $ARCH. Only x86_64 and arm64 are supported." ;;
    esac
    ;;
  Darwin)
    case "$ARCH" in
      arm64) ASSET="easy-subtitle-macos-arm64.tar.gz" ;;
      *) error "Unsupported macOS architecture: $ARCH. Only arm64 (Apple Silicon) is supported." ;;
    esac
    ;;
  *)
    error "Unsupported OS: $OS. Only Linux and macOS are supported."
    ;;
esac

# Get latest release tag
info "Fetching latest release..."
LATEST=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST" ]; then
  error "Could not determine latest release. Check https://github.com/${REPO}/releases"
fi

info "Latest version: ${LATEST}"

# Download
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${LATEST}/${ASSET}"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

info "Downloading ${ASSET}..."
curl -fsSL -o "${TMPDIR}/${ASSET}" "$DOWNLOAD_URL"

# Verify checksum if available
CHECKSUM_URL="${DOWNLOAD_URL}.sha256"
if curl -fsSL -o "${TMPDIR}/${ASSET}.sha256" "$CHECKSUM_URL" 2>/dev/null; then
  info "Verifying checksum..."
  cd "$TMPDIR"
  if command -v sha256sum &>/dev/null; then
    sha256sum -c "${ASSET}.sha256"
  elif command -v shasum &>/dev/null; then
    shasum -a 256 -c "${ASSET}.sha256"
  else
    warn "No sha256sum or shasum found, skipping checksum verification"
  fi
  cd - >/dev/null
fi

# Extract
info "Extracting..."
tar xzf "${TMPDIR}/${ASSET}" -C "$TMPDIR"

# Install
if [ -w "$INSTALL_DIR" ]; then
  mv "${TMPDIR}/${BINARY}" "${INSTALL_DIR}/${BINARY}"
else
  info "Installing to ${INSTALL_DIR} (requires sudo)..."
  sudo mv "${TMPDIR}/${BINARY}" "${INSTALL_DIR}/${BINARY}"
fi

chmod +x "${INSTALL_DIR}/${BINARY}"

info "Installed ${BINARY} ${LATEST} to ${INSTALL_DIR}/${BINARY}"

# Verify
if command -v "$BINARY" &>/dev/null; then
  info "Verification: $($BINARY --version)"
else
  warn "${INSTALL_DIR} may not be in your PATH"
fi

echo ""
info "Get started:"
echo "  ${BINARY} init              # generate config"
echo "  ${BINARY} --help            # see all commands"
echo ""
info "Prerequisites: mkvtoolnix and alass must be on your PATH"
