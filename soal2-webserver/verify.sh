#!/usr/bin/env bash
set -uo pipefail

SEVIMA_ROOT="$(cd "$(dirname "$0")" && pwd)"
. "${SEVIMA_ROOT}/lib/common.sh"

require_root
compute_ports

OUT="/root/bukti-verifikasi-soal2.txt"
exec > >(tee "$OUT") 2>&1

pass=0
fail=0

check() {
    label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        printf '  [ PASS ] %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '  [ FAIL ] %s\n' "$label"
        fail=$((fail + 1))
    fi
}

section() {
    echo
    echo "================================================================"
    echo " $1"
    echo "================================================================"
}

echo "Soal 2 verification evidence - Make Your Web Great Again"
echo "Participant : ${PESERTA_NAMA} (ID ${PESERTA_ID})"
echo "Host        : $(hostname -f 2>/dev/null || hostname)"
echo "System      : $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
echo "Kernel      : $(uname -r)"
echo "Time        : $(date -Is)"

section "A.1  Sudo accounts with password and pubkey"
total_user="$(getent passwd | cut -d: -f1 | grep -c "^${USER_PREFIX}[0-9]\+$")"
total_sudo="$(getent group "$USER_SUDO_GROUP" | cut -d: -f4 | tr ',' '\n' | grep -c "^${USER_PREFIX}[0-9]\+$")"
with_key=0
for u in "${USER_PREFIX}1" "${USER_PREFIX}$((USER_COUNT / 2))" "${USER_PREFIX}${USER_COUNT}"; do
    h="$(getent passwd "$u" 2>/dev/null | cut -d: -f6)"
    [ -n "$h" ] && [ -s "${h}/.ssh/authorized_keys" ] && with_key=$((with_key + 1))
done
echo "  ${USER_PREFIX}N accounts registered : ${total_user} / ${USER_COUNT}"
echo "  members of group ${USER_SUDO_GROUP}        : ${total_sudo} / ${USER_COUNT}"
echo "  authorized_keys sampled            : ${with_key} / 3"
check "account count matches" test "$total_user" -eq "$USER_COUNT"
check "all accounts have sudo" test "$total_sudo" -eq "$USER_COUNT"
check "password hashed in shadow" bash -c "getent shadow ${USER_PREFIX}1 | cut -d: -f2 | grep -q '^\\\$'"
check "credential manifest is 0600" bash -c "[ \"\$(stat -c %a /root/sevima-users.csv)\" = 600 ]"
check "private key dir is 0700" bash -c "[ \"\$(stat -c %a ${USER_KEY_DIR})\" = 700 ]"
echo
echo "  sample entry:"
getent passwd "${USER_PREFIX}1" | sed 's/^/    /'
sudo -lU "${USER_PREFIX}1" 2>/dev/null | tail -2 | sed 's/^/    /'

section "A.2  SSH on port ${SSH_PORT}"
eff_port="$(sshd -T 2>/dev/null | awk '/^port /{print $2}' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
eff_pw="$(sshd -T 2>/dev/null | awk '/^passwordauthentication /{print $2}')"
eff_pk="$(sshd -T 2>/dev/null | awk '/^pubkeyauthentication /{print $2}')"
echo "  sshd -T port           : ${eff_port}"
echo "  PasswordAuthentication : ${eff_pw}"
echo "  PubkeyAuthentication   : ${eff_pk}"
echo "  drop-in in use         : ${SSH_DROPIN}"
ls -1 /etc/ssh/sshd_config.d/ 2>/dev/null | sed 's/^/    /'
ss -tlnp 2>/dev/null | grep -E ":${SSH_PORT}\b" | sed 's/^/    /'
check "sshd LISTENing on ${SSH_PORT}" bash -c "ss -tln | grep -qE ':${SSH_PORT}\b'"
check "port 22 no longer in use" bash -c "! ss -tln | grep -qE ':22\b'"
check "effective port = ${SSH_PORT}" test "$eff_port" = "$SSH_PORT"
check "password login enabled" test "$eff_pw" = "yes"
check "pubkey login enabled" test "$eff_pk" = "yes"

section "A.2b  fail2ban"
if [ "$FAIL2BAN_ENABLE" = "yes" ]; then
    fail2ban-client status sshd 2>/dev/null | sed 's/^/    /'
    check "fail2ban active" systemctl is-active --quiet fail2ban
    check "sshd jail running" bash -c "fail2ban-client status sshd >/dev/null 2>&1"
    check "sshd jail watches port ${SSH_PORT}" bash -c "grep -q 'port = ${SSH_PORT}' /etc/fail2ban/jail.d/99-sevima.local"
else
    echo "  FAIL2BAN_ENABLE=no, skipped"
fi

section "A.3  Activity logging"
for unit in systemd-journald rsyslog auditd; do
    printf '  %-20s : %s\n' "$unit" "$(systemctl is-active "$unit" 2>/dev/null)"
done
echo "  audit rules active    : $(auditctl -l 2>/dev/null | wc -l)"
echo "  persistent journal    : $([ -d /var/log/journal ] && echo yes || echo no)"
echo "  sudo I/O recording    : $([ -d /var/log/sudo-io ] && echo yes || echo no)"
echo "  sudo-io purge         : $([ -x /etc/cron.daily/sevima-sudo-io-purge ] && echo "yes, ${SUDO_IO_RETENTION_DAYS}d" || echo no)"
check "auditd active" systemctl is-active --quiet auditd
check "rsyslog active" systemctl is-active --quiet rsyslog
check "audit rules loaded" bash -c "[ \$(auditctl -l 2>/dev/null | wc -l) -ge 15 ]"
check "persistent journal" test -d /var/log/journal
check "audit does not watch its own log" bash -c "! auditctl -l 2>/dev/null | grep -qE '^-w /var/log/?(/audit/?)? '"

section "A.4  Resource limits (ulimit)"
echo "  limits.d              : /etc/security/limits.d/99-sevima.conf"
grep -E 'nofile|nproc' /etc/security/limits.d/99-sevima.conf 2>/dev/null | sed 's/^/    /'
echo "  fs.file-max           : $(sysctl -n fs.file-max 2>/dev/null)"
echo "  net.core.somaxconn    : $(sysctl -n net.core.somaxconn 2>/dev/null)"
echo "  tcp_syncookies        : $(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null)"
for svc in nginx apache2 haproxy; do
    printf '  LimitNOFILE %-9s : %s\n' "$svc" "$(systemctl show -p LimitNOFILE --value "$svc" 2>/dev/null)"
done
check "limits.conf installed" test -f /etc/security/limits.d/99-sevima.conf
check "fs.file-max raised" bash -c "[ \$(sysctl -n fs.file-max) -ge 1000000 ]"
check "syncookies enabled" bash -c "[ \$(sysctl -n net.ipv4.tcp_syncookies) -eq 1 ]"
check "nginx LimitNOFILE raised" bash -c "[ \$(systemctl show -p LimitNOFILE --value nginx) -ge 65536 ]"

section "B  Certificate Authority"
echo "  root CA subject:"
openssl x509 -in "$(ca_cert)" -noout -subject 2>/dev/null | sed 's/^/    /'
openssl x509 -in "$(ca_cert)" -noout -dates 2>/dev/null | sed 's/^/    /'
echo "  basicConstraints:"
openssl x509 -in "$(ca_cert)" -noout -text 2>/dev/null | grep -A1 'Basic Constraints' | sed 's/^/    /'
echo
echo "  issued certificates:"
for host in "$HOST_WWW" "$HOST_UTARA" "$HOST_TIMUR" "$HOST_BARAT"; do
    crt="$(srv_cert "$host")"
    if [ -f "$crt" ]; then
        san="$(openssl x509 -in "$crt" -noout -ext subjectAltName 2>/dev/null | tail -1 | tr -d ' ')"
        ok="$(openssl verify -CAfile "$(ca_cert)" "$crt" 2>&1 | grep -c ': OK$')"
        printf '    %-22s SAN=%-45s verify=%s\n' "$host" "$san" "$([ "$ok" -eq 1 ] && echo OK || echo FAIL)"
    else
        printf '    %-22s MISSING\n' "$host"
    fi
done
echo
echo "  CA database (index.txt):"
if [ -s "${CA_DIR}/index.txt" ]; then
    awk -F'\t' '{printf "    status=%s serial=%s subject=%s\n", $1, $4, $6}' "${CA_DIR}/index.txt"
else
    echo "    (empty)"
fi
check "CA database records 4 issuances" bash -c "[ \$(wc -l <'${CA_DIR}/index.txt') -ge 4 ]"
check "cacert.pem exists" test -f "$(ca_cert)"
check "cacert.key exists" test -f "$(ca_key)"
check "CA key not world-readable" bash -c "[ \"\$(stat -c %a '$(ca_key)')\" = 400 ]"
check "root CA CN = ${CA_CN}" bash -c "openssl x509 -in '$(ca_cert)' -noout -subject | grep -q 'CN *= *${CA_CN}'"
check "Country = ${CA_COUNTRY}" bash -c "openssl x509 -in '$(ca_cert)' -noout -subject | grep -q 'C *= *${CA_COUNTRY}'"
check "Organization matches" bash -c "openssl x509 -in '$(ca_cert)' -noout -subject | grep -q 'Sentra Vidya Utama'"
check "CA trusted by system" bash -c "openssl verify '$(srv_cert "$HOST_BARAT")' | grep -q ': OK$'"

section "C.1  utara.sevima.site - apache2 port ${UTARA_PORT}"
curl -sS -o /dev/null -D - "http://${HOST_UTARA}:${UTARA_PORT}/" 2>/dev/null \
    | grep -iE 'HTTP/|x-owner-by|x-served-by|x-content-type|x-frame|server:' | sed 's/^/    /'
curl -sS "http://${HOST_UTARA}:${UTARA_PORT}/" 2>/dev/null | grep -o 'Hello World from Utara Site' | sed 's/^/    body: /'
check "utara responds 200" bash -c "curl -sS -o /dev/null -w '%{http_code}' 'http://${HOST_UTARA}:${UTARA_PORT}/' | grep -q 200"
check "utara X-Served-By apache2" bash -c "curl -sSI 'http://${HOST_UTARA}:${UTARA_PORT}/' | grep -qi 'x-served-by: *apache2'"
check "utara X-Owner-By set" bash -c "curl -sSI 'http://${HOST_UTARA}:${UTARA_PORT}/' | grep -qi 'x-owner-by: *${PESERTA_NAMA}'"
check "utara page content correct" bash -c "curl -sS 'http://${HOST_UTARA}:${UTARA_PORT}/' | grep -q 'Hello World from Utara Site'"
check "utara nosniff present" bash -c "curl -sSI 'http://${HOST_UTARA}:${UTARA_PORT}/' | grep -qi 'x-content-type-options: *nosniff'"
check "utara does not leak version" bash -c "! curl -sSI 'http://${HOST_UTARA}:${UTARA_PORT}/' | grep -qiE 'server:.*apache/[0-9]'"

section "C.2  timur.sevima.site - nginx port ${TIMUR_PORT}"
curl -sS -o /dev/null -D - "http://${HOST_TIMUR}:${TIMUR_PORT}/" 2>/dev/null \
    | grep -iE 'HTTP/|x-owner-by|x-served-by|x-content-type|x-frame|server:' | sed 's/^/    /'
curl -sS "http://${HOST_TIMUR}:${TIMUR_PORT}/" 2>/dev/null | grep -o 'Hello World from Timur Site' | sed 's/^/    body: /'
check "timur responds 200" bash -c "curl -sS -o /dev/null -w '%{http_code}' 'http://${HOST_TIMUR}:${TIMUR_PORT}/' | grep -q 200"
check "timur X-Served-By = ${TIMUR_SERVED_BY}" bash -c "curl -sSI 'http://${HOST_TIMUR}:${TIMUR_PORT}/' | grep -qi 'x-served-by: *${TIMUR_SERVED_BY}'"
check "timur X-Owner-By set" bash -c "curl -sSI 'http://${HOST_TIMUR}:${TIMUR_PORT}/' | grep -qi 'x-owner-by: *${PESERTA_NAMA}'"
check "timur page content correct" bash -c "curl -sS 'http://${HOST_TIMUR}:${TIMUR_PORT}/' | grep -q 'Hello World from Timur Site'"
check "timur nosniff present" bash -c "curl -sSI 'http://${HOST_TIMUR}:${TIMUR_PORT}/' | grep -qi 'x-content-type-options: *nosniff'"
check "timur does not leak version" bash -c "! curl -sSI 'http://${HOST_TIMUR}:${TIMUR_PORT}/' | grep -qiE 'server:.*nginx/[0-9]'"

section "C.3  barat.sevima.site - nginx HTTPS port ${BARAT_HTTPS_PORT}"
echo "  redirect from HTTP:"
curl -sS -o /dev/null -D - "http://${HOST_BARAT}:${BARAT_HTTP_PORT}/" 2>/dev/null \
    | grep -iE 'HTTP/|^location:' | sed 's/^/    /'
echo "  HTTPS without -k:"
curl -sS -o /dev/null -D - "https://${HOST_BARAT}:${BARAT_HTTPS_PORT}/" 2>/dev/null \
    | grep -iE 'HTTP/|x-served-by|strict-transport' | sed 's/^/    /'
echo "  negotiated protocol and cipher:"
echo | openssl s_client -connect "127.0.0.1:${BARAT_HTTPS_PORT}" -servername "$HOST_BARAT" 2>/dev/null \
    | grep -E 'Protocol|Cipher' | sed 's/^/    /'
echo "  certificate issuer presented:"
echo | openssl s_client -connect "127.0.0.1:${BARAT_HTTPS_PORT}" -servername "$HOST_BARAT" 2>/dev/null \
    | openssl x509 -noout -issuer -subject 2>/dev/null | sed 's/^/    /'
check "barat redirect 301" bash -c "curl -sS -o /dev/null -w '%{http_code}' 'http://${HOST_BARAT}:${BARAT_HTTP_PORT}/' | grep -q 301"
check "barat HTTPS valid without -k" bash -c "curl -sS --fail -o /dev/null 'https://${HOST_BARAT}:${BARAT_HTTPS_PORT}/'"
check "barat page content correct" bash -c "curl -sS 'https://${HOST_BARAT}:${BARAT_HTTPS_PORT}/' | grep -q 'Hello World from Barat Site'"
check "barat rejects TLS 1.1" bash -c "! echo | openssl s_client -connect 127.0.0.1:${BARAT_HTTPS_PORT} -servername ${HOST_BARAT} -tls1_1 2>/dev/null | grep -q 'BEGIN CERTIFICATE'"

section "D  HAProxy - load balancer www.sevima.site"
echo "  HTTP redirect:"
curl -sS -o /dev/null -D - "http://${HOST_WWW}/" 2>/dev/null \
    | grep -iE 'HTTP/|^location:' | sed 's/^/    /'
echo "  security headers at frontend:"
curl -sSI "https://${HOST_WWW}/" 2>/dev/null \
    | grep -iE 'strict-transport|x-content-type|x-frame|referrer-policy' | sed 's/^/    /'
echo "  default cert without SNI:"
echo | openssl s_client -connect "127.0.0.1:${HAPROXY_HTTPS_PORT}" 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null | sed 's/^/    /'
echo "  frontend certificate issuer:"
echo | openssl s_client -connect "127.0.0.1:${HAPROXY_HTTPS_PORT}" -servername "$HOST_WWW" 2>/dev/null \
    | openssl x509 -noout -issuer -subject 2>/dev/null | sed 's/^/    /'
echo
echo "  distribution over 20 requests to https://${HOST_WWW}/ :"
for i in $(seq 1 20); do
    curl -sS -o /dev/null -D - "https://${HOST_WWW}/" 2>/dev/null \
        | awk 'tolower($1)=="x-served-by:"{print $2}' | tr -d '\r'
done | sort | uniq -c | sed 's/^/    /'
distinct="$(for i in $(seq 1 20); do
    curl -sS -o /dev/null -D - "https://${HOST_WWW}/" 2>/dev/null \
        | awk 'tolower($1)=="x-served-by:"{print $2}' | tr -d '\r'
done | sort -u | wc -l)"
check "HAProxy active" systemctl is-active --quiet haproxy
check "www HTTPS valid without -k" bash -c "curl -sS --fail -o /dev/null 'https://${HOST_WWW}/'"
check "www HTTP redirects to HTTPS" bash -c "curl -sSI 'http://${HOST_WWW}/' | grep -qi '^location: *https://'"
check "round-robin uses two backends" test "$distinct" -ge 2
check "www cert issued by SEVIMA CA" bash -c "echo | openssl s_client -connect 127.0.0.1:${HAPROXY_HTTPS_PORT} -servername ${HOST_WWW} 2>/dev/null | openssl x509 -noout -issuer | grep -q '${CA_CN}'"
check "default cert without SNI = ${HOST_WWW}" bash -c "echo | openssl s_client -connect 127.0.0.1:${HAPROXY_HTTPS_PORT} 2>/dev/null | openssl x509 -noout -subject | grep -q '${HOST_WWW}'"
check "TRACE method rejected" bash -c "[ \"\$(curl -sS -o /dev/null -w '%{http_code}' -X TRACE 'https://${HOST_WWW}/')\" = 403 ]"
check "client X-Forwarded-For overwritten" bash -c "curl -sS -H 'X-Forwarded-For: 203.0.113.99' -o /dev/null 'https://${HOST_WWW}/'; ! grep -q 203.0.113.99 /var/log/nginx/timur-access.log /var/log/apache2/utara-access.log 2>/dev/null"

section "Port map"
ss -tlnp 2>/dev/null | awk 'NR==1 || /sshd|apache2|nginx|haproxy/' | sed 's/^/  /'

section "Summary"
echo "  Passed : ${pass}"
echo "  Failed : ${fail}"
echo
echo "  Evidence written to ${OUT}"
[ "$fail" -eq 0 ] || echo "  Some checks failed; see the [ FAIL ] lines above."
exit 0
