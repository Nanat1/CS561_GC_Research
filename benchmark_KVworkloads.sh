#!/bin/bash
# ZNS Benchmarking Framework - KVBench Adapted
# CS561 Spring 2026

# Workload Approximation:
# We approximated the KVBench workloads using RocksDB's db_bench tool with ZenFS backend. Due to db_bench's built-in benchmark design, some workload characteristics were approximated:
# Operation mixes were controlled via --benchmarks, --reads, and --delete_fraction flags.
# Key distributions were set globally via --distribution (uniform/zipfian); beta/normal distributions were approximated with uniform.
# Empty point queries were simulated via --existing_keys_fraction.
# Prefix skew was approximated via --prefix_size + zipfian distribution.
# Range deletes (KVBench-IV) were approximated with point deletes due to tool limitations.
# These approximations are sufficient for studying the finish threshold vs. GC tradeoff, which is the core focus of our project.

# Configuration
ZBD="nvme0n1"
AUX_PATH="/tmp/zenfs-aux"
RESULTS_DIR="$HOME/results/$(date +%Y%m%d_%H%M%S)"
mkdir -p $RESULTS_DIR

NUM_OPS=100000
VALUE_SIZE=4096
KEY_SIZE=16
THRESHOLDS=(10 25 50 75 90)
GC_MODES=("false" "true")

# KVBench workload definitions
declare -A WORKLOADS
WORKLOADS["kvbench-I"]="--benchmarks=readrandom --existing_keys_fraction=0.2 --distribution=uniform"
WORKLOADS["kvbench-II"]="--benchmarks=fillrandom,readrandom,updaterandom,deleterandom --reads=0.15 --delete_fraction=0.118 --distribution=uniform"
WORKLOADS["kvbench-III"]="--benchmarks=updaterandom,readrandom --reads=0.5 --existing_keys_fraction=0.5 --distribution=zipfian --distribution_zipfian_alpha=1.1"
WORKLOADS["kvbench-IV"]="--benchmarks=updaterandom,deleterandom --delete_fraction=1.0 --distribution=zipfian --distribution_zipfian_alpha=1.1"
WORKLOADS["kvbench-V"]="--benchmarks=fillrandom,readrandom --reads=0.05 --distribution=zipfian --distribution_zipfian_alpha=1.1 --prefix_size=8"

echo "================================================"
echo "  KVBench-adapted ZNS Benchmarking"
echo "  $(date)"
echo "================================================"

# Preloading function (for workloads that need it)
preload_data() {
    echo "  Preloading $NUM_OPS keys..."
    sudo ./plugin/zenfs/util/zenfs mkfs \
      --zbd=$ZBD \
      --aux_path=$AUX_PATH \
      --finish_threshold=90 \
      --enable_gc=false \
      --force 2>/dev/null
    
    sudo ./db_bench \
      --fs_uri=zenfs://dev:$ZBD \
      --benchmarks=fillrandom \
      --num=$NUM_OPS \
      --value_size=$VALUE_SIZE \
      --key_size=$KEY_SIZE \
      --distribution=uniform \
      --compression_type=none 2>&1 | tail -5
}

# Main experiment loop
for wl_name in "${!WORKLOADS[@]}"; do
    echo ""
    echo "=== Workload: $wl_name ==="
    
    # Preload for workloads that need existing data
    if [[ "$wl_name" =~ ^(kvbench-I|kvbench-III|kvbench-IV)$ ]]; then
        preload_data
    fi
    
    for gc in "${GC_MODES[@]}"; do
        for thresh in "${THRESHOLDS[@]}"; do
            echo "--- $wl_name: Threshold=$thresh%, GC=$gc ---"
            
            # Reset and format
            sudo nvme zns reset-zone -a /dev/$ZBD
            sudo ./plugin/zenfs/util/zenfs mkfs \
              --zbd=$ZBD \
              --aux_path=$AUX_PATH \
              --finish_threshold=$thresh \
              --enable_gc=$gc \
              --force 2>/dev/null
            
            # Run benchmark
            RESULT=$(sudo ./db_bench \
              --fs_uri=zenfs://dev:$ZBD \
              ${WORKLOADS[$wl_name]} \
              --num=$NUM_OPS \
              --value_size=$VALUE_SIZE \
              --key_size=$KEY_SIZE \
              --compression_type=none 2>&1)
            
            # Parse and save results
            THROUGHPUT=$(echo "$RESULT" | grep -oP '[\d.]+ MB/s' | head -1 | grep -oP '[\d.]+')
            OPS=$(echo "$RESULT" | grep -oP '[\d]+ ops/sec' | head -1 | grep -oP '[\d]+')
            TIME=$(echo "$RESULT" | grep -oP '[\d.]+ seconds' | head -1 | grep -oP '[\d.]+')
            
            echo "$wl_name,$thresh,$gc,$THROUGHPUT,$OPS,$TIME,$(date '+%Y-%m-%d %H:%M:%S')" >> "$RESULTS_DIR/results.csv"
            echo "  ✓ $THROUGHPUT MB/s, $OPS ops/sec"
            
            # Collect zone state for DLWA/Space Amp estimation
            sudo nvme zns report-zones /dev/$ZBD --output-format=json > "$RESULTS_DIR/zones_${wl_name}_thr${thresh}_gc${gc}.json"
        done
    done
done

echo ""
echo "================================================"
echo "  All experiments complete!"
echo "  Results: $RESULTS_DIR/results.csv"