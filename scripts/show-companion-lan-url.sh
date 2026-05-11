#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/miniconda3/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
DEFAULT_INSTALL_HOME="$HOME/.007Codex-companion"
if [[ ! -d "$DEFAULT_INSTALL_HOME" && -d "$HOME/.icodex-companion" ]]; then
  DEFAULT_INSTALL_HOME="$HOME/.icodex-companion"
elif [[ ! -d "$DEFAULT_INSTALL_HOME" && -d "$HOME/.deskrelay-companion" ]]; then
  DEFAULT_INSTALL_HOME="$HOME/.deskrelay-companion"
fi
INSTALL_HOME="${CODEX007_COMPANION_HOME:-${ICODEX_COMPANION_HOME:-$DEFAULT_INSTALL_HOME}}"
CONFIG_FILE="${CODEX007_COMPANION_CONFIG:-${ICODEX_COMPANION_CONFIG:-$INSTALL_HOME/config.json}}"
NODE_BIN="${NODE_BIN:-$(command -v node || true)}"

read_config_value() {
  [[ -n "$NODE_BIN" && -x "$NODE_BIN" && -f "$CONFIG_FILE" ]] || return 0
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

PORT="$(read_config_value port)"
PORT="${PORT:-${CODEX007_COMPANION_PORT:-${ICODEX_COMPANION_PORT:-3939}}}"
LAN_IP="$(first_lan_ip || true)"

if [[ -z "$LAN_IP" ]]; then
  echo "未找到可用的局域网地址。" >&2
  exit 1
fi

echo "局域网地址：http://$LAN_IP:$PORT"
