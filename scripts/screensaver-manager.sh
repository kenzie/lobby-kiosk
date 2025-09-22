#!/bin/bash
set -euo pipefail

# Standalone Screensaver Manager
SCREENSAVER_FILE="/opt/lobby/scripts/screensaver.html"
SCREENSAVER_STATE_FILE="/opt/lobby/config/screensaver.state"
NORMAL_URL="http://localhost:8080"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a /opt/lobby/logs/screensaver.log
}

get_current_hour() {
    date +%H
}

is_screensaver_time() {
    local hour=$(get_current_hour)
    # 11 PM (23) to 7 AM
    [[ $hour -ge 23 || $hour -lt 7 ]]
}

is_screensaver_active() {
    [[ -f "$SCREENSAVER_STATE_FILE" ]] && [[ $(cat "$SCREENSAVER_STATE_FILE" 2>/dev/null) == "active" ]]
}

activate_screensaver() {
    log "Activating screensaver"
    echo "active" > "$SCREENSAVER_STATE_FILE"
    
    # Navigate Chromium to screensaver page
    export DISPLAY=:0
    if pgrep -f chromium >/dev/null; then
        # Use xdotool to navigate to screensaver
        xdotool search --name "Chromium" windowactivate --sync key ctrl+l
        sleep 0.5
        xdotool type "file://$SCREENSAVER_FILE"
        xdotool key Return
    else
        log "Chromium not found, cannot activate screensaver"
        return 1
    fi
}

deactivate_screensaver() {
    log "Deactivating screensaver"
    echo "inactive" > "$SCREENSAVER_STATE_FILE"
    
    # Navigate Chromium back to normal display
    export DISPLAY=:0
    if pgrep -f chromium >/dev/null; then
        xdotool search --name "Chromium" windowactivate --sync key ctrl+l
        sleep 0.5
        xdotool type "$NORMAL_URL"
        xdotool key Return
    else
        log "Chromium not found, cannot deactivate screensaver"
        return 1
    fi
}

toggle_screensaver() {
    if is_screensaver_active; then
        deactivate_screensaver
    else
        activate_screensaver
    fi
}

check_time_based_activation() {
    local should_be_active=$(is_screensaver_time && echo "true" || echo "false")
    local currently_active=$(is_screensaver_active && echo "true" || echo "false")
    
    if [[ "$should_be_active" == "true" && "$currently_active" == "false" ]]; then
        activate_screensaver
    elif [[ "$should_be_active" == "false" && "$currently_active" == "true" ]]; then
        deactivate_screensaver
    fi
}

case "${1:-auto}" in
    "activate")
        activate_screensaver
        ;;
    "deactivate")
        deactivate_screensaver
        ;;
    "toggle")
        toggle_screensaver
        ;;
    "status")
        if is_screensaver_active; then
            echo "Screensaver: ACTIVE"
        else
            echo "Screensaver: INACTIVE"
        fi
        ;;
    "auto")
        check_time_based_activation
        ;;
    *)
        echo "Usage: $0 {activate|deactivate|toggle|status|auto}"
        exit 1
        ;;
esac