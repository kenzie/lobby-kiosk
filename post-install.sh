#!/bin/bash
set -euo pipefail

# Lobby Kiosk Post-Install Script - Idempotent Configuration
# Can be run multiple times safely to update system to latest state

KIOSK_USER="lobby"
KIOSK_DIR="/opt/lobby"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR: $1${NC}"; exit 1; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING: $1${NC}"; }

# Check requirements
[[ $EUID -ne 0 ]] && error "Run as root"

log "Starting lobby-kiosk post-install configuration..."

# Install git if not available
if ! command -v git &> /dev/null; then
    log "Installing git..."
    pacman -Sy --noconfirm git
fi

# Download latest configuration files
log "Downloading latest configuration files..."
cd /tmp
rm -rf lobby-kiosk-config
git clone https://github.com/kenzie/lobby-kiosk.git lobby-kiosk-config

# Install/update packages from list
log "Installing/updating packages..."
PACKAGE_LIST="/tmp/lobby-kiosk-config/configs/packages.txt"
if [[ ! -f "$PACKAGE_LIST" ]]; then
    error "Package list not found: $PACKAGE_LIST"
fi

# Filter out comments and empty lines, then install
PACKAGES=$(grep -v '^#' "$PACKAGE_LIST" | grep -v '^$' | tr '\n' ' ')
pacman -S --needed --noconfirm $PACKAGES

# Install xdotool for screensaver navigation
pacman -S --needed --noconfirm xdotool

# Create lobby user if doesn't exist
if ! id "$KIOSK_USER" &>/dev/null; then
    log "Creating lobby user..."
    useradd -m -s /bin/bash -G video,audio,wheel "$KIOSK_USER"
    echo "$KIOSK_USER:$KIOSK_USER" | chpasswd
fi

# Create directories
log "Setting up directories..."
mkdir -p "$KIOSK_DIR"/{app,config,logs,scripts,backups}
mkdir -p "$KIOSK_DIR/app"/{releases,shared}
chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR"

# Install systemd services
log "Installing systemd services..."
cp /tmp/lobby-kiosk-config/configs/systemd/*.target /etc/systemd/system/
cp /tmp/lobby-kiosk-config/configs/systemd/*.service /etc/systemd/system/
cp /tmp/lobby-kiosk-config/configs/systemd/*.timer /etc/systemd/system/ 2>/dev/null || true

# Install nginx config
log "Installing nginx configuration..."
cp /tmp/lobby-kiosk-config/configs/nginx/nginx.conf /etc/nginx/

# Install font config
log "Installing font configuration..."
mkdir -p /etc/fonts
cp /tmp/lobby-kiosk-config/configs/fonts/local.conf /etc/fonts/

# Install scripts and tools
log "Installing management scripts..."
cp /tmp/lobby-kiosk-config/scripts/*.sh "$KIOSK_DIR/scripts/"
cp /tmp/lobby-kiosk-config/bin/lobby /usr/local/bin/

# Screensaver HTML is included in scripts/ directory

# Set permissions
chmod +x "$KIOSK_DIR/scripts"/*.sh /usr/local/bin/lobby
chmod 644 "$KIOSK_DIR/scripts"/*.html 2>/dev/null || true
chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR/scripts"

# Configure autologin (idempotent)
log "Configuring autologin..."
mkdir -p /etc/systemd/system/getty@tty1.service.d/
cat > /etc/systemd/system/getty@tty1.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin $KIOSK_USER --noclear %I \$TERM
EOF

# Configure sudo permissions (idempotent)
log "Configuring sudo permissions..."
cat > /etc/sudoers.d/lobby << EOF
$KIOSK_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart lobby-*.service
$KIOSK_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl reload nginx
$KIOSK_USER ALL=(ALL) NOPASSWD: /usr/bin/reboot
$KIOSK_USER ALL=(ALL) NOPASSWD: /usr/local/bin/lobby update-system
$KIOSK_USER ALL=(ALL) NOPASSWD: /usr/bin/xset
$KIOSK_USER ALL=(ALL) NOPASSWD: /usr/bin/pacman -S --noconfirm xdotool
EOF

# Set version
echo "2.0.0" > "$KIOSK_DIR/config/version"
chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR/config/version"

# Enable services (idempotent)
log "Enabling services..."
systemctl daemon-reload
systemctl enable lobby-kiosk.target sshd tailscaled
systemctl enable lobby-resource-monitor.timer 2>/dev/null || true
systemctl enable lobby-screensaver.timer 2>/dev/null || true
# Use standard nginx.service instead of custom lobby-app.service
systemctl unmask nginx.service 2>/dev/null || true
systemctl enable nginx.service
systemctl start lobby-kiosk.target
systemctl start lobby-resource-monitor.timer 2>/dev/null || true
systemctl start lobby-screensaver.timer 2>/dev/null || true

# Boot optimization (idempotent)
log "Optimizing boot configuration..."
systemctl set-default multi-user.target
systemctl disable bluetooth cups avahi-daemon 2>/dev/null || true

# Configure GRUB for fast boot
sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=0/' /etc/default/grub
sed -i 's/#GRUB_TIMEOUT_STYLE=menu/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Configure X11 permissions for kiosk user
mkdir -p /etc/X11
echo 'allowed_users=anybody' > /etc/X11/Xwrapper.config
mv /usr/lib/Xorg.wrap /usr/lib/Xorg.wrap.disabled 2>/dev/null || true
chmod u+s /usr/lib/Xorg

# Deploy Vue application
log "Building and deploying Vue application..."
cd /opt/lobby
sudo -u lobby /opt/lobby/scripts/build-app.sh

# Cleanup
rm -rf /tmp/lobby-kiosk-config

log "Post-install configuration complete!"
echo ""
echo "System is ready. To start kiosk services:"
echo "  systemctl start lobby-kiosk.target"
echo ""
echo "To check status:"
echo "  lobby status"
echo ""
echo "To update again in the future:"
echo "  curl -sSL https://raw.githubusercontent.com/kenzie/lobby-kiosk/main/post-install.sh | sudo bash"