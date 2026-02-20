#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${HOME}/.config/talkback"
CONFIG_FILE="${CONFIG_DIR}/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Talkback not configured yet. Run /talkback:setup first."
  exit 1
fi

CURRENT=$(jq -r '.enabled' "$CONFIG_FILE")

if [ "$CURRENT" = "true" ]; then
  jq '.enabled = false' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  echo "Talkback: OFF"
else
  jq '.enabled = true' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  echo "Talkback: ON"
fi
