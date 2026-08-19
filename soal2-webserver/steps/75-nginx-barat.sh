#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

require_root
require_apt
compute_ports

export BARAT_CRT="$(srv_fullchain "$HOST_BARAT")"
export BARAT_KEY="$(srv_key "$HOST_BARAT")"

[ -f "$BARAT_CRT" ] || die "certificate ${BARAT_CRT} missing; run steps/50-ca.sh first"
[ -f "$BARAT_KEY" ] || die "key ${BARAT_KEY} missing; run steps/50-ca.sh first"

apt_install nginx

write_nginx_common

if [ ! -f /etc/nginx/dhparam.pem ]; then
    info "generating 2048-bit DH parameters"
    openssl dhparam -out /etc/nginx/dhparam.pem 2048 2>/dev/null
    chmod 0644 /etc/nginx/dhparam.pem
fi

NGINX_VER="$(nginx -v 2>&1 | sed -n 's#.*nginx/\([0-9.]*\).*#\1#p')"
if [ -n "$NGINX_VER" ] \
    && [ "$(printf '%s\n%s\n' 1.25.1 "$NGINX_VER" | sort -V | head -1)" = "1.25.1" ]; then
    export LISTEN_SSL_SUFFIX=""
    export HTTP2_DIRECTIVE="    http2 on;"
    info "nginx ${NGINX_VER}: using 'http2 on;'"
else
    export LISTEN_SSL_SUFFIX=" http2"
    export HTTP2_DIRECTIVE=""
    info "nginx ${NGINX_VER:-unknown}: using legacy 'listen ... ssl http2'"
fi

export BARAT_DOCROOT="${WEBROOT_BASE}/barat"

install -d -m 0755 "$BARAT_DOCROOT"
render_template www/barat.html "${BARAT_DOCROOT}/index.html" \
    '${HOST_BARAT} ${BARAT_HTTPS_PORT} ${CA_CN}'
chown -R www-data:www-data "$BARAT_DOCROOT"

render_template nginx/barat.conf /etc/nginx/sites-available/barat \
    '${BARAT_HTTP_PORT} ${BARAT_HTTPS_PORT} ${HOST_BARAT} ${BARAT_DOCROOT} ${BARAT_CRT} ${BARAT_KEY} ${HSTS_MAX_AGE} ${PESERTA_NAMA} ${LISTEN_SSL_SUFFIX} ${HTTP2_DIRECTIVE}'
ln -sfn /etc/nginx/sites-available/barat /etc/nginx/sites-enabled/barat

nginx -t || die "nginx config invalid; nothing restarted"

systemctl daemon-reload
systemctl restart nginx

open_firewall_port "$BARAT_HTTPS_PORT"
open_firewall_port "$BARAT_HTTP_PORT"

sleep 1

curl -sS -o /dev/null -D - "http://${HOST_BARAT}:${BARAT_HTTP_PORT}/" 2>/dev/null \
    | grep -iE 'HTTP/|^location:' \
    || die "redirect on port ${BARAT_HTTP_PORT} not working"

if curl -sS --fail "https://${HOST_BARAT}:${BARAT_HTTPS_PORT}/" >/dev/null; then
    info "TLS chain validated without -k"
else
    die "HTTPS validation failed; check that steps/50-ca.sh installed the CA"
fi

echo
if curl -sS "https://${HOST_BARAT}:${BARAT_HTTPS_PORT}/" | grep -q 'Hello World from Barat Site'; then
    info "barat OK"
else
    die "barat page content mismatch"
fi

echo
info "HSTS max-age=${HSTS_MAX_AGE} (kept short so the HTTP->HTTPS redirect stays demonstrable)"
