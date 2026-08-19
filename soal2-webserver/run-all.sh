#!/usr/bin/env bash
set -euo pipefail

SEVIMA_ROOT="$(cd "$(dirname "$0")" && pwd)"
. "${SEVIMA_ROOT}/lib/common.sh"

require_root
require_apt
require_identity
compute_ports

STEPS=(
    10-users.sh
    20-ssh.sh
    25-fail2ban.sh
    30-logging.sh
    40-limits.sh
    50-ca.sh
    60-apache-utara.sh
    70-nginx-timur.sh
    75-nginx-barat.sh
    80-haproxy.sh
    85-firewall.sh
)

echo "Peserta        : ${PESERTA_NAMA} (ID ${PESERTA_ID})"
echo "Port utara     : ${UTARA_PORT} (apache2)"
echo "Port timur     : ${TIMUR_PORT} (nginx)"
echo "Port barat     : ${BARAT_HTTPS_PORT} https, ${BARAT_HTTP_PORT} redirect"
echo "Port haproxy   : ${HAPROXY_HTTP_PORT} dan ${HAPROXY_HTTPS_PORT}"
echo "Port ssh       : ${SSH_PORT}"
echo "fail2ban       : ${FAIL2BAN_ENABLE}"
echo "ufw            : ${ENABLE_UFW}"
echo
echo "Langkah 20-ssh.sh akan memindahkan sshd ke port ${SSH_PORT}."
echo "Pastikan kamu punya cara masuk lain (konsol VM) sebelum melanjutkan."
echo
echo "Disarankan: pasang jaring pengaman dulu di terminal lain,"
echo "  systemd-run --on-active=15min --unit=ssh-rollback bash -c '"
echo "    rm -f ${SSH_DROPIN}; rm -rf /etc/systemd/system/ssh.socket.d;"
echo "    systemctl daemon-reload; systemctl restart ssh.socket 2>/dev/null; systemctl restart ssh'"
echo
printf 'Lanjutkan? [y/N] '
read -r answer
case "$answer" in
    y|Y) ;;
    *) echo "aborted"; exit 1 ;;
esac

for step in "${STEPS[@]}"; do
    echo
    echo "########################################################"
    echo "# ${step}"
    echo "########################################################"
    bash "${SEVIMA_ROOT}/steps/${step}" || die "step ${step} failed"
done

echo
echo "########################################################"
echo "# verify.sh"
echo "########################################################"
bash "${SEVIMA_ROOT}/verify.sh"
