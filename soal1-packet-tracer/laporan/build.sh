#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"

PESERTA_NAMA="${PESERTA_NAMA:-Umar Sabirin}"
PESERTA_ID="${PESERTA_ID:-99}"

CONF_DIR="${ROOT}/sevima-datacenter"
TOPOLOGI="${ROOT}/topologi-sevima-datacenter.png"
GAMBAR_DIR="${HERE}/tangkapan-layar"
CACHE_DIR="${HERE}/.cache-gambar"
TEMPLATE="${HERE}/template.html"
OUT_HTML="${HERE}/webgreat_soal1.html"

[ -f "$TEMPLATE" ] || { echo "ERROR: template hilang" >&2; exit 1; }
[ -d "$CONF_DIR" ] || { echo "ERROR: ${CONF_DIR} tidak ada" >&2; exit 1; }

lolos_html() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

b64() {
    if base64 --help 2>&1 | grep -q -- '-w'; then
        base64 -w0 "$1"
    else
        base64 -i "$1" | tr -d '\n'
    fi
}

OPT_MIME=""
optimalkan() {
    src="$1"
    install -d "$CACHE_DIR"
    out="${CACHE_DIR}/$(basename "${src%.*}").jpg"
    OPT_MIME=""
    if command -v sips >/dev/null 2>&1; then
        if [ ! -f "$out" ] || [ "$src" -nt "$out" ]; then
            sips -Z 1500 -s format jpeg -s formatOptions 72 "$src" --out "$out" >/dev/null 2>&1 || true
        fi
        if [ -s "$out" ]; then
            OPT_MIME="image/jpeg"
            echo "$out"
            return 0
        fi
    fi
    echo "$src"
}

satu_gambar() {
    f="$1"
    caption="$2"
    [ -f "$f" ] || return 0
    case "${f##*.}" in
        png) mime="image/png" ;;
        *)   mime="image/jpeg" ;;
    esac
    pakai="$(optimalkan "$f")"
    [ -n "$OPT_MIME" ] && mime="$OPT_MIME"
    printf '<figure><img src="data:%s;base64,%s"><figcaption>%s</figcaption></figure>\n' \
        "$mime" "$(b64 "$pakai")" "$caption"
}

blok_gambar() {
    prefix="$1"
    n=0
    for f in "$GAMBAR_DIR"/"$prefix"-*.png "$GAMBAR_DIR"/"$prefix"-*.jpg "$GAMBAR_DIR"/"$prefix"-*.jpeg; do
        [ -f "$f" ] || continue
        base="$(basename "$f")"
        caption="$(printf '%s' "${base%.*}" \
            | sed -e "s/^${prefix}-//" -e 's/^[0-9]\{1,2\}-//' -e 's/-/ /g')"
        satu_gambar "$f" "$caption"
        n=$((n + 1))
    done
    [ "$n" -eq 0 ] && printf '<!-- belum ada tangkapan layar %s-* -->\n' "$prefix"
    return 0
}

blok_konfig() {
    pola="$1"
    for f in "$CONF_DIR"/$pola; do
        [ -f "$f" ] || continue
        printf '<p class="berkas">%s</p>\n<pre>' "$(basename "$f")"
        lolos_html <"$f"
        printf '</pre>\n'
    done
}

sisip() {
    penanda="$1"
    buf="$(mktemp)"
    printf '%s' "$2" >"$buf"
    python3 - "$work" "$penanda" "$buf" <<'PY'
import sys, pathlib
t = pathlib.Path(sys.argv[1])
t.write_text(t.read_text().replace(sys.argv[2], pathlib.Path(sys.argv[3]).read_text()))
PY
    rm -f "$buf"
}

echo "==> menyusun laporan soal 1"
work="$(mktemp)"
cp "$TEMPLATE" "$work"

sisip "@@PESERTA_NAMA@@" "$PESERTA_NAMA"
sisip "@@PESERTA_ID@@"   "$PESERTA_ID"
sisip "@@TANGGAL@@"      "$(date '+%d %B %Y')"

sisip "@@KONFIG:ROUTER@@" "$(blok_konfig 'R-*_config.txt')"
sisip "@@KONFIG:SWITCH@@" "$(blok_konfig 'SW-*_config.txt')"
echo "    konfigurasi: $(ls "$CONF_DIR"/*_config.txt 2>/dev/null | wc -l | tr -d ' ') berkas"

if [ -f "$TOPOLOGI" ]; then
    sisip "@@GAMBAR:TOPOLOGI@@" "$(satu_gambar "$TOPOLOGI" 'Topologi ring data center dan tiga cabang')"
else
    sisip "@@GAMBAR:TOPOLOGI@@" '<!-- topologi PNG tidak ditemukan -->'
    echo "WARN: ${TOPOLOGI} tidak ada" >&2
fi

ada=0
for p in IP PING OSPF FAILOVER; do
    blok="$(blok_gambar "$p")"
    case "$blok" in '<!-- belum'*) ;; *) ada=$((ada + 1)) ;; esac
    sisip "@@GAMBAR:${p}@@" "$blok"
done

sisa="$(grep -o '@@[A-Z:._]*@@' "$work" | sort -u | tr '\n' ' ' || true)"
if [ -n "$sisa" ]; then
    rm -f "$work"
    echo "ERROR: penanda belum tersubstitusi: ${sisa}" >&2
    exit 1
fi

mv "$work" "$OUT_HTML"
echo "==> jadi: ${OUT_HTML} ($(du -h "$OUT_HTML" | cut -f1))"

if [ "$ada" -eq 0 ]; then
    echo "WARN: belum ada tangkapan layar Packet Tracer di ${GAMBAR_DIR}/" >&2
    echo "      lihat daftarnya di laporan/README.md" >&2
fi

echo
echo "    open '${OUT_HTML}'"
echo "    Cmd+P -> Save as PDF -> simpan ke ../laporan-soal1.pdf (root soal1)"
