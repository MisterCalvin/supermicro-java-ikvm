#!/bin/sh
# ipmikvm-tls2020 (part of ossobv/vcutil) // wdoekes/2020 // Public Domain
#
# A wrapper to call the SuperMicro iKVM console bypassing Java browser
# plugins.
#
# Requirements: base64, curl, java
#
# Usage:
#
#   $ ipmikvm-tls2020
#   Usage: ipmikvm-tls2020 [-u ADMIN] [-P ADMIN] IP.ADD.RE.SS
#
#   $ ipmikvm-tls2020 10.11.12.13 -P otherpassword
#   (connects KVM console on IPMI device at 10.11.12.13)
#
# This has been tested with iKVM__V1.69.39.0x0.
#
# See also: ipmikvm
#
set -e # Exit immediately if a command exits with a non-zero status
set -u # Treat unset variables as an error

# Source our logging library
. /usr/local/lib/logging.sh

APP_CACHE_DIR=$XDG_CACHE_HOME

setup_logging

log_info "Starting iKVM initialization"
log_info "CONTAINER_DEBUG is set to: ${CONTAINER_DEBUG:-0}"
log_debug "Using cache directory: $APP_CACHE_DIR"

check_connection() {
    local url="$1"
    local timeout=5
    log_debug "Testing connection to $url with ${timeout}s timeout"
    
    # Extract hostname and try to resolve using multiple methods
    local hostname=$(echo "$url" | sed 's|^https://||')
    log_debug "Testing connectivity to host: $hostname"
    
    # Try ping first
    if ping -c 1 -W 3 "$hostname" >/dev/null 2>&1; then
        log_debug "Host is responding to ping"
        local ip=$(ping -c 1 "$hostname" | grep PING | awk -F'[()]' '{print $2}')
        log_debug "Resolved IP address: $ip"
    else
        log_warn "Host not responding to ping - checking if blocked by firewall"
        # Try to get IP even if ping fails
        local ip=$(getent hosts "$hostname" | awk '{print $1}')
        if [ -n "$ip" ]; then
            log_debug "DNS resolution successful: $hostname -> $ip"
            log_debug "Host found but not responding to ping (possibly firewalled)"
        else
            log_error "Cannot resolve hostname: $hostname"
            log_debug "Check DNS settings or /etc/hosts configuration"
            return 1
        fi
    fi

    # Test HTTPS connection with stricter validation
    log_debug "Testing HTTPS connectivity to $url"
    local curl_output=$(curl --fail -sk --max-time $timeout $url -o/dev/null -w '%{http_code},%{time_total},%{size_download},%{ssl_verify_result}' 2>&1)
    local curl_status=$?
    
    if [ $curl_status -eq 0 ]; then
        IFS=',' read -r http_code time_taken size_download ssl_result <<EOF
$curl_output
EOF
        # Additional validation of the response
        if [ "$http_code" = "000" ] || [ "$size_download" = "0" ]; then
            log_error "HTTPS connection failed - no valid response from server"
            log_debug "Server at $ip is reachable but IPMI service is not responding"
            log_debug "Check if IPMI web service is running and port 443 is open"
            return 1
        fi
        
        log_debug "HTTPS connection successful:"
        log_debug "  - HTTP Status: $http_code"
        log_debug "  - Response time: ${time_taken}s"
        log_debug "  - Response size: $size_download bytes"
        log_debug "  - SSL verify result: $ssl_result"
        return 0
    else
        case $curl_status in
            7)  log_error "Cannot establish HTTPS connection to $url"
                log_debug "Host is reachable at $ip but connection was refused"
                log_debug "Check if IPMI HTTPS service is running and firewall allows port 443"
                ;;
            28) log_error "HTTPS connection timed out after ${timeout}s"
                log_debug "Host is reachable but not responding on HTTPS"
                log_debug "Check IPMI service status and firewall rules for port 443"
                ;;
            35|51|53|54|58|59|60|66|77|91) 
                log_error "SSL/TLS connection failed"
                log_debug "HTTPS connection failed with SSL error"
                log_debug "Check if IPMI HTTPS service is properly configured"
                ;;
            *)  log_error "HTTPS connection failed with status: $curl_status"
                log_debug "Unexpected connection error to $ip"
                log_debug "Full curl output: $curl_output"
                ;;
        esac
        return 1
    fi
}

get_launch_jnlp() {
    log_info "Beginning JNLP retrieval process"
    log_debug "Target host: $KVM_HOST"
    log_debug "Using credentials: user=$KVM_USER, password=<masked>"

    fail=1
    url="https://$KVM_HOST"
    temp=$(mktemp)
    log_debug "Created temporary cookie file at: $temp"
    
    # Test basic connectivity first with timeout
    if ! curl --fail -sk --max-time 5 "$url" -o/dev/null; then
        log_error "Cannot reach $url - possible network/firewall issue"
        rm "$temp"
        return 1
    fi
    log_debug "Basic connectivity test to $url successful"
    
    # Attempt login with timeout
    log_debug "Attempting authentication to $url/cgi/login.cgi"
    if ! curl --fail -sk --max-time 10 --cookie-jar "$temp" -XPOST "$url/cgi/login.cgi" \
          --data "name=$KVM_USER&pwd=$KVM_PASS&check=00" -o/dev/null; then
        log_error "Authentication failed - check credentials or IP restrictions"
        curl_status=$?
        case $curl_status in
            28) log_debug "Connection timed out - check IPMI web service status" ;;
            22) log_debug "Invalid credentials or access denied" ;;
            7)  log_debug "Connection refused - check if IPMI service is running" ;;
            35) log_debug "SSL handshake failed - check IPMI SSL configuration" ;;
            *)  log_debug "Unexpected error during authentication (status: $curl_status)" ;;
        esac
        rm "$temp"
        return 1
    fi
    log_info "Authentication successful"
    
    # Retrieve JNLP with timeout
    log_debug "Retrieving JNLP configuration"
    launch_jnlp=$(curl --fail -sk --max-time 10 --cookie "$temp" \
        --referer "$url/cgi/url_redirect.cgi?url_name=man_ikvm" \
        "$url/cgi/url_redirect.cgi?url_name=man_ikvm&url_type=jwsk")
    curl_status=$?
    
    if [ $curl_status -eq 0 ] && [ -n "$launch_jnlp" ]; then
        log_debug "JNLP fetch successful"
        fail=
    else
        log_error "Failed to retrieve JNLP configuration"
        case $curl_status in
            28) log_debug "JNLP fetch timed out - check IPMI service status" ;;
            22) log_debug "JNLP fetch denied - check user permissions" ;;
            *)  log_debug "JNLP fetch failed with status: $curl_status" ;;
        esac
    fi
    
    rm "$temp"
    log_debug "Cleaned up temporary cookie file: $temp"
    test -z "$fail" && echo "$launch_jnlp"
}

get_arguments() {
    log_debug "Parsing arguments from JNLP"
    launch_jnlp="$1"
    
    # Extract raw arguments and store in variable
    raw_args=$(echo "$launch_jnlp" | sed -e '/<argument>/!d;s#.*<argument>\([^<]*\)</argument>.*#\1#' | 
      sed -e "s/['\"$]//g;s/.*/&/" | sed -e 1,4d)
    
    # Convert newlines to spaces and trim trailing space
    args=$(echo "$raw_args" | tr '\n' ' ' | sed 's/ $//')
    
    # Use set to split args into positional parameters
    set -- $args
    
    # Create descriptive argument string
    description="KVM Port: $1, Virtual Media Port: $2, Company ID: $3, Board ID: $4, Use TLS: $5, Remote KVM Port: $6"
    
    log_debug "Extracted arguments with details: $description"
    echo "$args"
}

get_username() {
    log_debug "Extracting username from JNLP"
    launch_jnlp="$1"
    username=$(echo "$launch_jnlp" | sed -e '/<argument>/!d' |
      sed -e '2!d;s#.*<argument>\([^<]*\)</argument>#\1#')
    log_sensitive "DEBUG" "Extracted username:" "$username"
    echo "$username"
}

get_password() {
    log_debug "Extracting password from JNLP"
    launch_jnlp="$1"
    password=$(echo "$launch_jnlp" | sed -e '/<argument>/!d' |
      sed -e '3!d;s#.*<argument>\([^<]*\)</argument>#\1#')
    log_debug "Extracted password (length: ${#password})"
    echo "$password"
}

get_app_class() {
    log_debug "Extracting application class from JNLP"
    app_class=$(echo "$1" | sed -ne 's/.*<application-desc .*main-class="\([^"]*\)".*/\1/p')
    log_debug "Extracted application class: $app_class"
    echo "$app_class"
}

install_ikvm_application() {
    launch_jnlp="$1"
    destdir="$2"
    log_info "Starting iKVM application installation"
    log_debug "Installing to directory: $destdir"
    
    set -e
    
    # Extract and validate codebase
    codebase=$(echo "$launch_jnlp" | sed -e '/<jnlp /!d;s/.* codebase="//;s/".*//')
    if [ -z "$codebase" ]; then
        log_error "Failed to extract codebase from JNLP"
        return 1
    fi
    log_debug "Found codebase URL: $codebase"
    
    # Extract and validate JAR file
    jar=$(echo "$launch_jnlp" | sed -e '/<jar /!d;s/.* href="//;s/".*//')
    if [ -z "$jar" ]; then
        log_error "Failed to extract JAR filename from JNLP"
        return 1
    fi
    log_debug "Found JAR file: $jar"
    
    # Extract Linux libraries
    linuxlibs=$(echo "$launch_jnlp" |
      sed -e '/<nativelib /!d;/linux.*x86__/!d;s/.* href="//;s/".*//' |
      sort -u)
    log_debug "Found Linux libraries: $linuxlibs"
    
    # Create directory
    mkdir -p "$destdir"
    cd "$destdir"
    log_debug "Created and entered directory: $destdir"
    
    # Download and unpack files
    for x in $jar $linuxlibs; do
        log_info "Downloading: $x"
        download_url="$codebase$x.pack.gz"
        log_debug "Download URL: $download_url"
        
        if curl -kLf "$download_url" -o "$x.pack.gz"; then
            log_debug "Successfully downloaded: $x.pack.gz"
            
            if unpack200 "$x.pack.gz" "$x"; then
                log_debug "Successfully unpacked: $x"
            else
                log_error "Failed to unpack: $x"
                return 1
            fi
        else
            log_error "Failed to download: $download_url"
            return 1
        fi
    done
    
    log_debug "Extracting native libraries from JAR"
    if ! unzip -o liblinux*.jar; then
        log_error "Failed to extract native libraries"
        return 1
    fi
    
    rm -rf META-INF
    log_info "Application installation completed successfully"
}

log_info "Fetching JNLP configuration"
JNLP=$(get_launch_jnlp "$KVM_HOST" "$KVM_USER" "$KVM_PASS")

if [ -z "$JNLP" ]; then
    log_error "Failed to get launch.jnlp"
    exit 1
fi

log_debug "Searching for existing JAR file"
JAR=$(find $APP_CACHE_DIR -name 'iKVM*.jar' | sort | tail -n1)

if ! test -f "$JAR"; then
    log_info "No existing JAR found, starting installation"
    install_ikvm_application "$JNLP" "$APP_CACHE_DIR"
    JAR=$(find $APP_CACHE_DIR -name 'iKVM*.jar' | sort | tail -n1)
    if ! ls -l "$JAR"; then
        log_error "Installation failed - JAR file not found"
        exit 1
    fi
    log_info "Installation completed successfully"
else
    log_debug "Found existing JAR: $JAR"
fi

log_info "Writing configuration to environment"
log_debug "Setting up environment files in /etc/cont-env.d/"

# Write and verify each configuration file
echo "$JAR" > /etc/cont-env.d/KVM_JAR_FILE
log_debug "Wrote JAR file path: $JAR"

username=$(get_username "$JNLP")
echo "$username" > /etc/cont-env.d/KVM_EPHEMERAL_USERNAME
log_debug "Wrote ephemeral username (length: ${#username})"

password=$(get_password "$JNLP")
echo "$password" > /etc/cont-env.d/KVM_EPHEMERAL_PASSWORD
log_debug "Wrote ephemeral password (length: ${#password})"

app_class=$(get_app_class "$JNLP")
echo "$app_class" > /etc/cont-env.d/KVM_JAR_APPCLASS
log_debug "Wrote application class: $app_class"

arguments=$(get_arguments "$JNLP")
if [ -n "$arguments" ]; then
    echo "$arguments" > /etc/cont-env.d/KVM_LAUNCH_ARGUMENTS
    log_debug "Wrote launch arguments: $arguments"
else
    log_error "Failed to extract arguments from JNLP"
    exit 1
fi

# Verify all required files exist
for file in KVM_JAR_FILE KVM_EPHEMERAL_USERNAME KVM_EPHEMERAL_PASSWORD KVM_JAR_APPCLASS KVM_LAUNCH_ARGUMENTS; do
    if [ ! -f "/etc/cont-env.d/$file" ]; then
        log_error "Missing required environment file: $file"
        exit 1
    fi
done

log_info "Setup completed successfully"