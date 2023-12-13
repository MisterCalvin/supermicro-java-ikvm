#!/bin/sh

exec java $JAVA_OPTS -cp "$(cat /etc/cont-env.d/KVM_JAR_FILE)" $(cat /etc/cont-env.d/KVM_JAR_APPCLASS) $KVM_HOST $(cat /etc/cont-env.d/KVM_EPHEMERAL_USERNAME) $(cat /etc/cont-env.d/KVM_EPHEMERAL_PASSWORD) null $(cat /etc/cont-env.d/KVM_LAUNCH_ARGUMENTS) 
