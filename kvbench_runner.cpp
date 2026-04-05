// kvbench_runner.cpp
#include <rocksdb/db.h>
#include <rocksdb/options.h>
#include <rocksdb/slice.h>
#include <iostream>
#include <fstream>
#include <string>
#include <chrono>

int main(int argc, char** argv) {
    if (argc != 3) {
        std::cerr << "Usage: " << argv[0] << " <workload.txt> <db_path>" << std::endl;
        return 1;
    }
    
    std::string workload_file = argv[1];
    std::string db_path = argv[2];
    
    // RocksDB Options
    rocksdb::Options options;
    options.create_if_missing = true;
    options.use_direct_io_for_flush_and_compaction = true;
    
    rocksdb::DB* db;
    rocksdb::Status status = rocksdb::DB::Open(options, db_path, &db);
    if (!status.ok()) {
        std::cerr << "Failed to open DB: " << status.ToString() << std::endl;
        return 1;
    }
    
    // Statistics
    long inserts = 0, updates = 0, queries = 0, deletes = 0;
    auto start = std::chrono::high_resolution_clock::now();
    
    // Read & Execute workload
    std::ifstream wf(workload_file);
    std::string line;
    while (std::getline(wf, line)) {
        if (line.empty()) continue;
        
        char op = line[0];
        std::string kv = line.substr(1);
        size_t delim = kv.find(' ');
        std::string key = kv.substr(0, delim);
        std::string value = (delim != std::string::npos) ? kv.substr(delim + 1) : "";
        
        rocksdb::Slice k(key);
        rocksdb::Slice v(value);
        
        // 
        switch (op) {
            case 'I': {  // Insert
                db->Put(rocksdb::WriteOptions(), k, v);
                inserts++;
                break;
            }
            case 'U': {  // Update
                db->Put(rocksdb::WriteOptions(), k, v);
                updates++;
                break;
            }
            case 'Q': {  // Query
                std::string result;
                db->Get(rocksdb::ReadOptions(), k, &result);
                queries++;
                break;
            }
            case 'D': {  // Delete
                db->Delete(rocksdb::WriteOptions(), k);
                deletes++;
                break;
            }
            default:
                std::cerr << "Unknown operation: " << op << std::endl;
                break;
        }
    }
    
    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();
    
    // Output
    std::cout << "=== Performance Summary ===" << std::endl;
    std::cout << "Inserts: " << inserts << std::endl;
    std::cout << "Updates: " << updates << std::endl;
    std::cout << "Queries: " << queries << std::endl;
    std::cout << "Deletes: " << deletes << std::endl;
    std::cout << "Total Time: " << duration << " ms" << std::endl;
    if (duration > 0) {
        std::cout << "Throughput: " << (inserts + updates + queries + deletes) * 1000.0 / duration << " ops/s" << std::endl;
    }
    
    delete db;
    return 0;
}