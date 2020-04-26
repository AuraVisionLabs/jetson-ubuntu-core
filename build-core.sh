#!/bin/bash -ex
#
# Copyright (C) 2019 Canonical Ltd
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

print_usage()
{
    printf "Usage: %s <tx1|tx2|nano|xavier> <assert_file> <gadget_snap> <kernel_snap>\n" \
           "$(basename "$0")"
}

# Input validation
if [ $# -ne 4 ]; then
    print_usage
    exit 1
fi
board=$1
if [ "$board" != tx1 ] && [ "$board" != tx2 ] &&
       [ "$board" != nano ] && [ "$board" != xavier ]; then
    print_usage
    exit 1
fi
assert_file=$2
gadget_snap=$3
kernel_snap=$4

channel=stable
outdir=out-"$board"
sudo rm -rf "$outdir"
mkdir -p "$outdir"

# Create image file
ubuntu-image snap --output-dir "$outdir" --workdir "$outdir" \
             --channel "$channel" \
             --snap "$gadget_snap" \
             --snap "$kernel_snap" \
             "$assert_file"

# Generate tarball with all the needed parts for flashing
final_tree="$outdir"/final_tree
mkdir "$final_tree"
if [ "$board" = nano ]; then
    pushd "$outdir"
    wget https://developer.nvidia.com/embedded/dlc/l4t-jetson-driver-package-32-1-jetson-nano \
         -O Jetson-Nano-Tegra210_Linux_R32.1.0_aarch64.tbz2
    tar xf Jetson-Nano-Tegra210_Linux_R32.1.0_aarch64.tbz2
    cp unpack/gadget/u-boot.bin Linux_for_Tegra/bootloader/t210ref/p3450-porg/
    cp volumes/jetson/part0.img Linux_for_Tegra/bootloader/system-boot.ext4
    cp volumes/jetson/part12.img Linux_for_Tegra/bootloader/system-data.ext4
    rm jetson.img
    cd Linux_for_Tegra
    patch -p1 < ../../tarball-parts/nano/create-jetson-nano-sd-card-image.sh.patch
    patch -p1 < ../../tarball-parts/nano/flash.sh.patch
    sudo ./create-jetson-nano-sd-card-image.sh -o jetson.img -s 600M -r 200
    popd
    mv "$outdir"/Linux_for_Tegra/jetson.img "$final_tree"
    cp tarball-parts/"$board"/README.md "$final_tree"
elif [ "$board" = xavier ]; then
    bootloader_dir="$final_tree"/bootloader
    writable_part=36
    mkdir -p "$bootloader_dir"
    cp "$outdir"/unpack/gadget/cboot_t194.bin "$bootloader_dir"/
    cp "$outdir"/unpack/image/boot/lk/snapbootsel.bin "$bootloader_dir"/system.img
    cp "$outdir"/unpack/image/boot/lk/boot.img "$bootloader_dir"/boot.img
    cp "$outdir"/volumes/jetson/part"$writable_part".img "$bootloader_dir"/system-data.ext4
    cp tarball-parts/"$board"/* "$final_tree"
else
    bootloader_dir="$final_tree"/bootloader
    if [ "$board" = tx1 ]; then
        u_boot_dir="$bootloader_dir"/t210ref/p2371-2180
        writable_part=18
    else
        u_boot_dir="$bootloader_dir"/t186ref/p2771-0000/500
        writable_part=30
    fi
    mkdir -p "$u_boot_dir"
    cp "$outdir"/unpack/gadget/u-boot.bin "$u_boot_dir"
    cp "$outdir"/volumes/jetson/part0.img "$bootloader_dir"/system.img
    cp "$outdir"/volumes/jetson/part"$writable_part".img "$bootloader_dir"/system-data.ext4
    cp tarball-parts/"$board"/* "$final_tree"
fi

pushd "$final_tree"
tar -cJf ../core-18-jetson-"$board".tar.xz -- *
popd
