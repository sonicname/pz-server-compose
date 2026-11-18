#!/usr/bin/env bash
# Periodic world backup. Runs as the `backup` service (same image, different command).
#   1. asks the server to flush the world to disk via RCON `save`
#   2. tars the world save + player DB + server config into /backups
#   3. keeps only the newest BACKUP_KEEP archives
# Also usable once, on demand:  docker compose run --rm backup once
set -euo pipefail

SERVER_NAME="${SERVER_NAME:-pzserver}"
INTERVAL_MIN="${BACKUP_INTERVAL_MINUTES:-180}"
KEEP="${BACKUP_KEEP:-24}"
ZOMBOID_DIR="/home/steam/Zomboid"
DEST="/backups"

log() { echo "[backup $(date '+%F %T')] $*"; }

do_backup() {
  local save_dir="Saves/Multiplayer/${SERVER_NAME}"
  if [[ ! -d "${ZOMBOID_DIR}/${save_dir}" ]]; then
    log "no world yet at ${save_dir} — skipping"
    return 0
  fi

  if pz-rcon save >/dev/null 2>&1; then
    log "RCON save requested, waiting for flush"
    sleep 20
  else
    log "WARN: RCON save failed (server down?) — backing up files as-is"
  fi

  local stamp file
  stamp="$(date '+%Y%m%d-%H%M%S')"
  file="${DEST}/${SERVER_NAME}-${stamp}.tar.gz"

  # Paths that exist are included; missing optional ones are skipped.
  local paths=("${save_dir}")
  for p in "db/${SERVER_NAME}.db" "Server/${SERVER_NAME}.ini" \
           "Server/${SERVER_NAME}_SandboxVars.lua" "Server/${SERVER_NAME}_spawnregions.lua"; do
    [[ -e "${ZOMBOID_DIR}/${p}" ]] && paths+=("${p}")
  done

  tar -czf "${file}.part" -C "${ZOMBOID_DIR}" "${paths[@]}" --warning=no-file-changed || {
    rc=$?; [[ $rc -eq 1 ]] || { log "ERROR: tar failed ($rc)"; rm -f "${file}.part"; return 1; }
  }
  mv "${file}.part" "${file}"
  log "wrote $(du -h "${file}" | cut -f1) -> ${file}"

  # Rotation: newest first, delete everything after KEEP.
  ls -1t "${DEST}/${SERVER_NAME}-"*.tar.gz 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
    rm -f -- "${old}" && log "pruned ${old##*/}"
  done
}

if [[ "${1:-loop}" == "once" ]]; then
  do_backup
  exit $?
fi

log "every ${INTERVAL_MIN} min, keeping ${KEEP} archives"
# First backup after one interval, not immediately (server may still be booting).
while true; do
  sleep "$((INTERVAL_MIN * 60))" &
  wait $!
  do_backup || log "backup failed, will retry next interval"
done
