#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

require_root
require_apt
compute_ports

apt_install apache2

a2enmod headers >/dev/null
a2enmod remoteip >/dev/null

export UTARA_DOCROOT="${WEBROOT_BASE}/utara"

info "apache listening on ${UTARA_PORT} only (port 80 reserved for HAProxy)"
backup_once /etc/apache2/ports.conf
render_template apache/ports.conf /etc/apache2/ports.conf '${UTARA_PORT}'

a2dissite 000-default >/dev/null 2>&1 || true
a2dissite default-ssl >/dev/null 2>&1 || true

a2disconf 99-sevima >/dev/null 2>&1 || true
rm -f /etc/apache2/conf-available/99-sevima.conf
render_template apache/zz-sevima.conf /etc/apache2/conf-available/zz-sevima.conf '${HOST_UTARA}'
a2enconf zz-sevima >/dev/null

install -d -m 0755 "$UTARA_DOCROOT"
render_template www/utara.html "${UTARA_DOCROOT}/index.html" '${HOST_UTARA} ${UTARA_PORT}'
chown -R www-data:www-data "$UTARA_DOCROOT"

render_template apache/utara.conf /etc/apache2/sites-available/utara.conf \
    '${UTARA_PORT} ${HOST_UTARA} ${HOST_WWW} ${UTARA_DOCROOT} ${PESERTA_NAMA}'
a2ensite utara >/dev/null

apache2ctl configtest || die "apache config invalid; nothing restarted"

systemctl daemon-reload
systemctl enable apache2 >/dev/null 2>&1 || true
systemctl restart apache2

open_firewall_port "$UTARA_PORT"

sleep 1
curl -sS -o /dev/null -D - "http://${HOST_UTARA}:${UTARA_PORT}/" 2>/dev/null \
    | grep -iE 'HTTP/|x-owner-by|x-served-by' \
    || die "utara vhost not responding on port ${UTARA_PORT}"

echo
if curl -sS "http://${HOST_UTARA}:${UTARA_PORT}/" | grep -q 'Hello World from Utara Site'; then
    info "utara OK"
else
    die "utara page content mismatch"
fi
