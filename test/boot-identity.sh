#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export NERVES_SYSTEM="$work/system"
export NERVES_SDK_VERSION=0.0.0
export ROOTFS="$work/rootfs"
mkdir -p "$NERVES_SYSTEM/images/efi-part/EFI/BOOT" "$NERVES_SYSTEM/images/fwup_include"
touch "$ROOTFS" "$NERVES_SYSTEM/images/bzImage" \
    "$NERVES_SYSTEM/images/efi-part/EFI/BOOT/bootx64.efi" \
    "$NERVES_SYSTEM/images/grubenv_a_valid" "$NERVES_SYSTEM/images/grubenv_a" \
    "$NERVES_SYSTEM/images/grubenv_b" "$NERVES_SYSTEM/images/fwup_include/provisioning.conf"
cp "$root/grub.cfg" "$NERVES_SYSTEM/images/efi-part/EFI/BOOT/grub.cfg"

fwup -c -f "$root/fwup.conf" -o "$work/default.fw"
unzip -p "$work/default.fw" meta.conf > "$work/default.conf"
grep -Fq 'guid="f18a2026-1012-4f44-8000-000000000002"' "$work/default.conf"
grep -Fq 'NERVES_ESP' "$work/default.conf"

printf '%s\n' 'installer grub configuration' > "$work/installer-grub.cfg"
export ESP_LABEL=HILDA_INST
export GRUB_CONFIG="$work/installer-grub.cfg"
export DISK_GUID=c56a2026-1012-4f44-8000-000000000000
export ESP_GUID=c56a2026-1012-4f44-8000-000000000001
export ROOTFS_A_GUID=c56a2026-1012-4f44-8000-000000000002
export ROOTFS_B_GUID=c56a2026-1012-4f44-8000-000000000003
export APP_GUID=c56a2026-1012-4f44-8000-000000000004

fwup -c -f "$root/fwup.conf" -o "$work/installer.fw"
unzip -p "$work/installer.fw" meta.conf > "$work/installer.conf"
grep -Fq 'guid="c56a2026-1012-4f44-8000-000000000002"' "$work/installer.conf"
grep -Fq 'HILDA_INST' "$work/installer.conf"
test "$(unzip -p "$work/installer.fw" data/grub.cfg)" = 'installer grub configuration'

echo 'Default and overridden boot identities verified'