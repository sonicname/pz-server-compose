#!/usr/bin/env bash
# Thin wrapper: `pz-rcon <command...>` sends one RCON command to the local server.
# Example: docker compose exec pz pz-rcon players
set -euo pipefail
exec rcon -a "${RCON_HOST:-127.0.0.1}:${RCON_PORT:-27015}" -p "${RCON_PASSWORD:?RCON_PASSWORD not set}" "$*"
