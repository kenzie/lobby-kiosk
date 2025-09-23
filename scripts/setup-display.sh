#!/bin/bash
set -euo pipefail

# Display Setup Script - Systemd Service
export DISPLAY=:0

# Trap signals to clean up on exit
cleanup() {
    echo "Cleaning up display service..."
    pkill -f "chromium" || true
    pkill -f "Xorg" || true
    pkill -f "unclutter" || true
    exit 0
}
trap cleanup SIGTERM SIGINT

# Kill existing X server
pkill -f "Xorg" || true
sleep 2

# Clean lock files (skip if permission denied)
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 2>/dev/null || true

# Start X server
startx /opt/lobby/scripts/chromium-kiosk.sh -- :0 vt7 -quiet -nolisten tcp &
X_PID=$!

# Wait for X to start
for i in {1..30}; do
    if xset -display :0 q &>/dev/null; then
        echo "X server started"
        break
    fi
    sleep 1
done

# Configure display
xrandr --auto
xset -display :0 s off
xset -display :0 -dpms
xset -display :0 s noblank

# Apply custom XKB configuration if available
if [[ -f "/usr/share/X11/xkb/symbols/lobby/kiosk" ]]; then
    setxkbmap -display :0 -symbols "lobby/kiosk(basic)" 2>/dev/null || true
fi

# Hide cursor
unclutter -display :0 -idle 1 -root &

echo "Display setup complete"

# Keep the service running by monitoring X server
while kill -0 $X_PID 2>/dev/null; do
    sleep 10
    # Check if X is still responsive
    if ! xset -display :0 q &>/dev/null; then
        echo "X server became unresponsive, restarting..."
        break
    fi
done

echo "X server stopped, exiting"