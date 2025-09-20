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
    curl -f -s --max-time 10 "$HEALTH_URL" >/dev/null
}

check_display_health() {
    export DISPLAY=:0
    xset q >/dev/null 2>&1 && pgrep -f chromium >/dev/null
}

restart_service() {
    local service=$1
    log "Restarting $service due to failure"
    sudo systemctl restart "$service"
    sleep 10
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
            if [[ $FAILURE_COUNT -ge 10 ]]; then
                log "Maximum failures reached, rebooting system"
                sudo reboot
            else
                restart_service "lobby-display.service"
                restart_service "lobby-app.service"
                FAILURE_COUNT=0
            fi
        fi
    fi
    
    sleep 30
done