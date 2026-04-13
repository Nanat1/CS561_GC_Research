#!/bin/bash
# Record results/pages_to_write on zone FINISH across finish thresholds
# CS561 Spring 2026 - Ruoxi Cao
# Run this on the HOST (SCC), not inside the VM.
# Usage: bash record_pages_to_write.sh
#
# Prerequisites (one-time setup):
#   1. SSH key auth:     ssh-copy-id -p 8080 femu@localhost
#   2. Sudo no-passwd:   (inside VM) echo "femu ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/femu-nopasswd
#
# Requires: FEMU running with [FINISH] log instrumentation in zns.c
# Results: results/pages_to_write.csv

# ============================================================
# Config
# ============================================================
SSH="ssh -o BatchMode=yes -p 8080 femu@localhost"
FEMU_LOG="./log"                          # relative to confznsplusplus/build/
RESULTS_DIR="../../results"
CSV_FILE="$RESULTS_DIR/pages_to_write.csv"

ZBD="nvme0n1"
AUX_PATH="/tmp/zenfs-aux"
NUM_OPS=1000000
VALUE_SIZE=1024
KEY_SIZE=16
THRESHOLDS=(0 10 25 50 75 90)
GC_MODES=(false true)

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
echo "gc_mode,finish_threshold,finish_call_count,avg_pages_to_write,latency_micros_per_op,throughput_MB_per_s,timestamp" > $CSV_FILE

echo "================================================"
echo "  pages_to_write Recording Script"
echo "  $(date)"
echo "================================================"

for gc in "${GC_MODES[@]}"; do
    for thresh in "${THRESHOLDS[@]}"; do
        echo ""
        echo "--- GC: $gc, Threshold: $thresh% ---"

        # Clear previous FINISH log entries
        echo "  Clearing FEMU log..."
        > $FEMU_LOG

        # Reset zones and format ZenFS inside VM
        echo "  Resetting zones and formatting ZenFS..."
        $SSH "sudo rm -rf $AUX_PATH"
        $SSH "sudo nvme zns reset-zone -a /dev/$ZBD && \
            cd ~/rocksdb && \
            sudo ./plugin/zenfs/util/zenfs mkfs \
                --zbd=$ZBD \
                --aux_path=$AUX_PATH \
                --finish_threshold=$thresh \
                --enable_gc=$gc \
                --force 2>/dev/null"

        # Run fillrandom inside VM
        echo "  Running fillrandom..."
        BENCH_OUTPUT=$($SSH "cd ~/rocksdb && sudo ./db_bench \
            --fs_uri=zenfs://dev:$ZBD \
            --benchmarks=fillrandom \
            --num=$NUM_OPS \
            --value_size=$VALUE_SIZE \
            --key_size=$KEY_SIZE \
            --compression_type=none 2>&1")

        # Parse pages_to_write from FEMU log
        STATS=$(grep -a "\[FINISH\] pages_to_write:" $FEMU_LOG \
            | awk -F'pages_to_write: ' '{sum+=$2; count++} END {if (count>0) print count, sum/count; else print "0 N/A"}')

        COUNT=$(echo $STATS | awk '{print $1}')
        AVG=$(echo $STATS | awk '{print $2}')
        LATENCY=$(echo "$BENCH_OUTPUT" | grep "^fillrandom" | awk '{print $3}')
        THROUGHPUT=$(echo "$BENCH_OUTPUT" | grep "^fillrandom" | awk '{print $NF}')
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

        echo "  finish_calls: $COUNT, avg pages_to_write: $AVG, latency: ${LATENCY} micros/op, throughput: ${THROUGHPUT} MB/s"
        echo "$gc,$thresh,$COUNT,$AVG,$LATENCY,$THROUGHPUT,$TIMESTAMP" >> $CSV_FILE
    done
done

echo ""
echo "================================================"
echo "  Done. Results saved to: $CSV_FILE"
echo "================================================"
