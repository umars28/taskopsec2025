#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

require_root

export NOFILE_SOFT=65536
export NOFILE_HARD=131072
export NPROC_SOFT=8192
export NPROC_HARD=16384

LIMIT_VARS='${NOFILE_SOFT} ${NOFILE_HARD} ${NPROC_SOFT} ${NPROC_HARD}'

install -d -m 0755 /etc/security/limits.d
render_template limits/99-sevima.conf /etc/security/limits.d/99-sevima.conf "$LIMIT_VARS"

for f in /etc/pam.d/sshd /etc/pam.d/login /etc/pam.d/su; do
    [ -f "$f" ] || continue
    if ! grep -q 'pam_limits\.so' "$f"; then
        echo "session required pam_limits.so" >>"$f"
        info "added pam_limits.so to $f"
    fi
done

install -d -m 0755 /etc/systemd/system.conf.d
render_template systemd/system.conf /etc/systemd/system.conf.d/99-sevima.conf "$LIMIT_VARS"

for svc in nginx apache2 haproxy; do
    install -d -m 0755 "/etc/systemd/system/${svc}.service.d"
    render_template systemd/service-override.conf \
        "/etc/systemd/system/${svc}.service.d/99-sevima-limits.conf" "$LIMIT_VARS"
done

render_template sysctl/99-sevima.conf /etc/sysctl.d/99-sevima.conf ''
sysctl --system >/dev/null

systemctl daemon-reload

info "effective values"
echo "  fs.file-max          : $(sysctl -n fs.file-max)"
echo "  net.core.somaxconn   : $(sysctl -n net.core.somaxconn)"
echo "  tcp_syncookies       : $(sysctl -n net.ipv4.tcp_syncookies)"
echo "  nofile (this shell)  : $(ulimit -n)"
echo
echo "Service limits: systemctl show -p LimitNOFILE nginx apache2 haproxy"
