#!/usr/bin/env bash
# Serial processes avoid variants competing for CPU or sharing a JS heap.
set -euo pipefail
cd -- "$(dirname -- "$0")"
mkdir -p results
export EYG_TUI_BENCH_REVISION=$(git rev-parse HEAD)
for trial in 1 2 3 4 5; do
  case "$trial" in
    1|5) variants=(typescript core signals lustre) ;;
    2) variants=(core signals lustre typescript) ;;
    3) variants=(signals lustre typescript core) ;;
    4) variants=(lustre typescript core signals) ;;
  esac
  for workload in stream typing; do
    for rows in 20 200; do
      for variant in "${variants[@]}"; do
        output="results/${variant}-${workload}-${rows}-${trial}"
        bun bench.mjs "$variant" "$workload" "$rows" "$trial" > "$output.json" 2> "$output.log"
      done
    done
  done
  printf 'Finished trial %s of 5\n' "$trial"
done
