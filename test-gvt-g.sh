#!/bin/bash

set -e
source ./config

#make a dir for testing
mkdir -p "$TEST_DIR"

PCI_DEVICES="/sys/devices/pci0000:00"
GPU_CTRL="$PCI_DEVICES/$GPU_DEV"
VIRT_GPU="$GPU_CTRL/$VIRT_GPU_UUID"

create_virt_gpu(){
    if [ ! -e "$VIRT_GPU" ]; then
        modprobe kvmgt #unnecessary, probably
        echo "$VIRT_GPU_UUID" > "$GPU_CTRL/mdev_supported_types/$GVT_MODE/create"
        echo "created virtual gpu device."
    else
        echo "virtual gpu device already exists."
    fi
}

destroy_virt_gpu(){
    if [ -d "$VIRT_GPU" ]; then
        echo 1 > "$VIRT_GPU/remove"
        echo "destroyed virtual gpu device."
    else
        echo "virtual gpu is not there to destroy."
    fi
}

cleanup(){
    destroy_virt_gpu
    chown -R 1000:1000 "../$TEST_DIR" #in most cases will ease cleanup
}

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    #exit 1
fi

if [ ! -e "$GPU_CTRL" ]; then
   echo "GPU PCI device doesn't exist, did you set it correctly?"
   echo "device doesn't exist: $GPU_CTRL"
   exit 1
fi

#got this far, arm cleanup
trap cleanup EXIT

cd "$TEST_DIR"
create_virt_gpu

# link or copy the rom we built here
ROM_FILE="i915ovmf.rom"
BUILT_ROM="$WORKSPACE/Build/i915ovmf/${BUILD_TYPE}_GCC5/X64/$ROM_FILE"
ROM_FILEPATH="$(pwd)/$ROM_FILE"

# check built file exists
if [ ! -f "$BUILT_ROM" ]; then
    echo "Error - did not find built .rom file, did it build successfully?"
    exit 1
fi

# check built rom exists & that we didn't already create a symlink to it
if [ ! -e "./$ROM_FILE" ]; then
    #cp "$BUILT_ROM" . # can copy file or just link it
    ln -s "$BUILT_ROM" "./$ROM_FILE"
    echo "linked/copied rom file into test dir."
else
    echo "i915ovmf.rom already exists in test dir."
fi

# Create an UEFI disk that immediately shuts down the VM when booted
DUMMY_DISK="DumyDisk.img"
if [ ! -f "./$DUMMY_DISK" ]; then
    # create 500M img
    dd if=/dev/zero of="./$DUMMY_DISK" bs=100M count=5
    du -sh "$DUMMY_DISK"
    echo "created dummy img file."

    #create loop device
    LOOP_DEV=$(losetup -fP --show "$DUMMY_DISK")
    echo "created loop device"

    #format it as FAT32
    mkfs.fat -F 32 "$DUMMY_DISK"
    echo "formated the dummy_disk as fat32"

    #mount it
    MNT="mnt"
    mkdir -p "$MNT"
    mount -o loop "$LOOP_DEV" "$MNT"

    #verify
    #df -hP "$MNT"
    #lsblk -f

    # mk dirs structure
    mkdir -p "$MNT/EFI/BOOT"
    ls -l "$MNT"

    #unmount it
    umount "$MNT"

    #remove loop dev
    losetup -d "$LOOP_DEV"

    echo "created dummy UEFI disk."
fi

#
# you can try and link the built edk2 bios
# $WORKSPACE/edk2/Build/OvmfX64/${BUILD_TYPE}_GCC5/FV/OVMF_CODE.fd
#
#UEFI_BIOS="$WORKSPACE/edk2/Build.old/OvmfX64/${BUILD_TYPE}_GCC5/FV/OVMF_CODE.fd"
#UEFI_BIOS="$WORKSPACE/edk2/Build.old/OvmfX64/RELEASE_GCC5/FV/OVMF.fd" #works
UEFI_BIOS="$WORKSPACE/edk2/Build/OvmfX64/${BUILD_TYPE}_GCC5/FV/OVMF.fd"

# or you can use the system binaries, I mean you're compiling this for a reason right?
#UEFI_BIOS="/usr/share/edk2/x64/OVMF_CODE.fd"

if [ ! -e "$UEFI_BIOS" ]; then
    echo "can't find built OVMF bios, quiting."
    exit 1
fi

set +e #we want the exit code for  helpful log
#
# This will start a simple VM with blank disk image, so only UEFI bios + shell will be available
# you can verify the driver is loaded in UEFI shell via 'drivers' command (it will be last).
# then simply close the vm window.
# removed options
# -no-hpet \
#
qemu-system-x86_64 \
	-k en-us \
	-name uefitest,debug-threads=on \
	-serial stdio \
	-m 2048 \
	-M pc \
	-cpu host \
	-global PIIX4_PM.disable_s3=1 \
	-global PIIX4_PM.disable_s4=1 \
	-machine kernel_irqchip=on \
	-nodefaults \
	-rtc base=localtime,driftfix=slew \
	-global kvm-pit.lost_tick_policy=discard \
	-enable-kvm \
	-bios "$UEFI_BIOS" \
	-display gtk,gl=on,grab-on-hover=on \
	-full-screen \
	-vga none \
	-device "vfio-pci,sysfsdev=$VIRT_GPU,addr=02.0,display=on,x-igd-opregion=on,romfile=$ROM_FILEPATH" \
	-device qemu-xhci,p2=8,p3=8 \
	-device usb-kbd \
	-device usb-tablet \
	-drive format=raw,file=$DUMMY_DISK

RES_RUN=$?
if [ "$RES_RUN" -gt 0 ]; then
    echo -e "\n==== Failed to run test VM ====\n"
else
    reset #if you want to see messy output from VM/UEFI shell, comment this out
    echo -e "\n==== Success! ====\n"
    echo "Built ROM: " && ls -l "./$ROM_FILE"
fi

#cleanup - is done automatically