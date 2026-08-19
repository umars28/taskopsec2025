#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SEVIMA_ROOT="$(cd "${HERE}/.." && pwd)"
. "${SEVIMA_ROOT}/lib/common.sh"

require_identity
compute_ports

BUKTI="${HERE}/bukti/bukti-verifikasi-soal2.txt"
KONFIG="${HERE}/bukti/konfigurasi-soal2.txt"
GAMBAR_DIR="${HERE}/tangkapan-layar"
CACHE_DIR="${HERE}/.cache-gambar"
TEMPLATE="${HERE}/template.html"
OUT_HTML="${HERE}/webgreat_sevima.html"
OUT_PDF="${HERE}/webgreat_sevima.pdf"

if [ ! -s "$KONFIG" ]; then
    echo "PERINGATAN: ${KONFIG} belum ada; bagian dokumentasi konfigurasi akan kosong." >&2
    echo "Jalankan di VPS: bash laporan/kumpulkan.sh   lalu scp hasilnya ke laporan/bukti/" >&2
    echo >&2
fi

if [ ! -s "$BUKTI" ]; then
    echo "GAGAL: berkas bukti belum ada di ${BUKTI}" >&2
    echo >&2
    echo "Laporan ini diisi dari output verify.sh yang sungguhan, bukan contoh." >&2
    echo "Jalankan di VPS lebih dulu:" >&2
    echo "    bash verify.sh" >&2
    echo "lalu salin hasilnya ke laptop:" >&2
    echo "    scp -P ${SSH_PORT} root@<IP>:/root/bukti-verifikasi-soal2.txt ${HERE}/bukti/" >&2
    exit 1
fi

gagal="$(awk '/^  Failed :/{print $NF}' "$BUKTI" | tail -1)"
if [ -z "$gagal" ]; then
    echo "GAGAL: ${BUKTI} tidak memuat baris ringkasan; apakah verify.sh selesai sampai habis?" >&2
    exit 1
fi
if [ "$gagal" != "0" ]; then
    echo "PERINGATAN: masih ada ${gagal} pemeriksaan berstatus FAIL di berkas bukti." >&2
    echo "Laporan tetap dibangun, tapi perbaiki dulu sebelum dikumpulkan." >&2
    echo >&2
fi

ambil_konfig() {
    [ -f "$KONFIG" ] || return 0
    awk -v want="$1" '
        /^##### SECTION:/ {
            sec = $3
            sub(/^.*FILE: /, "", $0)
            file = $0
            aktif = (sec == want)
            if (aktif) printf "<p class=\"berkas\">%s</p>\n<pre>", file
            next
        }
        /^##### END/ { if (aktif) printf "</pre>\n"; aktif = 0; next }
        aktif {
            gsub(/&/, "\\&amp;"); gsub(/</, "\\&lt;"); gsub(/>/, "\\&gt;")
            print
        }
    ' "$KONFIG"
}

ambil_bagian() {
    awk -v pat="$1" '
        /^=+$/ {
            if ((getline hdr) > 0 && (getline sep) > 0) {
                tampil = (index(hdr, pat) > 0)
                next
            }
        }
        tampil { print }
    ' "$BUKTI"
}

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

blok_gambar() {
    prefix="$1"
    found=0
    for f in "$GAMBAR_DIR"/"$prefix"-*.png "$GAMBAR_DIR"/"$prefix"-*.jpg "$GAMBAR_DIR"/"$prefix"-*.jpeg; do
        [ -f "$f" ] || continue
        base="$(basename "$f")"
        ext="${base##*.}"
        case "$ext" in
            png) mime="image/png" ;;
            *)   mime="image/jpeg" ;;
        esac
        caption="$(printf '%s' "${base%.*}" \
            | sed -e "s/^${prefix}-//" -e 's/^[0-9]\{1,2\}-//' -e 's/-/ /g')"
        pakai="$(optimalkan "$f")"
        [ -n "$OPT_MIME" ] && mime="$OPT_MIME"
        printf '<figure><img src="data:%s;base64,%s"><figcaption>%s</figcaption></figure>\n' \
            "$mime" "$(b64 "$pakai")" "$caption"
        found=$((found + 1))
    done
    [ "$found" -eq 0 ] && printf '<!-- belum ada tangkapan layar %s-* -->\n' "$prefix"
    return 0
}

info "menyusun laporan"
work="$(mktemp)"
cp "$TEMPLATE" "$work"

TANGGAL="$(date '+%d %B %Y')"
RINGKASAN="$(ambil_bagian 'Summary' | lolos_html)"

for kunci in PESERTA_NAMA PESERTA_ID TANGGAL UTARA_PORT TIMUR_PORT \
             BARAT_HTTPS_PORT BARAT_HTTP_PORT TIMUR_SERVED_BY; do
    nilai="${!kunci}"
    python3 - "$work" "@@${kunci}@@" "$nilai" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace(sys.argv[2], sys.argv[3]))
PY
done

sisip_blok() {
    penanda="$1"
    isi="$2"
    buf="$(mktemp)"
    printf '%s' "$isi" >"$buf"
    python3 - "$work" "$penanda" "$buf" <<'PY'
import sys, pathlib
t = pathlib.Path(sys.argv[1])
t.write_text(t.read_text().replace(sys.argv[2], pathlib.Path(sys.argv[3]).read_text()))
PY
    rm -f "$buf"
}

sisip_blok "@@RINGKASAN@@" "$RINGKASAN"

for bagian in A.1 A.2 A.3 A.4 B C.1 C.2 C.3 D; do
    isi="$(ambil_bagian "$bagian" | lolos_html)"
    if [ -z "$(printf '%s' "$isi" | tr -d '[:space:]')" ]; then
        rm -f "$work"
        die "bagian '${bagian}' tidak ditemukan di berkas bukti; verify.sh mungkin berhenti di tengah"
    fi
    sisip_blok "@@BUKTI:${bagian}@@" "$isi"
    info "  bukti ${bagian} disisipkan"
done

for bagian in A.2 A.3 A.4 B C.1 C.2 C.3 D; do
    sisip_blok "@@KONFIG:${bagian}@@" "$(ambil_konfig "$bagian")"
done

sisip_blok "@@BUKTI:PORT@@" "$(ambil_bagian 'Port map' | lolos_html)"

jml_gambar=0
for pasangan in A1:A.1 A2:A.2 A3:A.3 A4:A.4 B:B C1:C.1 C2:C.2 C3:C.3 D:D; do
    prefix="${pasangan%%:*}"
    blok="$(blok_gambar "$prefix")"
    case "$blok" in
        '<!-- belum'*) ;;
        *) jml_gambar=$((jml_gambar + 1)) ;;
    esac
    sisip_blok "@@GAMBAR:${prefix}@@" "$blok"
done

mv "$work" "$OUT_HTML"
info "HTML jadi: ${OUT_HTML}"

if [ "$jml_gambar" -eq 0 ]; then
    warn "belum ada satu pun tangkapan layar di ${GAMBAR_DIR}/"
    warn "lihat daftar yang perlu difoto di laporan/README.md"
fi

if command -v wkhtmltopdf >/dev/null 2>&1; then
    info "mengonversi ke PDF dengan wkhtmltopdf"
    wkhtmltopdf --enable-local-file-access -q "$OUT_HTML" "$OUT_PDF"
    info "PDF jadi: ${OUT_PDF}"
elif command -v weasyprint >/dev/null 2>&1; then
    info "mengonversi ke PDF dengan weasyprint"
    weasyprint "$OUT_HTML" "$OUT_PDF"
    info "PDF jadi: ${OUT_PDF}"
else
    echo
    info "wkhtmltopdf/weasyprint tidak terpasang."
    info "Buka HTML-nya lalu simpan sebagai PDF dari browser:"
    echo
    echo "    open '${OUT_HTML}'"
    echo "    Cmd+P -> Save as PDF -> simpan ke ../webgreat_sevima.pdf (root soal2)"
    echo
    info "Atau pasang konverternya: brew install --cask wkhtmltopdf"
fi
