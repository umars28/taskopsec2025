# taskopsec2025

Technical test submission — Opsec 2025, PT. Sentra Vidya Utama.
Candidate: **Umar Sabirin** (ID 99).

| # | Task | Directory |
|---|---|---|
| 1 | Infrastructure Provisioning | [`soal1-packet-tracer/`](soal1-packet-tracer/) |
| 2 | Make Your Web Great Again | [`soal2-webserver/`](soal2-webserver/) |

## Deliverables

| Item | File |
|---|---|
| a) Cisco Packet Tracer project | `soal1-packet-tracer/sevima-datacenter-3cabang.pkt` |
| b) Packet Tracer screenshots | `soal1-packet-tracer/laporan/tangkapan-layar/` |
| c) PDF reports | `soal1-packet-tracer/laporan-soal1.pdf`<br>`soal2-webserver/webgreat_sevima.pdf` |

## Task 1 — Infrastructure Provisioning

Data center plus three branches (Jakarta, Bandung, Surabaya) built in Cisco Packet Tracer 9.0.

The four sites form a **ring** rather than hub-and-spoke, with **OSPF area 0** for inter-site
routing. That choice answers the brief directly: the data center must act as a backup "so that
recovery can be carried out quickly and efficiently". When a single link is cut, OSPF recomputes
the path in the opposite direction and the data center stays reachable with no manual
intervention.

This is demonstrated, not asserted — the report includes the routing table before and after a link
is administratively shut down, showing the next hop move from `10.0.0.1` to `10.0.0.6` and the
cost rise from 2 to 4, with pings still succeeding throughout.

22 devices, 22 links. Design rationale in [`DESAIN.md`](soal1-packet-tracer/DESAIN.md); per-device
IOS configuration in [`sevima-datacenter/`](soal1-packet-tracer/sevima-datacenter/).

## Task 2 — Make Your Web Great Again

Provisioning of a single Ubuntu 24.04 host: 1300 sudo accounts, SSH moved to port 2025, layered
logging, resource limits, an OpenSSL root CA, three virtual hosts (apache2 and nginx side by side),
and an HAProxy round-robin load balancer.

Implemented as idempotent scripts rather than manual steps. Every script validates its
configuration before restarting a service, so no service is ever started with a config that has
not been checked. Configuration lives as real template files under
[`templates/`](soal2-webserver/templates/) instead of being echoed from inside shell scripts,
which keeps each config readable and diffable on its own.

Automated verification: **54 checks passed, 0 failed**. Raw evidence in
[`laporan/bukti/`](soal2-webserver/laporan/bukti/).

Run instructions in [`soal2-webserver/README.md`](soal2-webserver/README.md).

## Security note

The brief requires 1300 accounts with passwords following the pattern `w3bsite#1` through
`w3bsite#1300` — fully derivable from the account name, and every account holds sudo. That was
implemented as specified, with mitigations that do not conflict with the requirement: fail2ban,
hardened SSH cryptography and session limits, and a set of kernel hardening parameters.

The credential manifest (`/root/sevima-users.csv`) and the private keys (`/root/sevima-keys/`) are
**never committed to this repository** — both are covered by `.gitignore`. The lab server is
destroyed once grading is complete.
