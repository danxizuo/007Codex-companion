#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="com.deskrelay.codex.companion-cloudflared"
COMPANION_LABEL="com.deskrelay.codex.companion"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
LAUNCHCTL_TARGET="gui/$(id -u)/$LABEL"
CLOUDFLARED_BIN="${CLOUDFLARED_BIN:-/opt/homebrew/bin/cloudflared}"
CLOUDFLARED_CONFIG="${CLOUDFLARED_CONFIG:-$HOME/.cloudflared/config.yml}"
CLOUDFLARED_LOG="${CLOUDFLARED_LOG:-$HOME/Library/Logs/DeskRelayCompanion/cloudflared.log}"
CLOUDFLARED_PROTOCOL="${CLOUDFLARED_PROTOCOL:-auto}"
CONFIG_FILE="${DESKRELAY_COMPANION_CONFIG:-$HOME/.deskrelay-companion/config.json}"
NODE_BIN="${NODE_BIN:-$(command -v node || true)}"
if [[ -z "$NODE_BIN" && -x /opt/miniconda3/bin/node ]]; then
  NODE_BIN="/opt/miniconda3/bin/node"
fi
COMPANION_PORT="${DESKRELAY_COMPANION_PORT:-}"
LOCAL_STATUS_URL="http://127.0.0.1:${COMPANION_PORT}/status"
PUBLIC_STATUS_URL="${DESKRELAY_CLOUDFLARE_STATUS_URL:-}"
AUTH_FILE="${DESKRELAY_COMPANION_AUTH_TOKEN_FILE:-$HOME/.deskrelay-companion/auth-token}"

cd "$ROOT_DIR"

if [[ ! -x "$CLOUDFLARED_BIN" ]]; then
  echo "cloudflared binary not found: $CLOUDFLARED_BIN" >&2
  exit 1
fi

if [[ ! -f "$CLOUDFLARED_CONFIG" ]]; then
  echo "cloudflared config not found: $CLOUDFLARED_CONFIG" >&2
  exit 1
fi

read_config_value() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    return 0
  fi
  if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
    return 0
  fi
  "$NODE_BIN" - "$CONFIG_FILE" "$1" <<'NODE' 2>/dev/null || true
const fs = require("fs");
const [path, key] = process.argv.slice(2);
try {
  const config = JSON.parse(fs.readFileSync(path, "utf8"));
  const value = config[key];
  if (value !== undefined && value !== null) process.stdout.write(String(value));
} catch {}
NODE
}

if [[ -z "$COMPANION_PORT" ]]; then
  COMPANION_PORT="$(read_config_value port)"
fi
COMPANION_PORT="${COMPANION_PORT:-3939}"
LOCAL_STATUS_URL="http://127.0.0.1:${COMPANION_PORT}/status"

if [[ -z "$PUBLIC_STATUS_URL" ]]; then
  PUBLIC_BASE_URL="$(read_config_value publicBaseURL)"
  if [[ -n "$PUBLIC_BASE_URL" ]]; then
    PUBLIC_STATUS_URL="${PUBLIC_BASE_URL%/}/status"
  fi
fi

if [[ -z "$PUBLIC_STATUS_URL" ]]; then
  echo "Public Cloudflare status URL is not configured." >&2
  echo "Set DESKRELAY_CLOUDFLARE_STATUS_URL or publicBaseURL in $CONFIG_FILE." >&2
  exit 1
fi

TUNNEL_ID="$(awk '/^tunnel:/ { print $2 }' "$CLOUDFLARED_CONFIG")"
if [[ -z "$TUNNEL_ID" ]]; then
  echo "tunnel id not found in config: $CLOUDFLARED_CONFIG" >&2
  exit 1
fi

AUTH_ARGS=()
if [[ ! -f "$AUTH_FILE" && -f "$HOME/.codex/deskrelay-companion-auth-token" ]]; then
  AUTH_FILE="$HOME/.codex/deskrelay-companion-auth-token"
fi

if [[ -f "$AUTH_FILE" ]]; then
  AUTH_TOKEN="$(tr -d '\r\n' < "$AUTH_FILE")"
  if [[ -n "$AUTH_TOKEN" ]]; then
    AUTH_ARGS=(-H "authorization: Bearer $AUTH_TOKEN")
  fi
fi

LOCAL_STATUS_BODY="$(mktemp)"
PUBLIC_STATUS_BODY="$(mktemp)"
cleanup() {
  rm -f "$LOCAL_STATUS_BODY" "$PUBLIC_STATUS_BODY"
}
trap cleanup EXIT

tunnel_is_active() {
  local info_json
  info_json="$("$CLOUDFLARED_BIN" tunnel info --output json "$TUNNEL_ID" 2>/dev/null || true)"
  if [[ -z "$info_json" ]]; then
    return 1
  fi

  python3 - "$info_json" <<'PY'
import json
import sys

try:
    payload = json.loads(sys.argv[1])
except Exception:
    raise SystemExit(1)

conns = payload.get("conns") or []
raise SystemExit(0 if len(conns) > 0 else 1)
PY
}

echo "Checking local Companion status..."
LOCAL_HTTP_CODE="$(curl -sS -o "$LOCAL_STATUS_BODY" -w '%{http_code}' "${AUTH_ARGS[@]}" "$LOCAL_STATUS_URL" || true)"
if [[ "$LOCAL_HTTP_CODE" != "200" ]]; then
  echo "Local Companion is not healthy enough for Cloudflare forwarding." >&2
  if [[ -s "$LOCAL_STATUS_BODY" ]]; then
    cat "$LOCAL_STATUS_BODY" >&2
    echo >&2
  fi
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents" "$(dirname "$CLOUDFLARED_LOG")"

cat >"$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${CLOUDFLARED_BIN}</string>
    <string>tunnel</string>
    <string>--config</string>
    <string>${CLOUDFLARED_CONFIG}</string>
    <string>--protocol</string>
    <string>${CLOUDFLARED_PROTOCOL}</string>
    <string>run</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>${HOME}</string>
  <key>StandardOutPath</key>
  <string>${CLOUDFLARED_LOG}</string>
  <key>StandardErrorPath</key>
  <string>${CLOUDFLARED_LOG}</string>
</dict>
</plist>
PLIST

if launchctl print "$LAUNCHCTL_TARGET" >/dev/null 2>&1; then
  echo "Reloading Cloudflare tunnel LaunchAgent..."
  /bin/launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
else
  echo "Bootstrapping Cloudflare tunnel LaunchAgent..."
fi

/bin/launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
/bin/launchctl kickstart -k "$LAUNCHCTL_TARGET"

echo "Waiting for tunnel to become active..."
for _ in {1..20}; do
  if tunnel_is_active; then
    break
  fi
  sleep 1
done

if ! tunnel_is_active; then
  echo "Cloudflare tunnel did not become active." >&2
  tail -n 60 "$CLOUDFLARED_LOG" >&2 || true
  exit 1
fi

echo "Checking public Cloudflare status..."
for _ in {1..20}; do
  PUBLIC_HTTP_CODE="$(curl -sS -o "$PUBLIC_STATUS_BODY" -w '%{http_code}' "${AUTH_ARGS[@]}" "$PUBLIC_STATUS_URL" || true)"
  if [[ "$PUBLIC_HTTP_CODE" == "200" ]]; then
    cat "$PUBLIC_STATUS_BODY"
    echo
    exit 0
  fi
  sleep 1
done

echo "Tunnel is active, but public /status did not return 200." >&2
if [[ -s "$PUBLIC_STATUS_BODY" ]]; then
  cat "$PUBLIC_STATUS_BODY" >&2
  echo >&2
fi
tail -n 60 "$CLOUDFLARED_LOG" >&2 || true
exit 1
