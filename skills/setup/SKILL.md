---
name: setup
description: Set up Talkback TTS. Run this once after installing the talkback plugin to configure Kokoro text-to-speech.
---

# Talkback Setup

Run the setup script to install and configure Kokoro TTS:

!`${CLAUDE_PLUGIN_ROOT}/scripts/setup-kokoro.sh`

After setup completes, Claude will automatically read responses aloud.

If setup fails, check the error message and ensure Docker or Python 3.8+ is installed.
