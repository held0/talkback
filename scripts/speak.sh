#!/usr/bin/env bash
set -uo pipefail

CONFIG_DIR="${HOME}/.config/talkback"
CONFIG_FILE="${CONFIG_DIR}/config.json"
LOG_FILE="${CONFIG_DIR}/talkback.log"

log() { echo "$(date '+%H:%M:%S'): $1" >> "$LOG_FILE"; }

log "speak.sh called (PID $$)"

# Read hook input from stdin into a temp file (avoids bash string mangling)
INPUT_FILE="$(mktemp /tmp/talkback_input_XXXXXX).json"
cat > "$INPUT_FILE"
INPUT_SIZE=$(wc -c < "$INPUT_FILE" | tr -d ' ')
log "input file: $INPUT_FILE, size: ${INPUT_SIZE} bytes"

# Skip if no input
if [ "$INPUT_SIZE" -lt 5 ]; then
  log "input too small, skipping"
  rm -f "$INPUT_FILE"
  exit 0
fi

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

log "config: enabled=$ENABLED voice=$VOICE speed=$SPEED"

# Exit silently if disabled
if [ "$ENABLED" != "true" ]; then
  log "disabled, skipping"
  rm -f "$INPUT_FILE"
  exit 0
fi

# Extract the assistant message from hook input (read from file, not variable)
MESSAGE=$(jq -r '.last_assistant_message // empty' "$INPUT_FILE" 2>/dev/null || true)
rm -f "$INPUT_FILE"

if [ -z "$MESSAGE" ]; then
  log "no last_assistant_message found, skipping"
  exit 0
fi

MSG_LEN=${#MESSAGE}
log "message extracted, length: $MSG_LEN chars"

# Truncate to max chars
MESSAGE=$(printf '%s' "$MESSAGE" | head -c "$MAX_CHARS")

# Strip markdown formatting for cleaner speech
MESSAGE=$(printf '%s' "$MESSAGE" | sed 's/```[^`]*```//g' | sed 's/`[^`]*`//g' | sed 's/[#*_~>]//g')

# Skip if message is too short after cleanup
if [ ${#MESSAGE} -lt 5 ]; then
  log "message too short after cleanup, skipping"
  exit 0
fi

log "cleaned message length: ${#MESSAGE} chars"

# Check if Kokoro is reachable (quick timeout)
if ! curl -s --max-time 2 "${KOKORO_URL}/v1/models" > /dev/null 2>&1; then
  log "Kokoro not reachable at ${KOKORO_URL}, skipping"
  exit 0
fi

log "Kokoro reachable, sending TTS request..."

# Create temp file for audio
AUDIO_FILE="$(mktemp /tmp/talkback_XXXXXX).mp3"

# Build JSON payload safely - write to file to avoid shell escaping issues
PAYLOAD_FILE="$(mktemp /tmp/talkback_payload_XXXXXX).json"
jq -n --arg input "$MESSAGE" --arg voice "$VOICE" --argjson speed "$SPEED" \
  '{model: "kokoro", input: $input, voice: $voice, speed: $speed, response_format: "mp3"}' > "$PAYLOAD_FILE"

log "payload file: $(cat "$PAYLOAD_FILE" | head -c 200)"

# Send to Kokoro TTS API (OpenAI-compatible)
CURL_ERR="$(mktemp /tmp/talkback_curlerr_XXXXXX).txt"
HTTP_CODE=$(curl -s -w "%{http_code}" -o "$AUDIO_FILE" \
  --max-time 25 \
  -X POST "${KOKORO_URL}/v1/audio/speech" \
  -H "Content-Type: application/json" \
  -d @"$PAYLOAD_FILE" 2>"$CURL_ERR")
CURL_EXIT=$?
log "curl exit code: $CURL_EXIT, stderr: $(cat "$CURL_ERR")"
rm -f "$PAYLOAD_FILE" "$CURL_ERR"

AUDIO_SIZE=$(wc -c < "$AUDIO_FILE" | tr -d ' ')
log "Kokoro response: HTTP $HTTP_CODE, audio size: ${AUDIO_SIZE} bytes"

if [ "$HTTP_CODE" != "200" ]; then
  log "TTS failed with HTTP $HTTP_CODE"
  rm -f "$AUDIO_FILE"
  exit 0
fi

if [ "$AUDIO_SIZE" -lt 100 ]; then
  log "audio file too small (${AUDIO_SIZE} bytes), skipping playback"
  rm -f "$AUDIO_FILE"
  exit 0
fi

# Play audio based on platform (in background, don't block)
log "playing audio via afplay..."
if command -v afplay &> /dev/null; then
  afplay "$AUDIO_FILE" && rm -f "$AUDIO_FILE" &
  log "afplay started in background (PID $!)"
elif command -v mpv &> /dev/null; then
  mpv --no-terminal "$AUDIO_FILE" && rm -f "$AUDIO_FILE" &
  log "mpv started in background"
elif command -v aplay &> /dev/null; then
  aplay "$AUDIO_FILE" && rm -f "$AUDIO_FILE" &
  log "aplay started in background"
else
  log "no audio player found!"
  rm -f "$AUDIO_FILE"
fi

exit 0
