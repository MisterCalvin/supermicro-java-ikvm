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

APP_CACHE_DIR=$XDG_CACHE_HOME

get_launch_jnlp() {
    fail=1
    url="https://$KVM_HOST"
    temp=$(mktemp)
    if curl --fail -sk --cookie-jar "$temp" -XPOST "$url/cgi/login.cgi" \
          --data "name=$KVM_USER&pwd=$KVM_PASS&check=00" -o/dev/null; then
        launch_jnlp=$(curl --fail -sk --cookie "$temp" \
            --referer "$url/cgi/url_redirect.cgi?url_name=man_ikvm" \
            "$url/cgi/url_redirect.cgi?url_name=man_ikvm&url_type=jwsk")
        test $? -eq 0 && fail=
    fi
    rm "$temp"
    test -z "$fail" && echo "$launch_jnlp"
}

get_arguments() {
    launch_jnlp="$1"
    echo "$launch_jnlp" | sed -e '/<argument>/!d;s#.*<argument>\([^<]*\)</argument>.*#\1#' | 
      sed -e "s/['\"$]//g;s/.*/&/" | sed -e 1,4d
}

get_username() {
    launch_jnlp="$1"
    echo "$launch_jnlp" | sed -e '/<argument>/!d' |
      sed -e '2!d;s#.*<argument>\([^<]*\)</argument>#\1#'
}

get_password() {
    launch_jnlp="$1"
    echo "$launch_jnlp" | sed -e '/<argument>/!d' |
      sed -e '3!d;s#.*<argument>\([^<]*\)</argument>#\1#'
}

get_app_class() {
    echo "$1" | sed -ne 's/.*<application-desc .*main-class="\([^"]*\)".*/\1/p'
}

# SYNOPSIS: get_app_class JNLP_DATA
install_ikvm_application() {
    launch_jnlp="$1"
    destdir="$2"

    set -e
    codebase=$(
      echo "$launch_jnlp" | sed -e '/<jnlp /!d;s/.* codebase="//;s/".*//')
    jar=$(
      echo "$launch_jnlp" | sed -e '/<jar /!d;s/.* href="//;s/".*//')
    linuxlibs=$(
      echo "$launch_jnlp" |
      sed -e '/<nativelib /!d;/linux.*x86__/!d;s/.* href="//;s/".*//' |
      sort -u)
    set -x
    mkdir -p "$destdir"
    cd "$destdir"
    for x in $jar $linuxlibs; do
        curl -ko $x.pack.gz "$codebase$x.pack.gz"
        unpack200 $x.pack.gz $x
    done
    unzip -o liblinux*.jar
    rm -rf META-INF
    set +x
    set +e
}

JNLP=$(get_launch_jnlp "$KVM_HOST" "$KVM_USER" "$KVM_PASS")
test -z "$JNLP" && echo "Failed to get launch.jnlp" >&2 && exit 1

JAR=$(find $APP_CACHE_DIR -name 'iKVM*.jar' | sort | tail -n1)
if ! test -f "$JAR"; then
    install_ikvm_application "$JNLP" "$APP_CACHE_DIR"
    JAR=$(find $APP_CACHE_DIR -name 'iKVM*.jar' | sort | tail -n1)
    if ! ls -l "$JAR"; then
        echo "Install failure" >&2
        exit 1
    fi
fi

echo $JAR > /etc/cont-env.d/KVM_JAR_FILE
echo $(get_username "$JNLP") > /etc/cont-env.d/KVM_EPHEMERAL_USERNAME
echo $(get_password "$JNLP") > /etc/cont-env.d/KVM_EPHEMERAL_PASSWORD
echo $(get_app_class "$JNLP") > /etc/cont-env.d/KVM_JAR_APPCLASS
echo $(get_arguments "$JNLP") > /etc/cont-env.d/KVM_LAUNCH_ARGUMENTS
