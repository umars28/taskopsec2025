#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

require_root
require_apt

apt_install openssh-server

MAIN="/etc/ssh/sshd_config"
DROPIN_DIR="/etc/ssh/sshd_config.d"

install -d -m 0755 "$DROPIN_DIR"

if ! grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "$MAIN"; then
    info "adding Include ${DROPIN_DIR} to sshd_config"
    backup_once "$MAIN"
    sed -i "1i Include ${DROPIN_DIR}/*.conf" "$MAIN"
fi

rm -f "${DROPIN_DIR}/99-sevima.conf"

conflict="$(find "$DROPIN_DIR" -maxdepth 1 -name '*.conf' -print 2>/dev/null | sort \
    | awk -v mine="$(basename "$SSH_DROPIN")" '{ n=$0; sub(/.*\//,"",n); if (n != mine && n < mine) print $0 }')"
if [ -n "$conflict" ]; then
    warn "these drop-ins are read BEFORE ${SSH_DROPIN} and win on shared directives:"
    echo "$conflict" >&2
fi

render_template sshd/01-sevima.conf "$SSH_DROPIN" '${SSH_PORT}'

BOTH="${DROPIN_DIR}/02-sevima-2fa.conf"
if [ "$SSH_REQUIRE_BOTH_FACTORS" = "yes" ]; then
    render_template sshd/auth-both-factors.conf "$BOTH" ''
else
    rm -f "$BOTH"
fi

sshd -t || die "sshd_config invalid; nothing restarted"

info "effective sshd values"
eff_port="$(sshd -T 2>/dev/null | awk '/^port /{print $2}' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
eff_pw="$(sshd -T 2>/dev/null | awk '/^passwordauthentication /{print $2}')"
eff_pk="$(sshd -T 2>/dev/null | awk '/^pubkeyauthentication /{print $2}')"
echo "  port                   : ${eff_port}"
echo "  passwordauthentication : ${eff_pw}"
echo "  pubkeyauthentication   : ${eff_pk}"

[ "$eff_port" = "$SSH_PORT" ] \
    || die "effective port is '${eff_port}', not ${SSH_PORT}; another drop-in wins"
[ "$eff_pw" = "yes" ] \
    || die "effective PasswordAuthentication is '${eff_pw}'; another drop-in (usually cloud-init) wins"
[ "$eff_pk" = "yes" ] \
    || die "effective PubkeyAuthentication is '${eff_pk}'; another drop-in wins"

if systemctl list-unit-files 2>/dev/null | grep -q '^ssh\.socket' \
    && systemctl is-enabled ssh.socket >/dev/null 2>&1; then
    info "ssh.socket active: overriding ListenStream"
    install -d -m 0755 /etc/systemd/system/ssh.socket.d
    render_template sshd/ssh-socket-override.conf \
        /etc/systemd/system/ssh.socket.d/override.conf '${SSH_PORT}'
    systemctl daemon-reload
    systemctl restart ssh.socket
fi

open_firewall_port "$SSH_PORT"

if command -v semanage >/dev/null 2>&1; then
    semanage port -a -t ssh_port_t -p tcp "$SSH_PORT" 2>/dev/null \
        || semanage port -m -t ssh_port_t -p tcp "$SSH_PORT" 2>/dev/null \
        || true
fi

systemctl restart ssh 2>/dev/null || systemctl restart sshd

sleep 2
info "listening sockets"
ss -tln 2>/dev/null | awk -v p=":${SSH_PORT}\$" '$4 ~ p {print "  " $4}'

if ! ss -tln 2>/dev/null | awk -v p=":${SSH_PORT}\$" '$4 ~ p' | grep -q .; then
    echo "WARN: port ${SSH_PORT} is not LISTENing. DO NOT close this session." >&2
    echo "Check: journalctl -u ssh -n 50 --no-pager" >&2
    exit 1
fi

if timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/${SSH_PORT}" 2>/dev/null; then
    info "IPv4 connect to port ${SSH_PORT} succeeded"
else
    echo "WARN: port ${SSH_PORT} LISTENs but REFUSES IPv4." >&2
    echo "Socket is likely IPv6-only ([::]:${SSH_PORT}); clients get Connection refused." >&2
    echo "DO NOT close this session. Check: ss -tln | grep ${SSH_PORT}" >&2
    exit 1
fi

echo
echo "KEEP THIS SESSION OPEN. Verify from a second terminal first:"
echo "  ssh -p ${SSH_PORT} ${USER_PREFIX}1@<host>"
echo "  ssh -p ${SSH_PORT} -i ${USER_KEY_DIR}/${USER_PREFIX}1 ${USER_PREFIX}1@<host>"
