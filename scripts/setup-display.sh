#!/bin/bash
set -euo pipefail

# Display Setup Script - Rapid MVP
export DISPLAY=:0

# Kill existing X server
pkill -f "Xorg" || true
sleep 2

# Clean lock files
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0

# Start X server
startx /opt/lobby/scripts/chromium-kiosk.sh -- :0 vt7 -quiet -nolisten tcp &

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

# Hide cursor
unclutter -display :0 -idle 1 -root &

echo "Display setup complete"