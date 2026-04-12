#!/bin/bash
#
# Ruoxi Cao <ruoxicao@bu.edu>
# Run FEMU as Zoned-Namespace (ZNS) SSDs
#

# Run this script under confznsplusplus/build
# Virtual machine disk image, use your own image path
OSIMGF=../../images/u20s.qcow2

if [[ ! -e "$OSIMGF" ]]; then
	echo ""
	echo "VM disk image couldn't be found ..."
	echo "Please prepare a usable VM image and place it as $OSIMGF"
	echo "Once VM disk image is ready, please rerun this script again"
	echo ""
	exit
fi

qemu=x86_64-softmmu/qemu-system-x86_64

# ============================================================
# SSD CONFIG SELECTOR
# ============================================================
# Default SSD Geomoetry
zns_channels=8
zns_ways=2
zns_dies_per_chip=1
zns_planes_per_die=1
zns_block_size_pages=2048
zns_ways_per_zone=2
zns_channels_per_zone=8

# ZNS latency
zns_page_write_latency=500000
zns_page_read_latency=50000
zns_channel_transfer_latency=25000
zns_block_erasure_latency=5000000

# Default device size in MB
devsz_mb=$((1024*16))
zns_zonesize=$((256 * 1024 * 1024))
zns_zonecap=$((256 * 1024 * 1024))

port_local=8080   # < Set to your desired port
port_image=22     # < Set to the exposed port on the image
memory=4G         # RAM


femu_device="femu,devsz_mb=${devsz_mb},femu_mode=3,zns_channels=${zns_channels},zns_ways=${zns_ways},zns_dies_per_chip=${zns_dies_per_chip},zns_planes_per_die=${zns_planes_per_die},zns_block_size_pages=${zns_block_size_pages},zns_ways_per_zone=${zns_ways_per_zone},zns_channels_per_zone=${zns_channels_per_zone},zns_page_write_latency=${zns_page_write_latency},zns_page_read_latency=${zns_page_read_latency},zns_channel_transfer_latency=${zns_channel_transfer_latency},zns_block_erasure_latency=${zns_block_erasure_latency},zns_zonesize=${zns_zonesize},zns_zonecap=${zns_zonecap}"

$qemu \
    -name "FEMU-ZNSSD-VM" \
    -enable-kvm \
    -cpu host \
    -smp 4 \
    -m "$memory" \
    -device virtio-scsi-pci,id=scsi0 \
    -device scsi-hd,drive=hd0 \
    -drive file=$OSIMGF,if=none,aio=native,cache=none,format=qcow2,id=hd0 \
    -device "$femu_device" \
    -net user,hostfwd=tcp::"$port_local"-:"$port_image" \
    -net nic,model=virtio \
    -nographic \
    -qmp unix:./qmp-sock,server,nowait 2>&1 | tee log
