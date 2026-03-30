#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ ! -x ./crazy_t3 ]]; then
  make
fi

RINGS=(64 128 256 512 1024)
TRACES=(1 3 10 32 64 128 256)
SEED="${1:-12345}"
USE_GPU="${2:-0}"

echo "ring,ticks,seed,traces,elapsed_us,carry,fp,trace_density,distinct_core,distinct_trace"

for ring in "${RINGS[@]}"; do
  ticks=$(( ring * 8 ))
  for traces in "${TRACES[@]}"; do
    if (( traces > ring )); then
      continue
    fi
    ./crazy_t3 "$ring" "$ticks" "$SEED" "$traces" 1 "$USE_GPU"
  done
done
