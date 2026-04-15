# Carrier & ISP Networking → HPC Networking
# Mental model translation for engineers making the transition

---

## Protocol stack mapping

| Carrier / ISP                  | HPC / AI Networking                    | Notes |
|-------------------------------|----------------------------------------|-------|
| MPLS data plane               | InfiniBand fabric / RoCEv2             | Both: low-latency, high-throughput, traffic-engineered |
| LDP / RSVP label distribution | Subnet Manager (SM) LID assignment     | SM assigns LIDs like LDP assigns labels — centralized |
| BGP route reflector           | UFM (Unified Fabric Manager)           | Central controller, fabric-wide view |
| ECMP across equal-cost paths  | Rail-optimized topology + NVSwitch     | Same goal: distribute load, no single bottleneck |
| QoS DSCP marking              | Service Level (SL) in InfiniBand       | SL maps to Virtual Lanes (VL) = your QoS queues |
| Traffic shaping / policing    | PFC + ECN + DCQCN                      | See Plate 03 — it's congestion control, not QoS |
| OSPF / IS-IS link state       | InfiniBand SA (Subnet Administrator)   | SA maintains topology, handles path queries |
| OAM / Y.1731 / CFM           | ibdiagnet / DCGM / UFM telemetry       | Fabric health monitoring |
| DCN / craft port              | BMC / IPMI / Redfish                   | Always-on OOB management |
| Chassis backplane / fabric    | NVSwitch (inside DGX node)             | Internal crossbar — GPUs don't route through external network |
| Fiber span / optical layer    | OSFP / DAC / AOC at 400G              | Same concepts, newer form factors |
| 5G fronthaul / CPRI           | NVLink over copper (within node)       | Ultra-low latency, dedicated medium |
| VLAN segmentation             | Partition Keys (PKeys) in InfiniBand   | Isolation between tenants/jobs |
| VRF (Virtual Routing/Fwd)     | QP (Queue Pair) per job               | Logical isolation of traffic flows |

---

## Addressing comparison

| Carrier                   | InfiniBand                  | Notes |
|--------------------------|----------------------------|-------|
| IP address (L3)           | GID (Global Identifier)     | 128-bit, globally unique, used for inter-subnet routing |
| MAC address (L2)          | LID (Local Identifier)      | 16-bit, assigned by SM, local to subnet |
| MPLS label                | LID (in forwarding table)   | Switch forwards based on LID, just like label forwarding |
| AS number                 | Subnet number               | Organizational boundary |
| Router ID (OSPF)          | Node GUID                   | Unique per HCA |
| Interface description      | Port GUID                   | Unique per port |

---

## Failure domain mapping

| Carrier scenario                    | HPC equivalent                          |
|------------------------------------|----------------------------------------|
| Fiber cut — link down               | IB port goes to Down/Polling state     |
| Route flap — route withdrawn/re-added | LID change after SM re-convergence   |
| LSP reroute (RSVP FRR)              | IB adaptive routing reconverges       |
| BGP peer down — traffic blackhole   | NVLink link down — GPU falls to PCIe  |
| CDN origin failure — all traffic fails | NVSwitch failure — node isolated     |
| Optical power degradation           | IB port degrades to lower speed (HDR→SDR) |
| Spanning tree loop                  | Pause storm (PFC misconfiguration)    |
| Broadcast storm                     | Incast congestion on fabric           |

---

## Diagnostic command mapping

| What you typed in carrier/ISP           | What you type in HPC               |
|----------------------------------------|------------------------------------|
| show interface                          | ibstat                             |
| show interface counters                 | perfquery                          |
| show ip route                           | ibroute / ibnetdiscover            |
| show mpls forwarding                    | ibfindnodesusing                   |
| ping                                    | ibping                             |
| traceroute                              | ibtracert                          |
| show spanning-tree                      | (no equivalent — IB is loop-free)  |
| show cdp neighbors / show lldp          | ibnetdiscover                      |
| netstat -s (socket stats)               | rdma stat                          |
| tcpdump / Wireshark                     | ibdump (raw IB capture)            |
| interface reset / shut no shut          | ibportstate -D <lid> <port> reset  |
| show hardware (chassis)                 | dcgmi discovery -l                 |
| IPMI / console access                   | ipmitool / Redfish / BMC           |

---

## Mental model shifts (things that trip up carrier engineers)

### 1. The fabric is lossless by design — not by accident
In Ethernet, you accept packet loss and rely on TCP to retransmit.
In HPC networking, a single dropped packet can stall an entire
training job. PFC was introduced specifically to prevent drops.
Think of PFC as a hardware-level PAUSE frame — the upstream sender
stops transmitting until the downstream buffer clears. This is not
optional in RDMA environments. See Plate 03.

### 2. The "network" is not just the switches
In carrier networking, the network is the routers and switches.
The servers are endpoints that generate traffic.
In HPC, the GPUs ARE the network participants. The NVSwitches inside
the DGX are as important as the external fabric switches. A DGX node
with a failed NVSwitch is as broken as a router with a failed fabric card.

### 3. There is no TCP in the fast path
RDMA bypasses the kernel. The NIC DMAs directly into GPU memory.
No socket, no TCP stack, no kernel network stack involvement.
This means your packet capture tools need to be RDMA-aware.
`tcpdump` will not show you RDMA traffic. Use `ibdump` or `rdma stat`.

### 4. The Subnet Manager is your IGP AND your LDP
In carrier, you run OSPF/IS-IS for link-state and LDP for label distribution.
In InfiniBand, the Subnet Manager does both:
- Discovers topology (like link-state protocol)
- Assigns LIDs (like label distribution)
- Computes paths (like Dijkstra/SPF)
- Programs forwarding tables on switches
One SM is active at a time. If it goes down, the fabric continues
forwarding (like MPLS — labels are in hardware) but no new paths
are computed until SM reconverges.

### 5. "Active" means Layer 2, not Layer 3
When ibstat shows "State: Active", that means the IB link layer is up —
equivalent to "Line protocol is up" in Cisco IOS.
It does NOT mean you have end-to-end reachability.
You still need SM to have assigned a LID and programmed paths.
After a link comes Active, allow 10-30 seconds for SM to converge.

---

## Your carrier skills that directly apply

- **MPLS TE / traffic engineering**: Rail topology IS traffic engineering.
  The physical design prevents contention. You understand this intuitively.
- **QoS and buffer management**: PFC/ECN/DCQCN is congestion control.
  You've done this at the line card level. Same principles.
- **OAM and monitoring**: ibdiagnet, DCGM, UFM are your new OSS tools.
  The concepts (threshold alerting, counter polling, topology discovery) are identical.
- **Scale**: You've managed infrastructure where a misconfiguration
  affects millions of users. That discipline makes you safer in HPC
  environments where one bad config drops a $50k training run.
- **Vendor diversity**: You know how to read vendor docs skeptically,
  find the real behavior in the datasheet footnotes, and test before trusting.

---

*Built by a carrier engineer who wouldn't stop asking why.*
