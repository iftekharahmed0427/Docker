#!/bin/bash
# GravelHost - Schedule I / Pterodactyl runtime entrypoint.
#
#   1. Work from the persistent volume (/home/container).
#   2. Keep serverPort + maxPlayers in the config in sync with the panel.
#   3. Start a headless X display (Unity still inits graphics under Wine).
#   4. Run the game with a clean, panel-friendly console:
#        - noisy Wine output goes to a file (wine-console.log)
#        - the mod's own Latest.log is tailed to stdout (this carries the
#          "DEDICATED SERVER READY" line the panel watches for)
#   5. Forward SIGINT/SIGTERM to the game so the mod saves and exits cleanly.

cd /home/container || exit 1

CONFIG="/home/container/UserData/server_config.toml"
MOD_LOG="/home/container/MelonLoader/Latest.log"
WINE_LOG="/home/container/wine-console.log"

# --- Sync the panel's port + player cap into the config each boot ------------
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

# --- Launch the game ---------------------------------------------------------
# The panel-provided startup command (the wine line) runs with its noisy Wine
# output redirected to a file; the mod's log is what we surface to the panel.
MODIFIED_STARTUP=$(echo -e "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo "container@pterodactyl:~$ ${MODIFIED_STARTUP}"

: > "${WINE_LOG}"
eval "${MODIFIED_STARTUP}" >"${WINE_LOG}" 2>&1 &
game_pid=$!

# Forward the panel's stop signal to the game for a clean save.
trap 'kill -INT "${game_pid}" 2>/dev/null' INT TERM

# Surface the DedicatedServerMod log (incl. the READY line) to the panel.
for _ in $(seq 1 180); do [ -f "${MOD_LOG}" ] && break; sleep 1; done
tail -n +1 -F "${MOD_LOG}" 2>/dev/null &
tail_pid=$!

wait "${game_pid}"
kill "${tail_pid}" 2>/dev/null || true
