# Getting started

## 1. Directory

```bash
project/
  confznsplusplus/          # ConfZNS++
  rocksdb/                  # RocksDB (with ZenFS)
  images/
    ubuntu-22.04.qcow2      # VM images
  results/
  README.md
```

## 2. Get and Compile ConfZNS++

### 2.1 

```bash
git clone https://github.com/stonet-research/confznsplusplus.git
cd confznsplusplus
```

### 2.2 Compile QEMU (ConfZNS++)

```bash
cd confznsplusplus
mkdir build_femu && cd build_femu

# copy all the scripts from femu-scripts to build-femu
cp ../femu-scripts/femu-copy-scripts.sh . 
./femu-copy-scripts.sh .

# only Debian/Ubuntu based distributions supported (dependencies)
./pkgdep.sh

# compile
./femu-compile.sh
```

Confirmation: 

```bash
ls -lh x86_64-softmmu/qemu-system-x86_64
```

### 2.3 Prepare Ubuntu VM image(qcow2)

```bash
# under the confznsplusplus directory
mkdir images 
cd images

wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img \
-O ubuntu-22.04.qcow2

# create VM overlay(optional)
apt install -y qemu-utils
qemu-img create -f qcow2 -F qcow2 -b ubuntu-22.04.qcow2 vm.qcow2
```

### 2.4 Run the device

```bash
./run-zns.sh
```

To run the script properly, one must substitute the address of the virtual machine with their own:

```sh
# Project root = parent dir of this script (femu-scripts/..)
PROJROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

IMGDIR="$PROJROOT/images"
OSIMGF="$IMGDIR/vm.qcow2"
```

## 3. Build Rocksdb with ZenFS

See the ZenFS [README.md](https://github.com/westerndigitalcorporation/zenfs/blob/master/README.md) for detailed instructions.

```bash
# Download, build and install libzbd
git clone https://github.com/westerndigitalcorporation/libzbd.git
cd libzbd
sh ./autogen.sh
./configure
make
sudo make install
sudo ldconfig

# download rocksdb and zenfs
git clone https://github.com/facebook/rocksdb.git
cd rocksdb
git clone https://github.com/westerndigitalcorporation/zenfs plugin/zenfs

# compile and install rocksdb with zenfs
# if the terminal is killed, lower down the parallelism (-j2)
DEBUG_LEVEL=0 ROCKSDB_PLUGINS=zenfs make -j"$(nproc)" db_bench

# compile zenfs
make
 
# verify
cd ../../..
ls db_bench
ls plugin/zenfs/util/zenfs
```

