# DGX H100 Specifications Reference
# Plate 01 · DGX Node Wiring
# Verified: April 2026

---

## GPU

| Spec | Value |
|------|-------|
| GPU model | NVIDIA H100 SXM5 |
| GPU count | 8 |
| Architecture | Hopper (GH100) |
| CUDA cores | 16,896 per GPU |
| Tensor cores | 528 per GPU (4th gen) |
| HBM3 per GPU | 80 GB |
| HBM3 bandwidth | 3.35 TB/s per GPU |
| Total GPU memory | 640 GB |
| FP8 (tensor) | 3,958 TFLOPS (w/ sparsity) |
| FP16 (tensor) | 1,979 TFLOPS (w/ sparsity) |
| BF16 (tensor) | 1,979 TFLOPS (w/ sparsity) |
| FP32 (tensor) | 989 TFLOPS |
| FP64 (tensor) | 66.9 TFLOPS |
| TDP per GPU | ~700W |
| Form factor | SXM5 (mezzanine) |

---

## NVLink / NVSwitch

| Spec | Value |
|------|-------|
| NVSwitch generation | NVSwitch 3.0 |
| NVSwitch count | 4 |
| NVLink version | NVLink 4.0 |
| NVLink connections per GPU | 18 |
| NVLink bandwidth per GPU | 900 GB/s bidirectional |
| NVLink total bisection BW | 3.6 TB/s |
| Topology | Full all-to-all (non-blocking) |
| Fabric management | nvidia-fabricmanager |

---

## Compute NICs (per GPU fabric)

| Spec | Value |
|------|-------|
| NIC model | NVIDIA ConnectX-7 |
| NIC count (compute) | 8 |
| Speed | 400 Gb/s NDR InfiniBand or 400GbE |
| PCIe interface | PCIe Gen5 x16 |
| PCIe bandwidth | ~64 GB/s per NIC |
| GPUDirect RDMA | Supported |
| Rail assignment | 1 NIC per GPU (rail-optimized) |
| RDMA engine | On-chip, kernel-bypass |

---

## Storage NICs

| Spec | Value |
|------|-------|
| NIC model | NVIDIA ConnectX-7 |
| NIC count (storage) | 2 |
| Speed | 400GbE |
| Purpose | NVMe-oF, Lustre, VAST, GPFS |
| GPUDirect Storage | Supported |

---

## CPU

| Spec | Value |
|------|-------|
| CPU model | Intel Xeon Platinum 8480C |
| Socket count | 2 |
| Cores per CPU | 60 |
| Total cores | 120 (240 threads) |
| L3 cache per CPU | 105 MB |
| Memory channels | 8 per socket |
| TDP | 350W per CPU |

---

## System Memory

| Spec | Value |
|------|-------|
| Total capacity | 2 TB |
| Type | DDR5 ECC |
| Speed | 4800 MT/s |
| Channels | 16 total (8 per socket) |

---

## Storage (internal)

| Spec | Value |
|------|-------|
| OS drive | 2× 1.92 TB NVMe SSD (RAID 1) |
| Scratch/cache | 8× 3.84 TB NVMe SSD |
| Total NVMe | ~32 TB raw |

---

## Power

| Spec | Value |
|------|-------|
| Total system TDP | 10.2 kW |
| PSU configuration | Redundant N+1 |
| Input voltage | 200-240V AC |
| Input current | ~40A at 240V (typical load) |
| Power connector | C19 |
| Recommended circuit | 60A 3-phase or 2× 30A single-phase |

---

## Physical

| Spec | Value |
|------|-------|
| Form factor | 10U rackmount |
| Weight | ~133 kg (~293 lbs) |
| Depth | 896 mm |
| Cooling | Forced air (front-to-rear) |
| Acoustic | High (plan for datacenter, not office) |

---

## Network port map (rear panel, left to right)

```
[BMC 1GbE][OOB Mgmt]  ← Always-on, OOB management

[mlx5_8 400GbE]       ← Storage NIC 0
[mlx5_9 400GbE]       ← Storage NIC 1

[mlx5_0 400G NDR]     ← Compute NIC 0 → GPU 0 → Rail 0
[mlx5_1 400G NDR]     ← Compute NIC 1 → GPU 1 → Rail 1
[mlx5_2 400G NDR]     ← Compute NIC 2 → GPU 2 → Rail 2
[mlx5_3 400G NDR]     ← Compute NIC 3 → GPU 3 → Rail 3
[mlx5_4 400G NDR]     ← Compute NIC 4 → GPU 4 → Rail 4
[mlx5_5 400G NDR]     ← Compute NIC 5 → GPU 5 → Rail 5
[mlx5_6 400G NDR]     ← Compute NIC 6 → GPU 6 → Rail 6
[mlx5_7 400G NDR]     ← Compute NIC 7 → GPU 7 → Rail 7
```

---

## Key firmware / driver versions (verify before deployment)

```bash
# NVIDIA driver
nvidia-smi | grep "Driver Version"

# NVLink firmware
nvidia-smi --query-gpu=index,vbios.version --format=csv

# ConnectX firmware
mlxfwmanager --query

# Check OFED version
ofed_info | head -5

# Recommended: MOFED 23.x or later for NDR support
```

---

*Source: NVIDIA DGX H100 System Architecture documentation.*
*Cross-referenced with NVIDIA DGX H100 User Guide, April 2026.*
