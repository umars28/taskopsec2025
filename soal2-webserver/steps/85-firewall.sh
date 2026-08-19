#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

require_root
require_apt
compute_ports

if [ "$ENABLE_UFW" != "yes" ]; then
    info "ENABLE_UFW=${ENABLE_UFW}, firewall not enabled"
    echo "  set ENABLE_UFW=\"yes\" in config.sh to enable"
    echo "  ports it would open: ${SSH_PORT} ${HAPROXY_HTTP_PORT} ${HAPROXY_HTTPS_PORT} ${UTARA_PORT} ${TIMUR_PORT} ${BARAT_HTTPS_PORT} ${BARAT_HTTP_PORT}"
    exit 0
fi

apt_install ufw

PORTS="${SSH_PORT} ${HAPROXY_HTTP_PORT} ${HAPROXY_HTTPS_PORT} ${UTARA_PORT} ${TIMUR_PORT} ${BARAT_HTTPS_PORT} ${BARAT_HTTP_PORT}"

info "allowing ports before enabling"
for p in $PORTS; do
    ufw allow "${p}/tcp" >/dev/null
    echo "  allow ${p}/tcp"
done

ufw --force disable >/dev/null 2>&1 || true
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null

ufw show added | grep -q "${SSH_PORT}/tcp" \
    || die "no rule for port ${SSH_PORT}; aborting to avoid lockout"

ufw --force enable >/dev/null

sleep 1
ss -tln | grep -qE ":${SSH_PORT}\b" \
    || die "sshd no longer LISTENing after enabling firewall; DO NOT close this session"

info "ufw status"
ufw status verbose | sed 's/^/  /'

echo
echo "Verify from a second terminal BEFORE closing this one:"
echo "  ssh -p ${SSH_PORT} ${USER_PREFIX}1@<host>"
echo "Locked out? Use the provider console: ufw disable"
