# Building `webgreat_sevima.pdf`

The brief asks for two things: **documentation of every configuration** and **validation results**.
This report carries both, per task item — the contents of the config files actually installed on
the server, followed by the verification output.

Evidence sections are **not hand-written**. They are pulled from a real `verify.sh` run on the VPS.
The narrative is already written; you supply raw evidence and screenshots.

## Three steps

### 1. Collect evidence from the VPS

On the VPS:

```bash
bash verify.sh              # validation results
bash laporan/kumpulkan.sh   # contents of installed config files
```

Then from your laptop:

```bash
scp -P 2025 root@<VPS_IP>:/root/bukti-verifikasi-soal2.txt laporan/bukti/
scp -P 2025 root@<VPS_IP>:/root/konfigurasi-soal2.txt      laporan/bukti/
```

`build.sh` refuses to run without the validation file, and warns if the config file is missing or
if any check still reports `FAIL`.

`kumpulkan.sh` reads the files **as installed on the server**, not the templates in this repo — so
what reaches the report is what actually ran, including anything you changed by hand.

### 2. Add screenshots

Put them in `tangkapan-layar/` named `<CODE>-<order>-<caption>.png`. The code decides which section
the image lands in, the number orders it within that section, and the rest becomes the caption with
hyphens turned into spaces. The order number may be omitted when a code has only one image.

Example: `C2-header-timur-di-browser.png` lands in section C.2 with the caption
*"header timur di browser"*.

Recognised codes: `A1` `A2` `A3` `A4` `B` `C1` `C2` `C3` `D`.

The full shot list is in `PANDUAN-SCREENSHOT.md`.

### 3. Build

```bash
bash laporan/build.sh
```

If `wkhtmltopdf` or `weasyprint` is installed the PDF is produced directly. Otherwise the script
prints the command to open the HTML and save it as PDF from the browser (Cmd+P → Save as PDF).
Enable **Background graphics** in the print dialog, or the file-name headers and config blocks lose
their backgrounds.

Save it as `../webgreat_sevima.pdf` — exactly that name, at the task root.

Images are downscaled to 1500 px JPEG via `sips` before embedding, so the PDF stays small enough to
attach to an email. Your originals under `tangkapan-layar/` are untouched.

## What build.sh checks for you

- The evidence file exists and contains the `Passed/Failed` summary line
- Every task section (A.1 through D) is present — if `verify.sh` stopped halfway, the build fails
  and names the missing section
- No `@@...@@` placeholder survives into the final HTML
- Candidate name, ID, and every port number come from `config.sh` rather than being retyped

## Deliverables per the brief

| Item | Status |
|---|---|
| `webgreat_sevima.pdf` | produced here |
| Upload to the personal GitHub repo `taskopsec2025` | done at the repository root |
| Submission link from the Human Capital team | handled manually by you |

The Packet Tracer project file and its screenshots belong to Task 1, under `soal1-packet-tracer/`.

**Do not commit** `bukti/bukti-verifikasi-soal2.txt` to a public repository without reading it
first — it contains the port map, account names, and configuration details. The credential manifest
(`/root/sevima-users.csv`) and private keys must never be included at all.
