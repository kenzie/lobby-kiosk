#!/bin/bash
set -euo pipefail

# Chromium Kiosk Mode - Rapid MVP
export DISPLAY=:0

# Wait for app server
while ! curl -s http://localhost:8080/health >/dev/null; do
    echo "Waiting for app server..."
    sleep 2
done

echo "Starting Chromium kiosk mode..."

exec chromium \
    --no-sandbox \
    --disable-dev-shm-usage \
    --disable-gpu \
    --disable-features=TranslateUI \
    --disable-extensions \
    --disable-plugins \
    --disable-sync \
    --disable-translate \
    --hide-scrollbars \
    --no-first-run \
    --fast \
    --fast-start \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --autoplay-policy=no-user-gesture-required \
    --kiosk \
    --window-position=0,0 \
    --start-fullscreen \
    http://localhost:8080