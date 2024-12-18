#!/bin/sh
# logging.sh - Common logging functions for SuperMicro Java iKVM

LOG_DIR="/config/log/supermicro-java-ikvm"

# Ensure log directory exists and is writable
setup_logging() {
    mkdir -p "$LOG_DIR" || {
        echo "Error: Cannot create log directory $LOG_DIR" >&2
        exit 1
    }
    chmod 700 "$LOG_DIR"
}

log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local session_log_file="${LOG_DIR}/sm-ikvm-$(date '+%Y%m%d').log"

    # Format: [LEVEL] TIMESTAMP: MESSAGE
    local log_message="[${level}] ${timestamp}: ${message}"
    echo "$log_message" >&2
    echo "$log_message" >> "$session_log_file"
}

# Verbose Java writes a ton of logs (1000+ lines every few seconds)
# Not sure if this is even helpful to enable but whatever
java_verbose_log() {
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local java_verbose_log_file="${LOG_DIR}/sm-ikvm-java-verbose-$(date '+%Y%m%d-%H%M%S').log"

    # Create and write to Java verbose log
    echo "[JAVA-VERBOSE] ${timestamp}: ${message}" >> "$java_verbose_log_file"
    chmod 600 "$java_verbose_log_file"
}

# Mask sensitive values (credentials, hostnames, etc)
mask_sensitive() {
    local input="$1"
    local masked="$input"

    if [ "${CONTAINER_DEBUG:-0}" -eq 2 ]; then
        echo "$input"
        return
    fi

    # First mask our known sensitive environment values
    if [ -n "$KVM_HOST" ]; then
        # Extract base hostname for variant matching
        local base_hostname=$(echo "$KVM_HOST" | cut -d. -f1)
        masked=$(echo "$masked" | sed "s/$base_hostname[^[:space:]\"<>]*\>/********/g")
    fi
    if [ -n "$KVM_USER" ]; then
        masked=$(echo "$masked" | sed "s/$KVM_USER/********/g")
    fi
    if [ -n "$KVM_PASS" ]; then
        masked=$(echo "$masked" | sed "s/$KVM_PASS/********/g")
    fi

    # Then mask any ephemeral credentials
    if [ -f /etc/cont-env.d/KVM_EPHEMERAL_USERNAME ]; then
        local eph_user=$(cat /etc/cont-env.d/KVM_EPHEMERAL_USERNAME)
        if [ -n "$eph_user" ]; then
            local len=${#eph_user}
            local stars=$(printf '%*s' "$len" | tr ' ' '*')
            masked=$(echo "$masked" | sed "s/$eph_user/$stars/g")
        fi
    fi
    if [ -f /etc/cont-env.d/KVM_EPHEMERAL_PASSWORD ]; then
        local eph_pass=$(cat /etc/cont-env.d/KVM_EPHEMERAL_PASSWORD)
        if [ -n "$eph_pass" ]; then
            local len=${#eph_pass}
            local stars=$(printf '%*s' "$len" | tr ' ' '*')
            masked=$(echo "$masked" | sed "s/$eph_pass/$stars/g")
        fi
    fi

    echo "$masked"
}

log_sensitive() {
    local level="$1"
    local prefix="$2"
    local value="$3"
    
    if [ "${CONTAINER_DEBUG:-0}" -ge 1 ]; then
        log_message "$level" "$prefix $(mask_sensitive "$value")"
    fi
}

log_info() {
    log_message "INFO" "$@"
}

log_warn() {
    log_message "WARN" "$@"
}

log_error() {
    log_message "ERROR" "$@"
}

log_debug() {
    if [ "${CONTAINER_DEBUG:-0}" -ge 1 ]; then
        log_message "DEBUG" "$@"
    fi
}