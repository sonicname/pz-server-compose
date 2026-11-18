#!/usr/bin/env bash
# Container entrypoint for the Project Zomboid dedicated server (Build 42).
#
#   (root)  fix UID/GID + volume ownership, then drop to the `steam` user
#   (steam) install/update the server via SteamCMD
#           apply memory setting + managed .ini keys + mod list
#           run the server with stdin on a FIFO so `docker stop` can send `quit`
#
# Command: `server` (default) or `backup` (runs the periodic backup loop).
set -euo pipefail

APP_ID=380870
MODE="${1:-server}"
SERVER_NAME="${SERVER_NAME:-pzserver}"
ZOMBOID_DIR="${HOME}/Zomboid"
INI="${ZOMBOID_DIR}/Server/${SERVER_NAME}.ini"
MODS_FILE="${MODS_FILE:-/config/mods.txt}"

log() { echo "[entrypoint $(date '+%F %T')] $*"; }

# --------------------------------------------------------------------------- #
# Phase 1 (root): ownership, then re-exec as steam
# --------------------------------------------------------------------------- #
if [[ "$(id -u)" == "0" ]]; then
  PUID="${PUID:-1000}"; PGID="${PGID:-1000}"
  if [[ "$(id -g steam)" != "${PGID}" ]]; then groupmod -o -g "${PGID}" steam; fi
  if [[ "$(id -u steam)" != "${PUID}" ]]; then usermod -o -u "${PUID}" steam; fi
  for d in "${SERVER_DIR}" "${ZOMBOID_DIR}" "${STEAMCMD_DIR}" /home/steam /backups; do
    [[ -d "$d" ]] || continue
    # Only walk the tree if the top level is wrong (cheap on every restart).
    if [[ "$(stat -c '%u:%g' "$d")" != "${PUID}:${PGID}" ]]; then
      log "fixing ownership of $d"
      chown -R "${PUID}:${PGID}" "$d" 2>/dev/null || log "WARN: cannot chown $d (read-only mount?)"
    fi
    chmod u+rwx "$d" 2>/dev/null || true
  done
  exec setpriv --reuid=steam --regid=steam --init-groups --inh-caps=-all "$0" "$@"
fi

if [[ "${MODE}" == "backup" ]]; then
  exec pz-backup "${@:2}"
fi

: "${RCON_PASSWORD:?RCON_PASSWORD must be set in .env}"
: "${ADMIN_PASSWORD:?ADMIN_PASSWORD must be set in .env}"

# --------------------------------------------------------------------------- #
# Phase 2: install / update
# --------------------------------------------------------------------------- #
install_server() {
  local beta=()
  # Empty STEAM_BRANCH = public (stable) branch. Never pass "-beta public".
  [[ -n "${STEAM_BRANCH:-}" ]] && beta=(-beta "${STEAM_BRANCH}")
  local attempt
  for attempt in 1 2 3; do
    log "SteamCMD app_update ${APP_ID} ${beta[*]:-(public)} — attempt ${attempt}"
    if "${STEAMCMD_DIR}/steamcmd.sh" +force_install_dir "${SERVER_DIR}" \
         +login anonymous +app_update "${APP_ID}" "${beta[@]}" validate +quit; then
      [[ -x "${SERVER_DIR}/start-server.sh" ]] && return 0
    fi
    sleep 10
  done
  log "ERROR: SteamCMD failed 3 times"
  return 1
}

if [[ ! -x "${SERVER_DIR}/start-server.sh" ]]; then
  install_server
elif [[ "${AUTO_UPDATE:-true}" == "true" ]]; then
  install_server || log "WARN: update failed — starting the already installed version"
else
  log "AUTO_UPDATE=false — skipping game update"
fi

# Steam client lib where the server's Steamworks wrapper looks for it
# (helps Workshop downloads), and the bundled JRE libs (libjsig preload error).
mkdir -p "${HOME}/.steam/sdk64"
cp -f "${STEAMCMD_DIR}/linux64/steamclient.so" "${HOME}/.steam/sdk64/" 2>/dev/null || true
export LD_LIBRARY_PATH="${SERVER_DIR}/jre64/lib:${SERVER_DIR}/linux64:${LD_LIBRARY_PATH:-}"

# --------------------------------------------------------------------------- #
# Phase 3: JVM memory (single source of truth: ProjectZomboid64.json vmArgs)
# --------------------------------------------------------------------------- #
JSON="${SERVER_DIR}/ProjectZomboid64.json"
if [[ -f "${JSON}" ]]; then
  MEM="${SERVER_MEMORY:-6g}"
  tmp="$(mktemp)"
  jq --arg xmx "-Xmx${MEM}" --arg xms "-Xms${MEM}" '
      .vmArgs |= ( map(select(startswith("-Xmx") or startswith("-Xms") | not)) + [$xms, $xmx] )
    ' "${JSON}" > "${tmp}" && cat "${tmp}" > "${JSON}"
  rm -f "${tmp}"
  log "JVM heap set to ${MEM}"
else
  log "WARN: ${JSON} not found — JVM memory left at game default"
fi

# --------------------------------------------------------------------------- #
# Phase 4: server .ini — managed keys are rewritten on every start.
# Everything else in the .ini is yours to edit (it is preserved).
# --------------------------------------------------------------------------- #
set_ini() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "${INI}"; then
    # Use awk (not sed) so values containing \ / & are written literally.
    # Value passed via ENVIRON: `awk -v` would eat the backslashes in "\ModID".
    K="${key}" V="${value}" awk 'BEGIN{k=ENVIRON["K"]; v=ENVIRON["V"]} index($0, k "=")==1 {print k "=" v; next} {print}' \
      "${INI}" > "${INI}.tmp" && cat "${INI}.tmp" > "${INI}" && rm -f "${INI}.tmp"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${INI}"
  fi
}

build_mod_lines() {
  WORKSHOP_ITEMS=""; MOD_IDS=""; MAP_FOLDERS=""
  [[ -f "${MODS_FILE}" ]] || { log "no ${MODS_FILE} — running vanilla"; return; }
  local line wid mids map id
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"                       # strip comments
    [[ -z "${line//[[:space:]]/}" ]] && continue
    IFS='|' read -r wid mids map <<< "${line}"
    wid="$(echo "${wid}" | xargs)"; map="$(echo "${map:-}" | xargs)"
    if [[ ! "${wid}" =~ ^[0-9]+$ ]]; then log "WARN: bad workshop id in line: ${line}"; continue; fi
    WORKSHOP_ITEMS+="${WORKSHOP_ITEMS:+;}${wid}"
    IFS=';' read -ra ids <<< "${mids}"
    for id in "${ids[@]}"; do
      id="$(echo "${id}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"   # keep inner spaces
      [[ -n "${id}" ]] && MOD_IDS+="${MOD_IDS:+;}\\${id}"              # B42 form: \ModID
    done
    [[ -n "${map}" ]] && MAP_FOLDERS+="${map};"
  done < "${MODS_FILE}"
}

mkdir -p "${ZOMBOID_DIR}/Server"
[[ -f "${INI}" ]] || { log "first run: creating ${INI}"; : > "${INI}"; }

build_mod_lines
set_ini WorkshopItems "${WORKSHOP_ITEMS}"
set_ini Mods "${MOD_IDS}"
set_ini Map "${MAP_FOLDERS}Muldraugh, KY"
log "mods: $(tr ';' '\n' <<< "${WORKSHOP_ITEMS}" | grep -c . || true) workshop items"

set_ini PublicName           "${SERVER_PUBLIC_NAME:-PZ with friends}"
set_ini PublicDescription    "${SERVER_DESCRIPTION:-}"
set_ini Password             "${SERVER_PASSWORD:-}"
set_ini Public               "${SERVER_LISTED:-false}"
set_ini MaxPlayers           "${MAX_PLAYERS:-8}"
set_ini DefaultPort          16261
set_ini UDPPort              16262
set_ini UPnP                 false
set_ini RCONPort             "${RCON_PORT:-27015}"
set_ini RCONPassword         "${RCON_PASSWORD}"
set_ini SaveWorldEveryMinutes "${SAVE_EVERY_MINUTES:-10}"
set_ini PauseEmpty           "${PAUSE_EMPTY:-true}"
set_ini DoLuaChecksum        "${LUA_CHECKSUM:-true}"
# Built-in backups as a second safety net (the backup service is the first).
set_ini BackupsOnStart       true
set_ini BackupsOnVersionChange true
set_ini BackupsCount         "${GAME_BACKUPS_COUNT:-5}"

# --------------------------------------------------------------------------- #
# Phase 5: run, with graceful shutdown on SIGTERM
# --------------------------------------------------------------------------- #
args=(-servername "${SERVER_NAME}")
if [[ ! -f "${ZOMBOID_DIR}/db/${SERVER_NAME}.db" ]]; then
  # Only on the very first boot: creates the admin account non-interactively.
  args+=(-adminusername "${ADMIN_USERNAME:-admin}" -adminpassword "${ADMIN_PASSWORD}")
fi
[[ -n "${BIND_IP:-}" ]] && args+=(-ip "${BIND_IP}")

FIFO="/tmp/pz-stdin"
rm -f "${FIFO}"; mkfifo "${FIFO}"
exec 3<>"${FIFO}"   # keep the FIFO open so the server never sees EOF

cd "${SERVER_DIR}"
log "starting: start-server.sh ${args[*]//"${ADMIN_PASSWORD}"/***}"
./start-server.sh "${args[@]}" <&3 &
PZ_PID=$!

shutdown() {
  log "SIGTERM received — saving and quitting (up to ${SHUTDOWN_TIMEOUT:-150}s)"
  echo "save" >&3 || true
  sleep 5
  echo "quit" >&3 || true
  local waited=0
  while kill -0 "${PZ_PID}" 2>/dev/null && (( waited < ${SHUTDOWN_TIMEOUT:-150} )); do
    sleep 1; waited=$((waited + 1))
  done
  if kill -0 "${PZ_PID}" 2>/dev/null; then
    log "WARN: server did not exit in time, sending SIGTERM"
    kill -TERM "${PZ_PID}" 2>/dev/null || true
  fi
  wait "${PZ_PID}" 2>/dev/null || true
  log "server stopped"
  exit 0
}
trap shutdown TERM INT

rc=0
wait "${PZ_PID}" || rc=$?
log "server process exited with code ${rc}"
exit "${rc}"
