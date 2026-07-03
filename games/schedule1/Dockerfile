# GravelHost - Schedule I (Schedule 1) dedicated server image for Pterodactyl
#
# Base: the upstream community image, which already bakes a proven stack:
#   Wine 11 + a .NET 6 Wine prefix + MelonLoader v0.7.2 + both server mod DLLs
#   (validated end-to-end in Phase 0 on both the mono and il2cpp runtimes).
# We add ONLY the Pterodactyl layer on top:
#   - the `container` user (uid/gid 988) and /home/container working dir
#   - ownership of the baked Wine prefix so that user can run Wine
#   - a foreground entrypoint that sets up a headless display and forwards SIGINT
#
# This same image is used for BOTH the egg install step and the runtime, since
# steamcmd (/home/steam/steamcmd) and the MelonLoader bootstrap
# (/home/steam/bootstrap) are already baked in the base.
FROM ghcr.io/ifbars/s1dedicatedservers:1.0.0

LABEL org.opencontainers.image.source="https://github.com/iftekharahmed0427/Docker"
LABEL org.opencontainers.image.description="Schedule I dedicated server (DedicatedServerMod under Wine), Pterodactyl-native"
LABEL org.opencontainers.image.licenses="GPL-3.0"

USER root

# Pterodactyl runs servers as uid/gid 988 (the `container` user), with the
# persistent volume mounted at /home/container. Create that user/group if the
# base image does not already have it.
RUN if ! getent group 988  >/dev/null; then groupadd -g 988 container; fi \
 && if ! getent passwd 988 >/dev/null; then useradd -d /home/container -m -u 988 -g 988 -s /bin/bash container; fi

# The baked Wine prefix lives OUTSIDE /home/container so the persistent volume
# cannot clobber it. Hand it to the container user so Wine runs at runtime.
RUN chown -R 988:988 /home/steam/wineprefix

# Pterodactyl runs BOTH the install and the runtime as the non-root `container`
# user (uid 988). It must be able to traverse /home/steam to reach the Wine
# prefix, and read the MelonLoader bootstrap + steamcmd during install. The
# base image's /home/steam is mode 700, so open just enough for read/traverse.
RUN chmod a+rx /home/steam \
 && chmod -R a+rX /home/steam/bootstrap /home/steam/steamcmd

# Runtime environment for the container user. The full WINEDLLOVERRIDES makes
# Wine prefer the native Steam/version DLLs the dedicated server needs (this is
# what upstream's run.sh sets at launch; we bake it so the startup line is clean).
ENV HOME=/home/container \
    USER=container \
    WINEPREFIX=/home/steam/wineprefix \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    STEAMAPPID=3164500 \
    DISPLAY=:0 \
    TZ=UTC \
    WINEDLLOVERRIDES="version=n,b;steam_api64=n,b;steamclient64=n,b;tier0_s64=n,b;vstdlib_s64=n,b;steamclient=n,b;tier0_s=n,b;vstdlib_s=n,b"

COPY entrypoint.sh /entrypoint.sh
COPY install.sh /install.sh
# Strip any CRLF (in case of a Windows checkout) and make executable.
RUN sed -i 's/\r$//' /entrypoint.sh /install.sh && chmod +x /entrypoint.sh /install.sh

USER container
WORKDIR /home/container

# Pterodactyl stops servers with SIGINT (^C); the mod traps it for a clean save.
STOPSIGNAL SIGINT

# Pterodactyl passes the server's startup command via the STARTUP env var; the
# entrypoint sets up the headless X display, then runs it in the foreground.
ENTRYPOINT ["/entrypoint.sh"]
