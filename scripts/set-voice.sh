#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${HOME}/.config/talkback/config.json"
VOICE="${1:-}"

if [ -z "$VOICE" ]; then
  echo "Usage: set-voice.sh <voice-name>"
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Talkback not configured yet. Run /talkback:setup first."
  exit 1
fi

jq --arg v "$VOICE" '.voice = $v' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
echo "Voice set to: $VOICE"
