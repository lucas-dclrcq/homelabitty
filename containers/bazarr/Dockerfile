FROM docker.io/library/python:3.13-alpine

ARG VERSION
ARG CHANNEL
ARG TARGETPLATFORM
ARG TARGETARCH
ARG TARGETOS

LABEL dev.ldclrcq.image.target_platform=$TARGETPLATFORM
LABEL dev.ldclrcq.image.target_architecture=$TARGETARCH
LABEL dev.ldclrcq.image.target_os=$TARGETOS
LABEL org.opencontainers.image.source="https://github.com/morpheus65535/bazarr"

ENV \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    CRYPTOGRAPHY_DONT_BUILD_RUST=1

ENV UMASK="0002" \
    TZ="Etc/UTC"

USER root
WORKDIR /app

#hadolint ignore=DL3018,DL3013
RUN \
    apk add --no-cache \
        bash \
        ca-certificates \
        catatonit \
        coreutils \
        curl \
        ffmpeg \
        jo \
        jq \
        libxml2 \
        libxslt \
        mediainfo \
        nano \
        trurl \
        tzdata \
        unzip \
        libpq \
    && \
    apk add --no-cache --virtual .build-deps \
        build-base \
        cargo \
        libffi-dev \
        libpq-dev \
        libxml2-dev \
        libxslt-dev \
    && \
    curl -fsSL -o /tmp/app.zip "https://github.com/morpheus65535/bazarr/releases/download/v${VERSION}/bazarr.zip" \
    && unzip -q /tmp/app.zip -d /app/bin \
    && \
    rm -rf /app/bin/bin \
    && \
    printf "UpdateMethod=docker\nBranch=master\nPackageVersion=%s\nPackageAuthor=[joryirving](https://github.com/joryirving)\n" "${VERSION}" > /app/package_info \
    && pip install --no-cache-dir --find-links https://wheel-index.linuxserver.io/alpine-3.20/ \
        --requirement /app/bin/requirements.txt \
        --requirement /app/bin/postgres-requirements.txt \
    && chown -R root:root /app \
    && chmod -R 755 /app \
    && apk del --purge .build-deps \
    && rm -rf \
        /root/.cache \
        /root/.cargo \
        /tmp/*

COPY ./entrypoint.sh /entrypoint.sh
COPY --from=ghcr.io/linuxserver/unrar:7.1.6 /usr/bin/unrar-alpine /usr/bin/unrar

USER nobody:nogroup
WORKDIR /config
VOLUME ["/config"]

ENTRYPOINT ["/usr/bin/catatonit", "--"]
CMD ["/entrypoint.sh"]
