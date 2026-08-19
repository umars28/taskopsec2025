#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

require_root
require_apt

FORCE_REISSUE="${FORCE_REISSUE:-no}"

apt_install openssl ca-certificates

info "setting up CA at ${CA_DIR}"
install -d -m 0700 "$CA_DIR"
install -d -m 0755 "${CA_DIR}/certs" "${CA_DIR}/newcerts" "${CA_DIR}/crl"
install -d -m 0700 "${CA_DIR}/private"
[ -f "${CA_DIR}/index.txt" ] || : >"${CA_DIR}/index.txt"
[ -f "${CA_DIR}/serial" ] || echo 1000 >"${CA_DIR}/serial"
[ -f "${CA_DIR}/crlnumber" ] || echo 1000 >"${CA_DIR}/crlnumber"
echo "unique_subject = no" >"${CA_DIR}/index.txt.attr"

CONF="${CA_DIR}/openssl.cnf"
render_template ca/openssl.cnf "$CONF" \
    '${CA_DIR} ${CERT_DAYS} ${CA_COUNTRY} ${CA_ORG} ${CA_CN}'

CACERT="$(ca_cert)"
CAKEY="$(ca_key)"

if [ -f "$CACERT" ] && [ -f "$CAKEY" ]; then
    info "reusing existing root CA"
else
    info "creating root CA key (${CA_KEY_BITS} bit) and certificate"
    (umask 077 && openssl genrsa -out "$CAKEY" "$CA_KEY_BITS" 2>/dev/null)
    chmod 0400 "$CAKEY"

    openssl req -config "$CONF" \
        -key "$CAKEY" \
        -new -x509 -days "$CA_DAYS" -sha256 -extensions v3_ca \
        -subj "/C=${CA_COUNTRY}/O=${CA_ORG}/CN=${CA_CN}" \
        -out "$CACERT"
    chmod 0444 "$CACERT"
fi

issued=0

needs_issue() {
    crt="$1"
    host="$2"
    [ "$FORCE_REISSUE" = "yes" ] && return 0
    [ -f "$crt" ] || return 0
    openssl verify -CAfile "$CACERT" "$crt" >/dev/null 2>&1 || return 0
    openssl x509 -in "$crt" -noout -checkend 2592000 >/dev/null 2>&1 || return 0
    openssl x509 -in "$crt" -noout -ext subjectAltName 2>/dev/null \
        | grep -q "DNS:${host}" || return 0
    return 1
}

issue_cert() {
    host="$1"
    extra_san="$2"
    key="$(srv_key "$host")"
    crt="$(srv_cert "$host")"
    csr="${CA_DIR}/certs/${host}.csr"
    ext="${CA_DIR}/certs/${host}.ext"
    chain="$(srv_fullchain "$host")"

    if ! needs_issue "$crt" "$host"; then
        info "  ${host} still valid, skipped"
        return 0
    fi

    san="DNS:${host}"
    [ -n "$extra_san" ] && san="${san},${extra_san}"

    export CERT_SAN="$san"
    render_template ca/server-ext.cnf "$ext" '${CERT_SAN}'

    if [ ! -f "$key" ]; then
        (umask 077 && openssl genrsa -out "$key" 2048 2>/dev/null)
    fi
    chmod 0640 "$key"

    openssl req -new -key "$key" -out "$csr" -sha256 \
        -subj "/C=${CA_COUNTRY}/O=${CA_ORG}/CN=${host}"

    rm -f "$crt"
    openssl ca -config "$CONF" -batch -notext \
        -extfile "$ext" -extensions ext_server \
        -days "$CERT_DAYS" -md sha256 \
        -in "$csr" -out "$crt" 2>/dev/null \
        || die "failed to issue certificate for ${host}"

    cat "$crt" "$CACERT" >"$chain"
    chmod 0644 "$crt" "$chain"

    openssl verify -CAfile "$CACERT" "$crt" >/dev/null \
        || die "certificate for ${host} failed verification against the CA"

    got_san="$(openssl x509 -in "$crt" -noout -ext subjectAltName 2>/dev/null | tail -1 | tr -d ' ')"
    info "  ${host} issued, SAN=${got_san}"
    issued=$((issued + 1))
}

info "issuing server certificates"
issue_cert "$HOST_WWW" "DNS:${DOMAIN_BASE}"
issue_cert "$HOST_UTARA" ""
issue_cert "$HOST_TIMUR" ""
issue_cert "$HOST_BARAT" ""

install -d -m 0750 "$HAPROXY_CERT_DIR"
for host in "$HOST_WWW" "$HOST_BARAT"; do
    out="$(srv_haproxy_pem "$host")"
    (umask 027 && cat "$(srv_cert "$host")" "$CACERT" "$(srv_key "$host")" >"$out")
    chmod 0640 "$out"
done
if getent group haproxy >/dev/null 2>&1; then
    chgrp -R haproxy "$HAPROXY_CERT_DIR" 2>/dev/null || true
fi

install -m 0644 "$CACERT" "/usr/local/share/ca-certificates/${CA_TRUST_NAME}.crt"
update-ca-certificates >/dev/null
if openssl verify "$(srv_cert "$HOST_BARAT")" >/dev/null 2>&1; then
    info "CA trusted by system (verify without -CAfile succeeds)"
else
    die "CA not trusted; update-ca-certificates did not take effect"
fi

for host in "$HOST_WWW" "$HOST_UTARA" "$HOST_TIMUR" "$HOST_BARAT" "$DOMAIN_BASE"; do
    if ! grep -qE "[[:space:]]${host}(\$|[[:space:]])" /etc/hosts; then
        echo "127.0.0.1    ${host}" >>/etc/hosts
        info "  /etc/hosts: ${host} -> 127.0.0.1"
    fi
done

if [ "$issued" -gt 0 ]; then
    for svc in nginx haproxy; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            info "reloading ${svc} for new certificates"
            systemctl reload "$svc" 2>/dev/null || systemctl restart "$svc"
        fi
    done
fi

EXPORT="/root/${CA_TRUST_NAME}.crt"
install -m 0644 "$CACERT" "$EXPORT"

echo
info "root CA"
openssl x509 -in "$CACERT" -noout -subject -issuer -dates
echo
info "CA database (${CA_DIR}/index.txt)"
awk -F'\t' '{printf "  status=%s kadaluarsa=%s serial=%s subject=%s\n", $1, $2, $4, $6}' "${CA_DIR}/index.txt"
echo "  next serial: $(cat "${CA_DIR}/serial")"
echo
echo "Copy ${EXPORT} to your laptop and trust it there (see docs/trust-ca-client.md)."
