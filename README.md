# Analyzing GC and GC-free Approaches in ZNS SSDs

CS561 Spring 2026 — Boston University DiSC Lab

| Name | Email |
|---|---|
| Hsiang En Liu | sliu10@bu.edu |
| Ruoxi Cao | ruoxicao@bu.edu |
| Zhixin Li | lzhx@bu.edu |

## 1. Overview

ZNS SSDs expose storage as fixed-size zones with sequential write requirements. When a zone runs out of active write space, the host can issue a **zone FINISH** command to lock the zone and release controller resources. The leftover empty blocks are then filled with dummy data, causing device-level write amplification (DLWA).

Two approaches exist for managing this:

- **GC-free**: Set a low finish threshold so zones are finished early and a new zone is opened when lifetime data does not match. No host-side GC, but higher DLWA.
- **Host-triggered GC**: Delay zone FINISH, mixing data with different lifetimes in the same zone. Lower DLWA, but GC interferes with throughput.

This project studies the tradeoffs between these two approaches using RocksDB with ZenFS on a ZNS SSD emulated by ConfZNS++, measuring **throughput**, **space amplification**, and **DLWA** across different finish thresholds and zone size configurations.

## 2. Project Structure

```
project/
  confznsplusplus/     # ConfZNS++ emulator (git submodule)
    build/             # run scripts go here after setup
  rocksdb/             # RocksDB with ZenFS (inside VM)
  	plugin/
  		zenfs/
  images/
    u20s.qcow2         # VM image (see Section 3.2)
  scripts/             # benchmark scripts
  results/
  README.md
```

## 3. Environment Setup

### 3.1 Initialize ConfZNS++ submodule

```bash
git submodule update --init --recursive
```

Then apply the required source modifications before compiling (see [Section 4](#4-zns-device-configuration)).

### 3.2 Prepare VM image

Request the FEMU VM image from this [form](https://docs.google.com/forms/d/e/1FAIpQLSdCyNTU7n-hwW1ODJ3i_q1vmS6eTT-V3c4vCL8ouYocNLhxvA/viewform).

```bash
mkdir images && cd images
wget http://people.cs.uchicago.edu/~huaicheng/femu/femu-vm.tar.xz
tar xJvf femu-vm.tar.xz
```

Verify integrity:

```bash
md5sum u20s.qcow2 > tmp.md5sum
diff tmp.md5sum u20s.md5sum
```

VM credentials: username `femu`, password `femu`, Ubuntu 20.04.1, kernel 5.4.

### 3.3 Compile ConfZNS++

```bash
cd confznsplusplus
mkdir build && cd build

cp ../femu-scripts/femu-copy-scripts.sh .
./femu-copy-scripts.sh .

sudo ./pkgdep.sh   # Debian/Ubuntu only
./femu-compile.sh
```

If compilation fails with warnings, add `--disable-werror` to `femu-compile.sh`:

```sh
../configure --enable-kvm --target-list=x86_64-softmmu --disable-werror
```

Verify:

```bash
ls -lh x86_64-softmmu/qemu-system-x86_64
```

### 3.4 Build RocksDB with ZenFS (inside VM)

SSH into the guest VM first:

```bash
ssh -p8080 femu@localhost
```

Then inside the VM:

```bash
# Install libzbd (required by ZenFS)
git clone https://github.com/westerndigitalcorporation/libzbd.git
cd libzbd
sh ./autogen.sh && ./configure && make
sudo make install && sudo ldconfig

# Clone RocksDB and ZenFS
git clone --branch v8.9.1 https://github.com/facebook/rocksdb.git
cd rocksdb
git clone https://github.com/westerndigitalcorporation/zenfs plugin/zenfs

# Compile (lower -j if the terminal is killed)
DEBUG_LEVEL=0 ROCKSDB_PLUGINS=zenfs make -j2 db_bench
sudo make install

# Compile zenfs utility
cd plugin/zenfs/util
make

# Verify
ls ~/rocksdb/db_bench
ls ~/rocksdb/plugin/zenfs/util/zenfs
```

## 4. ZNS Device Configuration

After every source file modification, recompile ConfZNS++ before running experiments.

### 4.1 Required source modifications

**1. Internal page size** — `confznsplusplus/hw/femu/zns/zns.c`, top of file:

```c
// Change from (16 * KiB) to match the external (NVMe-exposed) page size
#define ZNS_INTERNAL_PAGE_SIZE (4 * KiB)
```

**2. Active and open zone limits** — `zns_init_zone_cap()` in `zns.c`, around line 1969:

```c
n->max_active_zones = 32;
n->max_open_zones   = 16;
```

### 4.2 Experiment configuration

The key parameters we tuned are listed below. Full SSD geometry and latency settings (channels, ways, dies, planes, block size, page latencies, etc.) are in `scripts/run-znsplusplus.sh`.

| Parameter | Value | Location |
|---|---|---|
| `devsz_mb` | 16384 (16 GiB) | `scripts/run-znsplusplus.sh` |
| `zns_zonesize` | 256 MiB | `scripts/run-znsplusplus.sh` |
| `ZNS_INTERNAL_PAGE_SIZE` | 4 KiB | `zns.c` |
| `num_zones` (auto) | 64 | computed at runtime |
| `max_active_zones` | 32 | `zns.c` |
| `max_open_zones` | 16 | `zns.c` |

`num_zones` is derived automatically: `devsz_mb / zns_zonesize = 16384 MiB / 256 MiB = 64 zones`.
The constraint `num_zones ≥ max_active_zones ≥ max_open_zones` must always hold.

### 4.3 Recompile and verify

```bash
cd confznsplusplus/build
./femu-compile.sh
cp ../../scripts/run-znsplusplus.sh .
./run-znsplusplus.sh
```

Inside the VM — verify zone size, mar, and mor:

```bash
sudo nvme zns id-ns /dev/nvme0n1 -H        # check zone size, mar, mor
sudo nvme zns report-zones /dev/nvme0n1 | head -3  # check total zone count
```

Expected output:

```
mar : 32    Active Resources
mor : 16    Open Resources
LBA Format Extension 0 : Zone Size: 0x80000 LBAs  (= 256 MiB)
```

On the host — verify internal geometry (channels, ways, dies, planes, etc.):

```bash
grep -A 10 "======" confznsplusplus/build/log
```

FEMU prints a geometry table on startup:

```
[FEMU] Log: ===========================================
[FEMU] Log: |        ConfZNS HW Configuration()       |
[FEMU] Log: ===========================================
[FEMU] Log: | proglat     : 500000   | readlat   : 50000   |
[FEMU] Log: | eraslat     : 5000000   | xferlat   : 25000   |
[FEMU] Log: ===========================================
[FEMU] Log: | nchnl       : 8   | nway      : 2   |
[FEMU] Log: | nchnl/zone  : 8   | nway/zone : 2   |
[FEMU] Log: | die/chip    : 1   | io_qs     : 16    |
[FEMU] Log: | plane/die   : 1   | block/die : 2  |
[FEMU] Log: | pages/block : 2048   |  stripe   : 32768   |
[FEMU] Log: | page        : 4KiB|  zones    : 64  |
[FEMU] Log: ===========================================
```

## 5. Running Experiments

All benchmark scripts are in `scripts/` and should be run **inside the VM**.



## 6. Collecting Results


# Analyzing GC and GC-free Approaches in ZNS SSDs

CS561 Spring 2026 — Boston University DiSC Lab

| Name | Email |
|---|---|
| Hsiang En Liu | sliu10@bu.edu |
| Ruoxi Cao | ruoxicao@bu.edu |
| Zhixin Li | lzhx@bu.edu |

## 1. Overview

ZNS SSDs expose storage as fixed-size zones with sequential write requirements. When a zone runs out of active write space, the host can issue a **zone FINISH** command to lock the zone and release controller resources. The leftover empty blocks are then filled with dummy data, causing device-level write amplification (DLWA).

Two approaches exist for managing this:

- **GC-free**: Set a low finish threshold so zones are finished early and a new zone is opened when lifetime data does not match. No host-side GC, but higher DLWA.
- **Host-triggered GC**: Delay zone FINISH, mixing data with different lifetimes in the same zone. Lower DLWA, but GC interferes with throughput.

This project studies the tradeoffs between these two approaches using RocksDB with ZenFS on a ZNS SSD emulated by ConfZNS++, measuring **throughput**, **space amplification**, and **DLWA** across different finish thresholds and zone size configurations.

## 2. Project Structure

```
project/
  confznsplusplus/     # ConfZNS++ emulator (git submodule)
    build/             # run scripts go here after setup
  rocksdb/             # RocksDB with ZenFS (inside VM)
  	plugin/
  		zenfs/
  images/
    u20s.qcow2         # VM image (see Section 3.2)
  scripts/             # benchmark scripts
  results/
  README.md
```

## 3. Environment Setup

### 3.1 Initialize ConfZNS++ submodule

```bash
git submodule update --init --recursive
```

Then apply the required source modifications before compiling (see [Section 4](#4-zns-device-configuration)).

### 3.2 Prepare VM image

Request the FEMU VM image from this [form](https://docs.google.com/forms/d/e/1FAIpQLSdCyNTU7n-hwW1ODJ3i_q1vmS6eTT-V3c4vCL8ouYocNLhxvA/viewform).

```bash
mkdir images && cd images
wget http://people.cs.uchicago.edu/~huaicheng/femu/femu-vm.tar.xz
tar xJvf femu-vm.tar.xz
```

Verify integrity:

```bash
md5sum u20s.qcow2 > tmp.md5sum
diff tmp.md5sum u20s.md5sum
```

VM credentials: username `femu`, password `femu`, Ubuntu 20.04.1, kernel 5.4.

### 3.3 Compile ConfZNS++

```bash
cd confznsplusplus
mkdir build && cd build

cp ../femu-scripts/femu-copy-scripts.sh .
./femu-copy-scripts.sh .

sudo ./pkgdep.sh   # Debian/Ubuntu only
./femu-compile.sh
```

If compilation fails with warnings, add `--disable-werror` to `femu-compile.sh`:

```sh
../configure --enable-kvm --target-list=x86_64-softmmu --disable-werror
```

Verify:

```bash
ls -lh x86_64-softmmu/qemu-system-x86_64
```

### 3.4 Build RocksDB with ZenFS (inside VM)

SSH into the guest VM first:

```bash
ssh -p8080 femu@localhost
```

Then inside the VM:

```bash
# Install libzbd (required by ZenFS)
git clone https://github.com/westerndigitalcorporation/libzbd.git
cd libzbd
sh ./autogen.sh && ./configure && make
sudo make install && sudo ldconfig

# Clone RocksDB and ZenFS
git clone --branch v8.9.1 https://github.com/facebook/rocksdb.git
cd rocksdb
git clone https://github.com/westerndigitalcorporation/zenfs plugin/zenfs

# Compile (lower -j if the terminal is killed)
DEBUG_LEVEL=0 ROCKSDB_PLUGINS=zenfs make -j2 db_bench
sudo make install

# Compile zenfs utility
cd plugin/zenfs/util
make

# Verify
ls ~/rocksdb/db_bench
ls ~/rocksdb/plugin/zenfs/util/zenfs
```

## 4. ZNS Device Configuration

After every source file modification, recompile ConfZNS++ before running experiments.

### 4.1 Required source modifications

**1. Internal page size** — `confznsplusplus/hw/femu/zns/zns.c`, top of file:

```c
// Change from (16 * KiB) to match the external (NVMe-exposed) page size
#define ZNS_INTERNAL_PAGE_SIZE (4 * KiB)
```

**2. Active and open zone limits** — `zns_init_zone_cap()` in `zns.c`, around line 1969:

```c
n->max_active_zones = 32;
n->max_open_zones   = 16;
```

### 4.2 Experiment configuration

The key parameters we tuned are listed below. Full SSD geometry and latency settings (channels, ways, dies, planes, block size, page latencies, etc.) are in `scripts/run-znsplusplus.sh`.

| Parameter | Value | Location |
|---|---|---|
| `devsz_mb` | 16384 (16 GiB) | `scripts/run-znsplusplus.sh` |
| `zns_zonesize` | 256 MiB | `scripts/run-znsplusplus.sh` |
| `ZNS_INTERNAL_PAGE_SIZE` | 4 KiB | `zns.c` |
| `num_zones` (auto) | 64 | computed at runtime |
| `max_active_zones` | 32 | `zns.c` |
| `max_open_zones` | 16 | `zns.c` |

`num_zones` is derived automatically: `devsz_mb / zns_zonesize = 16384 MiB / 256 MiB = 64 zones`.
The constraint `num_zones ≥ max_active_zones ≥ max_open_zones` must always hold.

### 4.3 Recompile and verify

```bash
cd confznsplusplus/build
./femu-compile.sh
cp ../../scripts/run-znsplusplus.sh .
./run-znsplusplus.sh
```

Inside the VM:

```bash
sudo nvme zns id-ns /dev/nvme0n1 -H       # check zone size, mar, mor
sudo nvme zns report-zones /dev/nvme0n1| head -3  # check total zone count
```

Expected output:

```
mar : 32    Active Resources
mor : 16    Open Resources
LBA Format Extension 0 : Zone Size: 0x80000 LBAs  (= 256 MiB)
```

## 5. Running Experiments

All benchmark scripts are in `scripts/` and should be run **inside the VM**.



## 6. Collecting Results

