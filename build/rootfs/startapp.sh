#!/bin/sh

exec java $JAVA_OPTS -cp "$(cat /etc/cont-env.d/KVM_JAR_FILE)" tw.com.aten.ikvm.KVMMain $KVM_HOST $(cat /etc/cont-env.d/KVM_EPHEMERAL_USERNAME) $(cat /etc/cont-env.d/KVM_EPHEMERAL_PASSWORD) null 63630 623 2 0 1 5900 
