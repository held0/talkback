#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${HOME}/.config/talkback/config.json"
KOKORO_URL="http://localhost:8880"
CURRENT_VOICE="af_heart"

if [ -f "$CONFIG_FILE" ]; then
  KOKORO_URL=$(jq -r '.kokoro_url // "http://localhost:8880"' "$CONFIG_FILE")
  CURRENT_VOICE=$(jq -r '.voice // "af_heart"' "$CONFIG_FILE")
fi

echo "Current voice: ${CURRENT_VOICE}"
echo ""
echo "Available voices:"

RESPONSE=$(curl -s --max-time 5 "${KOKORO_URL}/v1/audio/voices" 2>/dev/null || echo "")

if [ -n "$RESPONSE" ]; then
  echo "$RESPONSE" | jq -r '.voices[]? // .[]?' 2>/dev/null || echo "$RESPONSE"
else
  echo "  Cannot reach Kokoro at ${KOKORO_URL}"
  echo "  Run /talkback:setup first."
fi
