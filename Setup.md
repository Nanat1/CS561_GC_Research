# Enviroment Setup

## 0. Directory

```bash
project/
  confznsplusplus/          # ConfZNS++
  rocksdb/                  # RocksDB
  images/
    ubuntu-22.04.qcow2      # VM 镜像
  results/
  README.md
```

## 1. Host Environment

Ubuntu22.04

## 1.1 Dependencies

```bash
apt update
apt install -y \
	sudo \
  build-essential ninja-build cmake pkg-config \
  python3 python3-pip \
  git wget curl \
  libglib2.0-dev libpixman-1-dev zlib1g-dev \
  libfdt-dev libaio-dev libcap-ng-dev libattr1-dev \
  libslirp-dev \
  flex bison \
  meson \
  libncurses5-dev libncursesw5-dev
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
cp ../femu-scripts/femu-copy-scripts.sh .
./femu-copy-scripts.sh .
# only Debian/Ubuntu based distributions supported
./pkgdep.sh
./femu-compile.sh
```

Confirmation: 

```bash
ls -lh x86_64-softmmu/qemu-system-x86_64
```

## 3. Prepare Ubuntu VM image(qcow2)

```bash
mkdir images
cd images
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img \
-O ubuntu-22.04.qcow2

# create VM overlay
apt install -y qemu-utils
qemu-img create -f qcow2 -F qcow2 -b ubuntu-22.04.qcow2 vm.qcow2
```

## 4. 