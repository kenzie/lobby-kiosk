#!/bin/bash
set -euo pipefail

# Nightly Memory Check - Restart services if memory usage exceeds thresholds
# Designed to run during screensaver/low-activity periods

KIOSK_DIR="/opt/lobby"
LOG_FILE="/opt/lobby/logs/memory-check.log"
MEMORY_THRESHOLD_MB=150  # Restart lobby-app.service above this
DISPLAY_THRESHOLD_MB=800 # Restart lobby-display.service above this

# Colors for terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[1;36m'
NC='\033[0m'

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

get_service_memory() {
    local service="$1"
    local memory_line=$(systemctl status "$service" 2>/dev/null | grep "Memory:" | head -1)
    
    if [[ -n "$memory_line" ]]; then
        # Extract memory value and convert to MB
        echo "$memory_line" | grep -o '[0-9.]*[KMGT]' | head -1 | sed 's/K$//' | sed 's/M$//' | sed 's/G$/000/' | sed 's/T$/000000/' | cut -d'.' -f1
    else
        echo "0"
    fi
}

check_and_restart_if_needed() {
    local service="$1"
    local threshold="$2"
    local current_memory=$(get_service_memory "$service")
    
    if [[ "$current_memory" -gt "$threshold" ]]; then
        warn "$service memory usage ($current_memory MB) exceeds threshold ($threshold MB)"
        
        # Take screenshot before restart for diagnostics
        if [[ -x "$KIOSK_DIR/scripts/screenshot.sh" ]]; then
            screenshot_path=$("$KIOSK_DIR/scripts/screenshot.sh" --filename "pre-restart-$(date +%Y%m%d-%H%M%S).png" 2>/dev/null || echo "")
            if [[ -n "$screenshot_path" ]]; then
                info "Screenshot taken: $screenshot_path"
            fi
        fi
        
        log "Restarting $service due to memory usage..."
        
        if systemctl restart "$service"; then
            log "Successfully restarted $service"
            sleep 10  # Wait for service to stabilize
            
            # Verify service is running
            if systemctl is-active "$service" >/dev/null; then
                new_memory=$(get_service_memory "$service")
                log "$service restarted successfully - memory now: ${new_memory}MB"
            else
                error "$service failed to start after restart"
                return 1
            fi
        else
            error "Failed to restart $service"
            return 1
        fi
        
        return 0
    else
        info "$service memory usage: ${current_memory}MB (under ${threshold}MB threshold)"
        return 1
    fi
}

main() {
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log "=== Nightly Memory Check Started ==="
    
    # Record current system memory state
    local system_memory=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    info "System memory usage: ${system_memory}%"
    
    local restart_count=0
    
    # Check lobby-app.service memory
    if check_and_restart_if_needed "lobby-app.service" "$MEMORY_THRESHOLD_MB"; then
        restart_count=$((restart_count + 1))
    fi
    
    # Check lobby-display.service memory
    if check_and_restart_if_needed "lobby-display.service" "$DISPLAY_THRESHOLD_MB"; then
        restart_count=$((restart_count + 1))
    fi
    
    # If any services were restarted, verify overall system health
    if [[ $restart_count -gt 0 ]]; then
        log "Restarted $restart_count service(s), waiting for system to stabilize..."
        sleep 30
        
        # Quick health check
        if curl -f -s --max-time 10 http://localhost:8080/health >/dev/null 2>&1; then
            log "System health check passed after restart(s)"
        else
            error "System health check failed after restart(s)"
            # Trigger watchdog to handle recovery
            systemctl restart lobby-watchdog.service
        fi
        
        # Log final memory state
        app_memory=$(get_service_memory "lobby-app.service")
        display_memory=$(get_service_memory "lobby-display.service")
        log "Final memory state - App: ${app_memory}MB, Display: ${display_memory}MB"
    else
        log "No restarts needed - all services within memory thresholds"
    fi
    
    log "=== Nightly Memory Check Completed ==="
}

# Run main function
main "$@"