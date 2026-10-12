#!/bin/sh

set -e

FWUP_CONFIG=$NERVES_DEFCONFIG_DIR/fwup.conf

# Run the common post-image processing for nerves
$BR2_EXTERNAL_NERVES_PATH/board/nerves-common/post-createfs.sh $TARGET_DIR $FWUP_CONFIG

# Use the system's A/B configuration instead of Buildroot's generic GRUB menu.
EFI_BOOT_DIR=$BINARIES_DIR/efi-part/EFI/BOOT
mkdir -p "$EFI_BOOT_DIR"
cp "$NERVES_DEFCONFIG_DIR/grub.cfg" "$EFI_BOOT_DIR/grub.cfg"
