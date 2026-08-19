# Task 1 report

```bash
bash laporan/build.sh
open laporan/webgreat_soal1.html
```

Cmd+P → Save as PDF → enable **Background graphics** under More settings. Save it as
`../laporan-soal1.pdf`, at the task root.

The narrative, addressing tables, all eight device configurations, and the verification results are
filled in automatically from `DESAIN.md` and `sevima-datacenter/*_config.txt`. All you add are
Packet Tracer screenshots.

## Screenshots needed

Put them in `tangkapan-layar/` named `<CODE>-<order>-<caption>.png`. The caption is derived from
the name, with hyphens turned into spaces. The code decides which section the image lands in.

| Code | Contents | How to capture |
|---|---|---|
| `IP` | Addresses assigned to hosts | PC-JKT-1 → Desktop → Command Prompt → `ipconfig /all`. Shows the DHCP lease and the DNS server in one shot. |
| `PING` | Connectivity tests | From PC-JKT-1: `ping 192.168.0.5`, then `ping 192.168.3.10` to PC-SBY-1. The second one matters most — inter-branch reachability is an explicit requirement. |
| `OSPF` | Adjacency and routing table | R-JKT CLI → `enable`, then `show ip ospf neighbor` and `show ip route ospf`. Expect two FULL neighbours and an ECMP pair to 192.168.3.0. |
| `FAILOVER` | Redundancy proof | Shut the R-DC ↔ R-JKT link, then on R-JKT run `show ip route ospf` and ping `192.168.0.5`. The route must move to next hop `10.0.0.6` while pings keep succeeding. |

More than one image per code is fine. Use the order number to control placement:
`PING-1-jakarta-ke-server-aplikasi.png`, `PING-2-jakarta-ke-surabaya.png`.

## The shot that carries the most weight

`FAILOVER` is what separates this report from a picture of a topology. The brief asks for a data
center that acts as a backup *"so that recovery can be carried out quickly and efficiently"*.
Without before-and-after captures around a cut link, the ring is only a claim.

Take two consecutive shots of `show ip route ospf`: one healthy, one after the link is shut. The
difference in next hop and cost between them is the proof.

## How to shut the link

In the R-JKT CLI tab:

```
enable
configure terminal
interface GigabitEthernet0/0
shutdown
end
```

`Gi0/0` on R-JKT is the one facing R-DC. Restore it afterwards with `no shutdown`.

The same thing can be done from the device's **Config** tab: sidebar → INTERFACE →
GigabitEthernet0/0 → clear the **Port Status: On** checkbox.

Prefer `shutdown` over deleting the cable on the canvas. Deleting means redrawing the link with
exactly the same type and ports; get it slightly wrong and the `.pkt` you submit is broken.

## Task 1 deliverables

| Item | Status |
|---|---|
| `sevima-datacenter-3cabang.pkt` | present |
| Packet Tracer screenshots | you capture them |
| PDF report | produced here |
