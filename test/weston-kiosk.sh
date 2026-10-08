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
    BR2_PACKAGE_COG_PLATFORM_FDO=y \
    BR2_PACKAGE_WESTON=y \
    BR2_PACKAGE_WESTON_DEFAULT_DRM=y \
    BR2_PACKAGE_WESTON_DRM=y \
    BR2_PACKAGE_WESTON_SHELL_KIOSK=y \
    BR2_PACKAGE_SEATD_BUILTIN=y; do
    grep -Fxq "$setting" "$work/.config"
done
if grep -Fxq BR2_PACKAGE_COG_PLATFORM_DRM=y "$work/.config"; then
    echo "Cog must use Wayland rather than direct DRM" >&2
    exit 1
fi

options=$(make -s -C "$buildroot" O="$work" printvars \
    VARS='COG_CONF_OPTS COG_PLATFORMS_LIST WESTON_CONF_OPTS')
grep -Fq -- '-Dwayland_weston_direct_display=false' <<< "$options"
if grep -Fq -- '-Dwayland_weston_direct_display=true' <<< "$options"; then
    echo "Cog 0.18.5 cannot use Weston 15 direct-display protocols" >&2
    exit 1
fi
grep -Fq 'COG_PLATFORMS_LIST=headless wayland' <<< "$options"
grep -Fq -- '-Dshell-kiosk=true' <<< "$options"
grep -Fxq 'shell=kiosk' "$root/rootfs_overlay/etc/xdg/weston/weston.ini"
grep -Fxq 'idle-time=0' "$root/rootfs_overlay/etc/xdg/weston/weston.ini"
echo "Weston kiosk configuration checks passed"