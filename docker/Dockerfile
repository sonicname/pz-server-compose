# Project Zomboid dedicated server (Steam app 380870) — SteamCMD on Debian.
# The game itself is NOT baked into the image: it is installed/updated into a
# volume at container start, so image rebuilds are rare and game updates are
# controlled by the AUTO_UPDATE / STEAM_BRANCH env vars.
FROM debian:bookworm-slim

ARG RCON_CLI_VERSION=0.10.3
ARG PUID=1000
ARG PGID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    STEAMCMD_DIR=/opt/steamcmd \
    SERVER_DIR=/opt/pzserver \
    HOME=/home/steam

RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl tar gzip jq tini procps \
      lib32gcc-s1 lib32stdc++6 libsdl2-2.0-0:i386 \
 && rm -rf /var/lib/apt/lists/*

# RCON client used for graceful shutdown, saves before backups, and admin commands.
RUN curl -fsSL "https://github.com/gorcon/rcon-cli/releases/download/v${RCON_CLI_VERSION}/rcon-${RCON_CLI_VERSION}-amd64_linux.tar.gz" \
      | tar -xz -C /tmp \
 && mv /tmp/rcon-${RCON_CLI_VERSION}-amd64_linux/rcon /usr/local/bin/rcon \
 && rm -rf /tmp/rcon-*

RUN groupadd -g ${PGID} steam \
 && useradd -m -u ${PUID} -g ${PGID} -d /home/steam steam \
 && mkdir -p ${STEAMCMD_DIR} ${SERVER_DIR} /home/steam/Zomboid \
 && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
      | tar -xz -C ${STEAMCMD_DIR} \
 && chown -R steam:steam ${STEAMCMD_DIR} ${SERVER_DIR} /home/steam

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=755 pz-rcon.sh /usr/local/bin/pz-rcon
COPY --chmod=755 backup.sh /usr/local/bin/pz-backup

USER steam
WORKDIR /home/steam

# Warm up steamcmd (self-update) at build time so first start is faster.
RUN ${STEAMCMD_DIR}/steamcmd.sh +quit || true

# Entrypoint starts as root only to fix volume ownership, then drops to `steam`.
USER root
RUN mkdir -p /backups /config && chown steam:steam /backups

VOLUME ["/opt/pzserver", "/home/steam/Zomboid"]
EXPOSE 16261/udp 16262/udp

HEALTHCHECK --interval=60s --timeout=10s --start-period=30m --retries=3 \
  CMD pgrep -f ProjectZomboid64 >/dev/null || exit 1

# No `tini -g`: SIGTERM must reach only entrypoint.sh, which sends `save`+`quit`
# to the server; signalling Java directly could kill it mid-save.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["server"]
