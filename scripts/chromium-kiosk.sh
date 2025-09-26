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

# Check if we should start in screensaver mode
if [[ -f "/opt/lobby/config/screensaver.state" ]] && [[ $(cat /opt/lobby/config/screensaver.state 2>/dev/null) == "active" ]]; then
    URL="file:///opt/lobby/scripts/screensaver.html"
    echo "Starting in screensaver mode"
else
    URL="http://localhost:8080"
    echo "Starting in normal mode"
fi

exec chromium \
    --no-sandbox \
    --disable-dev-shm-usage \
    --enable-gpu \
    --enable-gpu-rasterization \
    --enable-zero-copy \
    --disable-features=TranslateUI,VizDisplayCompositor,MediaRouter \
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
    --disable-hang-monitor \
    --disable-ipc-flooding-protection \
    --disable-popup-blocking \
    --disable-prompt-on-repost \
    --disable-renderer-backgrounding \
    --user-data-dir=/tmp/chromium-kiosk \
    --disable-web-security \
    --disable-dbus \
    --disable-d3d11 \
    --disable-gl-drawing-for-tests \
    --disable-gpu-sandbox \
    --disable-software-rasterizer \
    --disable-background-mode \
    --disable-component-update \
    --disable-domain-reliability \
    --disable-notifications \
    --disable-permissions-api \
    --disable-speech-api \
    --disable-web-resources \
    --no-service-autorun \
    --no-wifi \
    --metrics-recording-only \
    --no-crash-upload \
    --no-default-browser-check \
    --no-pings \
    --hide-scrollbars \
    --no-first-run \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --autoplay-policy=no-user-gesture-required \
    --enable-accelerated-video-decode \
    --enable-accelerated-mjpeg-decode \
    --enable-hardware-overlays \
    --disable-logging \
    --disable-login-animations \
    --disable-modal-animations \
    --wm-window-animations-disabled \
    --disable-office-editing-component-app \
    --disable-dinosaur-easter-egg \
    --disable-file-system \
    --disable-geolocation \
    --disable-ipc-flooding-protection \
    --disable-renderer-accessibility \
    --enable-threaded-animation \
    --enable-threaded-scrolling \
    --disable-in-process-stack-traces \
    --disable-histogram-customizer \
    --disable-gaia-services \
    --disable-search-engine-choice-screen \
    --disable-ipc-logging \
    --log-level=3 \
    --silent-debugger-extension-api \
    --disable-chrome-tracing \
    --kiosk \
    --start-fullscreen \
    --window-size=3840,2160 \
    --force-device-scale-factor=1 \
    "$URL" 2>/dev/null