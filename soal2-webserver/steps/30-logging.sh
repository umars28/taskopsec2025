#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

require_root
require_apt

info "installing logging stack"
apt_refresh
apt_install rsyslog auditd audispd-plugins acct logrotate

install -d -m 2755 /var/log/journal
install -d -m 0755 /etc/systemd/journald.conf.d
render_template journald/99-sevima.conf /etc/systemd/journald.conf.d/99-sevima.conf ''
if [ "$TEMPLATE_CHANGED" = "yes" ]; then
    systemd-tmpfiles --create --prefix /var/log/journal >/dev/null 2>&1 || true
    systemctl restart systemd-journald
fi

install -d -m 0750 /etc/audit/rules.d
render_template audit/99-sevima.rules /etc/audit/rules.d/99-sevima.rules '${CA_DIR}' 0640

systemctl enable --now auditd >/dev/null 2>&1 || true

if systemctl is-active --quiet auditd; then
    augenrules --load >/dev/null 2>&1 \
        || die "auditd rejected the rules; run 'augenrules --load' manually to see why"
    loaded="$(auditctl -l 2>/dev/null | wc -l)"
    [ "$loaded" -ge 15 ] \
        || die "only ${loaded} audit rules loaded, expected >= 15"
    info "audit rules loaded: ${loaded}"
else
    warn "auditd inactive (common on container-based VPS). Rules written but not loaded."
fi

install -d -m 0700 /var/log/sudo-io
SUDO_IO="/etc/sudoers.d/99-sevima-logging"
render_template sudoers/99-sevima-logging "$SUDO_IO" '' 0440
visudo -cf "$SUDO_IO" >/dev/null || {
    rm -f "$SUDO_IO"
    die "sudoers logging file invalid, reverted"
}

render_template cron/sevima-sudo-io-purge /etc/cron.daily/sevima-sudo-io-purge \
    '${SUDO_IO_RETENTION_DAYS}' 0755

if [ -f /etc/rsyslog.d/50-default.conf ]; then
    render_template rsyslog/49-sevima.conf /etc/rsyslog.d/49-sevima.conf ''
else
    warn "distro 50-default.conf missing; writing full syslog ruleset"
    render_template rsyslog/49-sevima-lengkap.conf /etc/rsyslog.d/49-sevima.conf ''
fi
rm -f /etc/rsyslog.d/99-sevima.conf
[ "$TEMPLATE_CHANGED" = "yes" ] && systemctl restart rsyslog

systemctl enable --now acct >/dev/null 2>&1 \
    || systemctl enable --now psacct >/dev/null 2>&1 || true

render_template logrotate/99-sevima /etc/logrotate.d/99-sevima ''
lr_out="$(logrotate -d /etc/logrotate.d/99-sevima 2>&1 || true)"
if printf '%s\n' "$lr_out" | grep -q '^error:'; then
    printf '%s\n' "$lr_out" | grep '^error:' >&2
    die "logrotate config invalid"
fi

info "log services"
for unit in systemd-journald rsyslog auditd; do
    printf '  %-20s %s\n' "$unit" "$(systemctl is-active "$unit" 2>/dev/null || echo inactive)"
done
echo "  audit rules active: $(auditctl -l 2>/dev/null | wc -l)"
