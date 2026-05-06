#!/bin/bash
# Compare GC vs GC-free under low finish thresholds
# CS561 Spring 2026 - Ruoxi Cao
# Run this on the HOST (SCC), not inside the VM.
# Usage: bash sweep_low_threshold_gc_vs_gcfree.sh
#
# Prerequisites (one-time setup):
#   1. SSH key auth:     ssh-copy-id -p 8080 femu@localhost
#   2. Sudo no-passwd:   (inside VM) echo "femu ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/femu-nopasswd
#
# Requires: FEMU running with [FINISH] log instrumentation in zns.c
# Results: results/low_threshold_gc_vs_gcfree.csv

# ============================================================
# Config
# ============================================================
SSH="ssh -o BatchMode=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=20 -p 8080 femu@localhost"
FEMU_LOG="./log"                          # relative to confznsplusplus/build/
RESULTS_DIR="../../results"
CSV_FILE="$RESULTS_DIR/low_threshold_gc_vs_gcfree.csv"

ZBD="nvme0n1"
AUX_PATH="/tmp/zenfs-aux"
NUM_OPS=3000000
VALUE_SIZE=1024
KEY_SIZE=16
LOW_THRESHOLDS=(0 5 10 15 20 25 30)
GC_START_LEVEL=20                         # fixed GC trigger level for GC mode

# ============================================================
# Check SSH connectivity
# ============================================================
if ! $SSH "exit" 2>/dev/null; then
    echo "ERROR: Cannot connect to VM. Run the one-time setup first:"
    echo "  ssh-copy-id -p 8080 femu@localhost"
    echo "  (inside VM) echo 'femu ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/femu-nopasswd"
    exit 1
fi

# ============================================================
# Setup
# ============================================================
mkdir -p $RESULTS_DIR
echo "benchmark,num_ops,gc_mode,gc_start_level,finish_threshold,total_pages_to_write,finish_call_count,latency_micros_per_op,throughput_MB_per_s,timestamp" > $CSV_FILE

echo "================================================"
echo "  GC vs GC-free: Low Finish Threshold Sweep"
echo "  Thresholds: ${LOW_THRESHOLDS[*]}"
echo "  GC start level (GC mode only): $GC_START_LEVEL%"
echo "  $(date)"
echo "================================================"

for thresh in "${LOW_THRESHOLDS[@]}"; do
    for gc in false true; do
        GC_LEVEL_VAL=$( [ "$gc" = "true" ] && echo "$GC_START_LEVEL" || echo "N/A" )
        LOG="fillrandom_gc${gc}_thresh${thresh}_${NUM_OPS}.log"

        echo ""
        echo "--- Threshold: $thresh%, GC: $gc ---"

        # Clear FEMU log
        echo "  Clearing FEMU log..."
        > $FEMU_LOG

        # Reset zones and format ZenFS
        echo "  Resetting zones and formatting ZenFS..."
        $SSH "sudo rm -rf $AUX_PATH"
        $SSH "sudo nvme zns reset-zone -a /dev/$ZBD && \
            cd ~/rocksdb && \
            sudo ./plugin/zenfs/util/zenfs mkfs \
                --zbd=$ZBD \
                --aux_path=$AUX_PATH \
                --finish_threshold=$thresh \
                --enable_gc=$gc \
                --gc_start_level=$GC_START_LEVEL \
                --force 2>/dev/null"

        # Run fillrandom
        echo "  Running fillrandom..."
        $SSH "cd ~/rocksdb && sudo ./db_bench \
            --fs_uri=zenfs://dev:$ZBD \
            --benchmarks=fillrandom \
            --num=$NUM_OPS \
            --value_size=$VALUE_SIZE \
            --key_size=$KEY_SIZE \
            --compression_type=none \
            > $LOG 2>&1"

        BENCH_OUTPUT=$($SSH "cat ~/rocksdb/$LOG")

        # Parse pages_to_write from FEMU log
        STATS=$(grep -a "\[FINISH\] zone:" $FEMU_LOG \
            | tail -n +2 \
            | awk -F'pages_to_write: ' '{sum+=$2; count++} END {if (count>0) print sum, count; else print "0 0"}')

        SUM=$(echo $STATS | awk '{print $1}')
        COUNT=$(echo $STATS | awk '{print $2}')
        LATENCY=$(echo "$BENCH_OUTPUT" | grep "^fillrandom" | awk '{print $3}')
        THROUGHPUT=$(echo "$BENCH_OUTPUT" | grep "^fillrandom" | awk '{print $(NF-1)}')
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

        echo "  pages_to_write: $SUM, finish_calls: $COUNT, latency: ${LATENCY} micros/op, throughput: ${THROUGHPUT} MB/s"
        echo "fillrandom,$NUM_OPS,$gc,$GC_LEVEL_VAL,$thresh,$SUM,$COUNT,$LATENCY,$THROUGHPUT,$TIMESTAMP" >> $CSV_FILE
    done
done

echo ""
echo "================================================"
echo "  Done. Results saved to: $CSV_FILE"
echo "================================================"
