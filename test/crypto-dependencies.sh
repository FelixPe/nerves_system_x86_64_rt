#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
buildroot=${NERVES_BR_DIR:-$root/deps/nerves_system_br}/buildroot
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

make -s -C "$buildroot" O="$work" \
    BR2_EXTERNAL="$root/deps/nerves_system_br" \
    NERVES_DEFCONFIG_DIR="$root" \
    BR2_DEFCONFIG="$root/nerves_defconfig" defconfig

for setting in \
    BR2_PACKAGE_CRYPTSETUP=y \
    BR2_PACKAGE_TPM2_TOOLS=y \
    BR2_PACKAGE_TPM2_TSS=y; do
    grep -Fxq "$setting" "$work/.config"
done

for setting in \
    CONFIG_MD=y \
    CONFIG_BLK_DEV_DM=y \
    CONFIG_DM_CRYPT=y \
    CONFIG_CRYPTO_AES=y \
    CONFIG_CRYPTO_XTS=y \
    CONFIG_CRYPTO_SHA256=y \
    CONFIG_TCG_TPM=y \
    CONFIG_TCG_TIS=y \
    CONFIG_TCG_CRB=y; do
    grep -Fxq "$setting" "$root/linux-6.18.defconfig"
done

echo "TPM and disk encryption dependencies are enabled"