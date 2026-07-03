#!/bin/bash
# GravelHost - Schedule I / Pterodactyl installer (egg-driven).
# Fetched and run by the egg's install step. Downloads everything into
# /mnt/server: the game (SteamCMD), Steamworks redist, MelonLoader, and the
# runtime-matching server mod DLL, then seeds server_config.toml. The Wine
# prefix is NOT handled here; the runtime entrypoint provisions it into the
# volume on first boot.
set -euo pipefail

STEAMAPPID=3164500
INSTALL_DIR=/mnt/server
MELONLOADER_VERSION="${MELONLOADER_VERSION:-v0.7.2}"
MOD_VERSION="${MOD_VERSION:-v1.0.0}"

RUNTIME=$(printf '%s' "${S1DS_RUNTIME:-mono}" | tr '[:upper:]' '[:lower:]')
case "${RUNTIME}" in
    mono)   DEFAULT_BRANCH="alternate"; MOD_DLL="DedicatedServerMod_Mono_Server.dll" ;;
    il2cpp) DEFAULT_BRANCH="";           MOD_DLL="DedicatedServerMod_Il2cpp_Server.dll" ;;
    *) echo "ERROR: S1DS_RUNTIME must be 'mono' or 'il2cpp' (got '${RUNTIME}')."; exit 1 ;;
esac
BRANCH="${STEAM_BRANCH:-$DEFAULT_BRANCH}"

echo "=== Schedule I install : runtime=${RUNTIME} branch=${BRANCH:-default} ML=${MELONLOADER_VERSION} mod=${MOD_VERSION} ==="
mkdir -p "${INSTALL_DIR}"; cd "${INSTALL_DIR}"

if [ -z "${STEAM_USER:-}" ] || [ -z "${STEAM_PASS:-}" ]; then
    echo "ERROR: STEAM_USER and STEAM_PASS are required to download the paid game."; exit 1
fi

# --- SteamCMD ----------------------------------------------------------------
export HOME="${INSTALL_DIR}/.steamhome"
mkdir -p "${INSTALL_DIR}/.steamcmd" "${HOME}"
curl -sSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar -xz -C "${INSTALL_DIR}/.steamcmd"
STEAMCMD="${INSTALL_DIR}/.steamcmd/steamcmd.sh"
chmod +x "${STEAMCMD}" 2>/dev/null || true

# --- 1) Download the paid game (real creds, Windows platform, branch) --------
echo ">>> Downloading Schedule I (app ${STEAMAPPID}) ..."
ARGS=(+@sSteamCmdForcePlatformType windows +force_install_dir "${INSTALL_DIR}"
      +login "${STEAM_USER}" "${STEAM_PASS}" "${STEAM_GUARD:-}" +app_update "${STEAMAPPID}")
[ -n "${BRANCH}" ] && ARGS+=(-beta "${BRANCH}")
ARGS+=(validate +quit)
"${STEAMCMD}" "${ARGS[@]}"
[ -f "${INSTALL_DIR}/Schedule I.exe" ] || { echo "ERROR: game not installed (bad creds, Steam Guard, or branch)."; exit 1; }

# --- 2) Steamworks redist (app 1007, anonymous) + native DLLs ----------------
echo ">>> Steamworks redist (app 1007) ..."
mkdir -p "${INSTALL_DIR}/.redist"
"${STEAMCMD}" +@sSteamCmdForcePlatformType windows +force_install_dir "${INSTALL_DIR}/.redist" \
    +login anonymous +app_update 1007 validate +quit || true
copy_dll() {
    local n="$1" s=""
    for c in "${INSTALL_DIR}/.redist/${n}" "${INSTALL_DIR}/.redist/redistributable_bin/${n}" \
             "${INSTALL_DIR}/.redist/redistributable_bin/win64/${n}" "${INSTALL_DIR}/Schedule I_Data/Plugins/x86_64/${n}"; do
        [ -f "$c" ] && { s="$c"; break; }
    done
    [ -z "$s" ] && s=$(find "${INSTALL_DIR}/.redist" "${INSTALL_DIR}" -type f -name "$n" 2>/dev/null | head -n1)
    [ -n "$s" ] && { cp -f "$s" "${INSTALL_DIR}/${n}"; echo "  + ${n}"; } || echo "  ! missing ${n}"
}
for d in steamclient64.dll steam_api64.dll tier0_s64.dll vstdlib_s64.dll steamclient.dll tier0_s.dll vstdlib_s.dll; do copy_dll "$d"; done

# --- 3) steam_appid.txt ------------------------------------------------------
printf "%s\n" "${STEAMAPPID}" > "${INSTALL_DIR}/steam_appid.txt"

# --- 4) MelonLoader (pinned version) -----------------------------------------
echo ">>> MelonLoader ${MELONLOADER_VERSION} ..."
curl -fsSL -o /tmp/ml.zip "https://github.com/LavaGang/MelonLoader/releases/download/${MELONLOADER_VERSION}/MelonLoader.x64.zip"
unzip -oq /tmp/ml.zip -d "${INSTALL_DIR}"   # -> version.dll + MelonLoader/
rm -f /tmp/ml.zip
[ -f "${INSTALL_DIR}/version.dll" ] || { echo "ERROR: MelonLoader extraction failed."; exit 1; }

# --- 5) Server mod DLL (pinned release, runtime-matched) ---------------------
echo ">>> DedicatedServerMod ${MOD_VERSION} (${MOD_DLL}) ..."
rm -rf /tmp/modzip && mkdir -p /tmp/modzip "${INSTALL_DIR}/Mods"
curl -fsSL -o /tmp/mod.zip "https://github.com/ifBars/S1DedicatedServers/releases/download/${MOD_VERSION}/Docker.zip"
unzip -oq /tmp/mod.zip -d /tmp/modzip
rm -f "${INSTALL_DIR}/Mods/DedicatedServerMod_Mono_Server.dll" "${INSTALL_DIR}/Mods/DedicatedServerMod_Il2cpp_Server.dll"
MODSRC=$(find /tmp/modzip -type f -name "${MOD_DLL}" | head -n1)
[ -n "${MODSRC}" ] || { echo "ERROR: ${MOD_DLL} not found in release ${MOD_VERSION}."; exit 1; }
cp -f "${MODSRC}" "${INSTALL_DIR}/Mods/${MOD_DLL}"
rm -rf /tmp/mod.zip /tmp/modzip
echo "  + Mods/${MOD_DLL}"

# --- 6) Seed server_config.toml (only if absent) -----------------------------
mkdir -p "${INSTALL_DIR}/UserData"
CFG="${INSTALL_DIR}/UserData/server_config.toml"
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

# --- Cleanup transient install artifacts -------------------------------------
rm -rf "${INSTALL_DIR}/.steamcmd" "${INSTALL_DIR}/.redist" "${HOME}"

echo "=== Schedule I install complete (runtime=${RUNTIME}) ==="
