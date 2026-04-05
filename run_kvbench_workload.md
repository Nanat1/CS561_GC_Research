# Get the file kvbench_runner.cpp
This is a script for running kvbench

# Make the executable for the script
    cd ~/rocksdb
    g++ -std=c++17 -I. -Iinclude kvbench_runner.cpp     -L. -lrocksdb -lstdc++ -lpthread -ldl    r

# Run the generated workload
    ./kvbench_runner ../workloads/kvbench-II-interleaved.txt /tmp/kvbench-test-db
                    # The forst argument is where the workload is saved, adjust file name & path accordingly
                                                            # The second argument is where the temporary data will be saved to 
                                                            # This folder will be generated automatically

# Output
    === Performance Summary ===
    Inserts: 50000
    Updates: 25000
    Queries: 15000
    Deletes: 10000
    Total Time: 305 ms
    Throughput: 327869 ops/s

# I am working on making it calculate amplification as well.