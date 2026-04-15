#!/usr/bin/env bash
# check-node-health.sh — full DGX H100 node health check
# Exit 0 = healthy, 1 = failures detected
set -uo pipefail

FAILURES=0
fail() { echo "FAIL: $1"; ((FAILURES++)); }
pass() { echo "PASS: $1"; }

# 1. Prerequisites
for cmd in nvidia-smi ibstat ibv_devinfo dcgmi; do
  command -v "$cmd" &>/dev/null || echo "WARN: $cmd not found"
done

# 2. GPU inventory (expect 8)
GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
[[ "$GPU_COUNT" -eq 8 ]] && pass "GPU count $GPU_COUNT" || fail "GPU count $GPU_COUNT (expected 8)"

# Persistence mode per GPU
nvidia-smi --query-gpu=index,persistence_mode --format=csv,noheader | \
  while IFS=',' read -r idx pm; do
    [[ "$(echo $pm | tr -d ' ')" == "Enabled" ]] || echo "WARN: GPU$idx persistence OFF"
  done

# 3. NVLink link state per GPU (expect 18 active)
for i in $(seq 0 7); do
  INACTIVE=$(nvidia-smi nvlink -s -i "$i" | grep -c "Inactive" || true)
  TOTAL=$(nvidia-smi nvlink -s -i "$i" | grep -c "Link" || true)
  if [[ "$INACTIVE" -eq 0 && "$TOTAL" -eq 18 ]]; then
    pass "GPU$i NVLink $TOTAL/$TOTAL"
  else
    fail "GPU$i NVLink $((TOTAL-INACTIVE))/$TOTAL active"
  fi
done

# 4. NVLink error counters
for i in $(seq 0 7); do
  ERRORS=$(nvidia-smi nvlink -e -i "$i" | grep -E "Replay|Recovery|CRC" | \
    awk '{sum += $NF} END {print sum+0}')
  [[ "$ERRORS" -eq 0 ]] && pass "GPU$i errors clean" || fail "GPU$i errors=$ERRORS"
done

# 5. GPU topology — flag non-NVLink GPU pairs
TOPO_OUT=$(nvidia-smi topo -m)
BAD_PATHS=$(echo "$TOPO_OUT" | grep -E "^GPU[0-9]" | awk '{
  for(i=2;i<=NF;i++) if ($i=="PHB"||$i=="NODE"||($i=="SYS"&&i<=9))
    print "GPU"NR-1"->GPU"i-2": "$i
}')
[[ -z "$BAD_PATHS" ]] && pass "All GPU pairs use NVLink" || fail "Non-NVLink paths: $BAD_PATHS"

# 6. Fabric Manager
systemctl is-active --quiet nvidia-fabricmanager && \
  pass "fabricmanager active" || fail "fabricmanager inactive"

# 7. InfiniBand ports
if command -v ibstat &>/dev/null; then
  IB_COUNT=$(ibstat | grep -c "^CA ")
  [[ "$IB_COUNT" -ge 8 ]] && pass "IB devices=$IB_COUNT" || fail "IB devices=$IB_COUNT (expected >=8)"

  ibstat | grep -E "CA |State:|Rate:" | while read -r line; do
    if [[ "$line" == CA* ]]; then CA=$(echo "$line" | awk '{print $2}')
    elif [[ "$line" == *State:* ]]; then
      S=$(echo "$line" | awk '{print $2}')
      [[ "$S" == "Active" ]] && pass "$CA $S" || fail "$CA $S"
    elif [[ "$line" == *Rate:* ]]; then
      R=$(echo "$line" | awk '{print $2}')
      [[ "$R" == "400" ]] || echo "WARN: $CA rate ${R}Gb/s (expected 400)"
    fi
  done
fi

# 8. GPU memory (expect ~80GB HBM3)
nvidia-smi --query-gpu=index,memory.total --format=csv,noheader | \
  while IFS=',' read -r idx total; do
    t=$(echo "$total" | tr -d ' MiB')
    [[ "$t" -gt 80000 ]] && pass "GPU$idx mem ${t}MiB" || fail "GPU$idx mem ${t}MiB"
  done

# 9. DCGM Level 1 diagnostic
if command -v dcgmi &>/dev/null; then
  DCGM_OUT=$(dcgmi diag -r 1 2>&1)
  echo "$DCGM_OUT" | grep -qi "fail" && fail "DCGM diag failures" || pass "DCGM L1 passed"
fi

echo "Failures: $FAILURES"
[[ "$FAILURES" -eq 0 ]]
