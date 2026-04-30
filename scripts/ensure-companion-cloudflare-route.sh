#!/usr/bin/env bash
set -euo pipefail

INSTALL_HOME="${ICODEX_COMPANION_HOME:-$HOME/.icodex-companion}"
CONFIG_FILE="${ICODEX_COMPANION_CONFIG:-$INSTALL_HOME/config.json}"
AUTH_FILE="${ICODEX_COMPANION_AUTH_TOKEN_FILE:-$INSTALL_HOME/auth-token}"
LOG_DIR="$HOME/Library/Logs/iCodexCompanion"
CLOUDFLARED_LABEL="com.danxizuo.icodex-companion-cloudflared"
CLOUDFLARED_PLIST="$HOME/Library/LaunchAgents/$CLOUDFLARED_LABEL.plist"
CLOUDFLARED_CONFIG="${CLOUDFLARED_CONFIG:-$HOME/.cloudflared/config.yml}"
CLOUDFLARED_BIN="${CLOUDFLARED_BIN:-$(command -v cloudflared || true)}"
CLOUDFLARED_TOKEN="${ICODEX_CLOUDFLARED_TOKEN:-}"
NODE_BIN="${NODE_BIN:-$(command -v node || true)}"
LAUNCH_DOMAIN="gui/$(id -u)"

if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" || ! -f "$CONFIG_FILE" ]]; then
  exit 0
fi

read_config_value() {
  "$NODE_BIN" - "$CONFIG_FILE" "$1" <<'NODE'
const fs = require("fs");
const [path, key] = process.argv.slice(2);
try {
  const config = JSON.parse(fs.readFileSync(path, "utf8"));
  const value = config[key];
  if (value !== undefined && value !== null) process.stdout.write(String(value));
} catch {}
NODE
}

normalize_url() {
  "$NODE_BIN" - "$1" <<'NODE'
const raw = (process.argv[2] || "").trim();
if (!raw) process.exit(0);
try {
  const url = new URL(raw.includes("://") ? raw : `https://${raw}`);
  if (url.protocol !== "https:" && url.protocol !== "http:") process.exit(0);
  url.hash = "";
  url.search = "";
  if (url.pathname === "/") url.pathname = "";
  process.stdout.write(url.toString().replace(/\/$/, ""));
} catch {}
NODE
}

url_host() {
  "$NODE_BIN" - "$1" <<'NODE'
try {
  process.stdout.write(new URL(process.argv[2]).hostname);
} catch {}
NODE
}

PUBLIC_BASE_URL="$(normalize_url "$(read_config_value publicBaseURL)")"
if [[ -z "$PUBLIC_BASE_URL" ]]; then
  exit 0
fi

PUBLIC_HOST="$(url_host "$PUBLIC_BASE_URL")"
PORT="$(read_config_value port)"
PORT="${PORT:-3939}"
AUTH_FILE="$(read_config_value authTokenFile || true)"
AUTH_FILE="${AUTH_FILE:-$INSTALL_HOME/auth-token}"
LOCAL_SERVICE_URL="http://127.0.0.1:$PORT"
PUBLIC_STATUS_URL="$PUBLIC_BASE_URL/status"

if [[ -z "$PUBLIC_HOST" || "$PUBLIC_HOST" == "localhost" || "$PUBLIC_HOST" == "127.0.0.1" ]]; then
  exit 0
fi

if [[ -z "$CLOUDFLARED_BIN" || ! -x "$CLOUDFLARED_BIN" ]]; then
  echo "Companion 已配置公网地址 $PUBLIC_BASE_URL，但未找到 cloudflared，无法补齐公网转发。" >&2
  exit 1
fi

restart_cloudflared() {
  /bin/launchctl bootout "$LAUNCH_DOMAIN" "$CLOUDFLARED_PLIST" >/dev/null 2>&1 || true
  /bin/launchctl bootstrap "$LAUNCH_DOMAIN" "$CLOUDFLARED_PLIST"
}

write_token_plist() {
  local token="$1"
  mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"
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
    <string>$token</string>
    <string>--url</string>
    <string>$LOCAL_SERVICE_URL</string>
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
}

update_existing_token_plist_url() {
  [[ -f "$CLOUDFLARED_PLIST" ]] || return 1
  /usr/bin/grep -q '<string>--token</string>' "$CLOUDFLARED_PLIST" || return 1
  /usr/bin/perl -0pi -e \
    "s#(<string>--url</string>\\s*<string>)http://127\\.0\\.0\\.1:[0-9]+(</string>)#\${1}${LOCAL_SERVICE_URL}\${2}#s" \
    "$CLOUDFLARED_PLIST"
}

write_config_plist() {
  mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"
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
    <string>--config</string>
    <string>$CLOUDFLARED_CONFIG</string>
    <string>tunnel</string>
    <string>run</string>
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
}

ensure_named_config_route() {
  [[ -f "$CLOUDFLARED_CONFIG" ]] || return 1
  /usr/bin/grep -q '^tunnel:' "$CLOUDFLARED_CONFIG" || return 1

python3 - "$CLOUDFLARED_CONFIG" "$PUBLIC_HOST" "$LOCAL_SERVICE_URL" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
host = sys.argv[2]
service = sys.argv[3]
lines = path.read_text().splitlines()

if not any(line.strip() == "ingress:" for line in lines):
    lines.extend(["", "ingress:"])

updated = False
deduped = []
index = 0
while index < len(lines):
    line = lines[index]
    if line.strip() == f"- hostname: {host}":
        block = [line, f"    service: {service}"]
        index += 1
        while index < len(lines) and not lines[index].startswith("  - "):
            if not lines[index].strip().startswith("service:"):
                block.append(lines[index])
            index += 1

        if not updated:
            deduped.extend(block)
            updated = True
        continue

    deduped.append(line)
    index += 1

lines = deduped

if not updated:
    insert_at = len(lines)
    for index, line in enumerate(lines):
        if line.strip().startswith("- service: http_status:"):
            insert_at = index
            break
    lines[insert_at:insert_at] = [
        f"  - hostname: {host}",
        f"    service: {service}",
    ]

path.write_text("\n".join(lines) + "\n")
PY

  local tunnel
  tunnel="$(awk '/^tunnel:/ { print $2; exit }' "$CLOUDFLARED_CONFIG")"
  if [[ -n "$tunnel" ]]; then
    "$CLOUDFLARED_BIN" tunnel route dns --overwrite-dns "$tunnel" "$PUBLIC_HOST" >/dev/null 2>&1 || true
  fi

  write_config_plist
  return 0
}

named_config_has_public_host() {
  [[ -f "$CLOUDFLARED_CONFIG" ]] || return 1
  /usr/bin/grep -q "hostname: ${PUBLIC_HOST//./\\.}" "$CLOUDFLARED_CONFIG"
}

verify_public_status() {
  local auth_args=()
  if [[ -r "$AUTH_FILE" ]]; then
    auth_args=(-H "Authorization: Bearer $(tr -d '\r\n' < "$AUTH_FILE")")
  fi

  local body
  body="$(mktemp)"
  for _ in {1..30}; do
    local code
    code="$(curl -sS --connect-timeout 3 --max-time 8 -o "$body" -w '%{http_code}' "${auth_args[@]}" "$PUBLIC_STATUS_URL" 2>/dev/null || true)"
    if [[ "$code" == "200" ]]; then
      rm -f "$body"
      return 0
    fi
    sleep 1
  done

  echo "Companion 本机服务已启动，但公网地址 $PUBLIC_STATUS_URL 没有返回 200。" >&2
  echo "请确认这个子域名已经指向当前用户的 Cloudflare Tunnel；否则二维码会保存一个不可用地址。" >&2
  if [[ -s "$body" ]]; then
    cat "$body" >&2
    echo >&2
  fi
  rm -f "$body"
  return 1
}

if named_config_has_public_host && ensure_named_config_route; then
  restart_cloudflared
elif [[ -n "$CLOUDFLARED_TOKEN" ]]; then
  write_token_plist "$CLOUDFLARED_TOKEN"
  restart_cloudflared
elif update_existing_token_plist_url; then
  restart_cloudflared
else
  echo "Companion 已配置公网地址 $PUBLIC_BASE_URL，但没有可更新的 Cloudflare token 或 named tunnel 配置。" >&2
  exit 1
fi

verify_public_status
