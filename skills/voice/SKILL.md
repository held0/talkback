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
