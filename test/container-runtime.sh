#!/usr/bin/env bash
# SPDX-FileCopyrightText: None
# SPDX-License-Identifier: CC0-1.0
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
buildroot=${NERVES_BR_DIR:-$root/deps/nerves_system_br}/buildroot
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

make -s -C "$buildroot" O="$work" \
    BR2_EXTERNAL="$root/deps/nerves_system_br" \
    NERVES_DEFCONFIG_DIR="$root" \
    BR2_DEFCONFIG="$root/nerves_defconfig" defconfig

for package in DOCKER_ENGINE DOCKER_CLI CONTAINERD RUNC TINI CGROUPFS_V2_MOUNT START_STOP_DAEMON; do
    if grep -Fxq "BR2_PACKAGE_$package=y" "$work/.config"; then
        echo "Unexpected Docker-related package enabled: $package" >&2
        exit 1
    fi
done

for package in CRUN LIBCAP LIBSECCOMP IPROUTE2 TAR GZIP; do
    if ! grep -Fxq "BR2_PACKAGE_$package=y" "$work/.config"; then
        echo "Missing OCI runtime support package: $package" >&2
        exit 1
    fi
done

options=$(make -s -C "$buildroot" O="$work" \
    NERVES_DEFCONFIG_DIR="$root" printvars VARS=CRUN_CONF_OPTS)
for option in --enable-caps --enable-seccomp; do
    grep -Fq -- "$option" <<< "$options"
done

for option in NAMESPACES UTS_NS IPC_NS PID_NS NET_NS SECCOMP SECCOMP_FILTER; do
    if ! grep -Fxq "CONFIG_$option=y" "$root/linux-6.18.defconfig"; then
        echo "Missing standalone OCI kernel feature: $option" >&2
        exit 1
    fi
done

for path in \
    etc/docker/daemon.json \
    usr/bin/nerves-start-dockerd \
    usr/libexec/nerves-dockerd; do
    if [[ -e "$root/rootfs_overlay/$path" ]]; then
        echo "Unexpected Docker overlay file: $path" >&2
        exit 1
    fi
done

echo "Standalone crun configuration checks passed"
