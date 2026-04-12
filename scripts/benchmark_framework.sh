#!/bin/bash
# ZNS Benchmarking Framework
# CS561 Spring 2026 - Shawna Liu
# Usage: sudo bash benchmark_framework.sh

# Configuration
ZBD="nvme0n1"
AUX_PATH="/tmp/zenfs-aux"
RESULTS_DIR="$HOME/results"
CSV_FILE="$RESULTS_DIR/results.csv"
NUM_OPS=1000000
VALUE_SIZE=1024
KEY_SIZE=16
THRESHOLDS=(0 10 25 50 75 90)
GC_MODES=("false" "true")
BENCHMARKS=("fillrandom" "readrandom")

# Setup
mkdir -p $RESULTS_DIR
echo "finish_threshold,gc_enabled,benchmark,throughput_mb_s,latency_micros_op,ops_sec,total_time_s,timestamp" > $CSV_FILE

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
      RESULT=$(sudo ./db_bench \
        --fs_uri=zenfs://dev:$ZBD \
        --benchmarks=$bench \
        --num=$NUM_OPS \
        --value_size=$VALUE_SIZE \
        --key_size=$KEY_SIZE \
        --compression_type=none 2>&1 | grep "$bench")

      # Parse results
      THROUGHPUT=$(echo $RESULT | grep -oP '[\d.]+ MB/s' | grep -oP '[\d.]+' || echo "N/A")
      LATENCY=$(echo $RESULT | grep -oP '[\d.]+ micros/op' | grep -oP '[\d.]+')
      OPS=$(echo $RESULT | grep -oP '[\d]+ ops/sec' | grep -oP '[\d]+')
      TIME=$(echo $RESULT | grep -oP '[\d.]+ seconds' | grep -oP '[\d.]+' | head -1)
      TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

      # Save to CSV
      echo "$thresh,$gc,$bench,$THROUGHPUT,$LATENCY,$OPS,$TIME,$TIMESTAMP" >> $CSV_FILE
      echo "  $bench: $THROUGHPUT MB/s, $LATENCY micros/op"
    done
  done
done

echo ""
echo "================================================"
echo "  Benchmarking complete!"
echo "  Results saved to: $CSV_FILE"
