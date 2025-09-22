#!/bin/bash
set -euo pipefail

# Lobby Kiosk System Update Script
# Updates system configuration from latest git repository

REPO_URL="https://github.com/kenzie/lobby-kiosk.git"
KIOSK_DIR="/opt/lobby"
TEMP_DIR="/tmp/lobby-update-$$"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR: $1${NC}"; exit 1; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING: $1${NC}"; }

# Check if running as root
[[ $EUID -ne 0 ]] && error "Must run as root"

log "Starting lobby-kiosk system update..."

# Create temp directory
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Clone latest repository
log "Downloading latest configuration..."
git clone "$REPO_URL" .

# Update scripts
log "Updating scripts..."
cp scripts/*.sh "$KIOSK_DIR/scripts/"
cp scripts/*.html "$KIOSK_DIR/scripts/" 2>/dev/null || true
chmod +x "$KIOSK_DIR/scripts"/*.sh
chmod 644 "$KIOSK_DIR/scripts"/*.html 2>/dev/null || true
chown lobby:lobby "$KIOSK_DIR/scripts"/*

# Update systemd services
log "Updating systemd services..."
cp configs/systemd/*.service /etc/systemd/system/
cp configs/systemd/*.target /etc/systemd/system/
systemctl daemon-reload

# Update nginx config
log "Updating nginx configuration..."
cp configs/nginx/nginx.conf /etc/nginx/

# Update management tools
log "Updating management tools..."
cp bin/lobby /usr/local/bin/
chmod +x /usr/local/bin/lobby

# Update sudo permissions
log "Updating sudo permissions..."
cat > /etc/sudoers.d/lobby << EOF
lobby ALL=(ALL) NOPASSWD: /usr/bin/systemctl
lobby ALL=(ALL) NOPASSWD: /usr/bin/reboot
lobby ALL=(ALL) NOPASSWD: /usr/local/bin/lobby *
lobby ALL=(ALL) NOPASSWD: /usr/bin/xset
lobby ALL=(ALL) NOPASSWD: /usr/bin/pacman -S --noconfirm xdotool
EOF
log "Sudoers updated successfully"

# Test nginx config
log "Testing nginx configuration..."
nginx -t || error "Invalid nginx configuration"

# Restart services
log "Restarting services..."
systemctl restart nginx.service
systemctl restart lobby-display.service

# Wait for services to stabilize
sleep 5

# Verify services are running
log "Verifying services..."
if ! systemctl is-active --quiet lobby-display.service; then
    error "lobby-display.service failed to start"
fi

if ! systemctl is-active --quiet nginx.service; then
    error "nginx.service failed to start"
fi

# Test app accessibility
log "Testing application..."
if ! curl -s http://localhost:8080/health >/dev/null; then
    error "Application not responding"
fi

# Cleanup
cd /
rm -rf "$TEMP_DIR"

log "Update complete! All services are running."
echo ""
echo "To check status: lobby status"
echo "To view logs: journalctl -u lobby-display.service -f"