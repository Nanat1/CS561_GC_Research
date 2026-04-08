#!/bin/bash
# ZNS Benchmarking Framework
# CS561 Spring 2026 - Shawna Liu
# Usage: sudo bash benchmark_framework.sh

# Configuration
ZBD="nvme0n1"
AUX_PATH="/tmp/zenfs-aux"
RESULTS_DIR="$HOME/results"
RAW_DIR="$RESULTS_DIR/raw"
CSV_FILE="$RESULTS_DIR/results.csv"
NUM_OPS=1000000
VALUE_SIZE=1024
KEY_SIZE=16
THRESHOLDS=(0 10 25 50 75 90)
GC_MODES=("false" "true")
BENCHMARKS=("fillrandom" "readrandom")

# Setup
mkdir -p "$RESULTS_DIR" "$RAW_DIR"
echo "finish_threshold,gc_enabled,benchmark,raw_output_file,timestamp" > "$CSV_FILE"

echo "================================================"
echo "  ZNS Benchmarking Framework"
echo "  $(date)"
echo "================================================"

for gc in "${GC_MODES[@]}"; do
  for thresh in "${THRESHOLDS[@]}"; do
    echo ""
    echo "--- Threshold: $thresh%, GC: $gc ---"

    # Reset zones
    echo "  Resetting zones..."
    sudo nvme zns reset-zone -a /dev/$ZBD

    # Format ZenFS
    echo "  Formatting ZenFS..."
    sudo ./plugin/zenfs/util/zenfs mkfs \
      --zbd=$ZBD \
      --aux_path=$AUX_PATH \
      --finish_threshold=$thresh \
      --enable_gc=$gc \
      --force 2>/dev/null

    # Run each benchmark
    for bench in "${BENCHMARKS[@]}"; do
      echo "  Running $bench..."
      TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
      FILE_TAG=$(date '+%Y%m%d_%H%M%S')
      RAW_FILE="$RAW_DIR/thresh${thresh}_gc${gc}_${bench}_${FILE_TAG}.txt"

      # Write header metadata into the raw file for traceability
      {
        echo "# ZNS Benchmark Raw Output"
        echo "# timestamp: $TIMESTAMP"
        echo "# finish_threshold: $thresh"
        echo "# gc_enabled: $gc"
        echo "# benchmark: $bench"
        echo "# num_ops: $NUM_OPS"
        echo "# value_size: $VALUE_SIZE"
        echo "# key_size: $KEY_SIZE"
        echo "# ------------------------------------------------"
      } > "$RAW_FILE"

      # Run db_bench and append full output (stdout + stderr)
      sudo ./db_bench \
        --fs_uri=zenfs://dev:$ZBD \
        --benchmarks=$bench \
        --num=$NUM_OPS \
        --value_size=$VALUE_SIZE \
        --key_size=$KEY_SIZE \
        --compression_type=none >> "$RAW_FILE" 2>&1

      # Record metadata in CSV
      echo "$thresh,$gc,$bench,$RAW_FILE,$TIMESTAMP" >> "$CSV_FILE"
      echo "  Saved raw output -> $RAW_FILE"
    done
  done
done

echo ""
echo "================================================"
echo "  Benchmarking complete!"
echo "  Raw outputs: $RAW_DIR"
echo "  Index CSV:   $CSV_FILE"
echo "================================================"