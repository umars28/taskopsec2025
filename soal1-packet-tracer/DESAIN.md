# Task 1 — Infrastructure Provisioning

Data center plus three branches (Jakarta, Bandung, Surabaya) in Cisco Packet Tracer 9.0.

## Design decisions

### Why a ring rather than hub-and-spoke

The brief asks for a data center that acts as a backup "so that if a problem occurs, recovery can
be carried out quickly and efficiently", and for the three branches to be "well connected to one
another".

Hub-and-spoke — every branch reaching only the data center — satisfies connectivity but leaves a
single point of failure: if a branch-to-DC link drops, that branch is fully isolated. A ring gives
two paths to every destination:

```
        R-DC ─────── R-JKT
         │              │
         │              │
        R-SBY ─────── R-BDG
```

When one link fails, OSPF recomputes the path in the opposite direction. That is the direct
technical justification for "fast recovery" — not merely a claim, and it is demonstrated in the
verification section below.

### Why the 2911, and no serial modules

Each ring node needs three ports: one to its own LAN, two to its neighbours. The Cisco 2911 has
exactly `GigabitEthernet0/0`, `0/1`, and `0/2`, so a four-node ring fits without any additional
module.

The alternative was fitting HWIC-2T cards for serial links, closer to a real WAN. That was rejected
because it adds a per-router power-cycle step that can fail, without changing the routing behaviour
under test.

### Why OSPF rather than static routes

Redundancy is only useful if something recomputes the path when a link dies. Static routes do not,
absent manually configured floating routes per destination. OSPF single-area detects the link down
via its hello timer and reconverges automatically — that is the core of "fast recovery".

## Addressing plan

### LAN per site

| Site | Router | Subnet | Gateway | DHCP |
|---|---|---|---|---|
| Data Center | R-DC | `192.168.0.0/24` | `192.168.0.1` | pool `LAN_DC`, excludes `.1`–`.20` |
| Jakarta | R-JKT | `192.168.1.0/24` | `192.168.1.1` | pool `LAN_JKT`, excludes `.1`–`.9` |
| Bandung | R-BDG | `192.168.2.0/24` | `192.168.2.1` | pool `LAN_BDG`, excludes `.1`–`.9` |
| Surabaya | R-SBY | `192.168.3.0/24` | `192.168.3.1` | pool `LAN_SBY`, excludes `.1`–`.9` |

The low range of each subnet is excluded from DHCP so infrastructure and server addresses are never
handed out to clients. The data center range is wider because that is where the static servers live.

### Inter-router links (the ring)

| Link | Subnet | Addresses |
|---|---|---|
| DC ↔ JKT | `10.0.0.0/30` | `.1` (R-DC Gi0/0) — `.2` (R-JKT Gi0/0) |
| JKT ↔ BDG | `10.0.0.4/30` | `.5` (R-JKT Gi0/1) — `.6` (R-BDG Gi0/0) |
| BDG ↔ SBY | `10.0.0.8/30` | `.9` (R-BDG Gi0/1) — `.10` (R-SBY Gi0/0) |
| SBY ↔ DC | `10.0.0.12/30` | `.13` (R-SBY Gi0/2) — `.14` (R-DC Gi0/2) |

Every point-to-point link uses a `/30` — two host addresses, zero waste.

### Servers in the data center

| Host | IP | Role |
|---|---|---|
| SRV-APP | `192.168.0.5` | Application server |
| SRV-DB | `192.168.0.6` | Database, and DNS for every LAN |
| SRV-BACKUP | `192.168.0.7` | Backup and recovery target |

All servers use static addressing rather than DHCP. The backup target must have a stable address so
that backup jobs from the branches do not depend on a lease that can change.

## Port allocation

| Device | Gi0/0 | Gi0/1 | Gi0/2 |
|---|---|---|---|
| R-DC | → R-JKT | → SW-DC | → R-SBY |
| R-JKT | → R-DC | → R-BDG | → SW-JKT |
| R-BDG | → R-JKT | → R-SBY | → SW-BDG |
| R-SBY | → R-BDG | → SW-SBY | → R-DC |

All three ports are used on every router — none spare, none short.

## OSPF

Process ID 1, everything in area 0. Router IDs are pinned explicitly to each router's lowest ring
address (`10.0.0.1`, `10.0.0.2`, `10.0.0.6`, `10.0.0.10`) so they will not shift if a loopback
interface is added later.

Each router advertises its own LAN plus both ring subnets it terminates. R-DC and R-SBY both
advertise `10.0.0.12/30` — the link that closes the ring, and therefore the one that makes
redundancy real.

## Inventory

22 devices, 22 links:

- 4 × Cisco 2911 (routers)
- 4 × Cisco 2960-24TT (switches, one per site)
- 3 × Server-PT (in the data center)
- 11 × PC-PT (2 in the DC NOC, 3 per branch)

## Verification plan

| Test | From | To | What it proves |
|---|---|---|---|
| ping | PC-JKT-1 | SRV-APP | A branch reaches the application in the DC |
| ping | PC-SBY-1 | SRV-BACKUP | A branch reaches the backup target |
| ping | PC-BDG-1 | SRV-DB | A branch reaches the database |
| ping | PC-JKT-1 | PC-SBY-1 | Branch-to-branch connectivity (explicit requirement) |

The redundancy test that substantiates the ring: shut one ring link, then repeat the inter-branch
ping. It must still reply, and `show ip route ospf` on the affected router must show a different
next hop than before.

## Artifacts

| File | Contents |
|---|---|
| `plan-sevima.json` | Source plan (hand-edited: ring layout and naming) |
| `sevima-datacenter/plan.json` | Exported plan |
| `sevima-datacenter/topology.js` | Builder script: 22 `lwAddDevice` plus 22 `lwAddLink` |
| `sevima-datacenter/full_build.js` | Full script including IOS configuration |
| `sevima-datacenter/R-*_config.txt` | IOS configuration per router |
| `sevima-datacenter/SW-*_config.txt` | Configuration per switch |
| `topologi-sevima-datacenter.png` | Labelled canvas screenshot |
| `sevima-datacenter-3cabang.pkt` | Packet Tracer project file |

The plan passes the validator with 0 errors and 0 warnings.

---

# Verification results

Run against Packet Tracer 9.0.0. Deploy verified 22/22 devices and 22/22 links; the health check
reported no links down and no duplicate addresses.

## Addresses actually assigned

| Host | Assigned IP | Method |
|---|---|---|
| SRV-APP | `192.168.0.5` | static |
| SRV-DB (DNS) | `192.168.0.6` | static |
| SRV-BACKUP | `192.168.0.7` | static |
| PC-NOC-1 / PC-NOC-2 | `192.168.0.11` / `.12` | static |
| PC-JKT-1/2/3 | `192.168.1.10` / `.11` / `.12` | DHCP |
| PC-BDG-1/2/3 | `192.168.2.11` / `.10` / `.12` | DHCP |
| PC-SBY-1/2/3 | `192.168.3.10` / `.11` / `.12` | DHCP |

DHCP leases begin at `.10` in the branches and `.21` in the data center, consistent with the
configured `ip dhcp excluded-address` ranges — so the exclusions are demonstrably effective rather
than merely present in the config.

## Connectivity tests

Real pings from the device consoles, not simulation mode:

| From | To | Result |
|---|---|---|
| PC-JKT-1 | SRV-APP `192.168.0.5` | 3/4 received — OK |
| PC-SBY-1 | SRV-BACKUP `192.168.0.7` | 3/4 received — OK |
| PC-BDG-1 | SRV-DB `192.168.0.6` | 3/4 received — OK |
| PC-JKT-1 | PC-SBY-1 `192.168.3.10` | 4/4 received — OK |

Losing the first packet to a new destination is normal behaviour, not a fault: that packet is
consumed by ARP resolution because no entry exists yet.

## OSPF adjacency

The R-JKT console log shows both ring sides reaching FULL:

```
%OSPF-5-ADJCHG: Process 1, Nbr 10.0.0.6 on GigabitEthernet0/1 from LOADING to FULL
%OSPF-5-ADJCHG: Process 1, Nbr 10.0.0.1 on GigabitEthernet0/0 from LOADING to FULL
```

## Redundancy test — evidence for the ring

`show ip route ospf` on R-JKT before the fault:

```
O    192.168.0.0 [110/2] via 10.0.0.1, GigabitEthernet0/0
O    192.168.3.0 [110/3] via 10.0.0.1, GigabitEthernet0/0
                 [110/3] via 10.0.0.6, GigabitEthernet0/1
```

Surabaya has **two equal-cost paths**, so the ring does not merely hold a passive standby — traffic
toward Surabaya is split across both directions (ECMP).

The DC↔Jakarta link was then cut, simulating a severed WAN circuit. The routing table afterwards:

```
O    192.168.0.0 [110/4] via 10.0.0.6, 00:00:19, GigabitEthernet0/1
O    192.168.3.0 [110/3] via 10.0.0.6, 00:00:19, GigabitEthernet0/1
```

What that shows:

- The next hop to the DC LAN moved from `10.0.0.1` (direct link) to `10.0.0.6` (via Bandung)
- Cost rose from 2 to 4, reflecting the longer path JKT → BDG → SBY → DC
- The route age of `00:00:19` shows OSPF has just recomputed rather than reusing a stale entry
- The subnet count dropped from 6 to 4 because `10.0.0.0/30` left the topology

**Ping PC-JKT-1 → SRV-APP while the link was down: 4/4 received, 0% loss.** The data center stayed
reachable with no manual intervention.

After the link was restored, the route returned to `[110/2] via 10.0.0.1` and the ECMP pair toward
Surabaya reappeared — convergence works in both directions.

## Implementation note

The generator script defaults every host to DHCP except one highest-addressed "anchor" per subnet,
which it makes static as a fallback. That behaviour was overridden by hand so the rule is uniform
and explainable: **all data center hosts static, all branch clients DHCP.**

The reason is not aesthetic. `dns-server 192.168.0.6` is advertised to every branch; on the first
attempt SRV-DB picked up a lease of `.23`, which would have left that DNS reference pointing at an
address nobody uses. The backup target likewise needs a fixed address so that branch backup jobs do
not depend on a lease that can change.
