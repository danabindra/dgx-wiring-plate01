## SYMPTOM: Training job hangs at startup

**Cause 1:** NV Fabric Manager not running.

```bash
systemctl status nvidia-fabricmanager
systemctl enable --now nvidia-fabricmanager
nvidia-smi topo -m   # expect NV18 between all GPUs
```

**Cause 2:** NCCL falling back to sockets instead of IB.

```bash
export NCCL_DEBUG=INFO
python -c "import torch; torch.distributed.init_process_group('nccl')"
# "Using IB" = good, "Using Socket" = RDMA broken

ibstat | grep -E "State|Rate"   # all ports: Active, 400
```

---

## SYMPTOM: nvidia-smi topo -m shows PHB instead of NV18

NVLink unused between those pairs; AllReduce falls back to PCIe (~10-20x slower).

```bash
nvidia-smi topo -m
nvidia-smi nvlink -s -i 0   # look for "<Inactive>"
nvidia-smi nvlink -e -i 0   # errors > 0 → escalate to NVIDIA support

# Driver reload (last resort, kills running jobs)
modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia
modprobe nvidia
systemctl start nvidia-fabricmanager
```

---

## SYMPTOM: IB port State = Down or Polling

Physical link not established — bad cable, switch port down, or NIC fault.

```bash
ibstat | grep -A 5 "Port 1"
cat /sys/class/infiniband/mlx5_0/ports/1/state
# 4=Active 1=Down 2=Init 3=Armed
```

Physical checks: reseat cable both ends → verify switch port enabled (`show interface ib X/Y` on ONYX) → swap with known-good cable → if still down, NIC hardware.

---

## SYMPTOM: IB port Active but rate = 200 Gb/s (HDR), not 400 (NDR)

```bash
ibstat | grep Rate

# Causes: HDR cable not NDR; switch port configured HDR; auto-neg issue
mlxconfig -d /dev/mst/mt4129_pciconf0 set LINK_TYPE_P1=2
mlxcable --DDM --cable --port /dev/mst/mt4129_pciconf0_cable0
```

NDR requires OSFP or NDR-capable QSFP-DD.

---

## SYMPTOM: LID = 0 on ibstat

Subnet Manager hasn't assigned a LID — port is up but unmanaged.

```bash
sminfo                       # errors if no SM found
ps aux | grep opensm
systemctl status opensm
systemctl start opensm
# Wait 30-60s for fabric discovery
ibstat | grep "Base lid"     # should be non-zero
```

UFM users: check console for node discovery, logs at `/var/log/ufm/ufm.log`.

---

## SYMPTOM: NCCL busbw lower than expected

Expected: ~800-900 GB/s intra-node (8x H100), 200-350 GB/s inter-node.

```bash
# Single node
./build/all_reduce_perf -b 1G -e 8G -f 2 -g 8

# Multi-node
mpirun -np 16 -H node1:8,node2:8 \
  -x NCCL_IB_HCA=mlx5 -x NCCL_DEBUG=WARN \
  ./build/all_reduce_perf -b 1G -e 8G -f 2 -g 8
```

Intra-node low (<600): check `nvlink -s`, `topo -m` shows NV18, NCCL_P2P_DISABLE unset.
Inter-node low (<50%): check ibstat rates, switch counters, NCCL_IB_HCA, PFC/ECN config.

---

## SYMPTOM: GPU degraded in DCGM or nvidia-smi

```bash
dcgmi health -g 0 -j
dcgmi diag -r 1              # fast
dcgmi diag -r 2              # longer

nvidia-smi --query-gpu=index,ecc.errors.uncorrected.volatile.total --format=csv,noheader
# uncorrected > 0: nvidia-smi --gpu-reset -i <id>; if persists, hardware failure
```

---

## SYMPTOM: Node unreachable via SSH, BMC alive

```bash
ipmitool -I lanplus -H <bmc-ip> -U admin -P <pw> chassis status
ipmitool -I lanplus -H <bmc-ip> -U admin -P <pw> chassis power cycle
ipmitool -I lanplus -H <bmc-ip> -U admin -P <pw> sol activate

# Redfish
curl -sk -u admin:<pw> https://<bmc-ip>/redfish/v1/Systems/System.Embedded.1 | jq .PowerState
```

---

## Quick command reference

```bash
# GPU
nvidia-smi
nvidia-smi topo -m
nvidia-smi nvlink -s -i <gpu>
nvidia-smi nvlink -e -i <gpu>
nvidia-smi --query-gpu=index,ecc.errors.uncorrected.volatile.total --format=csv

# IB
ibstat [mlx5_0]
ibdev2netdev
ibv_devinfo
ibping -S | ibping -L <lid>

# Fabric / DCGM
systemctl status nvidia-fabricmanager
journalctl -u nvidia-fabricmanager -f
dcgmi discovery -l
dcgmi health -g 0
dcgmi diag -r 1
```
