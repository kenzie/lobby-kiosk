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
    --disable-background-networking \
    --disable-background-timer-throttling \
    --disable-backgrounding-occluded-windows \
    --disable-breakpad \
    --disable-client-side-phishing-detection \
    --disable-component-extensions-with-background-pages \
    --disable-default-apps \
    --disable-features=VizDisplayCompositor \
    --disable-hang-monitor \
    --disable-ipc-flooding-protection \
    --disable-popup-blocking \
    --disable-prompt-on-repost \
    --disable-renderer-backgrounding \
    --disable-sync \
    --disable-web-security \
    --metrics-recording-only \
    --no-crash-upload \
    --no-default-browser-check \
    --no-pings \
    --hide-scrollbars \
    --no-first-run \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --autoplay-policy=no-user-gesture-required \
    --kiosk \
    --start-fullscreen \
    --window-size=3840,2160 \
    --force-device-scale-factor=1 \
    http://localhost:8080