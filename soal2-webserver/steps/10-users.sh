#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

require_root
require_apt
umask 077

mulai="$(date +%s)"

info "installing packages"
apt_refresh
apt_install sudo openssh-client passwd

command -v newusers >/dev/null 2>&1 \
    || die "newusers not found; passwd package incomplete"

getent group "$USER_SUDO_GROUP" >/dev/null \
    || die "group '$USER_SUDO_GROUP' does not exist; fix USER_SUDO_GROUP in config.sh"

install -d -m 0700 "$USER_KEY_DIR"

BATCH_BARU="$(mktemp)"
BATCH_PW="$(mktemp)"
DAFTAR_KUNCI="$(mktemp)"
MANIFEST="/root/sevima-users.csv"
trap 'rm -f "$BATCH_BARU" "$BATCH_PW" "$DAFTAR_KUNCI"' EXIT

declare -A SUDAH_ADA
while IFS=: read -r u _; do
    case "$u" in
        "${USER_PREFIX}"[0-9]*) SUDAH_ADA["$u"]=1 ;;
    esac
done < <(getent passwd)

baru=0
for i in $(seq 1 "$USER_COUNT"); do
    user="${USER_PREFIX}${i}"
    pass="${USER_PASSWORD_PREFIX}${i}"
    printf '%s:%s\n' "$user" "$pass" >>"$BATCH_PW"
    if [ -z "${SUDAH_ADA[$user]+x}" ]; then
        printf '%s:%s::::/home/%s:/bin/bash\n' "$user" "$pass" "$user" >>"$BATCH_BARU"
        baru=$((baru + 1))
    fi
done

lama=$((USER_COUNT - baru))
info "accounts: ${lama} existing, ${baru} to create"

if [ "$baru" -gt 0 ]; then
    newusers "$BATCH_BARU" \
        || die "newusers failed; check /etc/login.defs and available UID range"
fi

chpasswd <"$BATCH_PW"

current="$(getent group "$USER_SUDO_GROUP" | cut -d: -f4)"
new_members="$(for i in $(seq 1 "$USER_COUNT"); do echo "${USER_PREFIX}${i}"; done)"
combined="$(printf '%s\n%s\n' "$(echo "$current" | tr ',' '\n')" "$new_members" \
    | sed '/^$/d' | sort -u | paste -sd, -)"
gpasswd -M "$combined" "$USER_SUDO_GROUP"

declare -A RUMAH
while IFS=: read -r u _ _ _ _ h _; do
    case "$u" in
        "${USER_PREFIX}"[0-9]*) RUMAH["$u"]="$h" ;;
    esac
done < <(getent passwd)

for i in $(seq 1 "$USER_COUNT"); do
    user="${USER_PREFIX}${i}"
    [ -n "${RUMAH[$user]+x}" ] || die "account ${user} was not created; check newusers output"
    [ -f "${USER_KEY_DIR}/${user}" ] || echo "$user" >>"$DAFTAR_KUNCI"
done

jobs_n="$(nproc 2>/dev/null || echo 2)"
[ "$jobs_n" -gt 8 ] && jobs_n=8

if [ -s "$DAFTAR_KUNCI" ]; then
    perlu="$(wc -l <"$DAFTAR_KUNCI" | tr -d ' ')"
    info "generating ${perlu} ed25519 keypairs (${jobs_n} parallel)"
    xargs -P "$jobs_n" -I{} sh -c \
        'ssh-keygen -t ed25519 -N "" -C "$2" -f "$1/$2" -q' _ "$USER_KEY_DIR" {} \
        <"$DAFTAR_KUNCI"
fi

for i in $(seq 1 "$USER_COUNT"); do
    printf '%s\t%s\n' "${USER_PREFIX}${i}" "${RUMAH[${USER_PREFIX}${i}]}"
done | xargs -P "$jobs_n" -L1 sh -c '
    keydir="$1"; user="$2"; home="$3"
    install -d -m 0700 -o "$user" -g "$user" "$home/.ssh"
    install -m 0600 -o "$user" -g "$user" "$keydir/$user.pub" "$home/.ssh/authorized_keys"
' _ "$USER_KEY_DIR"

install -m 0600 /dev/null "$MANIFEST"
{
    echo "username,password,private_key,public_key"
    for i in $(seq 1 "$USER_COUNT"); do
        user="${USER_PREFIX}${i}"
        printf '%s,%s,%s,%s\n' \
            "$user" "${USER_PASSWORD_PREFIX}${i}" \
            "${USER_KEY_DIR}/${user}" "${USER_KEY_DIR}/${user}.pub"
    done
} >"$MANIFEST"
chmod 0600 "$MANIFEST"
chmod 0700 "$USER_KEY_DIR"

terdaftar="$(getent passwd | cut -d: -f1 | grep -c "^${USER_PREFIX}[0-9]\+$")"
ber_sudo="$(getent group "$USER_SUDO_GROUP" | cut -d: -f4 | tr ',' '\n' | grep -c "^${USER_PREFIX}[0-9]\+$")"
[ "$terdaftar" -eq "$USER_COUNT" ] \
    || die "only ${terdaftar} of ${USER_COUNT} accounts registered"
[ "$ber_sudo" -eq "$USER_COUNT" ] \
    || die "only ${ber_sudo} of ${USER_COUNT} accounts in group ${USER_SUDO_GROUP}"

durasi=$(( $(date +%s) - mulai ))
info "done in ${durasi}s: ${terdaftar} accounts, ${ber_sudo} in ${USER_SUDO_GROUP}"
info "credentials: ${MANIFEST} (0600), keys: ${USER_KEY_DIR}/ (0700)"
