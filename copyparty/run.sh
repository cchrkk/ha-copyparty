#!/bin/sh
# copyparty app for Home Assistant
#
# Three processes:
#   3923  copyparty, plain web UI / WebDAV, for the LAN and for a reverse proxy
#   3929  nginx, the port Supervisor's ingress talks to (the sidebar panel)
#   3930  copyparty behind nginx, mounted under the ingress path
#
# Why two copyparty workers: copyparty scopes its login cookie to the path
# given by --rp-loc, so the worker that serves the panel (mounted under
# /api/hassio_ingress/<token>) could not keep a session on 3923. Each worker
# has its own state directory (--hist/--dbpath/--ses-db); only the files are
# shared.
#
# Why nginx: Home Assistant strips the ingress prefix before forwarding the
# request and tells the app where it lives only through the X-Ingress-Path
# header. copyparty has no such option, so without nginx it would emit
# unprefixed URLs and the panel would fail on the first asset (util.js).

set -eu

OPTIONS=/data/options.json
BASE_CONF=/data/copyparty.conf
INGRESS_CONF=/data/copyparty-ingress.conf
NGINX_CONF=/data/nginx.conf

log() { printf '%s [copyparty] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >&2; }
alive() { kill -0 "$1" 2>/dev/null; }

if [ ! -f "$OPTIONS" ]; then
  log "ERROR: $OPTIONS not found"
  exit 1
fi

USERNAME=$(jq -r '.username // "chrk"' "$OPTIONS")
PASSWORD=$(jq -r '.password // ""' "$OPTIONS")
PERMISSIONS=$(jq -r '.permissions // "rw"' "$OPTIONS")
EXTRA_CONFIG=$(jq -r '.extra_config // ""' "$OPTIONS")

# Building the file index costs one stat per file at every start (and a scan
# of everything on the first one), which on /share or /media is a lot of I/O.
# Browsing, uploading and downloading work without it.
if [ "$(jq -r '.index // false' "$OPTIONS")" = "true" ]; then
  INDEX_FOLDERS=yes
else
  INDEX_FOLDERS=no
fi

if [ -z "$PASSWORD" ]; then
  log "ERROR: the 'password' option is empty; refusing to run an unauthenticated file server"
  exit 1
fi

case "$PERMISSIONS" in
  r) ACCS="r" ;;
  *) ACCS="rwmd" ;;
esac

# folder name -> path inside the container (mounted by Supervisor via "map:")
# Supervisor renamed the app folders in 2026.07: local_apps and all_app_configs
# are mounted at /local_apps and /app_configs, the legacy keys at /addons and
# /addon_configs. Try the new path first, then the old one.
folder_path() {
  case "$1" in
    config)         set -- /config /homeassistant ;;
    share)          set -- /share ;;
    media)          set -- /media ;;
    backup)         set -- /backup ;;
    ssl)            set -- /ssl ;;
    addons)         set -- /local_apps /addons ;;
    addon_configs)  set -- /app_configs /addon_configs ;;
    *)              echo ""; return 0 ;;
  esac
  for candidate in "$@"; do
    if [ -d "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  echo ""
}

build_conf() {
  out=$1
  with_index=$2

  {
    printf '[global]\n'
    if [ "$with_index" = yes ]; then
      printf '  e2dsa\n'
    fi
    printf '  no-robots\n'
    printf '  no-crt\n'
    # The config file wants "key: value"; "key=value" is silently ignored.
    printf '  xff-hdr: x-forwarded-for\n'
    # trust the private networks only: Home Assistant ingress (172.30.32.0/24),
    # the Cloudflare tunnel host and the LAN. Internet clients cannot spoof it.
    printf '  xff-src: lan\n'
    printf '  rproxy: 1\n'
    if [ "$with_index" = no ]; then
      # Home Assistant opens an app panel inside a sandboxed iframe, so the
      # browser sends "Origin: null" and copyparty's cors-check rejects every
      # login. Only this worker (reachable just through ingress) accepts it.
      printf '  acao-re: ^null$\n'
    fi
    printf '\n[accounts]\n'
    printf '  %s: %s\n' "$USERNAME" "$PASSWORD"

    jq -r '.folders[]?' "$OPTIONS" | while read -r folder; do
      [ -n "$folder" ] || continue
      path=$(folder_path "$folder")
      if [ -z "$path" ]; then
        log "WARNING: folder '$folder' is not mounted in this installation, skipped"
        continue
      fi
      printf '\n[/%s]\n  %s\n  accs:\n    %s: %s\n' "$folder" "$path" "$ACCS" "$USERNAME"
    done

    if [ -n "$EXTRA_CONFIG" ]; then
      printf '\n# --- extra_config ---\n%s\n' "$EXTRA_CONFIG"
    fi
  } > "$out"
}

build_conf "$BASE_CONF" "$INDEX_FOLDERS"
build_conf "$INGRESS_CONF" no

# The ingress path is stable per installation; Supervisor knows it.
INGRESS_PATH=""
if [ -n "${SUPERVISOR_TOKEN:-}" ]; then
  info=$(curl -fsS --max-time 10 \
    -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
    http://supervisor/addons/self/info 2>/dev/null || true)
  INGRESS_PATH=$(printf '%s' "$info" | jq -r '.data.ingress_entry // empty' 2>/dev/null || true)
fi
INGRESS_PATH=${INGRESS_PATH%/}

mkdir -p /data/direct/hist /data/direct/db /data/ingress/hist /data/ingress/db \
  /tmp/nginx-body /tmp/nginx-proxy

log "starting worker for port 3923 (with file index)"
set -- -c "$BASE_CONF" -i 0.0.0.0 -p 3923 \
  --hist /data/direct/hist \
  --dbpath /data/direct/db \
  --ses-db /data/direct/ses.db
# optional: a real certificate, so https on 3923 does not warn (see /ssl)
if [ -f /ssl/copyparty.pem ]; then
  set -- "$@" --cert /ssl/copyparty.pem
  log "using /ssl/copyparty.pem for https"
fi
copyparty "$@" &

DIRECT_PID=$!
INGRESS_PID=""
NGINX_PID=""

if [ -n "$INGRESS_PATH" ]; then
  log "starting worker for the sidebar (ingress ${INGRESS_PATH})"
  copyparty -c "$INGRESS_CONF" \
    -i 127.0.0.1 -p 3930 \
    --rp-loc "$INGRESS_PATH" \
    --hist /data/ingress/hist \
    --dbpath /data/ingress/db \
    --ses-db /data/ingress/ses.db &

  INGRESS_PID=$!

  # nginx puts the prefix back in front of every request, so copyparty sees
  # /api/hassio_ingress/<token>/... and generates URLs that work inside the
  # Home Assistant panel.
  cat > "${NGINX_CONF}.tpl" <<'EOF'
worker_processes 1;
pid /tmp/nginx.pid;
error_log /dev/stderr warn;

events {
    worker_connections 1024;
}

http {
    access_log off;
    client_max_body_size 0;
    client_body_temp_path /tmp/nginx-body;
    proxy_temp_path /tmp/nginx-proxy;

    server {
        listen 3929;

        location / {
            proxy_pass http://127.0.0.1:3930@@PREFIX@@$request_uri;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-For $http_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
            proxy_buffering off;
            proxy_request_buffering off;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
        }
    }
}
EOF
  sed "s|@@PREFIX@@|${INGRESS_PATH}|g" "${NGINX_CONF}.tpl" > "$NGINX_CONF"

  nginx -c "$NGINX_CONF" -g 'daemon off;' &
  NGINX_PID=$!
else
  log "WARNING: Supervisor did not report an ingress path; the sidebar panel will not work"
fi

shutdown() {
  code=${1:-0}
  trap - TERM INT
  log "stopping"
  for pid in "$DIRECT_PID" ${INGRESS_PID:+"$INGRESS_PID"} ${NGINX_PID:+"$NGINX_PID"}; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  exit "$code"
}
trap 'shutdown 0' TERM INT

while :; do
  alive "$DIRECT_PID" || break
  if [ -n "$INGRESS_PID" ]; then
    alive "$INGRESS_PID" || break
    alive "$NGINX_PID" || break
  fi
  sleep 5
done

log "a worker exited, restarting the app"
shutdown 1
