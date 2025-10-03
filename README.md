# Lobby Kiosk System

PROOF OF CONCEPT, SUPERCEDED BY KIOSKBOOK [https://github.com/kenzie/kioskbook]

Automated kiosk display system for Lenovo M75q-1 with enhanced reliability features.

## Features

- **Automated Installation** - Complete system setup from Arch Linux live USB
- **Vue.js Display** - Full-screen kiosk mode with lobby application
- **Screensaver System** - Automatic 11 PM - 7 AM operation with burn-in prevention
- **Enhanced Reliability** - Watchdog monitoring with escalating recovery steps
- **Resource Management** - Automated cleanup and monitoring
- **Management CLI** - `lobby` command for system operations

## Installation

### Requirements
- Lenovo M75q-1 (optimized for AMD Ryzen with integrated graphics)
- Arch Linux live USB
- Internet connection during installation

### Install Process

1. **Boot from Arch Linux live USB**

2. **Download installer:**
   ```bash
   curl -O https://raw.githubusercontent.com/kenzie/lobby-kiosk/main/install.sh
   ```

3. **Make executable:**
   ```bash
   chmod +x install.sh
   ```

4. **Run installer:**
   ```bash
   ./install.sh
   ```

5. **Follow prompts:**
   - Enter root password when prompted
   - Confirm disk destruction warning
   - Remove USB when prompted
   - System will reboot automatically

### Post-Installation

After reboot, the system will:
- Auto-login as `lobby` user
- Start the kiosk display automatically
- All services running and monitored

## Management

### System Status
```bash
lobby status
```

### Screensaver Control
```bash
lobby screensaver on      # Manual activation
lobby screensaver off     # Manual deactivation
lobby screensaver status  # Check current state
```

### System Operations
```bash
lobby update             # Update Vue application
lobby upgrade            # Upgrade kiosk system
lobby restart           # Restart all services
lobby fix               # Auto-fix common issues
lobby monitor           # Real-time monitoring
```

### Service Management
```bash
sudo systemctl status lobby-kiosk.target
sudo systemctl restart lobby-display.service
```

## Automatic Features

### Screensaver Schedule
- **Activates:** 11:00 PM daily
- **Deactivates:** 7:00 AM daily
- **Burn-in Prevention:** Elements move every 30 seconds
- **Content:** Route 19 logo, current time, CBW Islanders logo

### Monitoring & Recovery
- **Health Checks:** Every 30 seconds
- **Resource Monitoring:** Every 15 minutes
- **Escalating Recovery:** Cache clear → service restart → system reboot
- **Log Rotation:** Automatic cleanup of large log files

### Maintenance Window
During screensaver hours (11 PM - 7 AM), the system provides an 8-hour maintenance window for:
- Safe system updates
- Service restarts
- Configuration changes
- Automatic recovery operations

## System Architecture

### Services
- **lobby-app.service** - Serve-based static file server for Vue application
- **lobby-display.service** - X11 and Chromium display
- **lobby-watchdog.service** - Health monitoring and recovery
- **lobby-kiosk.target** - Main service orchestration

### File Structure
```
/opt/lobby/
├── app/
│   ├── current/          # Symlink to active deployment
│   ├── releases/         # Application releases
│   └── repo/            # Git repository cache
├── config/
│   └── version          # System version
├── logs/                # System logs
└── scripts/             # Management scripts
```

## Troubleshooting

### Common Issues

**Display not starting:**
```bash
sudo systemctl restart lobby-display.service
```

**Health check failures:**
```bash
tail -f /opt/lobby/logs/watchdog.log
lobby fix
```

**Service failures:**
```bash
systemctl list-units --state=failed
sudo systemctl restart lobby-kiosk.target
```

### Log Locations
- System logs: `journalctl -u lobby-kiosk.target`
- Watchdog: `/opt/lobby/logs/watchdog.log`
- Display: `journalctl -u lobby-display.service`

## Development

### Updating System Configuration
```bash
# Make changes to repository
git commit -m "Update configuration"
git push origin main

# Deploy to kiosk
sudo lobby upgrade
```

### Building Vue Application
The system automatically pulls and builds the Vue application from:
`https://github.com/kenzie/lobby-display.git`

## Support

For issues or improvements, check the system logs and use the `lobby` command for diagnostics and repairs.
