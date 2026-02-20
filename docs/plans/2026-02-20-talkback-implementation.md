# Talkback Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Claude Code plugin that automatically reads Claude's responses aloud using local Kokoro TTS.

**Architecture:** `Stop` hook fires when Claude finishes responding. A bash script extracts `last_assistant_message` from the JSON stdin, sends it to Kokoro's OpenAI-compatible TTS API, and plays the resulting audio. Config stored in `~/.config/talkback/config.json`.

**Tech Stack:** Bash scripts, jq (JSON parsing), curl (HTTP), afplay/aplay (audio), Docker or pip (Kokoro install)

---

### Task 1: Plugin Manifest and Marketplace Config

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`

**Step 1: Create plugin.json**

```json
{
  "name": "talkback",
  "description": "Automatic text-to-speech for Claude Code responses using local Kokoro TTS",
  "version": "0.1.0",
  "author": {
    "name": "YOUR_NAME",
    "email": "YOUR_EMAIL"
  },
  "repository": "https://github.com/YOUR_USERNAME/talkback",
  "license": "MIT",
  "keywords": ["tts", "voice", "speech", "kokoro", "accessibility"],
  "skills": "./skills/",
  "hooks": ["./hooks/stop.json"]
}
```

**Step 2: Create marketplace.json**

```json
{
  "name": "talkback",
  "metadata": {
    "description": "Talkback - Automatic voice output for Claude Code"
  },
  "owner": {
    "name": "YOUR_NAME",
    "email": "YOUR_EMAIL"
  },
  "plugins": [
    {
      "name": "talkback",
      "description": "Automatic text-to-speech for Claude Code responses using local Kokoro TTS. Zero cost, fully offline.",
      "version": "0.1.0",
      "source": "./",
      "category": "productivity",
      "homepage": "https://github.com/YOUR_USERNAME/talkback"
    }
  ]
}
```

**Step 3: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "feat: add plugin manifest and marketplace config"
```

---

### Task 2: Config Defaults

**Files:**
- Create: `config/defaults.json`

**Step 1: Create defaults.json**

```json
{
  "enabled": true,
  "voice": "af_heart",
  "speed": 1.0,
  "kokoro_url": "http://localhost:8880",
  "max_chars": 5000
}
```

Note: `max_chars` prevents extremely long responses from blocking audio for minutes.

**Step 2: Commit**

```bash
git add config/defaults.json
git commit -m "feat: add default talkback config"
```

---

### Task 3: Core speak.sh Script

**Files:**
- Create: `scripts/speak.sh`

**Step 1: Create speak.sh**

This is the main script called by the Stop hook. It receives JSON via stdin with `last_assistant_message`.

```bash
#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${HOME}/.config/talkback"
CONFIG_FILE="${CONFIG_DIR}/config.json"
PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Read hook input from stdin
INPUT=$(cat)

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
  exit 0
fi

# Extract the assistant message from hook input
MESSAGE=$(echo "$INPUT" | jq -r '.last_assistant_message // empty')

if [ -z "$MESSAGE" ]; then
  exit 0
fi

# Truncate to max chars
MESSAGE=$(echo "$MESSAGE" | head -c "$MAX_CHARS")

# Strip markdown formatting for cleaner speech
MESSAGE=$(echo "$MESSAGE" | sed 's/```[^`]*```//g' | sed 's/`[^`]*`//g' | sed 's/[#*_~>]//g' | sed 's/\[([^]]*)\]([^)]*)/\1/g')

# Skip if message is too short after cleanup
if [ ${#MESSAGE} -lt 5 ]; then
  exit 0
fi

# Check if Kokoro is reachable
if ! curl -s --max-time 2 "${KOKORO_URL}/v1/models" > /dev/null 2>&1; then
  exit 0
fi

# Create temp file for audio
AUDIO_FILE=$(mktemp /tmp/talkback_XXXXXX.mp3)

# Send to Kokoro TTS API (OpenAI-compatible)
HTTP_CODE=$(curl -s -w "%{http_code}" -o "$AUDIO_FILE" \
  -X POST "${KOKORO_URL}/v1/audio/speech" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg model "kokoro" \
    --arg input "$MESSAGE" \
    --arg voice "$VOICE" \
    --argjson speed "$SPEED" \
    '{model: $model, input: $input, voice: $voice, speed: $speed, response_format: "mp3"}'
  )")

if [ "$HTTP_CODE" != "200" ]; then
  rm -f "$AUDIO_FILE"
  exit 0
fi

# Play audio based on platform (in background, don't block)
if command -v afplay &> /dev/null; then
  afplay "$AUDIO_FILE" && rm -f "$AUDIO_FILE" &
elif command -v aplay &> /dev/null; then
  mpv --no-terminal "$AUDIO_FILE" && rm -f "$AUDIO_FILE" &
elif command -v mpv &> /dev/null; then
  mpv --no-terminal "$AUDIO_FILE" && rm -f "$AUDIO_FILE" &
else
  rm -f "$AUDIO_FILE"
fi

exit 0
```

**Step 2: Make executable**

```bash
chmod +x scripts/speak.sh
```

**Step 3: Verify jq is available (needed for JSON parsing)**

```bash
which jq || echo "jq not found - needs to be installed"
```

**Step 4: Commit**

```bash
git add scripts/speak.sh
git commit -m "feat: add core speak.sh TTS script"
```

---

### Task 4: Stop Hook Configuration

**Files:**
- Create: `hooks/stop.json`

**Step 1: Create stop.json**

```json
{
  "description": "Talkback TTS - reads Claude responses aloud via Kokoro",
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/speak.sh",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

Note: Using `Stop` event which provides `last_assistant_message` in stdin JSON. Timeout of 30s prevents hanging if Kokoro is slow.

**Step 2: Commit**

```bash
git add hooks/stop.json
git commit -m "feat: add Stop hook for automatic TTS"
```

---

### Task 5: Setup Skill and Script

**Files:**
- Create: `skills/setup/SKILL.md`
- Create: `scripts/setup-kokoro.sh`

**Step 1: Create setup-kokoro.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${HOME}/.config/talkback"
CONFIG_FILE="${CONFIG_DIR}/config.json"
PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KOKORO_URL="http://localhost:8880"

echo "=== Talkback Setup ==="

# Step 1: Check if Kokoro is already running
echo "Checking if Kokoro TTS is already running..."
if curl -s --max-time 3 "${KOKORO_URL}/v1/models" > /dev/null 2>&1; then
  echo "Kokoro is already running at ${KOKORO_URL}"
  mkdir -p "$CONFIG_DIR"
  if [ ! -f "$CONFIG_FILE" ]; then
    cp "${PLUGIN_DIR}/config/defaults.json" "$CONFIG_FILE"
  fi
  echo "Config written to ${CONFIG_FILE}"
  echo "=== Talkback is ready! ==="
  exit 0
fi

# Step 2: Try Docker
if command -v docker &> /dev/null; then
  echo "Docker found. Starting Kokoro TTS container..."

  # Stop existing container if any
  docker rm -f talkback-kokoro 2>/dev/null || true

  docker run -d \
    --name talkback-kokoro \
    -p 8880:8880 \
    --restart unless-stopped \
    ghcr.io/remsky/kokoro-fastapi-cpu:v0.4.6 \
    > /dev/null 2>&1

  echo "Waiting for Kokoro to start..."
  for i in $(seq 1 30); do
    if curl -s --max-time 2 "${KOKORO_URL}/v1/models" > /dev/null 2>&1; then
      echo "Kokoro started successfully!"
      mkdir -p "$CONFIG_DIR"
      if [ ! -f "$CONFIG_FILE" ]; then
        cp "${PLUGIN_DIR}/config/defaults.json" "$CONFIG_FILE"
        jq '.install_method = "docker"' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
      fi
      echo "Config written to ${CONFIG_FILE}"
      echo "=== Talkback is ready! ==="
      exit 0
    fi
    sleep 2
  done

  echo "ERROR: Kokoro container started but API not reachable after 60s"
  echo "Check: docker logs talkback-kokoro"
  exit 1
fi

# Step 3: Try pip
if command -v python3 &> /dev/null && command -v pip3 &> /dev/null; then
  echo "Python found. Installing kokoro-fastapi via pip..."

  pip3 install kokoro-fastapi 2>&1

  echo "Starting Kokoro server..."
  nohup python3 -m kokoro_fastapi --host 0.0.0.0 --port 8880 > "${CONFIG_DIR}/kokoro.log" 2>&1 &
  KOKORO_PID=$!
  echo "$KOKORO_PID" > "${CONFIG_DIR}/kokoro.pid"

  echo "Waiting for Kokoro to start..."
  for i in $(seq 1 60); do
    if curl -s --max-time 2 "${KOKORO_URL}/v1/models" > /dev/null 2>&1; then
      echo "Kokoro started successfully! (PID: $KOKORO_PID)"
      mkdir -p "$CONFIG_DIR"
      if [ ! -f "$CONFIG_FILE" ]; then
        cp "${PLUGIN_DIR}/config/defaults.json" "$CONFIG_FILE"
        jq '.install_method = "pip"' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
      fi
      echo "Config written to ${CONFIG_FILE}"
      echo "=== Talkback is ready! ==="
      exit 0
    fi
    sleep 2
  done

  echo "ERROR: Kokoro installed but API not reachable after 120s"
  echo "Check: ${CONFIG_DIR}/kokoro.log"
  exit 1
fi

# Step 4: Nothing available
echo "ERROR: Neither Docker nor Python 3 found."
echo ""
echo "Please install one of:"
echo "  - Docker: https://docs.docker.com/get-docker/"
echo "  - Python 3.8+: https://www.python.org/downloads/"
echo ""
echo "Then run /talkback:setup again."
exit 1
```

**Step 2: Make executable**

```bash
chmod +x scripts/setup-kokoro.sh
```

**Step 3: Create SKILL.md for /talkback:setup**

```markdown
---
name: setup
description: Set up Talkback TTS. Run this once after installing the talkback plugin to configure Kokoro text-to-speech.
---

# Talkback Setup

Run the setup script to install and configure Kokoro TTS:

!`${CLAUDE_PLUGIN_ROOT}/scripts/setup-kokoro.sh`

After setup completes, Claude will automatically read responses aloud.

If setup fails, check the error message and ensure Docker or Python 3.8+ is installed.
```

**Step 4: Commit**

```bash
git add scripts/setup-kokoro.sh skills/setup/SKILL.md
git commit -m "feat: add /talkback:setup skill with auto-install"
```

---

### Task 6: Toggle Skill

**Files:**
- Create: `skills/toggle/SKILL.md`
- Create: `scripts/toggle.sh`

**Step 1: Create toggle.sh**

```bash
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
```

**Step 2: Make executable**

```bash
chmod +x scripts/toggle.sh
```

**Step 3: Create SKILL.md**

```markdown
---
name: toggle
description: Toggle Talkback TTS on or off. Use when the user wants to mute or unmute voice output.
---

# Toggle Talkback

!`${CLAUDE_PLUGIN_ROOT}/scripts/toggle.sh`
```

**Step 4: Commit**

```bash
git add scripts/toggle.sh skills/toggle/SKILL.md
git commit -m "feat: add /talkback:toggle skill"
```

---

### Task 7: Voice Selection Skill

**Files:**
- Create: `skills/voice/SKILL.md`
- Create: `scripts/list-voices.sh`
- Create: `scripts/set-voice.sh`

**Step 1: Create list-voices.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${HOME}/.config/talkback/config.json"
KOKORO_URL="http://localhost:8880"

if [ -f "$CONFIG_FILE" ]; then
  KOKORO_URL=$(jq -r '.kokoro_url // "http://localhost:8880"' "$CONFIG_FILE")
  CURRENT_VOICE=$(jq -r '.voice // "af_heart"' "$CONFIG_FILE")
fi

echo "Current voice: ${CURRENT_VOICE:-af_heart}"
echo ""
echo "Available voices:"

RESPONSE=$(curl -s --max-time 5 "${KOKORO_URL}/v1/audio/voices" 2>/dev/null || echo "")

if [ -n "$RESPONSE" ]; then
  echo "$RESPONSE" | jq -r '.voices[]? // .[]?' 2>/dev/null || echo "$RESPONSE"
else
  echo "  Cannot reach Kokoro at ${KOKORO_URL}"
  echo "  Run /talkback:setup first."
fi
```

**Step 2: Create set-voice.sh**

```bash
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
```

**Step 3: Make executable**

```bash
chmod +x scripts/list-voices.sh scripts/set-voice.sh
```

**Step 4: Create SKILL.md**

```markdown
---
name: voice
description: Change Talkback voice settings. Use when the user wants to switch voices, change speed, or see available voices.
---

# Talkback Voice Settings

List available voices:

!`${CLAUDE_PLUGIN_ROOT}/scripts/list-voices.sh`

To change the voice, run:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/set-voice.sh <voice-name>
```

To change speed, edit `~/.config/talkback/config.json` and set `speed` (0.5 = slow, 1.0 = normal, 2.0 = fast).
```

**Step 5: Commit**

```bash
git add scripts/list-voices.sh scripts/set-voice.sh skills/voice/SKILL.md
git commit -m "feat: add /talkback:voice skill for voice selection"
```

---

### Task 8: Update Design Doc with Corrections

**Files:**
- Modify: `docs/plans/2026-02-20-talkback-design.md`

**Step 1: Update design doc**

Replace all references to `AssistantResponse` with `Stop`, and `$PLUGIN_DIR` with `${CLAUDE_PLUGIN_ROOT}`. Update the hook JSON format to match the correct schema.

**Step 2: Commit**

```bash
git add docs/plans/2026-02-20-talkback-design.md
git commit -m "docs: correct hook event name and env var in design"
```

---

### Task 9: README and LICENSE

**Files:**
- Create: `README.md`
- Create: `LICENSE`

**Step 1: Create README.md**

Write a concise README with:
- What talkback does (1-2 sentences)
- Installation (3 commands)
- Requirements (Docker or Python 3.8+)
- Configuration options
- How to toggle/change voice

**Step 2: Create MIT LICENSE file**

**Step 3: Commit**

```bash
git add README.md LICENSE
git commit -m "docs: add README and MIT license"
```

---

### Task 10: End-to-End Test

**Step 1: Start Kokoro locally**

```bash
docker run -d --name talkback-test -p 8880:8880 ghcr.io/remsky/kokoro-fastapi-cpu:v0.4.6
```

**Step 2: Test speak.sh manually**

```bash
echo '{"last_assistant_message": "Hello, this is a test of the talkback plugin.", "session_id": "test", "hook_event_name": "Stop"}' | ./scripts/speak.sh
```

Expected: Audio plays through speakers.

**Step 3: Test setup-kokoro.sh**

```bash
docker rm -f talkback-test
./scripts/setup-kokoro.sh
```

Expected: Detects Docker, starts container, writes config.

**Step 4: Test toggle.sh**

```bash
./scripts/toggle.sh  # Should say "OFF"
./scripts/toggle.sh  # Should say "ON"
```

**Step 5: Cleanup test container**

```bash
docker rm -f talkback-kokoro
```

**Step 6: Commit any fixes from testing**

```bash
git add -A && git commit -m "fix: adjustments from end-to-end testing"
```
