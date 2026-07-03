#!/bin/bash
# GravelHost - Schedule I / Pterodactyl installer.
# Baked into the image; the egg's install step just calls `bash /install.sh`.
# Runs in the Pterodactyl install container and writes the finished server to
# /mnt/server. Adapts upstream run.sh (download + redist + MelonLoader) to the
# Pterodactyl "install once" model.
set -euo pipefail

STEAMAPPID=3164500
INSTALL_DIR=/mnt/server
BOOTSTRAP=/home/steam/bootstrap

RUNTIME=$(printf '%s' "${S1DS_RUNTIME:-mono}" | tr '[:upper:]' '[:lower:]')
case "${RUNTIME}" in
    mono)   DEFAULT_BRANCH="alternate"; MOD_DLL="DedicatedServerMod_Mono_Server.dll" ;;
    il2cpp) DEFAULT_BRANCH="";           MOD_DLL="DedicatedServerMod_Il2cpp_Server.dll" ;;
    *) echo "ERROR: S1DS_RUNTIME must be 'mono' or 'il2cpp' (got '${RUNTIME}')."; exit 1 ;;
esac
BRANCH="${STEAM_BRANCH:-$DEFAULT_BRANCH}"

echo "=== Schedule I install : runtime=${RUNTIME} branch=${BRANCH:-default} dll=${MOD_DLL} ==="
mkdir -p "${INSTALL_DIR}"

if [ -z "${STEAM_USER:-}" ] || [ -z "${STEAM_PASS:-}" ]; then
    echo "ERROR: STEAM_USER and STEAM_PASS are required to download the paid game."
    exit 1
fi

# --- Working copy of SteamCMD (writable regardless of install user) ----------
STEAMCMD_DIR="${INSTALL_DIR}/.steamcmd"
export HOME="${INSTALL_DIR}/.steamhome"
mkdir -p "${STEAMCMD_DIR}" "${HOME}"
if [ -d /home/steam/steamcmd ]; then
    cp -a /home/steam/steamcmd/. "${STEAMCMD_DIR}/" 2>/dev/null || true
fi
if [ ! -f "${STEAMCMD_DIR}/steamcmd.sh" ]; then
    curl -sSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar -xz -C "${STEAMCMD_DIR}"
fi
STEAMCMD="${STEAMCMD_DIR}/steamcmd.sh"
chmod +x "${STEAMCMD}" 2>/dev/null || true

# --- 1) Download the paid game (real creds, Windows platform, matching branch)
echo ">>> SteamCMD: downloading app ${STEAMAPPID} ..."
STEAMCMD_ARGS=(
    +@sSteamCmdForcePlatformType windows
    +force_install_dir "${INSTALL_DIR}"
    +login "${STEAM_USER}" "${STEAM_PASS}" "${STEAM_GUARD:-}"
    +app_update "${STEAMAPPID}"
)
[ -n "${BRANCH}" ] && STEAMCMD_ARGS+=(-beta "${BRANCH}")
STEAMCMD_ARGS+=(validate +quit)
"${STEAMCMD}" "${STEAMCMD_ARGS[@]}"

if [ ! -f "${INSTALL_DIR}/Schedule I.exe" ]; then
    echo "ERROR: 'Schedule I.exe' missing after SteamCMD (bad credentials, Steam Guard, or wrong branch)."
    exit 1
fi

# --- 2) Steamworks redist (app 1007, anonymous) + copy native DLLs -----------
echo ">>> SteamCMD: Steamworks redist (app 1007) ..."
REDIST_DIR="${INSTALL_DIR}/.redist"
mkdir -p "${REDIST_DIR}"
"${STEAMCMD}" +@sSteamCmdForcePlatformType windows \
    +force_install_dir "${REDIST_DIR}" \
    +login anonymous \
    +app_update 1007 validate \
    +quit || true

copy_dll() {
    local name="$1" src=""
    local candidates=(
        "${REDIST_DIR}/${name}"
        "${REDIST_DIR}/redistributable_bin/${name}"
        "${REDIST_DIR}/redistributable_bin/win64/${name}"
        "${INSTALL_DIR}/Schedule I_Data/Plugins/x86_64/${name}"
    )
    for c in "${candidates[@]}"; do [ -f "$c" ] && { src="$c"; break; }; done
    [ -z "$src" ] && src=$(find "${REDIST_DIR}" "${INSTALL_DIR}" -type f -name "$name" 2>/dev/null | head -n1)
    if [ -n "$src" ]; then cp -f "$src" "${INSTALL_DIR}/${name}"; echo "  + ${name}"; else echo "  ! missing ${name}"; fi
}
for d in steamclient64.dll steam_api64.dll tier0_s64.dll vstdlib_s64.dll steamclient.dll tier0_s.dll vstdlib_s.dll; do
    copy_dll "$d"
done

# --- 3) steam_appid.txt ------------------------------------------------------
printf "%s\n" "${STEAMAPPID}" > "${INSTALL_DIR}/steam_appid.txt"

# --- 4) MelonLoader (baked in the image) -------------------------------------
echo ">>> Applying MelonLoader ..."
if [ ! -f "${BOOTSTRAP}/ml/version.dll" ]; then
    echo "ERROR: MelonLoader bootstrap missing in image at ${BOOTSTRAP}/ml."
    exit 1
fi
cp -f "${BOOTSTRAP}/ml/version.dll" "${INSTALL_DIR}/version.dll"
mkdir -p "${INSTALL_DIR}/MelonLoader"
cp -r "${BOOTSTRAP}/ml/MelonLoader/." "${INSTALL_DIR}/MelonLoader/"

# --- 5) The runtime-matching server mod DLL ----------------------------------
mkdir -p "${INSTALL_DIR}/Mods"
rm -f "${INSTALL_DIR}/Mods/DedicatedServerMod_Mono_Server.dll" \
      "${INSTALL_DIR}/Mods/DedicatedServerMod_Il2cpp_Server.dll"
cp -f "${BOOTSTRAP}/mods/${MOD_DLL}" "${INSTALL_DIR}/Mods/${MOD_DLL}"

# --- 6) Seed a valid server_config.toml (only if none exists yet) ------------
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
rm -rf "${STEAMCMD_DIR}" "${REDIST_DIR}" "${HOME}"

echo "=== Schedule I install complete (runtime=${RUNTIME}) ==="
