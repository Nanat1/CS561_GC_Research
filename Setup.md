# Getting started

## 1. Project Structure

```bash
project/
  confznsplusplus/          # ConfZNS++
    build-femu/
  rocksdb/                  # RocksDB(with ZenFS)
  images/
    u20s.qcow2      # VM images(requested from femu)
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
# under confznsplusplus
mkdir build-femu && cd build-femu

# copy all the scripts from femu-scripts to build-femu
cp ../femu-scripts/femu-copy-scripts.sh . 
./femu-copy-scripts.sh .

# only Debian/Ubuntu based distributions supported (dependencies)
sudo ./pkgdep.sh

# compile
./femu-compile.sh
```

If you come across some warnings while compiling, modify `femu-compile.sh`:
```sh
# disable warning error
../configure --enable-kvm --target-list=x86_64-softmmu --disable-werror
```
Confirmation: 

```bash
ls -lh x86_64-softmmu/qemu-system-x86_64
```

### 2.3 Prepare VM image

A recommended way to get FEMU running quickly - Use Femu's VM image file. The iamge can be requested from this [form](https://docs.google.com/forms/d/e/1FAIpQLSdCyNTU7n-hwW1ODJ3i_q1vmS6eTT-V3c4vCL8ouYocNLhxvA/viewform). For my group members, I have already sent you email.

```bash
mkdir ../../images

cd ../../images

wget http://people.cs.uchicago.edu/~huaicheng/femu/femu-vm.tar.xz

tar xJvf femu-vm.tar.xz
```

After these steps, you will get two files: "u20s.qcow2" and "u20s.md5sum".

You can verify the integrity of the VM image file by doing:

```bash
md5sum u20s.qcow2 > tmp.md5sum

diff tmp.md5sum u20s.md5sum
```

If diff complains that the above two files differ, then the VM image file is corrupted. Please redo the above steps.

The user account and guest OS of the VM:

- username: femu

- passwd : femu

- Guest OS: Ubuntu 20.04.1 server, with kernel 5.4

### 2.4 Run the device

```bash
cd confznsplusplus/build-fem
./run-zns.sh
```

To run the script properly, update the VM image path in `run-zns.sh` to point to your local qcow2 file. For example, if you run this script under `build-femu`: 

```sh
OSIMGF="../../images/u20s.qcow2"
```

## 3. Build Rocksdb with ZenFS

The following steps should be performed inside the guest VM after ConfZNS++ is launched successfully.

See the ZenFS [README.md](https://github.com/westerndigitalcorporation/zenfs/blob/master/README.md) for detailed instructions.

First we login in the guest OS installed above:
```
ssh -p8080 $femu@localhost
```
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
git clone --branch v8.9.1 https://github.com/facebook/rocksdb.git
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

