FROM caddy:builder AS builder

RUN xcaddy build \
    --with github.com/mohammed90/caddy-git-fs \
    --with github.com/RussellLuo/caddy-ext/ratelimit

FROM caddy

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

WORKDIR /srv

COPY Caddyfile /etc/caddy/Caddyfile

EXPOSE 80 443

CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]

