#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_HOME="${ICODEX_COMPANION_HOME:-$HOME/.icodex-companion}"
CONFIG_FILE="${ICODEX_COMPANION_CONFIG:-$INSTALL_HOME/config.json}"
AUTH_FILE="${ICODEX_COMPANION_AUTH_TOKEN_FILE:-$INSTALL_HOME/auth-token}"
HOST="${ICODEX_COMPANION_HOST:-0.0.0.0}"
LOG_DIR="$HOME/Library/Logs/iCodexCompanion"
COMPANION_LABEL="com.danxizuo.icodex-companion"
COMPANION_PLIST="$HOME/Library/LaunchAgents/$COMPANION_LABEL.plist"
LAUNCH_DOMAIN="gui/$(id -u)"
COMPANION_TARGET="$LAUNCH_DOMAIN/$COMPANION_LABEL"
NODE_BIN="${NODE_BIN:-$(command -v node || true)}"
CLI_PATH="$APP_DIR/packages/companion/dist/cli.js"

if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
  echo "未找到 Node.js，无法启动 Companion。" >&2
  exit 1
fi

if [[ ! -f "$CLI_PATH" ]]; then
  echo "未找到 Companion 程序，请先运行内测安装命令。" >&2
  exit 1
fi

if [[ ! -f "$COMPANION_PLIST" ]]; then
  echo "未找到 Companion 后台服务，请先运行内测安装命令。" >&2
  exit 1
fi

if [[ -z "${ICODEX_COMPANION_AUTH_TOKEN_FILE:-}" ]]; then
  PLIST_AUTH_FILE="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:ICODEX_COMPANION_AUTH_TOKEN_FILE' "$COMPANION_PLIST" 2>/dev/null || true)"
  if [[ -n "$PLIST_AUTH_FILE" ]]; then
    AUTH_FILE="$PLIST_AUTH_FILE"
  fi
fi

read_config_port() {
  "$NODE_BIN" -e '
const fs = require("fs");
const path = process.argv[1];
try {
  const config = JSON.parse(fs.readFileSync(path, "utf8"));
  if (Number.isFinite(Number(config.port))) process.stdout.write(String(Math.trunc(Number(config.port))));
} catch {}
' "$CONFIG_FILE"
}

port_in_use() {
  /usr/sbin/lsof -nP -tiTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

choose_port() {
  local preferred="$1"
  local port
  for port in "$preferred" $(/usr/bin/seq 3940 3999) $(/usr/bin/seq 4940 4999); do
    if ! port_in_use "$port"; then
      echo "$port"
      return 0
    fi
  done
  return 1
}

write_companion_plist() {
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
    <string>$CLI_PATH</string>
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
}

mkdir -p "$LOG_DIR"

/bin/launchctl bootout "$LAUNCH_DOMAIN" "$COMPANION_PLIST" >/dev/null 2>&1 || true

preferred_port="${ICODEX_COMPANION_PORT:-$(read_config_port)}"
preferred_port="${preferred_port:-3939}"
port="$(choose_port "$preferred_port")" || {
  echo "没有找到可用端口，Companion 没有启动。" >&2
  exit 1
}

"$NODE_BIN" "$CLI_PATH" configure \
  --config "$CONFIG_FILE" \
  --host "$HOST" \
  --port "$port" \
  --auth-token-file "$AUTH_FILE" >/dev/null
write_companion_plist

/bin/launchctl bootstrap "$LAUNCH_DOMAIN" "$COMPANION_PLIST"

if [[ ! -r "$AUTH_FILE" && -r "$HOME/.codex/icodex-companion-auth-token" ]]; then
  AUTH_FILE="$HOME/.codex/icodex-companion-auth-token"
fi
auth_args=()
if [[ -r "$AUTH_FILE" ]]; then
  auth_args=(-H "Authorization: Bearer $(/bin/cat "$AUTH_FILE")")
fi

for _ in {1..20}; do
  if /usr/bin/curl -fsS "${auth_args[@]}" "http://127.0.0.1:$port/status" >/dev/null 2>&1; then
    echo "Companion 已启动：http://127.0.0.1:$port"
    if [[ -f "$APP_DIR/scripts/show-companion-pairing.sh" ]]; then
      ICODEX_COMPANION_CONFIG="$CONFIG_FILE" \
        ICODEX_COMPANION_AUTH_TOKEN_FILE="$AUTH_FILE" \
        bash "$APP_DIR/scripts/show-companion-pairing.sh"
    fi
    if [[ -f "$APP_DIR/scripts/ensure-companion-cloudflare-route.sh" ]]; then
      if ! ICODEX_COMPANION_CONFIG="$CONFIG_FILE" \
        ICODEX_COMPANION_AUTH_TOKEN_FILE="$AUTH_FILE" \
        bash "$APP_DIR/scripts/ensure-companion-cloudflare-route.sh"; then
        echo "Companion 本机服务已启动，但公网地址暂未通过验活。可以先使用上面的局域网二维码连接。" >&2
      fi
    fi
    exit 0
  fi
  sleep 1
done

echo "Companion 启动后暂未通过本机验活，当前端口占用如下：" >&2
/usr/sbin/lsof -nP -iTCP:"$port" -sTCP:LISTEN >&2 || true
exit 1
