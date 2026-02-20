# Talkback

Automatic text-to-speech for Claude Code. Claude reads its responses aloud using local [Kokoro TTS](https://github.com/remsky/kokoro-fastapi) - free, offline, no API keys needed.

## Install

```bash
/plugin marketplace add YOUR_USERNAME/talkback
```

Then open `/plugin`, go to Discover, and install talkback. After that:

```bash
/talkback:setup
```

This auto-installs Kokoro TTS via Docker or pip.

## Requirements

- macOS or Linux
- Docker **or** Python 3.8+
- ~500MB disk space (Kokoro model)

## Skills

| Skill | Description |
|---|---|
| `/talkback:setup` | One-time Kokoro TTS setup |
| `/talkback:toggle` | Turn voice on/off |
| `/talkback:voice` | Change voice or speed |

## How It Works

A `Stop` hook fires after every Claude response. The hook script sends the response text to a local Kokoro TTS server and plays the audio in the background. Claude Code is not blocked - you can keep typing while audio plays.

## Config

Settings stored at `~/.config/talkback/config.json`:

| Setting | Default | Description |
|---|---|---|
| `enabled` | `true` | TTS on/off |
| `voice` | `af_heart` | Kokoro voice name |
| `speed` | `1.0` | Speech speed (0.5-2.0) |
| `kokoro_url` | `http://localhost:8880` | Kokoro API endpoint |
| `max_chars` | `5000` | Max chars to speak per response |

## License

MIT
