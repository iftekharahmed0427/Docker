#!/bin/bash
# GravelHost - Schedule I / Pterodactyl runtime entrypoint.
#
# The server runs as a clean, line-oriented stdin/stdout process (Wings-style):
# the game is exec'd in the FOREGROUND as the container's main process, so it
# owns the panel's stdin (admin console) and stdout, and receives the panel's
# stop signal (SIGINT) directly for a clean save. WINEDEBUG=-all (set in the
# image) keeps the output readable instead of Wine debug spam.

cd /home/container || exit 1

CONFIG="/home/container/UserData/server_config.toml"

# --- Keep the panel's port + player cap in sync with the config each boot ----
if [ -f "${CONFIG}" ]; then
    [ -n "${SERVER_PORT}" ] && sed -i "s/^serverPort = .*/serverPort = ${SERVER_PORT}/" "${CONFIG}"
    [ -n "${MAX_PLAYERS}" ] && sed -i "s/^maxPlayers = .*/maxPlayers = ${MAX_PLAYERS}/" "${CONFIG}"
fi

# --- Headless X display (Unity inits graphics under Wine even with -nographics)
export DISPLAY=:0
if [ ! -e /tmp/.X11-unix/X0 ]; then
    Xvfb :0 -screen 0 1024x768x24 -ac +extension GLX +render -noreset >/tmp/xvfb.log 2>&1 &
fi
for _ in $(seq 1 30); do [ -e /tmp/.X11-unix/X0 ] && break; sleep 0.5; done

# --- Run the game in the foreground as the main process ----------------------
# Panel substitutes {{VAR}} into $STARTUP; convert any leftover to shell form,
# echo it, then exec so the game (not this shell) is the process that receives
# stdin and signals.
MODIFIED_STARTUP=$(echo -e "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo "container@pterodactyl:~$ ${MODIFIED_STARTUP}"
eval "exec ${MODIFIED_STARTUP}"
