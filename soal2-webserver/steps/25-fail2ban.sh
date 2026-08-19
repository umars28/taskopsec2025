#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

require_root
require_apt

if [ "$FAIL2BAN_ENABLE" != "yes" ]; then
    info "FAIL2BAN_ENABLE=${FAIL2BAN_ENABLE}, skipped"
    exit 0
fi

info "installing fail2ban"
apt_install fail2ban python3-systemd

JAIL="/etc/fail2ban/jail.d/99-sevima.local"
install -d -m 0755 /etc/fail2ban/jail.d

FAIL2BAN_IGNORE="127.0.0.1/8 ::1"
[ -n "$FAIL2BAN_IGNOREIP" ] && FAIL2BAN_IGNORE="${FAIL2BAN_IGNORE} ${FAIL2BAN_IGNOREIP}"
export FAIL2BAN_IGNORE FAIL2BAN_BACKEND

JAIL_VARS='${FAIL2BAN_IGNORE} ${FAIL2BAN_BANTIME} ${FAIL2BAN_FINDTIME} ${FAIL2BAN_MAXRETRY} ${SSH_PORT} ${FAIL2BAN_BACKEND}'

start_fail2ban() {
    fail2ban-client -t >/dev/null 2>&1 || return 1
    systemctl enable fail2ban >/dev/null 2>&1 || true
    systemctl restart fail2ban || return 1
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if fail2ban-client status sshd >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

FAIL2BAN_BACKEND=systemd
render_template fail2ban/99-sevima.local "$JAIL" "$JAIL_VARS"

if ! start_fail2ban; then
    warn "systemd backend failed, falling back to auto"
    FAIL2BAN_BACKEND=auto
    render_template fail2ban/99-sevima.local "$JAIL" "$JAIL_VARS"
    start_fail2ban || die "fail2ban will not start; check: journalctl -u fail2ban -n 50 --no-pager"
fi

fail2ban-client status sshd | sed 's/^/  /'

fail2ban-client set sshd banip 198.51.100.7 >/dev/null
fail2ban-client status sshd | grep -i 'banned IP' | sed 's/^/  /'
fail2ban-client set sshd unbanip 198.51.100.7 >/dev/null
info "ban/unban verified"
