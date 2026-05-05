#!/bin/bash
# Record results/pages_to_write on zone FINISH across gc_start_level values
# CS561 Spring 2026 - Ruoxi Cao
# Run this on the HOST (SCC), not inside the VM.
# Usage: bash record_gc_start_level.sh
#
# Prerequisites (one-time setup):
#   1. SSH key auth:     ssh-copy-id -p 8080 femu@localhost
#   2. Sudo no-passwd:   (inside VM) echo "femu ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/femu-nopasswd
#
# Requires: FEMU running with [FINISH] log instrumentation in zns.c
# Results: results/gc_start_level.csv

# ============================================================
# Config
# ============================================================
SSH="ssh -o BatchMode=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=20 -p 2222 femu@localhost"
FEMU_LOG="./log"                          # relative to confznsplusplus/build/
RESULTS_DIR="../../results"
CSV_FILE="$RESULTS_DIR/gc_start_level.csv"

ZBD="nvme0n1"
AUX_PATH="/tmp/zenfs-aux"
NUM_OPS=3000000
VALUE_SIZE=1024
KEY_SIZE=16
FINISH_THRESHOLD=60                       # fixed; adjust if needed
GC_LEVELS=(0 20 40 50 60 70 80 90)

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
echo "finish_threshold,gc_start_level,total_pages_to_write,finish_call_count,latency_micros_per_op,throughput_MB_per_s,timestamp" > $CSV_FILE

echo "================================================"
echo "  gc_start_level Recording Script"
echo "  finish_threshold fixed at: $FINISH_THRESHOLD%"
echo "  $(date)"
echo "================================================"

for level in "${GC_LEVELS[@]}"; do
    echo ""
    echo "--- Threshold: $FINISH_THRESHOLD%, GC Start Level: $level% ---"

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
            --finish_threshold=$FINISH_THRESHOLD \
            --enable_gc=true \
            --gc_start_level=$level \
            --force 2>/dev/null"

    # Run fillrandom inside VM
    # 第一阶段：fillrandom（预热，不记录）
    echo "  Running fillrandom (warmup)..."
    $SSH "cd ~/rocksdb && sudo ./db_bench \
        --fs_uri=zenfs://dev:$ZBD \
        --benchmarks=fillrandom \
        --num=$NUM_OPS \
        --value_size=$VALUE_SIZE \
        --key_size=$KEY_SIZE \
        --compression_type=none \
        --disable_auto_compactions=true \
        --level0_file_num_compaction_trigger=999999 \
        --level0_slowdown_writes_trigger=999999 \
        --level0_stop_writes_trigger=999999 \
        > /dev/null 2>&1"

    # 清空 log，只记录 overwrite 阶段
    echo "  Clearing FEMU log before overwrite..."
    > $FEMU_LOG

    # 第二阶段：overwrite（正式记录）
    echo "  Running overwrite..."
    $SSH "cd ~/rocksdb && sudo ./db_bench \
        --fs_uri=zenfs://dev:$ZBD \
        --benchmarks=overwrite \
        --use_existing_db=true \
        --num=$NUM_OPS \
        --value_size=$VALUE_SIZE \
        --key_size=$KEY_SIZE \
        --disable_auto_compactions=true \
        --level0_file_num_compaction_trigger=999999 \
        --level0_slowdown_writes_trigger=999999 \
        --level0_stop_writes_trigger=999999 \
        --compression_type=none > overwrite_${NUM_OPS}_${level}.log 2>&1"

    BENCH_OUTPUT=$($SSH "cat ~/rocksdb/overwrite_${NUM_OPS}_${level}.log")

    # Parse pages_to_write from FEMU log
    STATS=$(grep -a "\[FINISH\] zone:" $FEMU_LOG \
        | tail -n +2 \
        | awk -F'pages_to_write: ' '{sum+=$2; count++} END {if (count>0) print sum, count, sum/count; else print "0 0 N/A"}')

    SUM=$(echo $STATS | awk '{print $1}')
    COUNT=$(echo $STATS | awk '{print $2}')
    LATENCY=$(echo "$BENCH_OUTPUT" | grep "^overwrite" | awk '{print $3}')
    THROUGHPUT=$(echo "$BENCH_OUTPUT" | grep "^overwrite" | awk '{print $(NF-1)}')
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    echo "  pages_to_write: $SUM, finish_calls: $COUNT, latency: ${LATENCY} micros/op, throughput: ${THROUGHPUT} MB/s"
    echo "$FINISH_THRESHOLD,$level,$SUM,$COUNT,$LATENCY,$THROUGHPUT,$TIMESTAMP" >> $CSV_FILE
done

echo ""
echo "================================================"
echo "  Done. Results saved to: $CSV_FILE"
echo "================================================"