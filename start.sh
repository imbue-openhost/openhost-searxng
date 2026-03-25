#!/bin/sh
set -e

# OpenHost mounts persistent storage at OPENHOST_APP_DATA_DIR.
# SearXNG expects config in /etc/searxng/ and cache data in /var/cache/searxng/.
# These are Docker VOLUMEs so we can't symlink over them. Instead we copy
# persisted config into the volume on startup and back it up on shutdown.
PERSIST="${OPENHOST_APP_DATA_DIR:-/data}"

CONFIG_BACKUP="$PERSIST/config"
DATA_BACKUP="$PERSIST/data"

mkdir -p "$CONFIG_BACKUP" "$DATA_BACKUP"

# Restore persisted config into the volume (survives container recreation)
if [ -f "$CONFIG_BACKUP/settings.yml" ]; then
    cp -a "$CONFIG_BACKUP/"* /etc/searxng/ 2>/dev/null || true
fi

# Restore persisted cache data
if [ "$(ls -A "$DATA_BACKUP" 2>/dev/null)" ]; then
    cp -a "$DATA_BACKUP/"* /var/cache/searxng/ 2>/dev/null || true
fi

# Generate and persist a secret key across restarts
SECRET_KEY_FILE="$PERSIST/.secret_key"
if [ -f "$SECRET_KEY_FILE" ]; then
    SECRET_KEY=$(cat "$SECRET_KEY_FILE")
else
    SECRET_KEY=$(head -c 32 /dev/urandom | base64 | tr -d '\n/+=' | head -c 64)
    echo -n "$SECRET_KEY" > "$SECRET_KEY_FILE"
fi

# Derive base_url from OpenHost environment variables
if [ -n "$OPENHOST_ZONE_DOMAIN" ]; then
    APP_SUBDOMAIN="${OPENHOST_APP_NAME:-searxng}"
    DOMAIN_NAME="${APP_SUBDOMAIN}.${OPENHOST_ZONE_DOMAIN}"

    case "$OPENHOST_ZONE_DOMAIN" in
        lvh.me|*.lvh.me|localhost|*.localhost)
            # Dev environment — use http with the router's external port
            ROUTER_PORT=""
            if [ -n "$OPENHOST_ROUTER_URL" ]; then
                ROUTER_PORT=$(echo "$OPENHOST_ROUTER_URL" | sed -n 's/.*:\([0-9]*\)$/\1/p')
            fi
            BASE_URL="http://${DOMAIN_NAME}${ROUTER_PORT:+:$ROUTER_PORT}/"
            ;;
        *)
            # Production — HTTPS on standard port
            BASE_URL="https://${DOMAIN_NAME}/"
            ;;
    esac
else
    DOMAIN_NAME="localhost"
    BASE_URL="http://localhost:3000/"
fi

# Write settings.yml if it doesn't already exist (first boot)
SETTINGS_FILE="/etc/searxng/settings.yml"
if [ ! -f "$SETTINGS_FILE" ]; then
    cat > "$SETTINGS_FILE" <<EOF
use_default_settings: true
server:
  base_url: "${BASE_URL}"
  secret_key: "${SECRET_KEY}"
  limiter: false
  image_proxy: true
  method: "GET"
ui:
  static_use_hash: true
EOF
fi

# Always export base_url and secret as env vars (overrides settings.yml)
export SEARXNG_BASE_URL="$BASE_URL"
export SEARXNG_SECRET="$SECRET_KEY"

# Back up config to persistent storage so it survives container recreation
cp -a /etc/searxng/* "$CONFIG_BACKUP/" 2>/dev/null || true

# Fix ownership for the searxng user inside the container
chown -R searxng:searxng "$PERSIST" 2>/dev/null || true
chown -R searxng:searxng /etc/searxng 2>/dev/null || true
chown -R searxng:searxng /var/cache/searxng 2>/dev/null || true

# Start Caddy in background — it rewrites Host from X-Forwarded-Host on
# port 3000, then proxies to SearXNG on port 8080.
/usr/local/bin/caddy run --config /app/Caddyfile &

# Hand off to the official SearXNG entrypoint
exec /usr/local/searxng/entrypoint.sh
