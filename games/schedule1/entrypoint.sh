#!/bin/bash
# GravelHost - Schedule I / Pterodactyl runtime entrypoint (generic Wine+.NET image).
#
#   1. First boot: copy the baked Wine prefix TEMPLATE into the server volume
#      (so it is owned by this server's own uid and Wine accepts it).
#   2. Keep the config's port + player cap in sync with the panel.
#   3. Start a headless X display.
#   4. Tail the mod's Latest.log to stdout. MelonLoader's console is not wired to
#      stdout under headless Wine, so the panel would otherwise never see the
#      server's progress or the "DEDICATED SERVER READY" line its start detector
#      watches for. This is how the panel gets the log.
#   5. Exec the game in the FOREGROUND as the main process, so it owns the
#      panel's stdin (the mod's stdio admin console) and receives SIGINT directly
#      for a clean save.

cd /home/container || exit 1

# Wings runs us as an arbitrary uid with no home; point HOME/cache at the
# writable volume so Wine and fontconfig have somewhere to write.
export HOME=/home/container
export XDG_CACHE_HOME=/home/container/.cache
mkdir -p "${XDG_CACHE_HOME}"

WINE_TEMPLATE="/opt/wineprefix"
export WINEPREFIX="/home/container/.wine"
CONFIG="/home/container/UserData/server_config.toml"
MOD_LOG="/home/container/MelonLoader/Latest.log"

# --- Provision the Wine prefix into the volume on first boot -----------------
if [ ! -f "${WINEPREFIX}/system.reg" ]; then
    echo "Provisioning Wine prefix into the server volume (first boot, one-time)..."
    mkdir -p "${WINEPREFIX}"
    cp -a --no-preserve=ownership "${WINE_TEMPLATE}/." "${WINEPREFIX}/"
fi

# --- Keep the panel's port + player cap in sync with the config each boot ----
if [ -f "${CONFIG}" ]; then
    [ -n "${SERVER_PORT}" ] && sed -i "s/^serverPort = .*/serverPort = ${SERVER_PORT}/" "${CONFIG}"
    [ -n "${MAX_PLAYERS}" ] && sed -i "s/^maxPlayers = .*/maxPlayers = ${MAX_PLAYERS}/" "${CONFIG}"
fi

# --- Headless X display ------------------------------------------------------
export DISPLAY=:0
if [ ! -e /tmp/.X11-unix/X0 ]; then
    Xvfb :0 -screen 0 1024x768x24 -ac +extension GLX +render -noreset >/tmp/xvfb.log 2>&1 &
fi
for _ in $(seq 1 30); do [ -e /tmp/.X11-unix/X0 ] && break; sleep 0.5; done

# --- Surface the mod log (incl. READY) to the panel console ------------------
mkdir -p "$(dirname "${MOD_LOG}")"
rm -f "${MOD_LOG}" 2>/dev/null || true
( for _ in $(seq 1 300); do [ -f "${MOD_LOG}" ] && break; sleep 1; done; tail -n +1 -F "${MOD_LOG}" 2>/dev/null ) &

# --- Run the game in the foreground as the main process ----------------------
MODIFIED_STARTUP=$(echo -e "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
eval "exec ${MODIFIED_STARTUP}"
