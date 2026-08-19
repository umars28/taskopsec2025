#!/usr/bin/env bash

SEVIMA_ROOT="${SEVIMA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TEMPLATE_DIR="${SEVIMA_ROOT}/templates"

set -a
. "${SEVIMA_ROOT}/config.sh"
set +a

die() {
    echo "ERROR: $*" >&2
    exit 1
}

info() {
    echo "==> $*"
}

warn() {
    echo "WARN: $*" >&2
}

require_root() {
    [ "$(id -u)" -eq 0 ] || die "run as root (sudo -i)"
}

require_apt() {
    command -v apt-get >/dev/null 2>&1 \
        || die "Debian/Ubuntu required (apt-get not found)"
}

require_identity() {
    [ -n "$PESERTA_ID" ] \
        || die "PESERTA_ID is empty in config.sh"
    case "$PESERTA_ID" in
        ''|*[!0-9]*) die "PESERTA_ID must be numeric, got '$PESERTA_ID'" ;;
    esac
    [ -n "$PESERTA_NAMA" ] \
        || die "PESERTA_NAMA is empty in config.sh"
}

compute_ports() {
    require_identity
    case "$PORT_MODE" in
        gabung)
            UTARA_PORT="80${PESERTA_ID}"
            TIMUR_PORT="81${PESERTA_ID}"
            ;;
        jumlah)
            UTARA_PORT=$((80 + PESERTA_ID))
            TIMUR_PORT=$((81 + PESERTA_ID))
            ;;
        *)
            die "PORT_MODE must be 'gabung' or 'jumlah', got '${PORT_MODE}'"
            ;;
    esac
    if [ "$UTARA_PORT" -gt 65535 ] || [ "$TIMUR_PORT" -gt 65535 ]; then
        die "computed port exceeds 65535 (PORT_MODE=${PORT_MODE}, PESERTA_ID=${PESERTA_ID})"
    fi
    if [ "$UTARA_PORT" -lt 1 ] || [ "$TIMUR_PORT" -lt 1 ]; then
        die "computed port invalid (PORT_MODE=${PORT_MODE}, PESERTA_ID=${PESERTA_ID})"
    fi
    export UTARA_PORT TIMUR_PORT
    for p in "$UTARA_PORT" "$TIMUR_PORT" "$BARAT_HTTPS_PORT" "$BARAT_HTTP_PORT" \
             "$HAPROXY_HTTP_PORT" "$HAPROXY_HTTPS_PORT" "$SSH_PORT"; do
        n=$(printf '%s\n' "$UTARA_PORT" "$TIMUR_PORT" "$BARAT_HTTPS_PORT" \
            "$BARAT_HTTP_PORT" "$HAPROXY_HTTP_PORT" "$HAPROXY_HTTPS_PORT" \
            "$SSH_PORT" | grep -c "^${p}$")
        [ "$n" -eq 1 ] || die "port $p collides between services; fix config.sh"
    done
}

apt_install() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" >/dev/null
}

apt_refresh() {
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
}

backup_once() {
    [ -e "$1" ] || return 0
    [ -e "${1}.orig" ] || cp -a "$1" "${1}.orig"
}

ca_cert() {
    echo "${CA_DIR}/cacert.pem"
}

ca_key() {
    echo "${CA_DIR}/cacert.key"
}

srv_key() {
    echo "${CA_DIR}/certs/$1.key"
}

srv_cert() {
    echo "${CA_DIR}/certs/$1.crt"
}

srv_fullchain() {
    echo "${CA_DIR}/certs/$1.fullchain.pem"
}

srv_haproxy_pem() {
    echo "${HAPROXY_CERT_DIR}/$1.pem"
}

require_envsubst() {
    command -v envsubst >/dev/null 2>&1 && return 0
    info "installing gettext-base for envsubst"
    apt_install gettext-base
    command -v envsubst >/dev/null 2>&1 \
        || die "envsubst still missing after installing gettext-base"
}

render_template() {
    tpl="${TEMPLATE_DIR}/$1"
    out="$2"
    vars="$3"
    mode="${4:-0644}"

    [ -f "$tpl" ] || die "template not found: ${tpl}"
    require_envsubst

    tmp="$(mktemp)"
    envsubst "$vars" <"$tpl" >"$tmp"

    leftover="$( { grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$tmp" \
        | grep -vxF '${APACHE_LOG_DIR}' | sort -u | tr '\n' ' '; } || true )"
    if [ -n "$leftover" ]; then
        rm -f "$tmp"
        die "unsubstituted placeholders in ${1}: ${leftover}"
    fi

    if [ -f "$out" ] && cmp -s "$tmp" "$out"; then
        TEMPLATE_CHANGED=no
    else
        install -m "$mode" "$tmp" "$out"
        TEMPLATE_CHANGED=yes
        echo "    wrote ${out}"
    fi
    rm -f "$tmp"
}

write_nginx_common() {
    install -d -m 0755 /etc/nginx/conf.d
    rm -f /etc/nginx/conf.d/99-sevima.conf
    render_template nginx/00-sevima-common.conf /etc/nginx/conf.d/00-sevima-common.conf ''
}

open_firewall_port() {
    command -v ufw >/dev/null 2>&1 || return 0
    ufw allow "$1/tcp" >/dev/null 2>&1 || true
}
