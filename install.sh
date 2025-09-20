#!/bin/bash
set -euo pipefail

# Lobby Kiosk System Installer - Rapid MVP
# Usage: curl -sSL https://raw.githubusercontent.com/kenzie/lobby-kiosk/main/install.sh | sudo bash

KIOSK_USER="lobby"
KIOSK_DIR="/opt/lobby"
REPO_URL="https://github.com/kenzie/lobby-display.git"
CONFIG_REPO_URL="https://raw.githubusercontent.com/kenzie/lobby-kiosk/main"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

# Check requirements
[[ $EUID -ne 0 ]] && error "Run as root"
[[ ! -f /etc/arch-release ]] && error "Arch Linux required"

log "Installing packages..."
pacman -Syu --noconfirm
pacman -S --noconfirm \
    git nginx nodejs npm chromium xorg-server xorg-xinit xorg-xset \
    xorg-xrandr mesa scrot unclutter sudo openssh tailscale cronie

# Create user and directories
log "Setting up user and directories..."
id "$KIOSK_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash -G video,audio "$KIOSK_USER"
mkdir -p "$KIOSK_DIR"/{app,config,logs,scripts,backups}
mkdir -p "$KIOSK_DIR/app"/{releases,shared}
chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR"

# Download and install configs
log "Installing configuration files..."
curl -sSL "$CONFIG_REPO_URL/configs/systemd/lobby-kiosk.target" -o /etc/systemd/system/lobby-kiosk.target
curl -sSL "$CONFIG_REPO_URL/configs/systemd/lobby-app.service" -o /etc/systemd/system/lobby-app.service  
curl -sSL "$CONFIG_REPO_URL/configs/systemd/lobby-display.service" -o /etc/systemd/system/lobby-display.service
curl -sSL "$CONFIG_REPO_URL/configs/systemd/lobby-watchdog.service" -o /etc/systemd/system/lobby-watchdog.service
curl -sSL "$CONFIG_REPO_URL/configs/nginx/nginx.conf" -o /etc/nginx/nginx.conf

# Download scripts
log "Installing management scripts..."
curl -sSL "$CONFIG_REPO_URL/scripts/setup-display.sh" -o "$KIOSK_DIR/scripts/setup-display.sh"
curl -sSL "$CONFIG_REPO_URL/scripts/chromium-kiosk.sh" -o "$KIOSK_DIR/scripts/chromium-kiosk.sh"
curl -sSL "$CONFIG_REPO_URL/scripts/build-app.sh" -o "$KIOSK_DIR/scripts/build-app.sh"
curl -sSL "$CONFIG_REPO_URL/scripts/watchdog.sh" -o "$KIOSK_DIR/scripts/watchdog.sh"
curl -sSL "$CONFIG_REPO_URL/bin/lobby" -o /usr/local/bin/lobby

# Make scripts executable
chmod +x "$KIOSK_DIR/scripts"/*.sh /usr/local/bin/lobby
chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR/scripts"

# Configure autologin
mkdir -p /etc/systemd/system/getty@tty1.service.d/
cat > /etc/systemd/system/getty@tty1.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin $KIOSK_USER --noclear %I \$TERM
EOF

# Configure sudo permissions
cat > /etc/sudoers.d/lobby << EOF
$KIOSK_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart lobby-*.service
$KIOSK_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl reload nginx
$KIOSK_USER ALL=(ALL) NOPASSWD: /usr/bin/reboot
EOF

# Initial app deployment
log "Building initial application..."
echo "2.0.0" > "$KIOSK_DIR/config/version"
chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR/config/version"
sudo -u "$KIOSK_USER" "$KIOSK_DIR/scripts/build-app.sh"

# Enable services
log "Enabling services..."
systemctl daemon-reload
systemctl enable lobby-kiosk.target
systemctl enable sshd tailscaled

# Boot optimization
systemctl set-default multi-user.target
systemctl disable bluetooth cups avahi-daemon 2>/dev/null || true

log "Installation complete!"
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Configure Tailscale: tailscale up"
echo "2. Reboot: reboot"
echo "3. Check status: lobby status"