#!/bin/sh
set -eu

# Start the local PicoLM OpenAI-compatible adapter first.
/app/local-llm-proxy &
PROXY_PID=$!

cleanup() {
  kill "$PROXY_PID" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

# PicoClaw's launcher serves the configuration WebUI and can spawn the gateway.
# Render routes its public HTTP port to container port 8080.
exec /app/picoclaw-launcher -port 8080 -public
