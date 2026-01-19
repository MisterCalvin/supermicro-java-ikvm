#!/bin/sh
set -e
set -u

APP_CACHE_DIR=$XDG_CACHE_HOME
CONT_ENV_DIR=/etc/cont-env.d

url="${KVM_PROTOCOL:-https}://$KVM_HOST"
temp=$(mktemp)

echo "Connecting to $url..."

curl --fail -s --cookie-jar "$temp" -XPOST "$url/cgi/login.cgi" \
    --data "name=$KVM_USER&pwd=$KVM_PASS&check=00" -o/dev/null

echo "Login successful, fetching JNLP..."
launch_jnlp=$(curl --fail -s --cookie "$temp" \
    --referer "$url/cgi/url_redirect.cgi?url_name=man_ikvm" \
    "$url/cgi/url_redirect.cgi?url_name=man_ikvm&url_type=jwsk")

echo "$launch_jnlp" > "$APP_CACHE_DIR/launch.jnlp"

# Extract JAR names - use 32-bit native lib since container is linux/386
main_jar=$(echo "$launch_jnlp" | sed -n 's/.*<jar href="\([^"]*\.jar\)".*/\1/p' | head -1)
native_jar=$(echo "$launch_jnlp" | sed -n 's/.*href="\(liblinux_x86__[^"]*\.jar\)".*/\1/p' | head -1)

echo "Main JAR: $main_jar"
echo "Native JAR (32-bit): $native_jar"

cd "$APP_CACHE_DIR"

# Download and decompress main JAR (two-step: gunzip then unpack200)
echo "Downloading ${main_jar}.pack.gz..."
curl -s --cookie "$temp" "$url/${main_jar}.pack.gz" -o "${main_jar}.pack.gz"
gunzip -f "${main_jar}.pack.gz" 2>/dev/null || true
if [ -f "${main_jar}.pack" ]; then
    unpack200 "${main_jar}.pack" "$main_jar"
    rm -f "${main_jar}.pack"
fi

if [ ! -f "$main_jar" ] || [ $(stat -c%s "$main_jar") -lt 1000 ]; then
    echo "ERROR: Failed to download main JAR"
    exit 1
fi
echo "Main JAR: $(stat -c%s "$main_jar") bytes"

# Download and decompress 32-bit native lib
if [ -n "$native_jar" ]; then
    echo "Downloading ${native_jar}.pack.gz..."
    curl -s --cookie "$temp" "$url/${native_jar}.pack.gz" -o "${native_jar}.pack.gz"
    gunzip -f "${native_jar}.pack.gz" 2>/dev/null || true
    if [ -f "${native_jar}.pack" ]; then
        unpack200 "${native_jar}.pack" "$native_jar"
        rm -f "${native_jar}.pack"
    fi
    # Extract .so files
    if [ -f "$native_jar" ]; then
        unzip -o "$native_jar" "*.so" 2>/dev/null || true
        ls -la *.so 2>/dev/null || echo "No .so files extracted"
    fi
fi

# Extract arguments from JNLP
main_class=$(echo "$launch_jnlp" | sed -n 's/.*main-class="\([^"]*\)".*/\1/p')
arguments=$(echo "$launch_jnlp" | sed -n 's/.*<argument>\([^<]*\)<\/argument>.*/\1/p' | tr '\n' ' ')

# Create environment files
echo "$APP_CACHE_DIR/$main_jar" > "$CONT_ENV_DIR/KVM_JAR_FILE"
echo "$main_class" > "$CONT_ENV_DIR/KVM_JAR_APPCLASS"
echo "$KVM_USER" > "$CONT_ENV_DIR/KVM_EPHEMERAL_USERNAME"
echo "$KVM_PASS" > "$CONT_ENV_DIR/KVM_EPHEMERAL_PASSWORD"
echo "$arguments" > "$CONT_ENV_DIR/KVM_LAUNCH_ARGUMENTS"

echo "Setup complete!"
rm "$temp"
