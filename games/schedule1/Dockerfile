# GravelHost - generic Wine 11 + .NET 6 runtime for Schedule I on Pterodactyl.
#
# Contains NO game and NO mod. The egg's install script downloads the game
# (SteamCMD), MelonLoader, and the server mod at install time. The ONE thing
# baked here is a Wine prefix with the .NET 6 desktop runtime, because building
# it needs wineboot + winetricks + a display and cannot run per-install.
#
# The prefix is baked as a read-only TEMPLATE at /opt/wineprefix. The entrypoint
# copies it into each server's volume on first boot, so it ends up owned by that
# server's own uid and Wine accepts it (works on any node, any uid).
FROM scottyhardy/docker-wine:stable-11.0

LABEL org.opencontainers.image.source="https://github.com/iftekharahmed0427/Docker"
LABEL org.opencontainers.image.description="Generic Wine 11 + .NET 6 runtime (Schedule I / Pterodactyl)"
LABEL org.opencontainers.image.licenses="GPL-3.0"

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl wget unzip xz-utils ca-certificates xvfb x11-utils procps \
 && rm -rf /var/lib/apt/lists/*

RUN if [ ! -f /usr/local/bin/winetricks ]; then \
      wget -O /usr/local/bin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks && \
      chmod +x /usr/local/bin/winetricks; \
    fi

# A build user to create the prefix as (Wine refuses to run as root).
RUN useradd -m -d /home/container -s /bin/bash container
RUN mkdir -p /opt/wineprefix && chown container:container /opt/wineprefix

# --- Build the Wine + .NET 6 desktop prefix template (as the build user) ------
USER container
ENV WINEPREFIX=/opt/wineprefix \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    WINEDLLOVERRIDES="version=n,b"
RUN set -e; \
    export DISPLAY=:99; \
    Xvfb :99 -screen 0 1024x768x24 -ac +extension GLX +render -noreset & \
    xvfb_pid=$!; \
    trap 'kill "$xvfb_pid" 2>/dev/null || true' EXIT; \
    sleep 5; \
    wineboot --init; \
    sleep 10; \
    winetricks -q corefonts || true; \
    winetricks -q vcrun2019 || true; \
    winetricks -q dotnetdesktop6; \
    test -d "$WINEPREFIX/drive_c/Program Files/dotnet/shared/Microsoft.WindowsDesktop.App"; \
    wineserver -k || true

# --- Finalize -----------------------------------------------------------------
USER root
# World-readable so the install (any uid) can copy the template into the volume.
RUN chmod -R a+rX /opt/wineprefix

COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

WORKDIR /home/container

# Runtime environment. The prefix lives in the volume (provisioned on first boot).
# The full WINEDLLOVERRIDES makes Wine prefer the native Steam/version DLLs.
ENV WINEPREFIX=/home/container/.wine \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    DISPLAY=:0 \
    STEAMAPPID=3164500 \
    WINEDLLOVERRIDES="version=n,b;steam_api64=n,b;steamclient64=n,b;tier0_s64=n,b;vstdlib_s64=n,b;steamclient=n,b;tier0_s=n,b;vstdlib_s=n,b"

STOPSIGNAL SIGINT
ENTRYPOINT ["/entrypoint.sh"]
