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

# Step 2: Try Docker (only if daemon is actually running)
if command -v docker &> /dev/null && docker info > /dev/null 2>&1; then
  echo "Docker found and running. Starting Kokoro TTS container..."
  docker rm -f talkback-kokoro 2>/dev/null || true
  if docker run -d \
    --name talkback-kokoro \
    -p 8880:8880 \
    --restart unless-stopped \
    ghcr.io/remsky/kokoro-fastapi-cpu:latest \
    > /dev/null 2>&1; then
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
    echo "WARNING: Kokoro container started but API not reachable after 60s."
    echo "Trying pip fallback..."
  else
    echo "Docker run failed. Trying pip fallback..."
  fi
elif command -v docker &> /dev/null; then
  echo "Docker installed but daemon not running. Trying pip fallback..."
fi

# Step 3: Try pip (in venv to avoid system Python restrictions)
if command -v python3 &> /dev/null; then
  VENV_DIR="${CONFIG_DIR}/venv"
  echo "Python found. Setting up Kokoro in virtual environment..."
  mkdir -p "$CONFIG_DIR"
  python3 -m venv "$VENV_DIR" 2>&1
  echo "Installing kokoro TTS library (this may take a few minutes)..."
  "${VENV_DIR}/bin/pip" install --upgrade pip > /dev/null 2>&1
  "${VENV_DIR}/bin/pip" install kokoro soundfile numpy 2>&1
  echo "Starting Kokoro TTS server..."
  nohup "${VENV_DIR}/bin/python" "${PLUGIN_DIR}/scripts/kokoro-server.py" --port 8880 > "${CONFIG_DIR}/kokoro.log" 2>&1 &
  KOKORO_PID=$!
  echo "$KOKORO_PID" > "${CONFIG_DIR}/kokoro.pid"
  echo "Waiting for Kokoro to start (first run downloads the model, may take a minute)..."
  for i in $(seq 1 120); do
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
  echo "ERROR: Kokoro installed but server not reachable after 240s"
  echo "Check logs: ${CONFIG_DIR}/kokoro.log"
  echo "Try manually: ${VENV_DIR}/bin/python ${PLUGIN_DIR}/scripts/kokoro-server.py"
  exit 1
fi

# Step 4: Nothing available
echo "ERROR: Neither Docker (running) nor Python 3 found."
echo ""
echo "Please either:"
echo "  - Start Docker Desktop and run /talkback:setup again"
echo "  - Install Python 3.8+: https://www.python.org/downloads/"
echo ""
echo "Then run /talkback:setup again."
exit 1
