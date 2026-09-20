#!/bin/sh
# Entrypoint for the replay.re game server image
#
# /srv is seeded once by checking if REServer is already present from /opt/replay/seed bundled during image build
# The settings file is generated every start
set -eu

SEED=/opt/replay/seed
INSTALL=/srv

case "${CHANNEL:-}" in
    *[!a-z0-9_-]*)
        echo "[entrypoint] CHANNEL must match [a-z0-9_-]+, got '$CHANNEL'" >&2
        exit 1
        ;;
esac

GAME_PORT=${GAME_PORT:-20770}
VOIP_PORT=${VOIP_PORT:-20771}

mkdir -p "$INSTALL/data/ugc"

if [ ! -x "$INSTALL/REServer" ]; then
    echo "[entrypoint] seeding $INSTALL from $SEED"
    cp -a "$SEED/." "$INSTALL/"
    chmod +x "$INSTALL/REServer"
fi

if [ ! -f "$INSTALL/cfg/server.cfg" ] && [ -f "$INSTALL/cfg/server.cfg.example" ]; then
    cp "$INSTALL/cfg/server.cfg.example" "$INSTALL/cfg/server.cfg"
fi

settings=""
append_string() {
    if [ -n "$2" ]; then
        settings="$settings${settings:+,
}    \"$1\": \"$2\""
    fi
}

append_raw() {
    if [ -n "$2" ]; then
        settings="$settings${settings:+,
}    \"$1\": $2"
    fi
}

append_raw auto_update "${AUTO_UPDATE:-}"
append_string channel "${CHANNEL:-}"
append_string restart_after_update "${RESTART_AFTER_UPDATE:-}"

mkdir -p "$INSTALL/settings"
printf '{\n%s\n}\n' "$settings" > "$INSTALL/settings/server.settings.json"

cd "$INSTALL"
exec stdbuf -o0 ./REServer \
    --bindaddr "[::]:${GAME_PORT}" \
    --voip-addr ":::${VOIP_PORT}" \
    "$@"
