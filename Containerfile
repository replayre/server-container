# The replay.re game server
#
# The build process will seed the image from seed/
# All future updates will be applied by the built-in updater

ARG BASE=debian:trixie-slim

FROM debian:forky-slim AS runtime-libs
RUN cp -L /usr/lib/x86_64-linux-gnu/libstdc++.so.6 /libstdc++.so.6

FROM ${BASE}
ARG BASE

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      coreutils \
      libssl3t64 \
      libstdc++6 \
 && rm -rf /var/lib/apt/lists/*

COPY seed /opt/replay/seed
COPY --from=runtime-libs /libstdc++.so.6 /opt/replay/seed/libstdc++.so.6
COPY entrypoint.sh /usr/local/bin/replay-entrypoint
RUN chmod 755 /usr/local/bin/replay-entrypoint

# use LDD to check if the base image libraries are new enough to handle the server build
# LDD gives way better debug messages
RUN set -eu; \
    missing=0; \
    for binary in /opt/replay/seed/REServer /opt/replay/seed/*.so; do \
        versions=$(ldd "$binary" 2>&1 | awk "/not found/ { if (match(\$0, /GLIBCXX_[0-9.]+|OPENSSL_[0-9.]+|GLIBC_[0-9.]+/)) print substr(\$0, RSTART, RLENGTH) }" | sort -uV | tr "\n" " "); \
        if [ -n "$versions" ]; then \
            echo "$(basename "$binary"): $versions" >&2; \
            missing=1; \
        fi; \
    done; \
    if [ "$missing" != 0 ]; then \
        echo "" >&2; \
        echo "The payload needs symbol versions this base image does not provide." >&2; \
        echo "It was built against a newer system than ${BASE}, so the image cannot run it." >&2; \
        exit 1; \
    fi; \
    /opt/replay/seed/REServer --help > /dev/null

ARG VERSION=dev
ARG REVISION=unknown
LABEL org.opencontainers.image.title="replay.re server" \
      org.opencontainers.image.description="Cyberpunk 2077 Multiplayer Server" \
      org.opencontainers.image.source="https://github.com/replayre/server-container" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}"

VOLUME ["/srv"]

# documentation only, real values come from GAME_PORT/VOIP_PORT
EXPOSE 20770/tcp
EXPOSE 20770/udp
EXPOSE 20771/udp
EXPOSE 20771/tcp

ENV CHANNEL=alpha \
    AUTO_UPDATE=true \
    RESTART_AFTER_UPDATE=auto \
    GAME_PORT=20770 \
    VOIP_PORT=20771

ENTRYPOINT ["/usr/local/bin/replay-entrypoint"]
