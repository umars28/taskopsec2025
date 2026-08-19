#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

require_root
require_apt
compute_ports

apt_install nginx

info "nginx listening on ${TIMUR_PORT} only (port 80 reserved for HAProxy)"
rm -f /etc/nginx/sites-enabled/default

write_nginx_common

export TIMUR_DOCROOT="${WEBROOT_BASE}/timur"

install -d -m 0755 "$TIMUR_DOCROOT"
render_template www/timur.html "${TIMUR_DOCROOT}/index.html" '${HOST_TIMUR} ${TIMUR_PORT}'
chown -R www-data:www-data "$TIMUR_DOCROOT"

render_template nginx/timur.conf /etc/nginx/sites-available/timur \
    '${TIMUR_PORT} ${HOST_TIMUR} ${HOST_WWW} ${TIMUR_DOCROOT} ${PESERTA_NAMA} ${TIMUR_SERVED_BY}'
ln -sfn /etc/nginx/sites-available/timur /etc/nginx/sites-enabled/timur

nginx -t || die "nginx config invalid; nothing restarted"

systemctl daemon-reload
systemctl enable nginx >/dev/null 2>&1 || true
systemctl restart nginx

open_firewall_port "$TIMUR_PORT"

sleep 1
curl -sS -o /dev/null -D - "http://${HOST_TIMUR}:${TIMUR_PORT}/" 2>/dev/null \
    | grep -iE 'HTTP/|x-owner-by|x-served-by' \
    || die "timur vhost not responding on port ${TIMUR_PORT}"

echo
if curl -sS "http://${HOST_TIMUR}:${TIMUR_PORT}/" | grep -q 'Hello World from Timur Site'; then
    info "timur OK"
else
    die "timur page content mismatch"
fi
