#!/bin/bash
set -euo pipefail

# Lobby Kiosk Maintenance Script
# Performs quarterly system maintenance with backup and rollback capabilities
# Run manually during maintenance windows: May, August, Christmas

KIOSK_DIR="/opt/lobby"
BACKUP_DIR="/opt/lobby/backups"
MAINTENANCE_LOG="/opt/lobby/logs/maintenance-$(date +%Y%m%d).log"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[1;36m'
NC='\033[0m'

log() { 
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}" | tee -a "$MAINTENANCE_LOG"
}
error() { 
    echo -e "${RED}[$(date +'%H:%M:%S')] ERROR: $1${NC}" | tee -a "$MAINTENANCE_LOG"
    exit 1
}
warn() { 
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING: $1${NC}" | tee -a "$MAINTENANCE_LOG"
}
info() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')] $1${NC}" | tee -a "$MAINTENANCE_LOG"
}

# Check if running as root
[[ $EUID -ne 0 ]] && error "Must run as root"

# Check available disk space (need at least 2GB for backups)
available_space=$(df /opt | tail -1 | awk '{print $4}')
if [[ $available_space -lt 2097152 ]]; then
    error "Insufficient disk space for backup (need 2GB, have $(($available_space/1024))MB)"
fi

show_maintenance_menu() {
    echo -e "${BLUE}=== Lobby Kiosk Maintenance ===${NC}"
    echo "Current system status:"
    echo "  Version: $(cat $KIOSK_DIR/config/version 2>/dev/null || echo 'unknown')"
    echo "  Uptime: $(uptime -p)"
    echo "  Last update: $(ls -la /var/log/pacman.log | awk '{print $6, $7, $8}')"
    echo
    echo "Maintenance options:"
    echo "  1) Full system maintenance (backup + update)"
    echo "  2) Backup only"
    echo "  3) Update only (dangerous without backup)"
    echo "  4) System check and report"
    echo "  5) Exit"
    echo
    read -p "Choose option [1-5]: " choice
}

create_backup() {
    local backup_name="maintenance-backup-$(date +%Y%m%d-%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    log "Creating system backup: $backup_name"
    
    # Create backup directory
    mkdir -p "$backup_path"
    
    # Backup critical system files
    info "Backing up system configuration..."
    mkdir -p "$backup_path/etc"
    cp -r /etc/pacman.* "$backup_path/etc/" 2>/dev/null || true
    cp -r /etc/systemd/system/lobby-* "$backup_path/etc/" 2>/dev/null || true
    cp -r /etc/sudoers.d/lobby "$backup_path/etc/" 2>/dev/null || true
    
    # Backup kiosk directory
    info "Backing up kiosk directory..."
    cp -r "$KIOSK_DIR" "$backup_path/opt-lobby" 2>/dev/null || true
    
    # Create package list
    info "Creating package list..."
    pacman -Qqe > "$backup_path/packages.txt"
    pacman -Qqm > "$backup_path/aur-packages.txt" 2>/dev/null || touch "$backup_path/aur-packages.txt"
    
    # System info
    info "Recording system information..."
    {
        echo "Backup created: $(date)"
        echo "Kernel: $(uname -r)"
        echo "Uptime: $(uptime)"
        free -h
        df -h
    } > "$backup_path/system-info.txt"
    
    # Create restore script
    cat > "$backup_path/restore.sh" << 'EOF'
#!/bin/bash
# Restore script - run as root
set -euo pipefail

BACKUP_DIR="$(dirname "$0")"
echo "Restoring from backup: $BACKUP_DIR"

# Stop services
systemctl stop lobby-kiosk.target

# Restore system files
cp -r "$BACKUP_DIR/etc"/* /etc/
cp -r "$BACKUP_DIR/opt-lobby"/* /opt/lobby/

# Reload and restart services
systemctl daemon-reload
systemctl start lobby-kiosk.target

echo "Restore complete. Check lobby status."
EOF
    chmod +x "$backup_path/restore.sh"
    
    # Compress backup
    info "Compressing backup..."
    cd "$BACKUP_DIR"
    tar -czf "$backup_name.tar.gz" "$backup_name"
    rm -rf "$backup_name"
    
    log "Backup created: $BACKUP_DIR/$backup_name.tar.gz"
    echo "$backup_name.tar.gz" > "$BACKUP_DIR/latest-backup.txt"
}

perform_system_update() {
    log "Starting system update process..."
    
    # Pre-update system check
    info "Running pre-update system check..."
    lobby review >> "$MAINTENANCE_LOG" 2>&1
    
    # Update keyring first (critical for Arch)
    log "Updating archlinux-keyring..."
    if ! pacman -Sy archlinux-keyring --noconfirm; then
        error "Failed to update archlinux-keyring"
    fi
    
    # Sync databases
    log "Synchronizing package databases..."
    pacman -Sy --noconfirm
    
    # Show what will be updated
    info "Packages to be updated:"
    pacman -Qu | head -20 | tee -a "$MAINTENANCE_LOG"
    local update_count=$(pacman -Qu | wc -l)
    
    if [[ $update_count -eq 0 ]]; then
        log "System already up to date"
        return 0
    fi
    
    info "$update_count packages will be updated"
    
    # Perform update
    log "Updating system packages..."
    if ! pacman -Su --noconfirm; then
        error "System update failed"
    fi
    
    # Update NPM packages
    if command -v npm >/dev/null; then
        log "Updating NPM global packages..."
        npm update -g serve 2>/dev/null || warn "NPM update failed"
    fi
    
    # Update lobby system configuration
    log "Updating lobby system configuration..."
    lobby upgrade >> "$MAINTENANCE_LOG" 2>&1 || warn "Lobby system update had issues"
    
    log "System update completed"
}

run_system_check() {
    log "Running comprehensive system check..."
    
    echo -e "${BLUE}=== System Health Report ===${NC}"
    
    # Basic system info
    echo "System Information:"
    echo "  Hostname: $(hostname)"
    echo "  Kernel: $(uname -r)"
    echo "  Uptime: $(uptime -p)"
    echo "  Load: $(uptime | awk -F'load average:' '{print $2}')"
    echo
    
    # Package status
    echo "Package Status:"
    echo "  Installed: $(pacman -Q | wc -l) packages"
    echo "  Updates available: $(pacman -Qu 2>/dev/null | wc -l) packages"
    echo "  Orphaned: $(pacman -Qdtq 2>/dev/null | wc -l) packages"
    echo
    
    # Service status
    echo "Service Status:"
    systemctl is-active lobby-kiosk.target lobby-app.service lobby-display.service lobby-watchdog.service || true
    echo
    
    # Resource usage
    echo "Resource Usage:"
    free -h
    echo
    df -h /opt /var /tmp
    echo
    
    # Security check
    echo "Security Status:"
    echo "  Failed login attempts: $(journalctl --since="24 hours ago" | grep -c "Failed password" || echo "0")"
    echo "  SSH connections: $(journalctl --since="24 hours ago" -u sshd | grep -c "Accepted" || echo "0")"
    echo
    
    # Run lobby review
    echo "Running lobby review:"
    lobby review
    
    log "System check completed"
}

cleanup_old_backups() {
    log "Cleaning up old backups (keeping last 5)..."
    cd "$BACKUP_DIR"
    ls -t *.tar.gz 2>/dev/null | tail -n +6 | xargs rm -f || true
    log "Backup cleanup completed"
}

main() {
    # Ensure log directory exists
    mkdir -p "$(dirname "$MAINTENANCE_LOG")"
    
    log "=== Starting Lobby Kiosk Maintenance ==="
    log "Maintenance log: $MAINTENANCE_LOG"
    
    # Show menu and handle choice
    show_maintenance_menu
    
    case $choice in
        1)
            log "Selected: Full system maintenance"
            create_backup
            perform_system_update
            cleanup_old_backups
            run_system_check
            log "=== Maintenance completed successfully ==="
            echo
            echo -e "${GREEN}Maintenance completed successfully!${NC}"
            echo "Log file: $MAINTENANCE_LOG"
            echo "Latest backup: $(cat $BACKUP_DIR/latest-backup.txt 2>/dev/null || echo 'none')"
            ;;
        2)
            log "Selected: Backup only"
            create_backup
            cleanup_old_backups
            log "=== Backup completed ==="
            ;;
        3)
            warn "Selected: Update without backup (not recommended)"
            read -p "Are you sure? This is risky without a backup. [y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                perform_system_update
                run_system_check
            else
                log "Update cancelled"
            fi
            ;;
        4)
            log "Selected: System check only"
            run_system_check
            ;;
        5)
            log "Maintenance cancelled by user"
            exit 0
            ;;
        *)
            error "Invalid option: $choice"
            ;;
    esac
}

# Handle interrupts gracefully
trap 'error "Maintenance interrupted"' INT TERM

main "$@"