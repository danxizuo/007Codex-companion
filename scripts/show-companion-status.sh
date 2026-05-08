#!/usr/bin/env bash
set -euo pipefail

read_deskrelay_env() {
  local primary="$1"
  local legacy="$2"
  local fallback="${3-}"
  local value="${!primary-}"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return
  fi
  value="${!legacy-}"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return
  fi
  printf '%s' "$fallback"
}

CONFIG_FILE="$(read_deskrelay_env DESKRELAY_COMPANION_CONFIG ICODEX_COMPANION_CONFIG "$HOME/.deskrelay-companion/config.json")"
AUTH_FILE="$(read_deskrelay_env DESKRELAY_COMPANION_AUTH_TOKEN_FILE ICODEX_COMPANION_AUTH_TOKEN_FILE "$HOME/.deskrelay-companion/auth-token")"
LABEL="$(read_deskrelay_env DESKRELAY_COMPANION_LAUNCH_LABEL ICODEX_COMPANION_LAUNCH_LABEL "com.deskrelay.codex.companion")"
LEGACY_LABEL="com.danxizuo.icodex-companion"
NODE_BIN="${NODE_BIN:-$(command -v node || true)}"
if [[ -z "$NODE_BIN" && -x /opt/miniconda3/bin/node ]]; then
  NODE_BIN="/opt/miniconda3/bin/node"
fi

if ! launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1 \
  && launchctl print "gui/$(id -u)/$LEGACY_LABEL" >/dev/null 2>&1; then
  CONFIG_FILE="$HOME/.icodex-companion/config.json"
  AUTH_FILE="$HOME/.icodex-companion/auth-token"
fi

if [[ ! -f "$CONFIG_FILE" && -f "$HOME/.icodex-companion/config.json" ]]; then
  CONFIG_FILE="$HOME/.icodex-companion/config.json"
fi
if [[ ! -f "$AUTH_FILE" && -f "$HOME/.icodex-companion/auth-token" ]]; then
  AUTH_FILE="$HOME/.icodex-companion/auth-token"
fi
if [[ ! -f "$AUTH_FILE" && -f "$HOME/.codex/deskrelay-companion-auth-token" ]]; then
  AUTH_FILE="$HOME/.codex/deskrelay-companion-auth-token"
fi

read_config_value() {
  if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" || ! -f "$CONFIG_FILE" ]]; then
    return 0
  fi
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

PORT="$(read_config_value port)"
PORT="${PORT:-3939}"
PUBLIC_BASE_URL="$(read_config_value publicBaseURL)"
LOCAL_STATUS_URL="http://127.0.0.1:${PORT}/status"
AUTH_ARGS=()

if [[ -f "$AUTH_FILE" ]]; then
  AUTH_TOKEN="$(tr -d '\r\n' < "$AUTH_FILE")"
  if [[ -n "$AUTH_TOKEN" ]]; then
    AUTH_ARGS=(-H "authorization: Bearer $AUTH_TOKEN")
  fi
fi

echo "Companion 状态"
echo
echo "配置文件：$CONFIG_FILE"
echo "访问密钥：$AUTH_FILE"
echo "本机地址：$LOCAL_STATUS_URL"
if [[ -n "$PUBLIC_BASE_URL" ]]; then
  echo "公网地址：$PUBLIC_BASE_URL"
fi
echo

for candidate in "$LABEL" "$LEGACY_LABEL"; do
  if launchctl print "gui/$(id -u)/$candidate" >/dev/null 2>&1; then
    echo "LaunchAgent：$candidate"
    launchctl print "gui/$(id -u)/$candidate" 2>/dev/null \
      | awk '/state =|pid =|path =|working directory =/{ print }'
    echo
    break
  fi
done

STATUS_BODY="$(mktemp)"
cleanup() {
  rm -f "$STATUS_BODY"
}
trap cleanup EXIT

HTTP_CODE="$(curl -sS -o "$STATUS_BODY" -w '%{http_code}' "${AUTH_ARGS[@]}" "$LOCAL_STATUS_URL" || true)"
echo "本机 /status：$HTTP_CODE"
if [[ "$HTTP_CODE" == "200" ]]; then
  if [[ -n "$NODE_BIN" && -x "$NODE_BIN" ]]; then
    "$NODE_BIN" - "$STATUS_BODY" <<'NODE'
const fs = require("fs");
try {
  const payload = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
  console.log(`名称：${payload.name ?? ""}`);
  console.log(`连接：${payload.mode ?? payload.status ?? ""}`);
  console.log(`app-server：${payload.appServer?.connectionStatus ?? ""}`);
  console.log(`会话数：${payload.runtime?.threads ?? ""}`);
} catch {
  process.exit(1);
}
NODE
  else
    cat "$STATUS_BODY"
    echo
  fi
else
  cat "$STATUS_BODY" >&2 || true
  echo >&2
  exit 1
fi
