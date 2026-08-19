#!/usr/bin/env bash
set -euo pipefail

SEVIMA_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${SEVIMA_ROOT}/lib/common.sh"

require_root
compute_ports

OUT="/root/konfigurasi-soal2.txt"

emit() {
    section="$1"
    path="$2"
    [ -f "$path" ] || return 0
    printf '##### SECTION: %s | FILE: %s\n' "$section" "$path"
    cat "$path"
    printf '##### END\n\n'
}

{
    emit A.2 /etc/ssh/sshd_config.d/01-sevima.conf
    emit A.2 /etc/fail2ban/jail.d/99-sevima.local

    emit A.3 /etc/audit/rules.d/99-sevima.rules
    emit A.3 /etc/rsyslog.d/49-sevima.conf
    emit A.3 /etc/sudoers.d/99-sevima-logging
    emit A.3 /etc/systemd/journald.conf.d/99-sevima.conf

    emit A.4 /etc/security/limits.d/99-sevima.conf
    emit A.4 /etc/systemd/system/nginx.service.d/99-sevima-limits.conf
    emit A.4 /etc/sysctl.d/99-sevima.conf

    emit B "${CA_DIR}/openssl.cnf"

    emit C.1 /etc/apache2/ports.conf
    emit C.1 /etc/apache2/conf-available/zz-sevima.conf
    emit C.1 /etc/apache2/sites-available/utara.conf

    emit C.2 /etc/nginx/conf.d/00-sevima-common.conf
    emit C.2 /etc/nginx/sites-available/timur

    emit C.3 /etc/nginx/sites-available/barat

    emit D /etc/haproxy/crt-list.txt
    emit D /etc/haproxy/haproxy.cfg
} >"$OUT"

jml="$(grep -c '^##### SECTION:' "$OUT")"
[ "$jml" -ge 15 ] || die "only ${jml} config files collected; run the deploy steps first"

info "collected ${jml} config files -> ${OUT}"
grep '^##### SECTION:' "$OUT" | sed 's/^##### SECTION: /  /'
echo
echo "Copy both files to your laptop:"
echo "  scp -P ${SSH_PORT} root@<IP>:/root/konfigurasi-soal2.txt laporan/bukti/"
echo "  scp -P ${SSH_PORT} root@<IP>:/root/bukti-verifikasi-soal2.txt laporan/bukti/"
