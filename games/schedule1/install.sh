#!/bin/bash
# GravelHost - Schedule I / Pterodactyl installer.
# Modeled on the standard parkervcp SteamCMD egg, adapted for the Windows game
# under Wine plus MelonLoader and the DedicatedServerMod. Runs as root in the
# installer container (ghcr.io/parkervcp/installers:debian); writes the finished
# server into /mnt/server. Pterodactyl re-chowns /mnt/server to the container
# user after install.
set -e

# installers:debian is minimal; make sure unzip is present for the mod zips.
apt-get update -qq >/dev/null 2>&1 || true
apt-get install -y --no-install-recommends unzip >/dev/null 2>&1 || true

STEAMAPPID=3164500
MELONLOADER_VERSION="${MELONLOADER_VERSION:-v0.7.2}"
MOD_VERSION="${MOD_VERSION:-v1.0.0}"

RUNTIME=$(printf '%s' "${S1DS_RUNTIME:-mono}" | tr '[:upper:]' '[:lower:]')
case "${RUNTIME}" in
    mono)   BRANCH="${STEAM_BRANCH:-alternate}"; MOD_DLL="DedicatedServerMod_Mono_Server.dll" ;;
    il2cpp) BRANCH="${STEAM_BRANCH:-}";           MOD_DLL="DedicatedServerMod_Il2cpp_Server.dll" ;;
    *) echo "ERROR: S1DS_RUNTIME must be 'mono' or 'il2cpp' (got '${RUNTIME}')."; exit 1 ;;
esac

echo "=== Schedule I install: runtime=${RUNTIME} branch=${BRANCH:-default} ML=${MELONLOADER_VERSION} mod=${MOD_VERSION} ==="

# --- SteamCMD (parkervcp pattern) --------------------------------------------
cd /tmp
mkdir -p /mnt/server/steamcmd
curl -sSL -o steamcmd.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
tar -xzf steamcmd.tar.gz -C /mnt/server/steamcmd
cd /mnt/server/steamcmd

# SteamCMD misbehaves unless /mnt is root-owned; Pterodactyl re-chowns afterward.
chown -R root:root /mnt
export HOME=/mnt/server

# --- Download the Windows game (paid; shared content account) ----------------
echo ">>> Downloading Schedule I (app ${STEAMAPPID}) ..."
BETA=""; [ -n "${BRANCH}" ] && BETA="-beta ${BRANCH}"
./steamcmd.sh +@sSteamCmdForcePlatformType windows +force_install_dir /mnt/server \
    +login "${STEAM_USER}" "${STEAM_PASS}" "${STEAM_AUTH:-}" \
    +app_update ${STEAMAPPID} ${BETA} validate +quit
[ -f "/mnt/server/Schedule I.exe" ] || { echo "ERROR: game not installed (creds, Steam Guard, or branch)."; exit 1; }

# --- Steamworks redist (app 1007, anonymous) + native DLLs -------------------
echo ">>> Steamworks redist (app 1007) ..."
mkdir -p /mnt/server/.redist
./steamcmd.sh +@sSteamCmdForcePlatformType windows +force_install_dir /mnt/server/.redist \
    +login anonymous +app_update 1007 validate +quit || true
cd /mnt/server
for n in steamclient64.dll steam_api64.dll tier0_s64.dll vstdlib_s64.dll steamclient.dll tier0_s.dll vstdlib_s.dll; do
    src=$(find /mnt/server/.redist "/mnt/server/Schedule I_Data/Plugins" -type f -name "$n" 2>/dev/null | head -n1)
    if [ -n "$src" ]; then cp -f "$src" "/mnt/server/$n"; echo "  + $n"; else echo "  ! $n"; fi
done

echo "${STEAMAPPID}" > /mnt/server/steam_appid.txt

# --- MelonLoader (pinned) ----------------------------------------------------
echo ">>> MelonLoader ${MELONLOADER_VERSION} ..."
curl -fsSL -o /tmp/ml.zip "https://github.com/LavaGang/MelonLoader/releases/download/${MELONLOADER_VERSION}/MelonLoader.x64.zip"
unzip -oq /tmp/ml.zip -d /mnt/server
[ -f /mnt/server/version.dll ] || { echo "ERROR: MelonLoader extraction failed."; exit 1; }

# --- Server mod DLL (pinned, runtime-matched) --------------------------------
echo ">>> DedicatedServerMod ${MOD_VERSION} (${MOD_DLL}) ..."
rm -rf /tmp/modzip; mkdir -p /tmp/modzip /mnt/server/Mods
curl -fsSL -o /tmp/mod.zip "https://github.com/ifBars/S1DedicatedServers/releases/download/${MOD_VERSION}/Docker.zip"
unzip -oq /tmp/mod.zip -d /tmp/modzip
rm -f /mnt/server/Mods/DedicatedServerMod_Mono_Server.dll /mnt/server/Mods/DedicatedServerMod_Il2cpp_Server.dll
MODSRC=$(find /tmp/modzip -type f -name "${MOD_DLL}" | head -n1)
[ -n "${MODSRC}" ] || { echo "ERROR: ${MOD_DLL} not found in release ${MOD_VERSION}."; exit 1; }
cp -f "${MODSRC}" "/mnt/server/Mods/${MOD_DLL}"
echo "  + Mods/${MOD_DLL}"

# --- Seed server_config.toml (only if absent) --------------------------------
mkdir -p /mnt/server/UserData
CFG=/mnt/server/UserData/server_config.toml
if [ ! -f "${CFG}" ]; then
echo ">>> Seeding server_config.toml ..."
cat > "${CFG}" <<TOML
[server]
serverName = '${SERVER_NAME:-GravelHost Schedule I}'
serverDescription = 'Schedule I dedicated server'
maxPlayers = ${MAX_PLAYERS:-8}
serverPort = 38465
serverPassword = ''

[authentication]
authProvider = 'SteamGameServer'
authTimeoutSeconds = 30
modVerificationEnabled = true
modVerificationTimeoutSeconds = 20
blockKnownRiskyClientMods = true
allowUnpairedClientMods = true
strictClientModMode = false
steamGameServerLogOnAnonymous = true
steamGameServerToken = ''
steamGameServerQueryPort = 27016
steamGameServerMode = 'Authentication'

[messaging]
messagingBackend = 'FishNetRpc'

[tcpConsole]
tcpConsoleEnabled = false
tcpConsoleBindAddress = '127.0.0.1'
tcpConsolePort = 4050
tcpConsoleRequirePassword = false
tcpConsolePassword = ''
stdioConsoleMode = 'Enabled'

[webPanel]
webPanelEnabled = false
webPanelBindAddress = '127.0.0.1'
webPanelPort = 4051

[gameplay]
ignoreGhostHostForSleep = true
timeProgressionMultiplier = 1.0
allowSleeping = true
pauseGameWhenEmpty = false
freshSaveQuestBootstrapMode = 'StartFromBeginning'

[autosave]
autoSaveEnabled = true
autoSaveIntervalMinutes = 15.0
autoSaveOnPlayerJoin = true
autoSaveOnPlayerLeave = true

[performance]
targetFrameRate = 60
vSyncCount = 0

[storage]
saveGamePath = ''
TOML
fi

# --- Cleanup -----------------------------------------------------------------
rm -rf /mnt/server/steamcmd /mnt/server/.redist /tmp/steamcmd.tar.gz /tmp/ml.zip /tmp/mod.zip /tmp/modzip

echo "=== Schedule I install complete (runtime=${RUNTIME}) ==="
