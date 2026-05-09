#!/usr/bin/env bash
set -euo pipefail

LEGACY_HOME="${ICODEX_COMPANION_HOME:-$HOME/.icodex-companion}"
LAUNCH_DOMAIN="gui/$(id -u)"
LEGACY_LABELS=(
  "com.danxizuo.icodex-companion"
  "com.danxizuo.icodex-companion-cloudflared"
)
LEGACY_PROCESS_PATTERNS=(
  "$LEGACY_HOME/app/packages/companion/dist/cli.js"
  "cloudflared.*icodex-companion"
)

removed_service=0
for label in "${LEGACY_LABELS[@]}"; do
  plist_path="$HOME/Library/LaunchAgents/$label.plist"
  launchctl_target="$LAUNCH_DOMAIN/$label"
  if launchctl print "$launchctl_target" >/dev/null 2>&1; then
    /bin/launchctl bootout "$LAUNCH_DOMAIN" "$plist_path" >/dev/null 2>&1 \
      || /bin/launchctl bootout "$launchctl_target" >/dev/null 2>&1 \
      || true
    removed_service=1
  fi
  if [[ -f "$plist_path" ]]; then
    rm -f "$plist_path"
    removed_service=1
  fi
done

for process_pattern in "${LEGACY_PROCESS_PATTERNS[@]}"; do
  if pgrep -f "$process_pattern" >/dev/null 2>&1; then
    pkill -TERM -f "$process_pattern" || true
    removed_service=1
  fi
done

if [[ "$removed_service" == "1" ]]; then
  echo "Removed legacy iCodex Companion service entries."
fi

if [[ "${1:-}" == "--remove-data" ]]; then
  if [[ "$LEGACY_HOME" != "$HOME/.icodex-companion" && "$LEGACY_HOME" != "$HOME/.icodex-companion/"* ]]; then
    echo "Refusing to remove unexpected legacy Companion directory: $LEGACY_HOME" >&2
    exit 1
  fi
  rm -rf "$LEGACY_HOME"
  echo "Removed legacy iCodex Companion data directory: $LEGACY_HOME"
fi
