FROM searxng/searxng:latest

# The SearXNG image is Void Linux-based (no apk/apt). Download a static
# Caddy binary for Host header rewriting (the OpenHost router strips Host
# and sets X-Forwarded-Host; SearXNG needs them to match for correct URLs).
RUN mkdir -p /usr/local/bin && \
    wget -qO /tmp/caddy.tar.gz "https://github.com/caddyserver/caddy/releases/download/v2.9.1/caddy_2.9.1_linux_amd64.tar.gz" && \
    tar -xzf /tmp/caddy.tar.gz -C /usr/local/bin caddy && \
    chmod +x /usr/local/bin/caddy && \
    rm /tmp/caddy.tar.gz

# Copy our startup wrapper and Caddyfile
COPY start.sh /app/start.sh
COPY Caddyfile /app/Caddyfile
RUN chmod +x /app/start.sh

EXPOSE 3000

ENTRYPOINT []
CMD ["/app/start.sh"]
