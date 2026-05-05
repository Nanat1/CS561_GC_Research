#!/bin/bash
set -e

# Install libzbd (required by ZenFS)
git clone https://github.com/westerndigitalcorporation/libzbd.git ~/libzbd
cd ~/libzbd
sh ./autogen.sh && ./configure && make
sudo make install && sudo ldconfig

# Configure git identity (required to create annotated tags)
git config --global user.email "ruoxicao@bu.edu"
git config --global user.name "Rosalie"

# Clone RocksDB
git clone --branch v8.9.1 https://github.com/facebook/rocksdb.git ~/rocksdb
cd ~/rocksdb

# Clone ZenFS fork
git clone https://github.com/ruoxicao77i/zenfs.git plugin/zenfs

# zenfs.mk uses git describe to generate version; requires an annotated tag
cd plugin/zenfs
git tag -a v0.0-research -m "research fork"
cd ~/rocksdb

# Compile RocksDB with ZenFS
DEBUG_LEVEL=0 ROCKSDB_PLUGINS=zenfs make -j$(nproc) db_bench
sudo make install

# Compile ZenFS utility
cd plugin/zenfs/util
make LDFLAGS=-lzbd

echo "Setup complete."
echo "  ~/rocksdb/db_bench"
echo "  ~/rocksdb/plugin/zenfs/util/zenfs"
