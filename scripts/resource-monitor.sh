#!/bin/bash
set -euo pipefail

# Resource Monitor - Prevents system exhaustion
KIOSK_DIR="/opt/lobby"
LOG_FILE="/opt/lobby/logs/resource-monitor.log"

# Thresholds
DISK_THRESHOLD=85      # % disk usage
MEMORY_THRESHOLD=90    # % memory usage
LOG_SIZE_THRESHOLD=100 # MB per log file

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_disk_space() {
    local usage=$(df "$KIOSK_DIR" | tail -1 | awk '{print $5}' | sed 's/%//')
    
    if [[ $usage -gt $DISK_THRESHOLD ]]; then
        log "WARNING: Disk usage at ${usage}% (threshold: ${DISK_THRESHOLD}%)"
        
        # Cleanup old releases (keep only 2 instead of 3)
        cd "$KIOSK_DIR/app/releases" 2>/dev/null && {
            ls -1t | tail -n +3 | xargs -r rm -rf
            log "Cleaned up old app releases"
        }
        
        # Cleanup old logs
        find "$KIOSK_DIR/logs" -name "*.log" -mtime +7 -delete 2>/dev/null || true
        log "Cleaned up old log files"
        
        # Clear browser cache
        rm -rf /tmp/chromium-kiosk/Default/Cache/* 2>/dev/null || true
        log "Cleared browser cache"
        
        return 1
    fi
    return 0
}

check_memory_usage() {
    local usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    
    if [[ $usage -gt $MEMORY_THRESHOLD ]]; then
        log "WARNING: Memory usage at ${usage}% (threshold: ${MEMORY_THRESHOLD}%)"
        
        # Clear system caches
        sync
        echo 1 > /proc/sys/vm/drop_caches 2>/dev/null || true
        log "Cleared system caches"
        
        return 1
    fi
    return 0
}

rotate_large_logs() {
    find "$KIOSK_DIR/logs" -name "*.log" -size +${LOG_SIZE_THRESHOLD}M -exec bash -c '
        for file; do
            mv "$file" "${file}.old"
            touch "$file"
            chown lobby:lobby "$file"
            echo "Rotated large log: $(basename "$file")"
        done
    ' _ {} +
}

check_service_memory() {
    # Check for memory leaks in services
    local chromium_mem=$(ps -o pid,rss,command -C chromium --no-headers | awk '{sum+=$2} END {print sum/1024}' 2>/dev/null || echo "0")
    
    if (( $(echo "$chromium_mem > 2048" | bc -l 2>/dev/null || echo "0") )); then
        log "WARNING: Chromium using ${chromium_mem}MB (threshold: 2GB)"
        # Let watchdog handle the restart
        return 1
    fi
    return 0
}

main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log "Resource monitor check started"
    
    local issues=0
    
    check_disk_space || issues=$((issues + 1))
    check_memory_usage || issues=$((issues + 1))
    check_service_memory || issues=$((issues + 1))
    rotate_large_logs
    
    if [[ $issues -gt 0 ]]; then
        log "Resource monitor found $issues issues"
        exit 1
    else
        log "Resource monitor check completed - all OK"
        exit 0
    fi
}

main "$@"