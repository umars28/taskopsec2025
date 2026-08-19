#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

require_root
require_apt
compute_ports

WWW_PEM="$(srv_haproxy_pem "$HOST_WWW")"
export CA_TRUST_FILE="/usr/local/share/ca-certificates/${CA_TRUST_NAME}.crt"
export HAPROXY_CRTLIST="/etc/haproxy/crt-list.txt"

[ -f "$WWW_PEM" ] || die "${WWW_PEM} missing; run steps/50-ca.sh first"
[ -f "$CA_TRUST_FILE" ] || die "CA not in trust store; run steps/50-ca.sh first"

apt_install haproxy socat

chgrp -R haproxy "$HAPROXY_CERT_DIR"
chmod 0750 "$HAPROXY_CERT_DIR"
chmod 0640 "$HAPROXY_CERT_DIR"/*.pem

info "writing cert list (first entry is the default for non-SNI connections)"
tmp_list="$(mktemp)"
{
    echo "$WWW_PEM"
    for pem in "$HAPROXY_CERT_DIR"/*.pem; do
        [ "$pem" = "$WWW_PEM" ] && continue
        echo "$pem"
    done
} >"$tmp_list"
install -m 0644 "$tmp_list" "$HAPROXY_CRTLIST"
rm -f "$tmp_list"

CFG="/etc/haproxy/haproxy.cfg"
backup_once "$CFG"

render_template haproxy/haproxy.cfg "$CFG" \
    '${HAPROXY_CERT_DIR} ${HAPROXY_HTTP_PORT} ${HAPROXY_HTTPS_PORT} ${HAPROXY_CRTLIST} ${HSTS_MAX_AGE} ${HOST_BARAT} ${HOST_WWW} ${DOMAIN_BASE} ${UTARA_PORT} ${TIMUR_PORT} ${BARAT_HTTPS_PORT} ${CA_TRUST_FILE}'

haproxy -c -f "$CFG" || die "haproxy config invalid; nothing restarted"

systemctl daemon-reload
systemctl enable haproxy >/dev/null 2>&1 || true
systemctl restart haproxy

open_firewall_port "$HAPROXY_HTTP_PORT"
open_firewall_port "$HAPROXY_HTTPS_PORT"

sleep 2

curl -sS -o /dev/null -D - "http://${HOST_WWW}/" 2>/dev/null \
    | grep -iE 'HTTP/|^location:' \
    || die "HTTP frontend not responding"

curl -sS --fail "https://${HOST_WWW}/" >/dev/null \
    || die "HTTPS for www failed validation against the trust store"

xff="$(curl -sS -H 'X-Forwarded-For: 203.0.113.99' "https://${HOST_WWW}/" -o /dev/null -w '%{http_code}')"
[ "$xff" = "200" ] || die "request with spoofed XFF was rejected; it should still be served"
if grep -q '203.0.113.99' /var/log/nginx/timur-access.log /var/log/apache2/utara-access.log 2>/dev/null; then
    die "spoofed XFF leaked into backend access logs"
fi
info "client XFF is overwritten by HAProxy"

echo
info "round-robin distribution over 20 requests"
for i in $(seq 1 20); do
    curl -sS -o /dev/null -D - "https://${HOST_WWW}/" 2>/dev/null \
        | awk 'tolower($1)=="x-served-by:"{print $2}' | tr -d '\r'
done | sort | uniq -c

echo
info "backend status"
echo "show stat" | socat stdio /run/haproxy/admin.sock 2>/dev/null \
    | awk -F, 'NR==1||$1=="be_www"||$1=="be_barat"{print $1","$2","$18}' \
    || echo "  (admin socket unreadable)"
