FROM --platform=linux/386 jlesage/baseimage-gui:debian-11-v4

ARG CONTAINER_MAJOR_VERSION=1.0
ARG CONTAINER_MINOR_VERSION=0

COPY assets/icon.png /tmp/icon.png

RUN \ 
	set-cont-env HOME "/app" && \
	set-cont-env APP_NAME "Supermicro Java iKVM Viewer" && \
	set-cont-env APP_VERSION "1.0" && \
	set-cont-env DOCKER_IMAGE_VERSION "${CONTAINER_MAJOR_VERSION}.${CONTAINER_MINOR_VERSION}" && \
	set-cont-env DOCKER_IMAGE_PLATFORM "linux/386" && \
    	APP_ICON_URL=/tmp/icon.png && \
    	install_app_icon.sh "$APP_ICON_URL"

ARG ZULU_VERSION=zulu8.74.0.17-ca-jre8.0.392-linux_i686

ENV \
    	KVM_HOST="" \
    	KVM_USER="" \
    	KVM_PASS="" \
    	DISPLAY_WIDTH=1024 \
    	DISPLAY_HEIGHT=768 \
	PATH="${PATH}:/opt/${ZULU_VERSION}/bin"

RUN \
	add-pkg curl socat unzip psmisc fontconfig libxrender1 libxtst6 x11-xserver-utils && \
	add-pkg --virtual certs ca-certificates && \
	mkdir /app && \
	curl -O --output-dir /tmp/ https://cdn.azul.com/zulu/bin/${ZULU_VERSION}.tar.gz && \
	tar -C /opt/ -xvf /tmp/${ZULU_VERSION}.tar.gz && \
	ln -s /opt/${ZULU_VERSION}/bin/unpack200 /usr/local/bin/unpack200 && \
	ln -s /opt/${ZULU_VERSION}/bin/java /usr/local/bin/java && \
	set-cont-env JAVA_OPTS "-Djava.util.prefs.systemRoot=/config/xdg/config -Djava.util.prefs.userRoot=/config/xdg/config -Duser.home=/app -Djava.library.path=/config/xdg/cache" && \
	mkdir -p /app/vmedia && \
	mkdir -p /app/screenshots && \
	del-pkg certs && \
	rm /tmp/${ZULU_VERSION}.tar.gz

COPY rootfs /

EXPOSE 5800 5900

WORKDIR /app

LABEL \
	org.opencontainers.image.authors="Kevin Moore" \
	org.opencontainers.image.title="Supermicro Java iKVM Viewer" \
	org.opencontainers.image.description="A container for connecting to Supermicro Java based iKVM viewers via a web browser" \
	org.opencontainers.image.source=https://github.com/MisterCalvin/supermicro-java-ikvm \
	org.opencontainers.image.version="${CONTAINER_MAJOR_VERSION}.${CONTAINER_MINOR_VERSION}" \
	org.opencontainers.image.licenses=MIT
