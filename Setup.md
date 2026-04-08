# Getting started

## 1. Project Structure

```bash
project/
  confznsplusplus/          # ConfZNS++
    build/
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
mkdir build && cd build

# copy all the scripts from femu-scripts to build
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

A recommended way to get FEMU running quickly - Use Femu's VM image file. The iamge can be requested from this [form](https://docs.google.com/forms/d/e/1FAIpQLSdCyNTU7n-hwW1ODJ3i_q1vmS6eTT-V3c4vCL8ouYocNLhxvA/viewform). For my group members, I have already sent you email.h/f.

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
cd confznsplusplus/build
./run-zns.sh
```

To run the script properly, update the VM image path in `run-zns.sh` to point to your local qcow2 file. For example, if you run this script under `build`: 

```sh
OSIMGF="../../images/u20s.qcow2"
```


## 3. Configuring the ZNS Device

The ZNS device parameters are hardcoded in `confznsplusplus/hw/femu/zns/zns.c`. After every modification, you must recompile before running experiments.

### 3.1 Key Parameters

There are **two files** that control ZNS device behavior:

**Zone size** (inside `confznsplusplus/hw/femu/femu.c`, around line 749):
```c
DEFINE_PROP_UINT64("zns_zonesize", FemuCtrl, zns_params.zone_size, (64 * MiB)),
```

**Active and open zone limits** (inside `zns_init_zone_cap()` in `zns.c`, around line 1969):
```c
n->max_active_zones = 0;   // 0 = unlimited (not realistic)
n->max_open_zones   = 0;   // 0 = unlimited (not realistic)
```

> **Note**: Do NOT modify `ZNS_ZONE_SIZE_BYTES` in `zns.c` — this macro is not used at runtime and changing it has no effect.

### 3.2 Parameter Relationships

The three parameters must satisfy this constraint at all times:

```
num_zones ≥ max_active_zones ≥ max_open_zones
```

Where `num_zones` is computed automatically at runtime:
```c
n->num_zones = ns->size / lbasz / n->zone_size;
// e.g. 4096MB / 64MB = 64 zones
```

> **Important**: Setting `max_active_zones = 0` causes the emulator to skip all active zone limit checks, which does not reflect real ZNS device behavior. Always set a non-zero value for experiments.

### 3.3 Experiment Configurations

| | Small-zone | Large-zone |
|---|---|---|
| `zone_size` (femu.c) | `64 * MiB` | `256 * MiB` |
| `num_zones` (auto) | 64 | 16 |
| `max_active_zones` (zns.c) | 16 | 8 |
| `max_open_zones` (zns.c) | 8 | 4 |

> **Note**: The values for `max_active_zones` and `max_open_zones` are tentative. Confirm final values with your mentor before running experiments. If RocksDB fails to start with an error related to open zones, increase `max_open_zones` accordingly.

### 3.4 How to Modify and Recompile

1. Edit zone size in `confznsplusplus/hw/femu/femu.c`:

```c
DEFINE_PROP_UINT64("zns_zonesize", FemuCtrl, zns_params.zone_size, (64 * MiB)),
```

2. Edit active/open zone limits in `confznsplusplus/hw/femu/zns/zns.c` inside `zns_init_zone_cap()`:

```c
n->max_active_zones = 16;
n->max_open_zones   = 8;
```

3. Recompile:

```bash
cd confznsplusplus/build
./femu-compile.sh
```

4. Restart the VM:

```bash
./run-zns.sh
```

5. Verify inside the VM:

```bash
# Check zone size, mar (max_active_zones) and mor (max_open_zones)
sudo nvme zns id-ns /dev/nvme0n1 -H

# Check total zone count
sudo nvme zns report-zones /dev/nvme0n1 | head -3
```

Expected output after setting `zone_size=64MiB, max_active_zones=16, max_open_zones=8`:
```
mar : 16    Active Resources
mor : 8     Open Resources
LBA Format Extension 0 : Zone Size: 0x20000 LBAs  (= 64MB)
```


## 4. Build Rocksdb with ZenFS

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
DEBUG_LEVEL=0 ROCKSDB_PLUGINS=zenfs make -j2 db_bench install

# compile zenfs
cd plugin/zens/util/zenfs
make

# verify
cd ../../..
ls db_bench
ls plugin/zenfs/util/zenfs
```



