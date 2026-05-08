#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_PATH="$ROOT_DIR/scripts/deskrelay-runtime-actions.tsv"
ACTION_ID="${1:-}"

if [[ ! -f "$MANIFEST_PATH" ]]; then
  echo "Runtime action manifest not found: $MANIFEST_PATH" >&2
  exit 1
fi

if [[ -z "$ACTION_ID" || "$ACTION_ID" == "list" ]]; then
  awk -F '\t' 'NR > 1 { printf "%s\t%s\t%s\n", $1, $2, $3 }' "$MANIFEST_PATH"
  exit 0
fi

SCRIPT_NAME=""
ACTION_NAME=""
while IFS=$'\t' read -r id name script_name _delay_ms _system_image_name; do
  [[ "$id" == "id" ]] && continue
  if [[ "$id" == "$ACTION_ID" ]]; then
    ACTION_NAME="$name"
    SCRIPT_NAME="$script_name"
    break
  fi
done < "$MANIFEST_PATH"

if [[ -z "$SCRIPT_NAME" ]]; then
  echo "Unsupported runtime action: $ACTION_ID" >&2
  exit 1
fi

SCRIPT_PATH="$ROOT_DIR/scripts/$SCRIPT_NAME"
if [[ ! -f "$SCRIPT_PATH" ]]; then
  echo "Runtime action script not found for $ACTION_NAME: $SCRIPT_PATH" >&2
  exit 1
fi

cd "$ROOT_DIR"
exec /bin/bash "$SCRIPT_PATH"
