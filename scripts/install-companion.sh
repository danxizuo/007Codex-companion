#!/usr/bin/env bash
set -euo pipefail

RELEASE_REPO="${ICODEX_COMPANION_RELEASE_REPO:-danxizuo/007Codex-companin}"
VERSION="${ICODEX_COMPANION_VERSION:-v0.1.0-beta.2}"
DOMAIN=""
CLOUDFLARED_TOKEN="${ICODEX_CLOUDFLARED_TOKEN:-}"
INSTALL_HOME="${ICODEX_COMPANION_HOME:-$HOME/.icodex-companion}"
APP_DIR="$INSTALL_HOME/app"
CONFIG_FILE="$INSTALL_HOME/config.json"
AUTH_FILE="$INSTALL_HOME/auth-token"
LOG_DIR="$HOME/Library/Logs/iCodexCompanion"
COMPANION_LABEL="com.danxizuo.icodex-companion"
CLOUDFLARED_LABEL="com.danxizuo.icodex-companion-cloudflared"
COMPANION_PLIST="$HOME/Library/LaunchAgents/$COMPANION_LABEL.plist"
CLOUDFLARED_PLIST="$HOME/Library/LaunchAgents/$CLOUDFLARED_LABEL.plist"
PORT="${ICODEX_COMPANION_PORT:-}"
HOST="${ICODEX_COMPANION_HOST:-0.0.0.0}"
NAME="${ICODEX_COMPANION_NAME:-007Codex Companion}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain|--public-base-url)
      DOMAIN="${2:-}"
      shift 2
      ;;
    --cloudflared-token)
      CLOUDFLARED_TOKEN="${2:-}"
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --home)
      INSTALL_HOME="${2:-}"
      APP_DIR="$INSTALL_HOME/app"
      CONFIG_FILE="$INSTALL_HOME/config.json"
      AUTH_FILE="$INSTALL_HOME/auth-token"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$DOMAIN" ]]; then
  echo "Usage: install-companion.sh --domain u001.sci2web.top [--cloudflared-token TOKEN]" >&2
  exit 2
fi

if [[ "$DOMAIN" != http://* && "$DOMAIN" != https://* ]]; then
  DOMAIN="https://$DOMAIN"
fi

command -v curl >/dev/null 2>&1 || { echo "curl is required." >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "tar is required." >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "Node.js is required." >&2; exit 1; }
NODE_BIN="$(command -v node)"

port_in_use() {
  lsof -nP -tiTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

choose_port() {
  local preferred="${1:-3939}"
  local port
  for port in "$preferred" $(seq 3940 3999) $(seq 4940 4999); do
    if ! port_in_use "$port"; then
      echo "$port"
      return 0
    fi
  done
  return 1
}

PNPM_BIN="${PNPM_BIN:-}"
if [[ -z "$PNPM_BIN" ]]; then
  if command -v pnpm >/dev/null 2>&1; then
    PNPM_BIN="$(command -v pnpm)"
  elif command -v corepack >/dev/null 2>&1; then
    corepack enable pnpm >/dev/null 2>&1 || true
    PNPM_BIN="$(command -v pnpm || true)"
  fi
fi
if [[ -z "$PNPM_BIN" ]]; then
  echo "pnpm is required. Install Node.js with Corepack enabled, then rerun this script." >&2
  exit 1
fi

mkdir -p "$INSTALL_HOME" "$LOG_DIR" "$HOME/Library/LaunchAgents"

ARCHIVE_NAME="icodex-companion-$VERSION.tar.gz"
ARCHIVE_URL="https://github.com/$RELEASE_REPO/releases/download/$VERSION/$ARCHIVE_NAME"
TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "Downloading 007Codex Companion $VERSION..."
curl -fL "$ARCHIVE_URL" -o "$TMP_DIR/$ARCHIVE_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
tar -xzf "$TMP_DIR/$ARCHIVE_NAME" -C "$APP_DIR" --strip-components 1

"$PNPM_BIN" -C "$APP_DIR" install --prod --frozen-lockfile

launchctl bootout "gui/$(id -u)" "$COMPANION_PLIST" >/dev/null 2>&1 || true
launchctl bootout "gui/$(id -u)" "$CLOUDFLARED_PLIST" >/dev/null 2>&1 || true

if [[ -z "$PORT" ]]; then
  PORT="$(choose_port 3939)" || {
    echo "No available Companion port was found." >&2
    exit 1
  }
elif port_in_use "$PORT"; then
  PORT="$(choose_port "$PORT")" || {
    echo "No available Companion port was found." >&2
    exit 1
  }
fi

if [[ ! -s "$AUTH_FILE" ]]; then
  umask 077
  node -e 'process.stdout.write(require("crypto").randomBytes(32).toString("base64url") + "\n")' >"$AUTH_FILE"
fi

"$NODE_BIN" "$APP_DIR/packages/companion/dist/cli.js" configure \
  --config "$CONFIG_FILE" \
  --host "$HOST" \
  --port "$PORT" \
  --public-base-url "$DOMAIN" \
  --auth-token-file "$AUTH_FILE" \
  --name "$NAME"

cat >"$COMPANION_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$COMPANION_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$NODE_BIN</string>
    <string>$APP_DIR/packages/companion/dist/cli.js</string>
    <string>start</string>
    <string>--config</string>
    <string>$CONFIG_FILE</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>$APP_DIR</string>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/companion.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/companion.err.log</string>
</dict>
</plist>
PLIST

launchctl bootstrap "gui/$(id -u)" "$COMPANION_PLIST"
launchctl kickstart -k "gui/$(id -u)/$COMPANION_LABEL"

if [[ -n "$CLOUDFLARED_TOKEN" ]]; then
  CLOUDFLARED_BIN="${CLOUDFLARED_BIN:-$(command -v cloudflared || true)}"
  if [[ -z "$CLOUDFLARED_BIN" ]]; then
    echo "cloudflared token was provided, but cloudflared was not found." >&2
    exit 1
  fi

  cat >"$CLOUDFLARED_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$CLOUDFLARED_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$CLOUDFLARED_BIN</string>
    <string>tunnel</string>
    <string>--no-autoupdate</string>
    <string>run</string>
    <string>--token</string>
    <string>$CLOUDFLARED_TOKEN</string>
    <string>--url</string>
    <string>http://127.0.0.1:$PORT</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/cloudflared.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/cloudflared.err.log</string>
</dict>
</plist>
PLIST

  launchctl bootstrap "gui/$(id -u)" "$CLOUDFLARED_PLIST"
  launchctl kickstart -k "gui/$(id -u)/$CLOUDFLARED_LABEL"
fi

echo "Waiting for Companion on 127.0.0.1:$PORT..."
for _ in {1..30}; do
  if curl -fsS -H "authorization: Bearer $(tr -d '\r\n' < "$AUTH_FILE")" "http://127.0.0.1:$PORT/status" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -fsS -H "authorization: Bearer $(tr -d '\r\n' < "$AUTH_FILE")" "http://127.0.0.1:$PORT/status" >/dev/null 2>&1; then
  echo "Companion service did not become healthy. Check $LOG_DIR/companion.err.log" >&2
  exit 1
fi

echo
echo "007Codex Companion installed and running."
echo "Pair this Mac with the iOS app using the QR code below:"
"$NODE_BIN" "$APP_DIR/packages/companion/dist/cli.js" pair --config "$CONFIG_FILE"
