# Task 2 — Make Your Web Great Again

Provisioning scripts covering every item of Task 2: bulk sudo accounts, SSH on port 2025, activity
logging, resource limits, an OpenSSL root CA, three virtual hosts (apache2 and nginx on the same
host), and an HAProxy load balancer.

**Target:** Debian or Ubuntu, run as `root`. The scripts refuse to run without `apt-get`, because
the package names (`apache2`), the `sudo` group, and `update-ca-certificates` are Debian-specific.

## Layout

```
config.sh          values you edit
lib/common.sh      shared functions, loads config.sh
templates/         real configuration files, one per destination file
steps/             one file per task item, run in order
verify.sh          collects evidence for the report
run-all.sh         runs every step, then verify.sh
laporan/           report generator
docs/              client-side instructions
```

Every file under `steps/` can be run on its own; each one loads `lib/common.sh` and recomputes its
own ports.

### Configuration lives in files, not in `echo` statements

Every config that lands on the system has its own source file under `templates/`, named and
nested to mirror its destination:

| Template | Destination |
|---|---|
| `templates/nginx/barat.conf` | `/etc/nginx/sites-available/barat` |
| `templates/haproxy/haproxy.cfg` | `/etc/haproxy/haproxy.cfg` |
| `templates/apache/utara.conf` | `/etc/apache2/sites-available/utara.conf` |
| `templates/audit/99-sevima.rules` | `/etc/audit/rules.d/99-sevima.rules` |
| `templates/ca/openssl.cnf` | `/root/ca/openssl.cnf` |

An nginx config therefore still reads as an nginx config — syntax highlighting, `diff`, and review
all work without going through the shell script that installs it.

Scripts fill them via `render_template <template> <destination> '<variable-list>' [mode]`, which
uses `envsubst` with an **explicit variable list**. That list matters: without it `envsubst` would
also consume nginx's `$uri` and `$request_uri`, openssl's `$dir`, and apache's
`${APACHE_LOG_DIR}`, turning them all into empty strings and silently breaking the configs.

Two safeguards:

- **A missed placeholder fails the step.** Add a variable to a template but forget to declare it,
  and the script stops and names the variable — rather than writing a file with a hole in it.
- **Unchanged files are not rewritten.** `render_template` compares the rendered output against
  what is already on disk; if identical, nothing is written and the service is not restarted. That
  makes idempotency observable rather than merely claimed.

The only config still assembled inside a script is HAProxy's `crt-list.txt`, because its contents
depend on which `.pem` files actually exist.

## What you must fill in first

Open `config.sh` and set the first two lines:

```bash
PESERTA_ID=""      # participant ID number
PESERTA_NAMA=""    # your name; goes into the X-Owner-By header
```

Every script calls `require_identity` and **stops with a clear message** if either is empty — no
silent defaults.

### `PORT_MODE`

The brief writes the vhost port as `80 + participant ID`, then gives its own example: *"if the
participant ID is 23, use port 8023."* So it means concatenation, not addition, and the default
`PORT_MODE="gabung"` is correct.

| `PORT_MODE` | Meaning | ID=23 yields |
|---|---|---|
| `gabung` (default, matches the brief) | `80` and `81` concatenated with the ID | `8023` and `8123` |
| `jumlah` | arithmetic addition | `103` and `104` |

`jumlah` exists only as an escape hatch if a grader reads it differently. Do not use it without a
reason — small IDs produce privileged ports, and ID=363 would land exactly on port 443.

## Running

All at once:

```bash
sudo -i
cd /path/to/soal2-webserver
bash run-all.sh
```

Or step by step, so each stage can be captured separately. **This is what I recommend on a VPS** —
if a step fails you have not already moved the SSH port.

| Step | Item | Contents |
|---|---|---|
| `steps/10-users.sh` | A.1 | 1300 `sevima-adm1..1300` accounts, sudo, passwords, ed25519 keypairs |
| `steps/20-ssh.sh` | A.2 | sshd moved to port 2025, crypto and session hardening |
| `steps/25-fail2ban.sh` | A.2 | sshd jail, automatic banning |
| `steps/30-logging.sh` | A.3 | rsyslog, persistent journald, auditd, sudo I/O, process accounting |
| `steps/40-limits.sh` | A.4 | limits.conf, systemd limits, sysctl, unit sandboxing |
| `steps/50-ca.sh` | B | root CA under `/root/ca` plus 4 server certificates |
| `steps/60-apache-utara.sh` | C.1 | apache2 vhost for `utara.sevima.site` |
| `steps/70-nginx-timur.sh` | C.2 | nginx vhost for `timur.sevima.site` |
| `steps/75-nginx-barat.sh` | C.3 | nginx HTTPS vhost for `barat.sevima.site` plus redirect |
| `steps/80-haproxy.sh` | D | round-robin load balancer for `www.sevima.site` |
| `steps/85-firewall.sh` | — | ufw default-deny (opt-in) |
| `verify.sh` | — | writes all evidence to `/root/bukti-verifikasi-soal2.txt` |

All scripts are **idempotent**. Anything that changes a service configuration validates it first
(`sshd -t`, `apache2ctl configtest`, `nginx -t`, `haproxy -c`, `fail2ban-client -t`, `visudo -c`,
`logrotate -d`) and refuses to restart on invalid config.

## Port map

With `PESERTA_ID=99` and `PORT_MODE=gabung`:

| Port | Service | Notes |
|---|---|---|
| 2025 | sshd | replaces 22 |
| 80 | HAProxy | HTTP frontend, 301 redirect to HTTPS |
| 443 | HAProxy | HTTPS frontend, host-based routing |
| 8099 | apache2 | `utara.sevima.site`, HTTP only |
| 8199 | nginx | `timur.sevima.site`, HTTP only |
| 4435 | nginx | `barat.sevima.site`, HTTPS |
| 8080 | nginx | HTTP redirect for `barat` |
| 8404 | HAProxy stats | bound to `127.0.0.1` only |

## Two ambiguities in the brief, and how they were resolved

### 1. `X-Served-By` for timur

Item C.a.2.b reads: *"X-Served-By: filled with the type of web server (apache2)"* — while the
preceding sentence requires the `timur` vhost to be served by **nginx**. The `(apache2)` text is
carried over from item C.a.1.

The **rule** was followed rather than the parenthetical — "filled with the type of web server" —
so the value is `nginx`. If a grader insists on the literal text, change `TIMUR_SERVED_BY="apache2"`
in `config.sh` and re-run `steps/70-nginx-timur.sh`.

### 2. "Login using a password and using a pubkey"

Default: both methods are **available** (`PasswordAuthentication yes` plus
`PubkeyAuthentication yes`). To require both at once as two factors, set
`SSH_REQUIRE_BOTH_FACTORS="yes"`, which installs `AuthenticationMethods publickey,password`.

Item C.3.b — *"redirect all HTTP requests to HTTPS"* — sits under the `barat` vhost item, so its
scope is barat alone, not the whole host. There is no conflict with item D: HAProxy owns 80 and
443, while nginx performs its own redirect on port 8080 for `barat`, satisfying C.3.b exactly where
the brief asks for it.

## Non-obvious technical points

**`ssh.socket` ignores `Port`.** Ubuntu 22.10 and later enable socket activation for SSH. On those
systems, changing `Port` in `sshd_config` has no effect at all — the port comes from
`ListenStream` in the socket unit. `20-ssh.sh` detects this and writes a socket override.

**sshd drop-ins use first-value-wins.** Files in `sshd_config.d/` are read in alphabetical order
and the first value found for a keyword is the one used. Cloud images typically ship
`50-cloud-init.conf` containing `PasswordAuthentication no`, so a drop-in named `99-*` would
**lose** to it. Hence the name `01-sevima.conf`, and hence `20-ssh.sh` verifies the result of
`sshd -T` before continuing.

**Apache uses the opposite rule.** Files in `conf-enabled/` are also read alphabetically, but for a
repeated directive the **last** one wins. Ubuntu's `security.conf` sets `ServerTokens OS`, so a
file named `99-*` would lose. Ours is named `zz-sevima.conf` so it is read last. Copying the `99-`
naming habit from sshd to Apache produces a silent failure in exactly one of the two.

**Socket binding is not automatically dual-stack.** `ListenStream=2025` binds `[::]:2025`, and
whether that also serves IPv4 depends on `net.ipv6.bindv6only`. Where it does not, clients get
`Connection refused` while `ss` still shows the port listening. The socket override sets
`BindIPv6Only=both`, and the script opens a real IPv4 TCP connection to `127.0.0.1:2025` to confirm
before declaring success.

**`limits.conf` does not apply to systemd services.** That file is read by `pam_limits`, which only
runs for login sessions. nginx, apache2, and haproxy are started by systemd without PAM, so their
limits must come from a `LimitNOFILE` drop-in. Verify with `systemctl show -p LimitNOFILE nginx`.

**Certificates without SAN are always rejected.** Modern browsers ignore `CN` entirely and read
only `subjectAltName`. `50-ca.sh` sets a SAN on every certificate and prints it on issue.

**HAProxy needs certificate and key in one file**, unlike nginx which keeps them separate.
`50-ca.sh` writes combined files under `/etc/haproxy/certs/`. The order in `crt-list.txt` decides
which certificate answers a connection without SNI — `www` is deliberately placed first.

**HSTS applies per host, not per port.** `HSTS_MAX_AGE` is deliberately set to 300 seconds. At a
one-year value, once a browser has opened `https://barat.sevima.site:4435` it will never again send
plain HTTP to that host on any port — making the port 8080 redirect impossible to demonstrate in a
browser. Raise the value outside a lab.

## Security measures

| Layer | Contents |
|---|---|
| SSH | modern KEX/cipher/MAC only, `LoginGraceTime 30`, `MaxStartups`, no X11/agent/tunnel forwarding, `PermitEmptyPasswords no` |
| fail2ban | `sshd` jail on port 2025, ban/unban exercised during provisioning |
| Kernel | `tcp_syncookies`, `rp_filter`, redirects and source routing refused, `kptr_restrict`, `protected_symlinks`, core dumps off |
| systemd | `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=full`, `ProtectHome=read-only`, `RestrictSUIDSGID` for nginx/apache2/haproxy |
| TLS | TLS 1.2+ only, AEAD cipher suites only, session tickets off, 2048-bit dhparam |
| HAProxy | client `X-Forwarded-*` stripped then rewritten, HTTP method allowlist, 200 req/10s per-IP rate limit, TLS-verified backend to `barat` |
| Web headers | `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy` on all three vhosts and at the frontend |
| Logging | real client IP restored via `mod_remoteip` and `real_ip`; sudo-io recordings pruned automatically |
| Secrets | manifest `0600`, CA key `0400`, key directory `0700`, `.gitignore` included |

`steps/85-firewall.sh` prepares a default-deny ufw setup but is **not enabled by default**
(`ENABLE_UFW="no"`). Turn it on yourself once you are sure you can reach the provider console — the
script verifies the SSH port rule exists before enabling, and confirms sshd is still listening
afterwards.

## Security caveats that cannot be fixed

The brief requires 1300 sudo accounts with passwords following `w3bsite#1` through `w3bsite#1300`.
That pattern is fully derivable from the account name. Implemented as specified, but:

- never use this pattern outside a lab
- on a public VPS, restrict port 2025 at the provider firewall to your own IP and the grader's
- destroy the VPS once grading is complete

`10-users.sh` writes a credential manifest to `/root/sevima-users.csv` (mode `0600`) and private
keys to `/root/sevima-keys/` (mode `0700`). Both contain secrets: never commit them, never attach
them to the report, delete them after grading.

## Manual steps

| Item | Why it is not automated |
|---|---|
| Trusting the CA on your laptop | modifies the system trust store; steps in `docs/trust-ca-client.md` |
| `/etc/hosts` on your laptop | needs the server IP, which only you know |
| Screenshots | must come from your own screen; list in `laporan/PANDUAN-SCREENSHOT.md` |

## Producing the report

The brief asks for `webgreat_sevima.pdf` containing documentation of every configuration and the
validation results. The narrative is already written in `laporan/template.html`; the configuration
and evidence sections are filled automatically from the real host.

```bash
bash verify.sh                # on the VPS: validation results
bash laporan/kumpulkan.sh     # on the VPS: contents of every installed config file
scp -P 2025 root@<IP>:/root/bukti-verifikasi-soal2.txt laporan/bukti/
scp -P 2025 root@<IP>:/root/konfigurasi-soal2.txt      laporan/bukti/
bash laporan/build.sh         # on your laptop
```

`build.sh` refuses to run without the validation file and stops if any task section is missing from
it. Details in `laporan/README.md`.
