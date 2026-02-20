#!/usr/bin/env bash
set -uo pipefail

CONFIG_DIR="${HOME}/.config/talkback"
CONFIG_FILE="${CONFIG_DIR}/config.json"

# Read hook input from stdin into a temp file (avoids bash string mangling)
INPUT_FILE=$(mktemp /tmp/talkback_input_XXXXXX.json)
cat > "$INPUT_FILE"

# Load config (or defaults if no config exists)
if [ -f "$CONFIG_FILE" ]; then
  ENABLED=$(jq -r '.enabled // true' "$CONFIG_FILE")
  VOICE=$(jq -r '.voice // "af_heart"' "$CONFIG_FILE")
  SPEED=$(jq -r '.speed // 1.0' "$CONFIG_FILE")
  KOKORO_URL=$(jq -r '.kokoro_url // "http://localhost:8880"' "$CONFIG_FILE")
  MAX_CHARS=$(jq -r '.max_chars // 5000' "$CONFIG_FILE")
else
  ENABLED="true"
  VOICE="af_heart"
  SPEED="1.0"
  KOKORO_URL="http://localhost:8880"
  MAX_CHARS="5000"
fi

# Exit silently if disabled
if [ "$ENABLED" != "true" ]; then
  rm -f "$INPUT_FILE"
  exit 0
fi

# Extract the assistant message from hook input (read from file, not variable)
MESSAGE=$(jq -r '.last_assistant_message // empty' "$INPUT_FILE" 2>/dev/null || true)
rm -f "$INPUT_FILE"

if [ -z "$MESSAGE" ]; then
  exit 0
fi

# Truncate to max chars
MESSAGE=$(printf '%s' "$MESSAGE" | head -c "$MAX_CHARS")

# Strip markdown formatting for cleaner speech
MESSAGE=$(printf '%s' "$MESSAGE" | sed 's/```[^`]*```//g' | sed 's/`[^`]*`//g' | sed 's/[#*_~>]//g')

# Skip if message is too short after cleanup
if [ ${#MESSAGE} -lt 5 ]; then
  exit 0
fi

# Check if Kokoro is reachable (quick timeout)
if ! curl -s --max-time 2 "${KOKORO_URL}/v1/models" > /dev/null 2>&1; then
  exit 0
fi

# Create temp file for audio
AUDIO_FILE=$(mktemp /tmp/talkback_XXXXXX.mp3)

# Build JSON payload safely (pipe message through jq to handle special chars)
JSON_PAYLOAD=$(printf '%s' "$MESSAGE" | jq -Rs --arg voice "$VOICE" --argjson speed "$SPEED" \
  '{model: "kokoro", input: ., voice: $voice, speed: $speed, response_format: "mp3"}')

# Send to Kokoro TTS API (OpenAI-compatible)
HTTP_CODE=$(curl -s -w "%{http_code}" -o "$AUDIO_FILE" \
  -X POST "${KOKORO_URL}/v1/audio/speech" \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD")

if [ "$HTTP_CODE" != "200" ]; then
  rm -f "$AUDIO_FILE"
  exit 0
fi

# Play audio based on platform (in background, don't block)
if command -v afplay &> /dev/null; then
  afplay "$AUDIO_FILE" && rm -f "$AUDIO_FILE" &
elif command -v mpv &> /dev/null; then
  mpv --no-terminal "$AUDIO_FILE" && rm -f "$AUDIO_FILE" &
elif command -v aplay &> /dev/null; then
  aplay "$AUDIO_FILE" && rm -f "$AUDIO_FILE" &
else
  rm -f "$AUDIO_FILE"
fi

exit 0
