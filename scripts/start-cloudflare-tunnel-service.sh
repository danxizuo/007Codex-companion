#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="com.danxizuo.007Codex-companion-cloudflared"
LEGACY_LABEL="com.danxizuo.icodex-companion-cloudflared"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
LAUNCHCTL_TARGET="gui/$(id -u)/$LABEL"
CLOUDFLARED_BIN="${CLOUDFLARED_BIN:-/opt/homebrew/bin/cloudflared}"
CLOUDFLARED_CONFIG="${CLOUDFLARED_CONFIG:-$HOME/.cloudflared/config.yml}"
CLOUDFLARED_LOG="${CLOUDFLARED_LOG:-$HOME/Library/Logs/007Codex-companion/cloudflared.log}"
CLOUDFLARED_PROTOCOL="${CLOUDFLARED_PROTOCOL:-auto}"
COMPANION_PORT="${CODEX007_COMPANION_PORT:-${ICODEX_COMPANION_PORT:-3939}}"
LOCAL_STATUS_URL="http://127.0.0.1:${COMPANION_PORT}/status"
PUBLIC_STATUS_URL="${ICODEX_CLOUDFLARE_STATUS_URL:-https://wwww.sci2web.top/status}"
AUTH_FILE="${CODEX007_COMPANION_AUTH_TOKEN_FILE:-${ICODEX_COMPANION_AUTH_TOKEN_FILE:-$HOME/.007Codex-companion/auth-token}}"

cd "$ROOT_DIR"

if [[ ! -x "$CLOUDFLARED_BIN" ]]; then
  echo "cloudflared binary not found: $CLOUDFLARED_BIN" >&2
  exit 1
fi

if [[ ! -f "$CLOUDFLARED_CONFIG" ]]; then
  echo "cloudflared config not found: $CLOUDFLARED_CONFIG" >&2
  exit 1
fi

TUNNEL_ID="$(awk '/^tunnel:/ { print $2 }' "$CLOUDFLARED_CONFIG")"
if [[ -z "$TUNNEL_ID" ]]; then
  echo "tunnel id not found in config: $CLOUDFLARED_CONFIG" >&2
  exit 1
fi

AUTH_ARGS=()
if [[ ! -f "$AUTH_FILE" && -f "$HOME/.codex/icodex-companion-auth-token" ]]; then
  AUTH_FILE="$HOME/.codex/icodex-companion-auth-token"
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

/bin/launchctl bootout "gui/$(id -u)/$LEGACY_LABEL" >/dev/null 2>&1 || true

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
