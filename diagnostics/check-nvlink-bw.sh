#!/usr/bin/env bash
# check-nvlink-bw.sh — validate NVLink P2P bandwidth and error counters
set -euo pipefail

# P2P capability matrix
nvidia-smi topo -p2p r
nvidia-smi topo -p2p n

# NVLink throughput sample (5s)
nvidia-smi dmon -s u -d 1 -c 5

# Error counters across GPUs 0-7
TOTAL_ERRORS=0
for i in $(seq 0 7); do
  echo "GPU $i:"
  ERRORS=$(nvidia-smi nvlink -e -i "$i" | tee /dev/stderr | \
    grep -E "Replay|Recovery|CRC|Fatal" | awk '{sum += $NF} END {print sum+0}')
  TOTAL_ERRORS=$((TOTAL_ERRORS + ERRORS))
done

# P2P bandwidth test if cuda-samples available
BWTEST=$(find /usr /opt /home -name "bandwidthTest" -type f 2>/dev/null | head -1)
if [[ -n "$BWTEST" ]]; then
  "$BWTEST" --mode=P2P --htod=0 --dtoh=0
fi

echo "Total NVLink errors: $TOTAL_ERRORS"
[[ "$TOTAL_ERRORS" -eq 0 ]]
