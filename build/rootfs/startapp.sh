#!/bin/sh

JAR_FILE=$(cat /etc/cont-env.d/KVM_JAR_FILE)
MAIN_CLASS=$(cat /etc/cont-env.d/KVM_JAR_APPCLASS)
ARGS=$(cat /etc/cont-env.d/KVM_LAUNCH_ARGUMENTS)

export LD_LIBRARY_PATH="$XDG_CACHE_HOME:$LD_LIBRARY_PATH"

echo "Starting KVM..."
echo "  JAR: $JAR_FILE"
echo "  Class: $MAIN_CLASS"
echo "  Args: $ARGS"

exec java $JAVA_OPTS \
    -Djava.library.path="$XDG_CACHE_HOME" \
    -cp "$JAR_FILE" $MAIN_CLASS $ARGS
