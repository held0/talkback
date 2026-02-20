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
  mkdir -p "$CONFIG_DIR"
  echo "Starting Kokoro server..."
  nohup python3 -m kokoro_fastapi --host 0.0.0.0 --port 8880 > "${CONFIG_DIR}/kokoro.log" 2>&1 &
  KOKORO_PID=$!
  echo "$KOKORO_PID" > "${CONFIG_DIR}/kokoro.pid"
  echo "Waiting for Kokoro to start..."
  for i in $(seq 1 60); do
    if curl -s --max-time 2 "${KOKORO_URL}/v1/models" > /dev/null 2>&1; then
      echo "Kokoro started successfully! (PID: $KOKORO_PID)"
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
