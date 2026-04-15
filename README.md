# DGX Node Wiring — Field Reference

**AI Infrastructure Engineering Series · Plate 01**

> If you came from carrier or ISP networking — MPLS, BGP, IPoMPLS, 5G transport —
> this repo is written for you. The concepts aren't new. The vocabulary is.

---

## What this is

A field-level reference for the DGX H100 node: how it's wired internally, what
healthy looks like, how to read the topology, and how to diagnose it when something
is wrong. Written from the perspective of someone who spent years in carrier
infrastructure before moving into HPC and AI networking.

Not a vendor manual. Not a marketing doc. The kind of document you want at 2am
when a training job is failing and you need to know whether the problem is the
fabric, the node, or the application.

Credit: [fabriclab.dev](https://fabriclab.dev) for building the best open
curriculum in this space. This repo is not a replacement — it's a companion with
a different angle: real diagnostic artifacts, field scripts, and the carrier
engineer's mental model applied to GPU infrastructure.

---

## The three networks inside one DGX H100

This is the first thing that trips up people coming from traditional networking.
A DGX H100 is not one server on one network. It is one chassis running three
physically separate networks simultaneously.

```
┌─────────────────────────────────────────────────────────────────┐
│                        DGX H100 NODE                            │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              COMPUTE FABRIC (InfiniBand / RoCEv2)        │   │
│  │   8× ConnectX-7 HCA · NDR 400G · PCIe Gen5 x16          │   │
│  │   One NIC per GPU · Rail-optimized topology              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              STORAGE FABRIC (NVMe-oF / GPUDirect)       │   │
│  │   2× ConnectX-7 HCA · 400GbE · Dedicated storage rail   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              OOB MANAGEMENT (1GbE)                       │   │
│  │   BMC · IPMI / Redfish · Always-on on 5V standby        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              INTRA-NODE GPU FABRIC (NVLink / NVSwitch)   │   │
│  │   4× NVSwitch 3.0 · 900 GB/s per GPU bidirectional      │   │
│  │   Full all-to-all crossbar · NOT Ethernet · NOT PCIe     │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

**Carrier analogy:**
- Compute fabric = your MPLS data plane. High-throughput, low-latency, what the
  workload actually uses.
- Storage fabric = your out-of-band file transfer / provisioning network.
  Separate plane, separate switches, never mixed with compute.
- OOB management = your DCN / craft port / console server. Always reachable,
  even if the main system is down.
- NVLink/NVSwitch = your internal backplane. Think chassis fabric on a Cisco ASR
  or Juniper PTX. The cards don't route through the external network to talk to
  each other — they use the internal crossbar. Except here the crossbar is
  900 GB/s and the "cards" are H100 GPUs.

---

## GPU layout and NVSwitch crossbar

```
GPU 0 ──┐
GPU 1 ──┤
GPU 2 ──┤──► NVSwitch 0 ──┐
GPU 3 ──┘                  │
                           ├──► Full all-to-all mesh
GPU 4 ──┐                  │    Any GPU → Any GPU
GPU 5 ──┤                  │    No bottleneck
GPU 6 ──┤──► NVSwitch 1 ──┘    No head-of-line blocking
GPU 7 ──┘

Each GPU connects to ALL 4 NVSwitches simultaneously.
Each NVSwitch connects to ALL 8 GPUs.
Result: 900 GB/s bidirectional per GPU to any peer GPU.
```

**Why this matters for training:**
AllReduce — the operation that synchronizes gradients across GPUs — runs entirely
over NVLink within a node. It never touches the external IB/Ethernet fabric. The
external fabric only matters for inter-node communication. This is why intra-node
AllReduce is fast and inter-node AllReduce is where you feel the fabric.

### NVLink vs PCIe — why two fabrics inside the same node

PCIe connects GPUs to the CPU and to NICs. It is used for:
- Launching CUDA kernels (CPU → GPU command submission)
- Small control messages
- GPUDirect RDMA: NIC DMA path into GPU HBM (data arrives from network → NIC →
  PCIe → GPU without CPU involvement)

NVLink connects GPUs directly to each other. It is used for:
- Tensor-parallel operations (splitting a model layer across GPUs)
- AllReduce during training
- Any operation where GPU A needs data that lives in GPU B's HBM

The practical result: when you run `nvidia-smi topo -m`, you will see two
different bandwidth numbers depending on whether the path is NVLink (fast,
~900 GB/s) or PCIe (slower, ~64 GB/s Gen5 x16). Model sharding strategy
follows this topology — you shard within NVLink domain first, then across nodes.

---

## IB rail topology — one NIC per GPU

```
GPU 0 ── PCIe ── CX-7 NIC 0 ──► IB Rail 0 → Leaf Switch → Spine
GPU 1 ── PCIe ── CX-7 NIC 1 ──► IB Rail 1 → Leaf Switch → Spine
GPU 2 ── PCIe ── CX-7 NIC 2 ──► IB Rail 2 → Leaf Switch → Spine
GPU 3 ── PCIe ── CX-7 NIC 3 ──► IB Rail 3 → Leaf Switch → Spine
GPU 4 ── PCIe ── CX-7 NIC 4 ──► IB Rail 4 → Leaf Switch → Spine
GPU 5 ── PCIe ── CX-7 NIC 5 ──► IB Rail 5 → Leaf Switch → Spine
GPU 6 ── PCIe ── CX-7 NIC 6 ──► IB Rail 6 → Leaf Switch → Spine
GPU 7 ── PCIe ── CX-7 NIC 7 ──► IB Rail 7 → Leaf Switch → Spine
```

Each GPU has its own dedicated NIC. Each NIC connects to a separate leaf switch.
This is called rail-optimized topology. The purpose: when GPU 0 on Node A does
AllReduce with GPU 0 on Node B, the traffic goes GPU 0 → NIC 0 → Rail 0 Leaf →
Spine → Rail 0 Leaf on Node B → NIC 0 → GPU 0. No shared uplink congestion with
GPUs 1-7 doing their own AllReduce simultaneously.

**Carrier analogy:** Think of each rail as a separate MPLS TE tunnel with reserved
bandwidth. Traffic engineering that's baked into the physical topology rather than
configured in software.

---

## Power architecture

```
DGX H100 total TDP: up to 10.2 kW

Power distribution:
  8× H100 SXM5 GPU:     ~700W each  =  5,600W
  4× NVSwitch 3.0:      ~50W each   =    200W
  8× ConnectX-7 NIC:    ~30W each   =    240W
  2× Intel Xeon CPU:    ~350W each  =    700W
  DIMMs, NVMe, fans:                =  ~460W
  ─────────────────────────────────────────────
  Total (approximate):               ~7,200W typical
                                     10,200W peak TDP

Power feeds: Dual PSU configuration, A+B feeds from separate PDUs
```

If you're designing the rack, plan for 208V 3-phase. A single DGX H100 can pull
enough current to make a 20A 120V circuit look embarrassing. You want dedicated
30A or 60A circuits, properly load-balanced across phases.

---

## Quick reference: port map

| Port | Interface | Speed | Purpose |
|------|-----------|-------|---------|
| NICs 0-7 | ConnectX-7 HCA | 400G NDR IB or 400GbE | Compute fabric (1 per GPU) |
| NICs 8-9 | ConnectX-7 HCA | 400GbE | Storage fabric |
| BMC | Dedicated 1GbE | 1GbE | OOB management (Redfish/IPMI) |
| PCIe slots | Gen5 x16 | ~64 GB/s | GPU-to-NIC DMA path |
| NVLink | NVSwitch 3.0 | 900 GB/s | GPU-to-GPU (internal only) |

---

## Files in this repo

```
topology/
  nvidia-smi-topo-expected.txt    Annotated healthy nvidia-smi topo -m output
  nvlink-adjacency-map.txt        GPU-to-NVSwitch connectivity matrix
  ib-rail-map.txt                 IB port-to-GPU-to-rail mapping

diagnostics/
  check-node-health.sh            Full node health check (run first)
  check-nvlink-bw.sh              NVLink bandwidth validation per GPU pair
  check-ib-ports.sh               IB port state, speed, and LID validation

reference/
  dgx-h100-specs.md               Full spec table and connector reference
  troubleshooting.md              Symptom → root cause → fix (NOC format)
  carrier-to-hpc-mapping.md       BGP → SM, ECMP → NVSwitch, and other translations
```

---

## Related plates

- Plate 02 — NVLink & NVSwitch
- Plate 03 — PFC / ECN / DCQCN
- Plate 06 — RDMA Packet Path

---

*Built by a carrier engineer who refused to stay in her lane.*  
*Questions, corrections, PRs welcome.*
