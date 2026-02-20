# Talkback - Claude Code Voice Plugin Design

## Overview

Talkback is a Claude Code plugin that automatically reads Claude's text responses aloud using local text-to-speech via Kokoro TTS. No cloud API needed, no costs, fully offline.

## Goals

- Automatic TTS for every Claude Code response (no manual triggering)
- Zero-config after initial setup
- Local/offline TTS via Kokoro (free, no API keys)
- Seamless integration like superpowers plugin
- Distributable via Claude Code plugin marketplace

## Architecture: Hook + Config

Uses a `Stop` hook that fires when Claude finishes responding, providing `last_assistant_message` via JSON stdin. A shell script reads config, sends text to local Kokoro API, plays audio. No persistent server process beyond Kokoro itself.

## Plugin Structure

```
talkback/
├── .claude-plugin/
│   ├── plugin.json              # Plugin manifest
│   └── marketplace.json         # Marketplace catalog (for distribution)
├── hooks/
│   └── stop.json                 # Stop hook definition
├── scripts/
│   ├── speak.sh                 # Main: text → Kokoro API → audio playback
│   ├── setup-kokoro.sh          # Auto-install Kokoro (Docker/pip fallback)
│   └── toggle.sh                # Enable/disable TTS
├── skills/
│   ├── setup/
│   │   └── SKILL.md             # /talkback:setup - One-time Kokoro setup
│   ├── toggle/
│   │   └── SKILL.md             # /talkback:toggle - Enable/disable
│   └── voice/
│       └── SKILL.md             # /talkback:voice - Change voice/speed
├── config/
│   └── defaults.json            # Default settings template
├── LICENSE
└── README.md
```

## Hook Mechanism

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

### Flow

1. Claude finishes response → `Stop` event fires
2. Hook calls `speak.sh` with JSON via stdin (contains `last_assistant_message`)
3. `speak.sh` reads config from `~/.config/talkback/config.json`
4. If enabled: POST text to Kokoro at `http://localhost:8880/v1/audio/speech`
5. Kokoro returns audio → played via `afplay` (macOS) / `aplay` (Linux)
6. Runs asynchronously in background - does not block Claude Code

## Config

Stored at `~/.config/talkback/config.json`:

```json
{
  "enabled": true,
  "voice": "af_heart",
  "speed": 1.0,
  "language": "en",
  "kokoro_url": "http://localhost:8880",
  "provider": "kokoro"
}
```

## Setup Flow (/talkback:setup)

Fully automatic, no user interaction required:

1. Check if Kokoro is already reachable (`curl localhost:8880`)
   - Yes → Write config, done
   - No → Continue
2. Check if Docker is available
   - Yes → `docker run` Kokoro container → done
3. Check if Python 3.8+ is available
   - Yes → `pip install kokoro-fastapi` → start server → done
4. Neither available → Error message: "Install Docker or Python 3.8+"

## Skills

### /talkback:setup
- One-time Kokoro installation
- Auto-detects best installation method
- Writes initial config

### /talkback:toggle
- Toggle TTS on/off
- Updates config.json `enabled` field

### /talkback:voice
- List available Kokoro voices
- Change voice, speed, language
- Updates config.json

## Distribution

### Installation (end user)
```
/plugin marketplace add username/talkback    # Register marketplace
/plugin                                       # Open UI → Discover → Install
/talkback:setup                               # One-time Kokoro setup
```

### GitHub Repo Structure
The repo serves as both marketplace and plugin:
- `.claude-plugin/marketplace.json` lists the talkback plugin
- `.claude-plugin/plugin.json` contains plugin metadata

## TTS Provider

### Primary: Kokoro (local, free)
- Apache 2.0 license, ~300MB model
- OpenAI-compatible API (`/v1/audio/speech`)
- Good English quality, German still limited
- Runs on CPU, no GPU needed

### Future options (architecture supports swapping):
- OpenAI TTS ($0.60/1M chars, excellent German)
- ElevenLabs (best quality, expensive)
- Piper (free, good German)

## Technical Requirements

- macOS or Linux
- Docker OR Python 3.8+
- ~500MB disk space (Kokoro model + container)
- Audio output device

## Name

"Talkback" - not trademarked by Google (not on their official trademark list, TalkBack was rebranded to Android Accessibility Suite in 2018, source code is Apache 2.0).
