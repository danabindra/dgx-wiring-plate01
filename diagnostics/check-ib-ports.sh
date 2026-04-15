#!/usr/bin/env bash
# check-ib-ports.sh — validate InfiniBand port state, physical state, rate, LID
set -uo pipefail

command -v ibstat &>/dev/null || { echo "ibstat not found"; exit 1; }

FAILURES=0
fail() { echo "FAIL: $1"; ((FAILURES++)); }
pass() { echo "PASS: $1"; }

CURRENT_CA=""
CURRENT_PORT=""

while IFS= read -r line; do
  if [[ "$line" =~ ^CA\ \'(mlx[0-9_]+)\' ]]; then
    CURRENT_CA="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ Port\ ([0-9]+): ]]; then
    CURRENT_PORT="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ State:\ ([A-Za-z]+) ]]; then
    S="${BASH_REMATCH[1]}"
    [[ "$S" == "Active" ]] && pass "$CURRENT_CA p$CURRENT_PORT State=$S" \
      || fail "$CURRENT_CA p$CURRENT_PORT State=$S"
  elif [[ "$line" =~ Physical\ state:\ ([A-Za-z\ ]+) ]]; then
    P=$(echo "${BASH_REMATCH[1]}" | xargs)
    [[ "$P" == "LinkUp" || "$P" == "Polling" ]] && pass "$CURRENT_CA p$CURRENT_PORT Phys=$P" \
      || fail "$CURRENT_CA p$CURRENT_PORT Phys=$P"
  elif [[ "$line" =~ Rate:\ ([0-9]+) ]]; then
    R="${BASH_REMATCH[1]}"
    if [[ "$R" -ge 400 ]]; then pass "$CURRENT_CA p$CURRENT_PORT Rate=${R}Gb/s"
    elif [[ "$R" -ge 200 ]]; then echo "WARN: $CURRENT_CA p$CURRENT_PORT Rate=${R}Gb/s (expected 400)"
    else fail "$CURRENT_CA p$CURRENT_PORT Rate=${R}Gb/s"
    fi
  elif [[ "$line" =~ Base\ lid:\ ([0-9]+) ]]; then
    L="${BASH_REMATCH[1]}"
    [[ "$L" -gt 0 ]] && pass "$CURRENT_CA p$CURRENT_PORT LID=$L" \
      || fail "$CURRENT_CA p$CURRENT_PORT LID=0 (no SM)"
  fi
done < <(ibstat)

# Device-to-netdev mapping
command -v ibdev2netdev &>/dev/null && ibdev2netdev || ls /sys/class/infiniband/ 2>/dev/null

# RDMA device summary
command -v ibv_devinfo &>/dev/null && \
  ibv_devinfo | grep -E "hca_id|port:|state:|active_width:|active_speed:"

echo "Failures: $FAILURES"
[[ "$FAILURES" -eq 0 ]]
