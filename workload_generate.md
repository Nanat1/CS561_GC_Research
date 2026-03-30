# Steps to prepare generator of workload:
    # 1 Clone the generator
    git clone https://github.com/BU-DiSC/K-V-Workload-Generator.git
    cd K-V-Workload-Generator && make

    # 2 generate (verify)
    ./load_gen -I 10000

# KVBench-I: Empty PQ-heavy (preloading)
    # 20% non-empty PQ, 80% empty PQ | ZD=beta, ED=uniform
    # Generate file for Preload
        ./load_gen \
            -I 100000 \
            -E 8 -L 0.5 \
            --OP workloads/kvbench-I-preload.txt
    # Generate the workload
        ./load_gen \
            --PL \
            -Q 100000 \
            -Z 0.8 \
            --ED 0 \
            --ZD 2 \
            --ZD_BALPHA 2.0 \
            --ZD_BBETA 5.0 \
            --OP workloads/kvbench-I-query.txt

# KVBench-II: Interleaved Inserts, Deletes, PQs, Updates
    # 50% insert, 10% delete, 15% empty PQ, 25% update | ID=ED=UD=uniform
    ./load_gen \
        -I 50000 \
        -D 10000 \
        -Q 15000 \
        -Z 1.0 \
        -U 25000 \
        --ID 0 \
        --UD 0 \
        --ED 0 \
        --ZD 0 \
        --OP workloads/kvbench-II-interleaved.txt

# KVBench-III: Multi-distribution Update and PQ (Preloading)
    # 50% updates, 25% non-empty PQ, 25% empty PQ | UD=Zipfian, ED=ZD=uniform
    # Generate file for Preload
    ./load_gen \
        -I 100000 \
        -E 8 -L 0.5 \
        --OP workloads/kvbench-III-preload.txt
    # Generate the workload
    ./load_gen \
        --PL \
        -U 50000 \
        -Q 50000 \
        -Z 0.5 \
        --UD 3 \
        --UD_ZALPHA 1.1 \
        --ED 0 \
        --ZD 0 \
        --OP workloads/kvbench-III-multi-dist.txt

# KVBench-IV: Update and Range Delete-heavy (Preloading)
    # 50% updates, 50% range delete | UD=Zipfian
    # Generate file for Preload
    ./load_gen \
        -I 100000 \
        -E 8 -L 0.5 \
        --OP workloads/kvbench-IV-preload.txt
    # Generate the workload
    ./load_gen \
        --PL \
        -U 50000 \
        -R 50000 \
        -y 0.1 \
        --UD 3 \
        --UD_ZALPHA 1.1 \
        --OP workloads/kvbench-IV-update-rangedel.txt

# KVBench-V: Insert-heavy with Skewed Prefixes
    # 95% insert, 5% non-empty PQ | ID=Zipfian, ZD=uniform
    ./load_gen \
        -I 95000 \
        -Q 5000 \
        -Z 0 \
        --ID 3 \
        --ID_ZALPHA 1.1 \
        --ED 0 \
        --OP workloads/kvbench-V-insert-heavy.txt