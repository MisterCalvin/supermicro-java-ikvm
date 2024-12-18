#!/bin/sh
# startapp.sh - Launch the iKVM Java application

# Source our logging library
. /usr/local/lib/logging.sh

setup_logging

log_info "Starting iKVM Java application launcher"

# Read and log configuration files
JAR_FILE=$(cat /etc/cont-env.d/KVM_JAR_FILE)
log_debug "Using JAR file: $JAR_FILE"

JAR_APPCLASS=$(cat /etc/cont-env.d/KVM_JAR_APPCLASS)
log_debug "Using application class: $JAR_APPCLASS"

USERNAME=$(cat /etc/cont-env.d/KVM_EPHEMERAL_USERNAME)
log_sensitive "DEBUG" "Using ephemeral username:" "$USERNAME"

PASSWORD=$(cat /etc/cont-env.d/KVM_EPHEMERAL_PASSWORD)
log_debug "Using ephemeral password (length: ${#PASSWORD})"

ARGUMENTS=$(cat /etc/cont-env.d/KVM_LAUNCH_ARGUMENTS)
log_debug "Using launch arguments: $ARGUMENTS"

if [ "${CONTAINER_DEBUG:-0}" = "1" ]; then
    JAVA_DEBUG_OPTS="$JAVA_OPTS -Djavax.net.debug=ssl,handshake"
    log_debug "Container debugging level 1 enabled"

    # Check if verbose Java logging is also enabled
    if [ "${JAVA_VERBOSE_LOGGING:-0}" = "1" ]; then
        log_debug "Java verbose logging enabled"
        JAVA_VERBOSE_LOG_PROPS="${JAVA_VERBOSE_LOG_FILE%.log}.properties"

        # Create Java logging properties file
        cat > "$JAVA_VERBOSE_LOG_PROPS" << EOF
handlers=java.util.logging.FileHandler, java.util.logging.ConsoleHandler
.level=FINE

java.util.logging.FileHandler.pattern=$JAVA_VERBOSE_LOG_FILE
java.util.logging.FileHandler.limit=50000000
java.util.logging.FileHandler.count=1
java.util.logging.FileHandler.formatter=java.util.logging.SimpleFormatter
java.util.logging.FileHandler.level=FINE

java.util.logging.ConsoleHandler.level=FINE
java.util.logging.ConsoleHandler.formatter=java.util.logging.SimpleFormatter

java.util.logging.SimpleFormatter.format=[%4\$s] %1\$tF %1\$tT: %5\$s%6\$s%n

# Specific class logging levels
com.ami.kvm.level=FINE
javax.net.ssl.level=FINE
EOF

        JAVA_DEBUG_OPTS="$JAVA_DEBUG_OPTS -verbose:jni -verbose:class -Djava.util.logging.config.file=$JAVA_VERBOSE_LOG_PROPS"
        log_java_verbose "Verbose Java options set: $JAVA_DEBUG_OPTS"
    else
        log_debug "Java verbose logging disabled"
    fi
else
    log_debug "Container debugging disabled"
    JAVA_DEBUG_OPTS="$JAVA_OPTS"
fi

log_debug "Java options set: $JAVA_DEBUG_OPTS"
log_debug "KVM host: $KVM_HOST"

process_java_output() {
    while IFS= read -r line; do
        case "$line" in
            *"[Dynamic-linking"*|*"[Registering JNI"*)
                log_debug "JNI: $line"
                ;;
            *"error"*|*"Error"*|*"ERROR"*)
                log_error "$line"
                ;;
            *"warn"*|*"Warn"*|*"WARN"*)
                log_warn "$line"
                ;;
            *)
                log_debug "JAVA: $line"
                ;;
        esac
    done
}

# Note: Using a pipe means exec won't work as intended
java $JAVA_DEBUG_OPTS \
    -cp "$JAR_FILE" \
    $JAR_APPCLASS \
    $KVM_HOST \
    "$USERNAME" \
    "$PASSWORD" \
    null \
    $ARGUMENTS 2>&1 | process_java_output