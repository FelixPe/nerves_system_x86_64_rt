# Generic x86_64 System with preempt_rt kernel

[![Hex version](https://img.shields.io/hexpm/v/nerves_system_x86_64.svg "Hex version")](https://hex.pm/packages/nerves_system_x86_64)
[![CI](https://github.com/nerves-project/nerves_system_x86_64/actions/workflows/ci.yml/badge.svg)](https://github.com/nerves-project/nerves_system_x86_64/actions/workflows/ci.yml)
[![REUSE status](https://api.reuse.software/badge/github.com/nerves-project/nerves_system_x86_64)](https://api.reuse.software/info/github.com/nerves-project/nerves_system_x86_64)

This is the base Nerves System configuration for a generic x86_64 system that
can be run with Qemu. It can be used as a base for real x86_64 systems, but it
probably will require some work.

This system boots in UEFI mode using GPT and EFI GRUB. BIOS/MBR images are not
supported; existing installations require a complete reflash to migrate.

| Feature              | Description                     |
| -------------------- | ------------------------------- |
| CPU                  | Intel                           |
| Memory               | 512 MB+ DRAM                    |
| Storage              | 32 GB+ disk/SSD (/dev/sda)       |
| Linux kernel         | 6.18                            |
| IEx terminal         | Virtual serial - ttyS0          |
| Hardware I/O         | None                            |
| Ethernet             | Yes                             |

## Using

The most common way of using this Nerves System is create a project with `mix
nerves.new` and to export `MIX_TARGET=x86_64_rt`. See the [Getting started
guide](https://nerves.hexdocs.pm/getting-started.html#creating-a-new-nerves-app)
for more information.

If you need custom modifications to this system for your device, clone this
repository and update as described in [Making custom
systems](https://nerves.hexdocs.pm/systems.html#customizing-your-own-nerves-system)

## C library and native dependencies

This system uses glibc 2.43 from the official
`nerves_toolchain_x86_64_nerves_linux_gnu` 15.3.1 toolchain. Native dependencies
must target `x86_64-nerves-linux-gnu`, not musl.

When migrating from a musl-based system, fetch the new dependency with
`mix deps.get` and perform a full clean Buildroot rebuild; an incremental
rebuild is not supported when changing libc. In the system build shell
(`mix nerves.system.shell`), run `make clean`, then `make`.
Rebuild the firmware application's native dependencies and NIFs against the
new system as well. Do not reuse musl-built system or application artifacts.

glibc enables using glibc-dependent native code such as `rclex`, but does not
provide ROS 2 itself. The firmware still needs compatible ROS 2 libraries and
their runtime dependencies, built for this target.

## Cog on Weston

This system includes Cog's FDO/Wayland backend and Weston with its DRM backend
and kiosk shell. Weston owns the display and input devices, makes application
windows fullscreen, and disables idle screen blanking. Cog's direct DRM
backend and its local pointer patch are no longer included. Existing kernel
and Nerves patches are unchanged.

The root filesystem includes Intel's VA-API media driver and Mesa's Intel and
Virtio/Venus Vulkan drivers with the Vulkan loader. Virtio/Venus acceleration
also requires compatible host-side QEMU and virglrenderer support. Hardware
acceleration depends on the GPU, firmware, and driver versions.

Intel's `i915` and `xe` kernel drivers are modules. NervesUEvent discovers the
GPU and invokes `modprobe` after the root filesystem is mounted, so the drivers
can read their firmware from `/lib/firmware`. Built-in Intel GPU drivers would
request it before that filesystem is available. This uses NervesUEvent's
default `autoload_modules: true`, not an eudev daemon; devtmpfs creates the device
nodes. The `virtio_gpu` driver is also a module, loaded only when a matching
virtual GPU is present. It does not need external GPU firmware; making it
modular avoids loading it on physical hardware and defers QEMU graphics
initialization to userspace device discovery. Core DRM and the Virtio transport,
storage, and network drivers remain built in.
Before starting Weston, wait for the GPU's DRM card and, when using hardware
acceleration, render nodes under `/dev/dri` rather than using a fixed startup
delay.

For an existing build directory, run `make linux-dirclean` followed by `make`
in `mix nerves.system.shell` to rebuild the kernel and install the new GPU
modules. Rebuild and deploy the firmware application using the resulting
system artifact; changing the firmware files alone does not update the kernel.
On real hardware, check `dmesg` for `i915`/`xe` initialization and firmware-load
errors, confirm that the GPU has a render node under `/dev/dri`, and inspect
Weston's startup log for a hardware GL renderer rather than `llvmpipe` or
`softpipe`. Configuration checks cannot establish that hardware acceleration
works on a particular GPU.

The firmware application owns startup and supervision of both processes;
the system does not automatically launch them or hard-code a kiosk URL.
Create a private runtime directory owned by the user running Weston and Cog:

```sh
mkdir -p /run/weston
chmod 0700 /run/weston
```

Start Weston as a separately supervised process with these settings. The
built-in libseat backend is intended for the root-run Nerves application and
does not require a separate seatd daemon:

```sh
XDG_RUNTIME_DIR=/run/weston LIBSEAT_BACKEND=builtin weston --config=/etc/xdg/weston/weston.ini --socket=wayland-0
```

Once Weston accepts Wayland connections and the local HTTP endpoint is ready,
start Cog with the same runtime directory and socket:

```sh
XDG_RUNTIME_DIR=/run/weston WAYLAND_DISPLAY=wayland-0 cog --platform=fdo http://localhost:4000
```

Remove the old `--platform=drm`, `--platform-params=renderer=gles`, and
`COG_PLATFORM_DRM_POINTER`/`COG_PLATFORM_DRM_CURSOR` settings from the
application launcher. Use readiness checks rather than fixed startup delays.
Restart Cog if Weston exits and is restarted, since its Wayland connection
is lost. Keep restart attempts bounded with backoff and capture both logs.

Native touchscreen input does not require a mouse cursor. Mouse-capable
devices may still show one; this configuration does not force cursors hidden.

The system-local makefile disables Cog 0.18.5's optional Weston direct-display
extension because it does not recognize Weston 15's protocol package. Normal
Wayland rendering remains enabled; Weston can still use direct scanout when
the buffers and output permit it.

When reusing a Buildroot build directory, run `make cog-dirclean` followed by
`make` in `mix nerves.system.shell` to remove the previously patched Cog and
build the new configuration. Rebuild firmware against the resulting system
artifact. Validate display output, touch input, and restart recovery on the
target device. The configuration check is `bash test/weston-kiosk.sh` after
the Nerves Buildroot tree has been prepared.

## Storage layout

Use a disk of at least 32 GB. Both read-only SquashFS rootfs slots reserve
4 GiB (8388608 sectors of 512 bytes) each. The writable ext4 application
partition mounted at `/root` has a 10 GiB minimum and expands to use the
remaining disk space. On a 32 GB disk, approximately 21.8 GiB is available
for `/root`, including container and application data.

This layout is intended for complete flashing of new devices. Migration from
the previous partition layout is not supported.

### Boot identity

Firmware builds can override `ESP_LABEL`, `DISK_GUID`, `ESP_GUID`,
`ROOTFS_A_GUID`, `ROOTFS_B_GUID`, `APP_GUID`, and `GRUB_CONFIG` through
environment variables. `GRUB_CONFIG` is the path to the GRUB configuration
included in the firmware. Its EFI label and root `PARTUUID` values must match
the corresponding firmware settings. Without overrides, the existing Nerves
label, GUIDs, and GRUB configuration are unchanged.

Use distinct identities for disks that may be attached at the same time. These
settings affect complete flashes; they do not rewrite existing partition IDs or
GRUB configuration during firmware upgrades.

## OCI containers

This system includes `crun` with Linux capabilities and seccomp support for
running prepared OCI bundles (`config.json` and a root filesystem). It does not
include a container engine, image pull/unpack tooling, or automatic container
startup. The firmware application owns bundle preparation, persistent storage,
container networking, lifecycle, and supervision.

Before starting containers, wait for Nerves filesystem preparation to complete
and `/root` to be mounted read/write. For bundles using cgroup resource controls,
the application must prepare the cgroup hierarchy, including mounting cgroup v2
at `/sys/fs/cgroup` if it is not already mounted. No daemon launcher or automatic
cgroup-mount helper is provided. `crun` does not automatically configure a bridge
or NAT; networking must be configured separately or the bundle must explicitly
use host networking.

`libcap`, `libseccomp`, `iproute2`, `tar`, and `gzip` are retained for container
support, along with the kernel's cgroup, namespace, bridge/veth, and OverlayFS
facilities. This is not a preconfigured rootless-container environment.

When migrating an existing system build, perform a clean Buildroot rebuild:
run `make clean` followed by `make` in `mix nerves.system.shell`, then rebuild
and deploy the firmware application using the new system artifact. Buildroot
does not uninstall files from previously enabled packages during incremental
builds. Remove any application calls to the old `nerves-start-dockerd` launcher.
Existing `/root/docker` data is not deleted by this change; remove it separately
only if it is no longer needed. The configuration check is
`bash test/container-runtime.sh` after preparing the Nerves Buildroot tree.

## Running in QEMU (UEFI)

It's possible to run Nerves projects built with this system in Qemu with some
work. If you create a Nerves projects with the `nerves_system_x86_64_rt`
dependency, here are the steps:

Create firmware like normal:

```sh
export MIX_TARGET=x86_64_rt
mix deps.get
mix firmware
```

Create the disk image (virtual MicroSD/SD/eMMC):

```sh
qemu-img create -f raw disk.img 32G
```

Use `fwup` to write the image for the first time:

```sh
# Substitute the .fw file based on your project
fwup -d disk.img _build/x86_64_dev/nerves/images/circuits_quickstart.fw
```

This system is UEFI-only. Existing BIOS/MBR disks must be fully reflashed;
they cannot be migrated with an OTA update. Run QEMU with OVMF. Firmware file
locations vary by distribution; these paths match Debian/Ubuntu packages:

```sh
OVMF_CODE=/usr/share/OVMF/OVMF_CODE_4M.fd
OVMF_VARS=/usr/share/OVMF/OVMF_VARS_4M.fd
cp "$OVMF_VARS" OVMF_VARS.fd

qemu-system-x86_64 -machine q35 -m 1024 -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" -drive if=pflash,format=raw,file=OVMF_VARS.fd -drive file=disk.img,if=virtio,format=raw -net nic,model=virtio -net user,hostfwd=tcp::10022-:22 -nographic -serial mon:stdio
```

You should eventually get an IEx prompt. The first boot takes longer since the
application data partition will be formatted. Run `poweroff` at the IEx prompt
to exit out of Qemu or if you're having trouble, run `killall
qemu-system-x86_64` in another shell window.

You can ssh into the system by using port 10022. Try `ssh -p 10022 localhost`.
It's possible to run an "over-the-air" firmware update also using ssh by running
the following:

```sh
mix firmware.gen.script # create the upload.sh script
SSH_OPTIONS="-p 10022" ./upload.sh localhost
```

## Root disk naming

If you have multiple SSDs, or other devices connected, it's
possible that Linux will enumerate those devices in a nondeterministic order.
This can be mitigated by using `udev` to populate the `/dev/disks/by-*`
directories, but even this can be inconvenient when you just want to refer to
the drive that provides the root filesystem. To address this, `erlinit` creates
`/dev/rootdisk0`, `/dev/rootdisk0p1`, etc. and symlinks them to the expected
devices. For example, if your root file system is on `/dev/mmcblk0p1`, you'll
get a symlink from `/dev/rootdisk0p1` to `/dev/mmcblk0p1` and the whole disk
will be `/dev/rootdisk0`. Similarly, if the root filesystem is on `/dev/sdb1`,
you'd still get `/dev/rootdisk0p1` and `/dev/rootdisk0` and they'd by symlinked
to `/dev/sdb1` and `/dev/sdb` respectively.

## Provisioning devices

This system supports storing provisioning information in a small key-value store
outside of any filesystem. Provisioning is an optional step and reasonable
defaults are provided if this is missing.

Provisioning information can be queried using the Nerves.Runtime KV store's
[`Nerves.Runtime.KV.get/1`](https://nerves-runtime.hexdocs.pm/Nerves.Runtime.KV.html#get/1)
function.

Keys used by this system are:

Key                    | Example Value     | Description
:--------------------- | :---------------- | :----------
`nerves_serial_number` | `"12345678"`      | By default, this string is used to create unique hostnames and Erlang node names. If unset, it defaults to part of the Ethernet adapter's MAC address.

The normal procedure would be to set these keys once in manufacturing or before
deployment and then leave them alone.

For example, to provision a serial number on a running device, run the following
and reboot:

```elixir
iex> cmd("fw_setenv nerves_serial_number 12345678")
```

This system supports setting the serial number offline. To do this, set the
`NERVES_SERIAL_NUMBER` environment variable when burning the firmware. If you're
programming MicroSD cards using `fwup`, the commandline is:

```sh
sudo NERVES_SERIAL_NUMBER=12345678 fwup path_to_firmware.fw
```

Serial numbers are stored on the MicroSD card so if the MicroSD card is
replaced, the serial number will need to be reprogrammed. The numbers are stored
in a U-boot environment block. This is a special region that is separate from
the application partition so reformatting the application partition will not
lose the serial number or any other data stored in this block.

Additional key value pairs can be provisioned by overriding the default provisioning.conf
file location by setting the environment variable
`NERVES_PROVISIONING=/path/to/provisioning.conf`. The default provisioning.conf
will set the `nerves_serial_number`, if you override the location to this file,
you will be responsible for setting this yourself.
