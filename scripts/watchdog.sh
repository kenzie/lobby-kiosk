#!/bin/bash
set -euo pipefail

# Lobby Kiosk Watchdog - Rapid MVP
HEALTH_URL="http://localhost:8080/health"
FAILURE_COUNT=0
MAX_FAILURES=3

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a /opt/lobby/logs/watchdog.log
}

check_app_health() {
    local response=$(curl -f -s --max-time 10 "$HEALTH_URL" 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        # Check if we're in screensaver mode during overnight hours
        local current_hour=$(date +%H)
        if [[ $current_hour -ge 23 || $current_hour -lt 7 ]]; then
            # During screensaver hours, accept screensaver mode as healthy
            echo "$response" | grep -q '"mode":"screensaver"' && return 0
        fi
        # During normal hours, ensure we're not stuck in screensaver mode
        echo "$response" | grep -q '"mode":"normal"' && return 0
    fi
    return 1
}

check_display_health() {
    export DISPLAY=:0
    xset q >/dev/null 2>&1 && pgrep -f chromium >/dev/null
}

escalate_recovery() {
    local failure_count=$1
    
    case $failure_count in
        1|2)
            log "Light recovery: clearing browser cache and reloading page"
            rm -rf /tmp/chromium-kiosk/Default/Cache/* 2>/dev/null || true
            ;;
        3)
            log "Medium recovery: restarting display service"
            sudo systemctl restart lobby-display.service
            sleep 10
            ;;
        4|5)
            log "Heavy recovery: restarting all lobby services"
            sudo systemctl restart lobby-app.service
            sudo systemctl restart lobby-display.service
            sleep 15
            ;;
        6|7)
            log "Critical recovery: clearing X11 locks and restarting services"
            sudo pkill -f chromium || true
            sudo pkill -f Xorg || true
            rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 2>/dev/null || true
            sudo systemctl restart lobby-display.service
            sleep 20
            ;;
        *)
            if [[ $failure_count -ge 10 ]]; then
                log "Maximum failures reached, rebooting system"
                sudo reboot
            else
                log "Extended recovery: full service restart cycle"
                sudo systemctl restart lobby-kiosk.target
                sleep 30
            fi
            ;;
    esac
}

log "Watchdog started"

while true; do
    if check_app_health && check_display_health; then
        if [[ $FAILURE_COUNT -gt 0 ]]; then
            log "Health restored after $FAILURE_COUNT failures"
        fi
        FAILURE_COUNT=0
    else
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
        log "Health check failed (attempt $FAILURE_COUNT/$MAX_FAILURES)"
        
        if [[ $FAILURE_COUNT -ge $MAX_FAILURES ]]; then
            escalate_recovery $FAILURE_COUNT
            
            # Reset failure count after certain recovery attempts
            if [[ $FAILURE_COUNT -eq 3 || $FAILURE_COUNT -eq 5 || $FAILURE_COUNT -eq 7 ]]; then
                FAILURE_COUNT=0
            fi
        fi
    fi
    
    sleep 30
done