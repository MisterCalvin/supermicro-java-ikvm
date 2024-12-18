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

# Ephemeral usernames / passwords are the same, but let's mask them anyway
mask_sensitive() {
    local input="$1"
    local len=${#input}
    if [ "$len" -eq 0 ]; then
        echo "<empty>"
    elif [ "$len" -le 4 ]; then
        echo "****"
    else
        local prefix="${input%"${input#??}"}"
        local suffix="${input#"${input%??}"}"
        local masks=$(printf "%*s" $((len-4)) | tr ' ' '*')
        echo "${prefix}${masks}${suffix}"
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
    if [ "${CONTAINER_DEBUG:-0}" = "1" ]; then
        log_message "DEBUG" "$@"
    fi
}

log_sensitive() {
    local level="$1"
    local prefix="$2"
    local value="$3"
    
    if [ "${CONTAINER_DEBUG:-0}" -eq 1 ]; then
        log_message "$level" "$prefix $(mask_sensitive "$value")"
    fi
}
