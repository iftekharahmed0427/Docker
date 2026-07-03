#!/bin/bash
# GravelHost - Schedule I / Pterodactyl entrypoint.
#
# Responsibilities:
#   1. Work from the persistent volume (/home/container).
#   2. Start a headless X display (the Unity game still initialises graphics
#      under Wine even with -nographics).
#   3. Run the panel-provided startup command, forwarding SIGINT/SIGTERM to the
#      game so the DedicatedServerMod saves and exits cleanly on stop.

cd /home/container || exit 1

# --- Headless display --------------------------------------------------------
export DISPLAY=:0
if [ ! -e /tmp/.X11-unix/X0 ]; then
    Xvfb :0 -screen 0 1024x768x24 -ac +extension GLX +render -noreset >/tmp/xvfb.log 2>&1 &
fi
# Wait up to ~15s for the X socket before launching the game.
for _ in $(seq 1 30); do
    [ -e /tmp/.X11-unix/X0 ] && break
    sleep 0.5
done

# --- Startup command (standard Pterodactyl/yolks pattern) --------------------
# The panel substitutes {{VAR}} tokens into $STARTUP; convert any leftover
# {{ }} to shell ${ } form, echo the final command, then run it.
MODIFIED_STARTUP=$(echo -e "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo "container@pterodactyl:~$ ${MODIFIED_STARTUP}"

# Run in the background so we can trap and forward the stop signal to the game.
eval "${MODIFIED_STARTUP}" &
game_pid=$!
trap 'kill -INT "${game_pid}" 2>/dev/null' INT TERM
wait "${game_pid}"
