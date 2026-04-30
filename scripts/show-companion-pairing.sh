#!/usr/bin/env bash
set -euo pipefail

INSTALL_HOME="${ICODEX_COMPANION_HOME:-$HOME/.icodex-companion}"
APP_DIR="${ICODEX_COMPANION_APP_DIR:-$INSTALL_HOME/app}"
CONFIG_FILE="${ICODEX_COMPANION_CONFIG:-$INSTALL_HOME/config.json}"
AUTH_FILE="${ICODEX_COMPANION_AUTH_TOKEN_FILE:-$INSTALL_HOME/auth-token}"
NODE_BIN="${NODE_BIN:-$(command -v node || true)}"
CLI_PATH="$APP_DIR/packages/companion/dist/cli.js"

if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
  echo "未找到 Node.js，无法显示 Companion 配对二维码。" >&2
  exit 1
fi

if [[ ! -f "$CLI_PATH" ]]; then
  echo "未找到 Companion 程序，请先运行内测安装命令。" >&2
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "未找到 Companion 配置，请先运行内测安装命令。" >&2
  exit 1
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

first_lan_ip() {
  local default_interface
  default_interface="$(/sbin/route -n get default 2>/dev/null | /usr/bin/awk '/interface:/{print $2; exit}')"
  if [[ -n "$default_interface" ]]; then
    /usr/sbin/ipconfig getifaddr "$default_interface" 2>/dev/null && return 0
  fi

  /usr/sbin/ipconfig getifaddr en0 2>/dev/null && return 0
  /usr/sbin/ipconfig getifaddr en1 2>/dev/null && return 0

  /sbin/ifconfig | /usr/bin/awk '
    /^[a-z0-9]+:/{ iface=$1; sub(":", "", iface) }
    /inet / && $2 !~ /^127\./ && $2 !~ /^169\.254\./ {
      print $2
      exit
    }
  '
}

CONFIG_AUTH_FILE="$(read_config_value authTokenFile)"
if [[ -n "$CONFIG_AUTH_FILE" ]]; then
  AUTH_FILE="$CONFIG_AUTH_FILE"
fi

PORT="$(read_config_value port)"
PORT="${PORT:-3939}"
PUBLIC_BASE_URL="$(read_config_value publicBaseURL)"
LAN_IP="$(first_lan_ip || true)"
LAN_BASE_URL=""
if [[ -n "$LAN_IP" ]]; then
  LAN_BASE_URL="http://$LAN_IP:$PORT"
fi

echo
echo "Companion 配对信息"
echo

PAIR_ARGS=(
  pair
  --config "$CONFIG_FILE"
  --auth-token-file "$AUTH_FILE"
)

if [[ -n "$PUBLIC_BASE_URL" ]]; then
  echo "公网地址：$PUBLIC_BASE_URL"
  PAIR_ARGS+=(--connection-url "$PUBLIC_BASE_URL")
else
  echo "未配置公网地址。"
fi

if [[ -n "$LAN_BASE_URL" ]]; then
  echo
  echo "局域网地址：$LAN_BASE_URL"
  PAIR_ARGS+=(--connection-url "$LAN_BASE_URL")
fi

echo
echo "合并配对二维码："
"$NODE_BIN" "$CLI_PATH" "${PAIR_ARGS[@]}"

echo
echo "如果二维码已经滚出终端，可以随时重新显示："
echo "bash $APP_DIR/scripts/show-companion-pairing.sh"
