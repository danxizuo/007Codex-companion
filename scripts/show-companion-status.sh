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
AUTH_FILE="${CODEX007_COMPANION_AUTH_TOKEN_FILE:-${ICODEX_COMPANION_AUTH_TOKEN_FILE:-$INSTALL_HOME/auth-token}}"
NODE_BIN="${NODE_BIN:-$(command -v node || true)}"

if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
  echo "未找到 Node.js，无法读取 Companion 配置。" >&2
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

if [[ -f "$CONFIG_FILE" ]]; then
  CONFIG_AUTH_FILE="$(read_config_value authTokenFile)"
  if [[ -n "$CONFIG_AUTH_FILE" ]]; then
    AUTH_FILE="$CONFIG_AUTH_FILE"
  fi
  PORT="$(read_config_value port)"
else
  PORT=""
fi

PORT="${PORT:-${CODEX007_COMPANION_PORT:-${ICODEX_COMPANION_PORT:-3939}}}"
STATUS_URL="http://127.0.0.1:${PORT}/status"
DIAGNOSTICS_URL="http://127.0.0.1:${PORT}/diagnostics"
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

echo "007Codex-companion 服务状态"
echo "本机地址：$STATUS_URL"

if launchctl print "gui/$(id -u)/com.danxizuo.007Codex-companion" >/dev/null 2>&1; then
  echo "LaunchAgent：com.danxizuo.007Codex-companion 已加载"
elif launchctl print "gui/$(id -u)/com.danxizuo.icodex-companion" >/dev/null 2>&1; then
  echo "LaunchAgent：com.danxizuo.icodex-companion 已加载"
elif launchctl print "gui/$(id -u)/com.deskrelay.codex.companion" >/dev/null 2>&1; then
  echo "LaunchAgent：com.deskrelay.codex.companion 已加载"
else
  echo "LaunchAgent：未发现已加载的 Companion LaunchAgent"
fi

LISTENER_PID="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | head -n 1 || true)"
if [[ -n "$LISTENER_PID" ]]; then
  echo "监听进程：PID ${LISTENER_PID}，端口 ${PORT}"
else
  echo "监听进程：未发现端口 ${PORT} 的监听进程"
fi

STATUS_BODY="$(mktemp)"
DIAGNOSTICS_BODY="$(mktemp)"
cleanup() {
  rm -f "$STATUS_BODY" "$DIAGNOSTICS_BODY"
}
trap cleanup EXIT

STATUS_CODE="$(curl -sS -o "$STATUS_BODY" -w '%{http_code}' "${AUTH_ARGS[@]}" "$STATUS_URL" || true)"
echo "状态接口：HTTP $STATUS_CODE"
if [[ "$STATUS_CODE" == "200" ]]; then
  "$NODE_BIN" - "$STATUS_BODY" <<'NODE'
const fs = require("fs");
const payload = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const root = payload.payload?.root ?? payload.root ?? payload ?? {};
const name = root.name ?? "unknown";
const mode = root.mode ?? root.status ?? "unknown";
const port = root.port ?? "unknown";
console.log(`设备：${name}`);
console.log(`模式：${mode}`);
console.log(`服务端口：${port}`);
NODE
fi

DIAGNOSTICS_CODE="$(curl -sS -o "$DIAGNOSTICS_BODY" -w '%{http_code}' "${AUTH_ARGS[@]}" "$DIAGNOSTICS_URL" || true)"
echo "诊断接口：HTTP $DIAGNOSTICS_CODE"
