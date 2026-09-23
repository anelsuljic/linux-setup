# Virtualization with qemu/kvm

How to set up qemu/kvm with libvirt on the ASUS ROG Strix G513RW running Arch
with hyprland, for one windows 11 vm that gets the nvidia dgpu and its own nvme
drive, and for linux vms used to try out distros. Everything the vms need to
survive a reinstall of the host lives outside of the root filesystem, so on a
fresh host only the [host setup](#2-host-setup) is repeated and the vms are
defined again from their saved definitions.

The decisions behind the setup, so that the rest makes sense:

- **libvirt with virt-manager**, connected to `qemu:///system`. It handles
  permissions, networking, uefi, tpm and pci devices, and it stores every vm as
  an xml file that can be exported and imported.
- **Windows lives on the Samsung nvme** (`/dev/nvme0n1` today) and gets the
  whole nvme controller as a pci device. The host binds it to `vfio-pci` at boot
  and never sees the drive again.
- **The dgpu stays on the host** for cuda and `gpu-run`, and is handed to a vm
  only while that vm runs. libvirt does the driver switching, a small hook
  script takes care of what would keep the nvidia driver busy. For that to work
  without a logout, hyprland has to stop managing the dgpu, which costs the hdmi
  port on the host.
- **The screen of the windows vm is the laptop panel**, through
  [Looking Glass](https://looking-glass.io/): the dgpu renders into shared
  memory and a client window on hyprland shows it. A virtual display driver
  inside windows replaces the monitor that the dgpu does not have.
- **Everything else lives on `lv_vmstore`**, mounted at `/vmstore`: linux vm
  disks, isos, uefi variables, tpm state and the exported xml definitions.

## 1. What this laptop has

Facts the rest of the guide relies on, all read from this machine:

- AMD Ryzen 9 6900HX, 8 cores / 16 threads, 30 GiB of ram, AMD-V (`svm`) on in
  the bios. The kernel turns the AMD iommu on by itself when the bios exposes
  it, no kernel parameter is needed ([Arch wiki: PCI passthrough via OVMF, Enabling IOMMU](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#Enabling_IOMMU)).
- The pci devices that matter, each one alone in its iommu group, which is the
  best case for passthrough:

  | Device | PCI address | Vendor:device | IOMMU group |
  |---|---|---|---|
  | NVIDIA RTX 3070 Ti Laptop GPU | `01:00.0` | `10de:24a0` | 14 |
  | NVIDIA HDMI audio (same gpu) | `01:00.1` | `10de:228b` | 14 |
  | Samsung 970 EVO Plus 500 GB (windows) | `02:00.0` | `144d:a808` | 15 |
  | Micron 2450 1 TB (host) | `05:00.0` | `1344:5411` | 18 |
  | AMD Radeon 680M igpu | `06:00.0` | `1002:1681` | 19 |

- The host is on the Micron: efi and `/boot` partitions, then luks with lvm
  `volgroup0` holding `lv_root`, `lv_swap` and `lv_vmstore` (350 GiB, ext4,
  currently not mounted). Grub boots it, mkinitcpio builds the initramfs with
  the systemd hooks (`sd-encrypt`, `lvm2`), `amdgpu` is early loaded through
  `/etc/mkinitcpio.conf.d/graphics.conf`.
- Hybrid graphics as set up by [setup-graphics-rog.sh](../setups/setup-graphics/readme.md):
  the igpu drives the panel (2560x1440 at 165 Hz), the hdmi port is wired to the
  dgpu, hyprland manages both gpus and the dgpu sleeps in D3cold.
- `kvm_amd` is already loaded, nothing else related to virtualization is
  installed.

Commands to confirm it on any boot:

```bash
lscpu | grep -E 'Model name|Virtualization'     # AMD-V
ls /sys/kernel/iommu_groups | wc -l              # 28 groups here, 0 means the iommu is off
lsmod | grep -w kvm_amd
```

To list every iommu group with its devices (script from the
[asus-linux vfio guide](https://asus-linux.org/guides/vfio-guide/)):

```bash
for g in $(find /sys/kernel/iommu_groups/* -maxdepth 0 -type d | sort -V); do
    echo "IOMMU group ${g##*/}:"
    for d in $g/devices/*; do echo -e "\t$(lspci -nns ${d##*/})"; done
done
```

> `/dev/nvme0n1` and `/dev/nvme1n1` are numbered in probe order and can swap
> between boots. The comments in `/etc/fstab` still call the efi partition of
> the host `/dev/nvme0n1p1`, and today that drive is `nvme1n1`. Always identify
> the windows drive by its pci address `02:00.0` or by
> `/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_500GB_S4EVNX0NB19363E`.

## 2. Host setup

Everything in this section is host configuration. It is what has to be redone
on a fresh install, and nothing here touches the vms themselves.

### 2.1 Packages

```bash
sudo pacman -S --needed qemu-desktop libvirt virt-manager edk2-ovmf swtpm dnsmasq
yay -S looking-glass looking-glass-module-dkms
```

- `qemu-desktop`: qemu with kvm, spice, virtio-gpu and usb passthrough, the
  variant the [Arch wiki](https://wiki.archlinux.org/title/QEMU#Installation)
  recommends for a desktop.
- `libvirt` and `virt-manager`: the daemon and its gui, `virsh` comes with
  libvirt.
- `edk2-ovmf`: the uefi firmware of the vms. `swtpm`: the emulated tpm 2.0
  that windows 11 requires. `dnsmasq`: dhcp and dns of the default vm network.
- `looking-glass` is the client, `looking-glass-module-dkms` the `kvmfr`
  kernel module that lets it use the dma engine of the gpu. Both are aur
  packages ([Arch wiki: Looking Glass](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#Using_Looking_Glass_to_stream_guest_screen_to_the_host)),
  and dkms needs the headers of every installed kernel, which the nvidia setup
  already installs.

### 2.2 libvirt daemon and access

```bash
sudo systemctl enable --now libvirtd.service
sudo usermod -aG libvirt,kvm "$USER"
```

- `libvirtd.service` also pulls in `virtlogd` and `virtlockd` through their
  sockets ([Arch wiki: libvirt, Daemon](https://wiki.archlinux.org/title/Libvirt#Daemon)).
- The `libvirt` group gets password-less access to the system connection
  through a polkit rule that libvirt ships. The `kvm` group is for the
  `/dev/kvmfr0` device of Looking Glass later on.

Log out and back in for the groups, then make `virsh` talk to the system
connection by default. The line belongs in `~/.bashrc_custom`
(`setups/setup-bashrc`):

```bash
export LIBVIRT_DEFAULT_URI=qemu:///system
```

Check:

```bash
virsh list --all      # empty list, no error
```

### 2.3 Default network

libvirt ships a `default` nat network, `virbr0` on `192.168.122.0/24`, where
dnsmasq hands out addresses and the vms reach the internet through whatever
host interface is up ([libvirt: virtual networking](https://wiki.libvirt.org/VirtualNetworking.html#the-default-configuration)).
It only needs to be started and set to autostart:

```bash
virsh net-autostart default
virsh net-start default
virsh net-list --all          # default   active   yes
```

If `default` is not listed at all:

```bash
virsh net-define /usr/share/libvirt/networks/default.xml
```

### 2.4 The vm store

Mount `lv_vmstore` at `/vmstore`. The uuid is that of the filesystem inside
the logical volume, it survives reinstalls of the host as long as the volume
is not formatted:

```bash
sudo mkdir /vmstore
lsblk -o NAME,UUID /dev/mapper/volgroup0-lv_vmstore   # ce3c7188-b888-4b2d-bb1d-9df284c0d9f1
```

Add it to `/etc/fstab` next to the other entries:

```
# /dev/mapper/volgroup0-lv_vmstore
UUID=ce3c7188-b888-4b2d-bb1d-9df284c0d9f1	/vmstore  	ext4      	rw,relatime	0 2
```

```bash
sudo systemctl daemon-reload
sudo mount /vmstore
```

Then the folders. `iso` and `xml` belong to the user so that isos can be
copied and definitions exported without sudo, the rest stays with root and
libvirt changes the owner of the files it creates on its own:

```bash
sudo mkdir -p /vmstore/{images,iso,nvram,tpm,xml}
sudo chown "$USER" /vmstore/iso /vmstore/xml
```

| Folder | Content |
|---|---|
| `images/` | Disk images of the linux vms, libvirt pool `default`. |
| `iso/` | Installation isos, libvirt pool `iso`. |
| `nvram/` | Uefi variables of the vms (`<name>_VARS.fd`), the boot entries live here. |
| `tpm/` | State of the emulated tpm of the windows vm. |
| `xml/` | Exported definitions, one `<name>.xml` per vm, see [2.9](#29-saving-the-vm-definitions). |
| `share/` | Folder the windows vm mounts through virtiofs, see [3.4](#34-sharing-files-with-the-host). Created there. |

Storage pools tell libvirt and virt-manager where to create and look for
files ([Arch wiki: libvirt, Storage pools](https://wiki.archlinux.org/title/Libvirt#Storage_pools)).
The `default` pool is redefined so that virt-manager creates new disks in
`/vmstore/images` instead of `/var/lib/libvirt/images`:

```bash
virsh pool-destroy default 2>/dev/null; virsh pool-undefine default 2>/dev/null
virsh pool-define-as default dir --target /vmstore/images
virsh pool-define-as iso dir --target /vmstore/iso
virsh pool-autostart default && virsh pool-start default
virsh pool-autostart iso && virsh pool-start iso
virsh pool-list       # both active, autostart yes
```

### 2.5 Bind the windows nvme to vfio-pci at boot

The host must never mount, probe or format the Samsung drive, so `vfio-pci`
claims its controller before the `nvme` driver can. Binding by vendor:device
id is enough because the two nvme drives are different models
([Arch wiki: Binding vfio-pci via device ID](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#Binding_vfio-pci_via_device_ID)).

Two files in two different folders, one for modprobe and one for mkinitcpio,
each one only understands its own syntax.

The modprobe one, `/etc/modprobe.d/vfio.conf`:

```
options vfio-pci ids=144d:a808
softdep nvme pre: vfio-pci
```

The `softdep` line makes sure `vfio-pci` is loaded whenever `nvme` is about to
be, and the modules go into the initramfs so that the drive is taken before
the real root even exists ([Arch wiki: Loading vfio-pci early](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#Loading_vfio-pci_early)).
The `modconf` hook, already in `HOOKS`, copies `/etc/modprobe.d` into the
image, so the ids are known there too.

The mkinitcpio one, `/etc/mkinitcpio.conf.d/vfio-modules.conf`, next to
`graphics.conf`:

```
MODULES+=(vfio_pci vfio vfio_iommu_type1)
```

```bash
sudo mkinitcpio -P
```

Reboot and check:

```bash
lspci -nnk -s 02:00.0        # Kernel driver in use: vfio-pci
lsblk                        # the Samsung drive is gone
sudo dmesg | grep -i vfio    # vfio_pci: add [144d:a808[ffff:ffff]] ...
```

> The Arch wiki warns that early loading vfio can freeze the framebuffer and
> hide the luks password prompt. That happens when vfio takes a gpu, here it
> only takes the nvme, and `amdgpu` is early loaded anyway.

### 2.6 Hyprland on the igpu only

A pci device can only change driver when no process has it open, and hyprland
keeps the dgpu open all the time because it manages it for the hdmi port
(see [setup-graphics readme](../setups/setup-graphics/readme.md)). This is
the same reason why supergfxctl asks for a logout when switching to its vfio
mode. Instead of logging out before every vm, hyprland is told to leave the
dgpu alone when a marker file exists, so the switch happens on vm start
without any logout.

`~/.config/hypr/conf/environments/default.lua` is written by
`setup-graphics-rog.sh`, so make the change in the file and in the script
(`setups/setup-graphics/setup-graphics-rog.sh`, the heredoc that writes
`default.lua`), otherwise a rerun of the script undoes it. Replace the line

```lua
for _, dev in ipairs(other) do table.insert(amd, dev) end
```

with

```lua
-- With ~/.config/hypr/igpu-only present hyprland leaves the dgpu alone, so
-- that a vm can take it without a logout. The hdmi port then only works
-- inside the vm that has the dgpu. Egl is restricted to mesa as well: glvnd
-- otherwise loads the nvidia egl library while hyprland looks for its egl
-- device, and that library opens /dev/nvidia0 and keeps it open. Every app
-- hyprland starts inherits the variable, gpu-run sets it back to nvidia.
local igpu_only = io.open(os.getenv("HOME") .. "/.config/hypr/igpu-only", "r")
if igpu_only then
    igpu_only:close()
    hl.env("__EGL_VENDOR_LIBRARY_FILENAMES", "/usr/share/glvnd/egl_vendor.d/50_mesa.json")
else
    for _, dev in ipairs(other) do table.insert(amd, dev) end
end
```

Leaving the dgpu out of `AQ_DRM_DEVICES` is not enough on its own: the nvidia
driver only lets a device go when every process has closed it, and glvnd makes
hyprland (and any egl app) open it without ever rendering on it. The
`__EGL_VENDOR_LIBRARY_FILENAMES` line stops that. The same env variable has to
be set the other way round in `gpu-run` (`setups/setup-graphics/files/gpu-run`
and `/usr/local/bin/gpu-run`), otherwise egl apps started with it silently
render on the igpu:

```sh
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
```

Create the marker and log out and in:

```bash
touch ~/.config/hypr/igpu-only
```

Check that hyprland has only the amd card open and that nothing holds the
dgpu. Variables set from the config do not show in `/proc/<pid>/environ`, the
open files are what counts:

```bash
ls -l /proc/$(pidof Hyprland)/fd | grep -E 'dri|nvidia'    # only the amdgpu card and render node, no /dev/nvidia*
ls -l /dev/dri/by-path/                                    # which cardN and renderDN belong to 06:00.0 (amd) and 01:00.0 (nvidia)
sudo fuser -v /dev/nvidia* /dev/dri/by-path/pci-0000:01:00.0-*   # nothing, or nvidia-powerd only
dgpu                                                        # still D3cold
```

Anything that `fuser` lists on `/dev/nvidia*` besides `nvidia-powerd` has to
be closed before a vm with the dgpu starts; the hook of 2.7 refuses the start
and names it otherwise. `rog-control-center` is one of them: it reads the card
through nvml, which opens `/dev/nvidia0`, so close it before starting a vm.

One more file, because `AQ_DRM_DEVICES` is only honoured when hyprland
starts: when the nvidia driver comes back after a vm, its drm card appears
again as a new device and aquamarine adds every hotplugged gpu, list or not,
so hyprland would grab the dgpu after the first vm. The rule below takes the
`seat` tags away from the drm card of the nvidia gpu, and a device without
them is unknown to logind, which then refuses to hand it to any compositor of
the session ([systemd: multi-seat](https://www.freedesktop.org/wiki/Software/systemd/multiseat/)).
Only the card node is affected; the render node, `gpu-run` and cuda are not.

`/etc/udev/rules.d/72-vfio-dgpu.rules`:

```
# The drm card of the nvidia dgpu is hidden from logind so that no compositor
# of the session can take it: hyprland would otherwise grab it every time the
# nvidia driver comes back after a vm (aquamarine adds hotplugged gpus even
# when AQ_DRM_DEVICES leaves them out). The render node is not affected.
SUBSYSTEM=="drm", KERNEL=="card[0-9]*", ATTRS{vendor}=="0x10de", TAG-="seat", TAG-="master-of-seat"
```

```bash
sudo udevadm control --reload
```

It applies the next time the card is added, that is after the next vm or
reboot. A hyprland that already holds the card keeps it until a logout.

What changes on the host: the hdmi port does nothing while hyprland runs on
the igpu, it belongs to whichever vm has the dgpu (a monitor plugged in shows
that vm directly). Cuda and `gpu-run` keep working as before, they do not need
hyprland to manage the card. Removing the marker file and logging in again
gives the old behaviour back.

### 2.7 libvirt hook that frees the dgpu

libvirt itself unbinds `nvidia` and binds `vfio-pci` when a vm with
`managed="yes"` pci devices starts, and reverses it when the vm stops. What it
cannot do is stop `nvidia-powerd`, which keeps the driver open, or tell why an
unbind failed. That is the job of the hook, which libvirt runs on every vm
event with the vm xml on stdin ([libvirt: hooks](https://libvirt.org/hooks.html)).
The hook only acts for vms that have the dgpu attached, so linux vms without
it are not touched.

`/etc/libvirt/hooks/qemu`:

```bash
#!/bin/bash
# Frees the nvidia dgpu for a vm that has it attached and gives it back when
# the vm stops. libvirt binds vfio-pci and rebinds nvidia on its own
# (managed="yes"), this only handles what would keep the nvidia driver busy.
# libvirt runs it as: qemu <vm> <operation> <phase> - with the vm xml on stdin.

vm="$1" operation="$2" phase="$3"
gpu="0000:01:00.0"

uses_gpu=$(xmllint --xpath \
    "count(//hostdev/source/address[@bus='0x01'][@slot='0x00'][@function='0x0'])" -)
[ "$uses_gpu" != "0" ] || exit 0

# nvidia-powerd allows five starts per boot, reset-failed lifts that.
powerd_start() {
    systemctl reset-failed nvidia-powerd.service
    systemctl start nvidia-powerd.service
}

shopt -s nullglob
case "$operation/$phase" in
    prepare/begin)
        systemctl stop nvidia-powerd.service
        # Only /dev/nvidia* matters: the nvidia driver waits for every user of
        # these to close them before it lets the card go, and libvirt would
        # hang. A drm node held open is unplugged cleanly by the kernel.
        if fuser -s /dev/nvidia* 2>/dev/null; then
            echo "$vm: the dgpu is in use on the host, see: fuser -v /dev/nvidia*" >&2
            powerd_start
            exit 1
        fi
        echo on > "/sys/bus/pci/devices/$gpu/power/control"    # wake it from D3cold
        ;;
    release/end)
        # libvirt has rebound nvidia by now. The udev rule of
        # nvidia-laptop-power-cfg enables the runtime power management on that
        # bind, repeating it here costs nothing and covers a refused start.
        for _ in $(seq 50); do
            [ "$(basename "$(readlink "/sys/bus/pci/devices/$gpu/driver" 2>/dev/null)")" = nvidia ] && break
            sleep 0.2
        done
        echo auto > "/sys/bus/pci/devices/$gpu/power/control"
        powerd_start
        ;;
esac
```

```bash
sudo chmod +x /etc/libvirt/hooks/qemu
sudo systemctl restart libvirtd.service     # hooks are picked up at daemon start
```

- `prepare/begin` runs before libvirt touches any device. A non zero exit
  aborts the vm start, so a dgpu that is still in use shows up as a clear
  error in virt-manager instead of a hung libvirt.
- `release/end` runs after libvirt has given the dgpu back to `nvidia`. It
  sets the runtime power management to `auto` so the card goes back to
  sleep, and starts `nvidia-powerd` again.
- `xmllint` comes with `libxml2`, a dependency of libvirt. Hooks must not call
  `virsh`, libvirt would deadlock, hence the sysfs and xml parsing.

### 2.8 Looking Glass on the host

Looking Glass moves frames from the vm to the host through a shared memory
device, whose size depends on the resolution. For the 2560x1440 panel it is
64 MiB ([Looking Glass: determining memory](https://looking-glass.io/docs/B7/install_libvirt/#determining-memory)):

```
2560 x 1440 x 4 bytes x 2 frames = 29.5 MiB, + 10 MiB, rounded up to a power of 2 = 64 MiB
```

The kvmfr module creates that device
([Looking Glass: IVSHMEM with the KVMFR module](https://looking-glass.io/docs/B7/ivshmem_kvmfr/)).
Three files, then load it:

`/etc/modprobe.d/kvmfr.conf`:

```
options kvmfr static_size_mb=64
```

`/etc/modules-load.d/kvmfr.conf`:

```
kvmfr
```

`/etc/udev/rules.d/99-kvmfr.rules`, so that both qemu (runs as
`libvirt-qemu`, member of `kvm`) and the user (added to `kvm` in 2.2) can use
it:

```
SUBSYSTEM=="kvmfr", GROUP="kvm", MODE="0660"
```

```bash
sudo modprobe kvmfr
ls -l /dev/kvmfr0          # crw-rw---- root kvm, a character device
```

qemu runs inside a cgroup that only allows a fixed list of devices, so
`/dev/kvmfr0` has to be added to it. In `/etc/libvirt/qemu.conf` uncomment
the `cgroup_device_acl` block and add the device, the result looks like this:

```
cgroup_device_acl = [
    "/dev/null", "/dev/full", "/dev/zero",
    "/dev/random", "/dev/urandom",
    "/dev/ptmx", "/dev/kvm",
    "/dev/userfaultfd",
    "/dev/kvmfr0"
]
```

```bash
sudo systemctl restart libvirtd.service
```

Client settings, `~/.config/looking-glass/client.ini`
([Looking Glass: client usage](https://looking-glass.io/docs/B7/usage/)).
The escape key is what toggles input capture and prefixes every shortcut, the
default `ScrollLock` does not exist on this keyboard. The chosen key is not
passed to the vm:

```ini
[app]
shmFile=/dev/kvmfr0

[win]
fullScreen=yes

[input]
escapeKey=KEY_RIGHTCTRL
```

`looking-glass-client -m help` lists the valid key names. The windows side of
Looking Glass must be the exact same version as the client, check it with
`pacman -Q looking-glass`.

### 2.9 Saving the vm definitions

libvirt keeps the vm definitions in `/etc/libvirt/qemu/`, which does not
survive a reinstall. `vm-export` copies them into `/vmstore/xml`, run it after
every change made in virt-manager or with `virsh edit`.

`/usr/local/bin/vm-export`:

```bash
#!/bin/sh
# Saves the definition of every vm into /vmstore/xml, so that a fresh host
# can take them back with: virsh define /vmstore/xml/<name>.xml

set -e
export LIBVIRT_DEFAULT_URI=qemu:///system
for vm in $(virsh list --all --name); do
    virsh dumpxml --inactive "$vm" > "/vmstore/xml/$vm.xml"
    echo "saved /vmstore/xml/$vm.xml"
done
```

```bash
sudo chmod +x /usr/local/bin/vm-export
```

`--inactive` writes the stored definition, without the runtime details of a
running vm.

### 2.10 Everything the host setup produced

The list to keep in mind for a reinstall, all of it is in this guide:

| Where | What |
|---|---|
| `/etc/fstab` | The `/vmstore` line. |
| `/etc/modprobe.d/vfio.conf`, `/etc/mkinitcpio.conf.d/vfio-modules.conf` | The windows nvme on vfio-pci. |
| `~/.config/hypr/conf/environments/default.lua`, `~/.config/hypr/igpu-only`, `/usr/local/bin/gpu-run`, `/etc/udev/rules.d/72-vfio-dgpu.rules` | Hyprland on the igpu. |
| `/etc/libvirt/hooks/qemu` | The dgpu hook. |
| `/etc/modprobe.d/kvmfr.conf`, `/etc/modules-load.d/kvmfr.conf`, `/etc/udev/rules.d/99-kvmfr.rules`, `/etc/libvirt/qemu.conf` | Looking Glass. |
| `~/.config/looking-glass/client.ini` | Looking Glass client. |
| `/usr/local/bin/vm-export` | Export of the definitions. |

## 3. Windows 11 vm

### 3.1 New install

#### Isos

Download the windows 11 iso from
[microsoft](https://www.microsoft.com/software-download/windows11) and the
virtio drivers iso from the
[virtio-win project](https://github.com/virtio-win/virtio-win-pkg-scripts)
into the iso pool. Windows ships no driver for virtio devices, so the second
iso is needed during the install for the network card and afterwards for the
guest tools:

```bash
mv ~/Downloads/Win11*.iso /vmstore/iso/win11.iso
curl -L -o /vmstore/iso/virtio-win.iso \
    https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso
virsh pool-refresh iso
```

#### Create the vm in virt-manager

Once: `Edit > Preferences > General > Enable XML editing`, it adds an XML tab
to every device page.

`File > New Virtual Machine`:

1. `Local install media`, browse to `win11.iso` in the `iso` pool. The
   detected os is `Windows 11`, which makes virt-manager pick the secure boot
   firmware and add a tpm 2.0 on its own.
2. Memory `16384`, CPUs `12`.
3. Uncheck `Enable storage for this virtual machine`. The disk is the
   passed-through nvme.
4. Name `win11`, check `Customize configuration before install`, `Finish`.

In the customize window:

1. `Overview`: chipset `Q35`, firmware `UEFI` (the secure boot variant,
   `OVMF_CODE.secboot.4m.fd`). In its XML tab, inside `<os>`, add or edit the
   `nvram` line so that the uefi variables land on the vm store:
   ```xml
   <nvram>/vmstore/nvram/win11_VARS.fd</nvram>
   ```
   libvirt fills in the template on its own; with the manual firmware form the
   line is `<nvram template="/usr/share/edk2/x64/OVMF_VARS.4m.fd">/vmstore/nvram/win11_VARS.fd</nvram>`.
2. `CPUs`: uncheck `Copy host CPU configuration` and set the model to
   `host-passthrough`. `Topology > Manually set`: 1 socket, 6 cores,
   2 threads.
3. `TPM`: model `CRB`, version `2.0`. In its XML tab, move the state to the vm
   store:
   ```xml
   <tpm model="tpm-crb">
     <backend type="emulator" version="2.0">
       <source type="dir" path="/vmstore/tpm/win11"/>
     </backend>
   </tpm>
   ```
   libvirt creates the folder with the right owner
   ([libvirt: TPM device](https://libvirt.org/formatdomain.html#tpm-device)).
4. `NIC`: device model `virtio`.
5. `Add Hardware > PCI Host Device`: `0000:02:00.0 Samsung Electronics ... NVMe`.
6. `Add Hardware > Storage`: device type `CDROM device`, select
   `virtio-win.iso` from the `iso` pool.
7. Remove `USB Redirector 1` and `2`.
8. `Begin Installation`.

#### Install windows

The spice window of virt-manager shows the vm. Press a key when the firmware
says `Press any key to boot from CD or DVD`, the nvme appears in the disk
list of the installer as a normal drive because it is a real one.

- Windows has no network until the virtio driver is loaded. At the disk step
  click `Load driver` and browse to `E:\NetKVM\w11\amd64` (the virtio-win cd),
  then continue. The alternative is an offline install with a local account:
  `Shift+F10`, then `start ms-cxh:localonly`.
- After the first login open the virtio-win cd and run
  `virtio-win-guest-tools.exe`. It installs every virtio driver, the spice
  agent (clipboard, resolution) and the qemu guest agent (clean shutdown from
  virt-manager).
- Run windows update, then shut down the vm and export the definition:

```bash
vm-export
```

#### Add the dgpu and tune the vm

With the vm off, `virsh edit win11` (or the XML tab of `Overview` in
virt-manager). The blocks below replace or add to what virt-manager
generated, the parts not shown stay as they are.

Start with the Looking Glass shared memory device, because it needs the qemu
namespace on the first line and **libvirt drops that namespace on save unless
a `<qemu:...>` element uses it in the same edit**. Changing the first line on
its own therefore looks like the change is refused. Both at once, the first
line:

```xml
<domain type="kvm" xmlns:qemu="http://libvirt.org/schemas/domain/qemu/1.0">
```

and the device right before `</domain>`, its size the 64 MiB of 2.8 in bytes:

```xml
<qemu:commandline>
  <qemu:arg value="-device"/>
  <qemu:arg value="{'driver':'ivshmem-plain','id':'shmem0','memdev':'looking-glass'}"/>
  <qemu:arg value="-object"/>
  <qemu:arg value="{'qom-type':'memory-backend-file','id':'looking-glass','mem-path':'/dev/kvmfr0','size':67108864,'share':true}"/>
</qemu:commandline>
```

After saving, `virsh dumpxml win11 | head -1` shows the namespace. The other
blocks can be added in the same or in later edits.

Pin the vcpus to cores 2 to 7 (cpus 4 to 15 of `lscpu -e`, a core is a pair
of consecutive cpus on this amd) and keep cores 0 and 1 for the host, hyprland
and the Looking Glass client. `topoext` tells windows which vcpus are siblings
([Arch wiki: CPU pinning](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#CPU_pinning),
[Improving performance on AMD CPUs](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#Improving_performance_on_AMD_CPUs)):

```xml
<vcpu placement="static">12</vcpu>
<cputune>
  <vcpupin vcpu="0" cpuset="4"/>
  <vcpupin vcpu="1" cpuset="5"/>
  <vcpupin vcpu="2" cpuset="6"/>
  <vcpupin vcpu="3" cpuset="7"/>
  <vcpupin vcpu="4" cpuset="8"/>
  <vcpupin vcpu="5" cpuset="9"/>
  <vcpupin vcpu="6" cpuset="10"/>
  <vcpupin vcpu="7" cpuset="11"/>
  <vcpupin vcpu="8" cpuset="12"/>
  <vcpupin vcpu="9" cpuset="13"/>
  <vcpupin vcpu="10" cpuset="14"/>
  <vcpupin vcpu="11" cpuset="15"/>
  <emulatorpin cpuset="0-3"/>
</cputune>
<cpu mode="host-passthrough" check="none" migratable="off">
  <topology sockets="1" dies="1" clusters="1" cores="6" threads="2"/>
  <cache mode="passthrough"/>
  <feature policy="require" name="topoext"/>
</cpu>
```

Hyper-V enlightenments, paravirtual interfaces that windows uses when it
finds them ([libvirt: Hyper-V features](https://libvirt.org/formatdomain.html#hypervisor-features)).
Replace the `<hyperv>` block inside `<features>`:

```xml
<hyperv mode="custom">
  <relaxed state="on"/>
  <vapic state="on"/>
  <spinlocks state="on" retries="8191"/>
  <vpindex state="on"/>
  <runtime state="on"/>
  <synic state="on"/>
  <stimer state="on">
    <direct state="on"/>
  </stimer>
  <reset state="on"/>
  <frequencies state="on"/>
  <reenlightenment state="on"/>
  <tlbflush state="on"/>
  <ipi state="on"/>
</hyperv>
```

Inside `<devices>`, the dgpu with both of its functions. `managed="yes"` is
what makes libvirt do the driver switching:

```xml
<hostdev mode="subsystem" type="pci" managed="yes">
  <source>
    <address domain="0x0000" bus="0x01" slot="0x00" function="0x0"/>
  </source>
</hostdev>
<hostdev mode="subsystem" type="pci" managed="yes">
  <source>
    <address domain="0x0000" bus="0x01" slot="0x00" function="0x1"/>
  </source>
</hostdev>
```

Still inside `<devices>`, what Looking Glass asks for
([Looking Glass: libvirt installation](https://looking-glass.io/docs/B7/install_libvirt/#keyboard-mouse-display-audio)):
the emulated display stays as `vga` (a fallback that shows in the spice
window), the tablet goes away, virtio keyboard and mouse come in, the sound
card plays through spice and the memory balloon is off because it hurts
passthrough. Keep the `<graphics type="spice">` device, it carries keyboard,
mouse, clipboard and audio to the client.

```xml
<video>
  <model type="vga"/>
</video>
<input type="mouse" bus="virtio"/>
<input type="keyboard" bus="virtio"/>
<sound model="ich9">
  <audio id="1"/>
</sound>
<audio id="1" type="spice"/>
<memballoon model="none"/>
```

(remove `<input type="tablet" bus="usb">...</input>` and any other `<sound>`
or `<audio>` element).

Save, export, and start the vm:

```bash
vm-export
virsh start win11
lspci -nnk -s 01:00.0        # Kernel driver in use: vfio-pci while the vm runs
```

Open the vm in virt-manager, the spice window still works through the
emulated display. Inside windows install the nvidia driver from
[nvidia.com](https://www.nvidia.com/Download/index.aspx) (GeForce RTX 3070 Ti
Laptop GPU), reboot, and check in the device manager that the gpu shows no
error. Error `Code 43` is handled in [3.1 Code 43](#code-43).

#### Looking Glass inside windows

1. Download the windows host installer from
   [looking-glass.io/downloads](https://looking-glass.io/downloads), same
   version as `pacman -Q looking-glass`. Run `looking-glass-host-setup.exe`
   as administrator with the default options, it installs the ivshmem driver
   and a service that starts on boot
   ([Looking Glass: host installation](https://looking-glass.io/docs/B7/install_host/)).
2. The dgpu has no monitor, so windows has no display on it to capture. The
   [Virtual Display Driver](https://github.com/VirtualDrivers/Virtual-Display-Driver)
   adds one, see [below](#the-virtual-display). An hdmi dummy plug does the
   same job in hardware.
3. `Settings > System > Display`: select the virtual display, `Multiple
   displays > Show only on 2` (the number of the virtual one), so that the
   emulated vga is off and the desktop lives on the dgpu.
4. On the host:

```bash
looking-glass-client
```

The window fills the panel, `RightCtrl` toggles between the vm and hyprland,
`RightCtrl+Q` quits the client, `RightCtrl+F` toggles full screen. Audio and
clipboard go through spice, nothing else to configure.

#### The virtual display

The driver creates a monitor that windows treats as a real one, attached to
the gpu of your choice. Everything is configured in one xml file, the control
app only installs, reloads and edits it
([VDD wiki: configuring the driver](https://github.com/VirtualDrivers/Virtual-Display-Driver/wiki/How-to-configure-the-driver)).

1. Download `VDD.Control.<version>.zip` from the
   [releases page](https://github.com/VirtualDrivers/Virtual-Display-Driver/releases),
   extract it anywhere and run `Virtual Driver Control` as administrator. It
   is portable, nothing else to install; it needs the Visual C++
   redistributable, which the Looking Glass host installer already pulled in.
2. Click `Install Driver` (bottom right) and wait for `Task Progress` to
   finish. Windows gets a new display at once, at a default resolution and on
   whichever gpu the driver picked.
3. Open `C:\VirtualDisplayDriver\vdd_settings.xml` in notepad (as
   administrator) or through `Tools > XML editor` of the app and make it say:
   one monitor, on the nvidia gpu by its device manager name, the resolution
   of the panel:
   ```xml
   <?xml version='1.0' encoding='utf-8'?>
   <vdd_settings>
       <monitors>
           <count>1</count>
       </monitors>
       <gpu>
           <friendlyname>NVIDIA GeForce RTX 3070 Ti Laptop GPU</friendlyname>
       </gpu>
       <global>
           <g_refresh_rate>60</g_refresh_rate>
           <g_refresh_rate>165</g_refresh_rate>
       </global>
       <resolutions>
           <resolution>
               <width>2560</width>
               <height>1440</height>
               <refresh_rate>165</refresh_rate>
           </resolution>
           <resolution>
               <width>1920</width>
               <height>1080</height>
               <refresh_rate>165</refresh_rate>
           </resolution>
       </resolutions>
       <options>
           <CustomEdid>false</CustomEdid>
           <PreventSpoof>false</PreventSpoof>
           <EdidCeaOverride>false</EdidCeaOverride>
           <HardwareCursor>true</HardwareCursor>
           <SDR10bit>false</SDR10bit>
           <HDRPlus>false</HDRPlus>
           <logging>false</logging>
           <debuglogging>false</debuglogging>
       </options>
   </vdd_settings>
   ```
   The `friendlyname` is what `Device Manager > Display adapters` shows for
   the dgpu, copy it from there if it differs. It matters: the vm has two
   display adapters, the emulated vga and the dgpu, and Looking Glass can
   only capture a display that hangs off the dgpu. `g_refresh_rate` values
   apply to every resolution, the `resolution` entries are the modes windows
   offers. `HardwareCursor` stays on so that the cursor of the vm is drawn by
   Looking Glass instead of twice.
4. Click `Restart Driver` in the app so it reads the file. `Settings > System > Display > Identify` 
   then shows two numbered displays; the new one is the virtual monitor, at `2560x1440` and, under 
   `Advanced display`, `165 Hz`.
5. Now step 3 above: select the virtual display, `Show only on <its number>`.
   The spice window of virt-manager goes black, that is expected, the desktop
   now only exists on the dgpu and the Looking Glass client shows it.

To get the desktop back on the emulated vga without seeing anything, click
into the black spice window, press `Win+P` and pick `Duplicate` with the arrow
keys and `Enter`. If windows ever comes up black after a driver update, the
project's advice is to boot into safe mode and uninstall the virtual display
from the device manager.

#### Code 43

Mobile nvidia gpus check for a battery, and a vm has none, which on some
models leaves the driver with `Code 43`. The asus-linux guide provides an acpi
table that adds a fake battery ([asus-linux: Code 43](https://asus-linux.org/guides/vfio-guide/)):

```bash
sudo curl -Lo /vmstore/acpitable.bin https://asus-linux.org/files/vfio/acpitable.bin
```

Add to the `<qemu:commandline>` block:

```xml
<qemu:arg value="-acpitable"/>
<qemu:arg value="file=/vmstore/acpitable.bin"/>
```

If that is not enough, hide the hypervisor from the driver as the
[Arch wiki](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#Video_card_driver_virtualisation_detection)
describes: `<vendor_id state="on" value="0123456789ab"/>` inside `<hyperv>`
and `<kvm><hidden state="on"/></kvm>` inside `<features>`.

### 3.2 Using it

```bash
virsh start win11 && looking-glass-client
```

or from virt-manager. Shut down from inside windows, or `virsh shutdown win11`
(the guest agent makes it a clean one). Afterwards the dgpu is back on the
host:

```bash
lspci -nnk -s 01:00.0        # Kernel driver in use: nvidia
dgpu                         # D3cold again after a few seconds
```

Every change to the vm in virt-manager or `virsh edit` is followed by
`vm-export`. Never `virsh undefine win11 --nvram` or `--tpm`, those delete the
uefi variables and the tpm state, `virsh undefine win11 --keep-nvram` is the
safe form if the definition ever has to be removed.

> Windows 11 turns on device encryption (bitlocker) by itself on some
> editions when signed in with a microsoft account, and its key is sealed by
> the emulated tpm in `/vmstore/tpm/win11`. Keep that folder, and keep the
> recovery key that windows stores in the microsoft account, or turn device
> encryption off in `Settings > Privacy & security > Device encryption`.

### 3.3 Reuse after a host reinstall

Windows itself is untouched by a host reinstall, it is on its own drive. What
it needs from the host is the definition, the uefi variables and the tpm
state, all on `/vmstore`. See [5. After a host reinstall](#5-after-a-host-reinstall).

### 3.4 Sharing files with the host

Windows mounts a folder of the host through virtiofs, a shared file system
that works over the memory of the vm instead of the network, so it needs no
samba and no addresses ([libvirt: virtiofs](https://libvirt.org/kbase/virtiofs.html)).
The host side is `virtiofsd`, already installed as a dependency of qemu, and
libvirt starts it with the vm. The windows side is the driver and service that
the virtio-win guest tools installed in 3.1, plus [WinFsp](https://winfsp.dev/),
the framework they run on ([virtio-win: virtiofs](https://github.com/virtio-win/kvm-guest-drivers-windows/wiki/Virtiofs:-Shared-file-system)).

First, create a folder in your host. You can create it where you want, for example on the vm store so that it survives a reinstall:

```bash
sudo mkdir /vmstore/share
sudo chown "$USER":users /vmstore/share
```

With the vm off, `virsh edit win11`. virtiofs needs the memory of the vm to
be shareable with the daemon, which is what `memoryBacking` does; add it
right after `<currentMemory>`:

```xml
<memoryBacking>
  <source type="memfd"/>
  <access mode="shared"/>
</memoryBacking>
```

and the share inside `<devices>`. `target dir` is only a tag, the name under
which windows sees the share:

```xml
<filesystem type="mount" accessmode="passthrough">
  <driver type="virtiofs" queue="1024"/>
  <source dir="/vmstore/share"/>
  <target dir="share"/>
</filesystem>
```

`vm-export`, start the vm, and in windows, in a terminal run as
administrator:

```
winget install WinFsp.WinFsp
reg add HKLM\Software\virtiofs /v Owner /t REG_SZ /d 1000:982
reg add HKLM\Software\virtiofs /v FileSystemName /t REG_SZ /d NTFS
Set-Service -Name "VirtioFsSvc" -StartupType Automatic
Start-Service -Name "VirtioFsSvc"
```

- `Owner` is the uid and gid that windows gives to everything it creates,
  `id -u` and `id -g` of the user on the host (`1000` and `982`, the `users`
  group), so the files belong to you and not to root.
- `FileSystemName` makes the share report itself as ntfs, without it windows
  refuses to run executables from it as administrator.
- The service was installed by the guest tools but could not run without
  WinFsp, these two lines start it now and on every boot.

The share appears as drive `Z:`. Check from the host that a file created in
windows lands in `/vmstore/share` owned by the user.

## 4. Linux vms

### 4.1 New install

Nothing is passed through, so a linux vm is all virtio: paravirtual disk,
network, video and file share, which is what makes it fast without giving it
any hardware. The steps below are for a vm called `fedora`; change the name
and the sizes, everything else is the same for every distro. The example
sizes are 8 GiB of ram and 8 vcpus (4 cores with their 2 threads, half of the
cpu) on a 40 GiB disk, plenty for a desktop and leaving the host and the
windows vm room.

#### The iso

```bash
mv ~/Downloads/Fedora-Workstation-Live-*.iso /vmstore/iso/
virsh pool-refresh iso
```

#### Create the vm in virt-manager

`File > New Virtual Machine`:

1. `Local install media`, browse to the iso in the `iso` pool. If the
   detection does not name the distro, untick `Automatically detect from the
   installation media` and pick it, or the closest `Generic Linux`. The choice
   only sets defaults.
2. Memory `8192`, CPUs `8`.
3. `Select or create custom storage > Manage`, pool `default`, `+` to create
   a volume: name `fedora.qcow2`, format `qcow2`, capacity `40` GiB, leave
   `Allocate entire volume now` off (the file grows as the vm uses it). It
   lands in `/vmstore/images/fedora.qcow2`.
4. Name `fedora`, tick `Customize configuration before install`, `Finish`.

In the customize window, in this order:

1. `Overview`: chipset `Q35`, firmware `UEFI x86_64:
   /usr/share/edk2/x64/OVMF_CODE.4m.fd` (no secure boot, nothing needs it; the
   `secboot` variant only when the distro's secure boot is what is being
   tested). In its XML tab add, inside `<os>`:
   ```xml
   <nvram>/vmstore/nvram/fedora_VARS.fd</nvram>
   ```
   so that the boot entry of the distro survives a host reinstall like the
   one of windows does.
2. `CPUs`: untick `Copy host CPU configuration`, model `host-passthrough`,
   `Topology > Manually set`: 1 socket, 4 cores, 2 threads. Then in its XML
   tab replace the `<cpu>` element with:
   ```xml
   <cpu mode="host-passthrough" check="none" migratable="off">
     <topology sockets="1" dies="1" clusters="1" cores="4" threads="2"/>
     <cache mode="passthrough"/>
     <feature policy="require" name="topoext"/>
   </cpu>
   ```
   The guest then sees the real cache sizes and which vcpus are siblings, the
   same reasons as for windows.
3. `VirtIO Disk 1`: bus `VirtIO` (the default for a linux os), and in its XML
   tab make the `<driver>` line:
   ```xml
   <driver name="qemu" type="qcow2" cache="none" io="native" discard="unmap"/>
   ```
   `cache="none"` with `io="native"` skips the host page cache, the guest has
   its own; `discard="unmap"` passes trims through, so that `fstrim` inside
   the guest shrinks the qcow2 file again
   ([Arch wiki: virtio disk](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#Virtio_disk)).
4. `NIC`: device model `virtio`, network source `default`.
5. `Display Spice`: listen type `None`, tick `OpenGL`, and pick the render
   node of the igpu. `Video Virtio`: model `Virtio`, tick `3D acceleration`.
   The desktop of the guest then renders on the igpu through virgl instead of
   in software, which is the difference between a laggy and a smooth desktop
   ([Arch wiki: QEMU guest graphics acceleration](https://wiki.archlinux.org/title/QEMU/Guest_graphics_acceleration#virgl)).
   In the XML tab of the display the result is:
   ```xml
   <graphics type="spice">
     <listen type="none"/>
     <gl enable="yes" rendernode="/dev/dri/by-path/pci-0000:06:00.0-render"/>
   </graphics>
   ```
   The render node is given by pci path on purpose: `renderD128`/`renderD129`
   swap depending on whether the dgpu is on the host or in a vm, the path of
   the igpu does not. In the XML tab of `Video Virtio`, add the resolution of
   the panel to the model, otherwise the guest is never offered more than
   1280x800, see
   [the resolution of the panel](#the-resolution-of-the-panel-and-its-165-hz-not-tested):
   ```xml
   <model type="virtio" heads="1" primary="yes">
     <acceleration accel3d="yes"/>
     <resolution x="2560" y="1440"/>
   </model>
   ```
6. `Sound ich9` stays, virt-manager wires it to spice, the viewer plays it.
7. Remove `USB Redirector 1` and `2`. Keep the `Tablet`, it is what makes the
   mouse move seamlessly between the viewer window and the host.
8. The share of [3.4](#34-sharing-files-with-the-host), which linux mounts
   natively. In the XML tab of `Overview` add after `<currentMemory>`:
   ```xml
   <memoryBacking>
     <source type="memfd"/>
     <access mode="shared"/>
   </memoryBacking>
   ```
   and `Add Hardware > Filesystem`: driver `virtiofs`, source path
   `/vmstore/share`, target path `share`.
9. `Begin Installation`.


#### If the distro hangs right after the grub menu (not tested)

Debian, Fedora, Rocky and the rest of the RHEL family, live isos included,
hang with a frozen viewer and one core at 100 % after choosing a grub entry.
It is an open incompatibility between Arch's `edk2-ovmf` (202505 and newer)
and the grub those distros patch
([Arch wiki: QEMU troubleshooting](https://wiki.archlinux.org/title/QEMU/Troubleshooting#Linux_guest_boot_hangs_with_GRUB_in_UEFI_mode)).
Fedora's build of the same firmware does not have it, and it installs next
to Arch's, under `/usr/share/edk2/ovmf/`, without touching it:

```bash
yay -S edk2-ovmf-fedora
```

libvirt orders the firmware descriptions by file name and Fedora's sort
before Arch's, so from then on the automatic `UEFI` choice of virt-manager
and `--boot uefi` pick Fedora's firmware for every new vm, which is fine for
any linux. For a vm that already exists, in `Overview` pick
`/usr/share/edk2/ovmf/OVMF_CODE_4M.fd` in the firmware dropdown (its files
are listed there once the package is in), or with `virt-install` replace
`--boot uefi,...` by:

```
--boot loader=/usr/share/edk2/ovmf/OVMF_CODE_4M.fd,loader.readonly=yes,loader.type=pflash,nvram=/vmstore/nvram/fedora_VARS.fd,nvram.template=/usr/share/edk2/ovmf/OVMF_VARS_4M.fd
```

The windows vm keeps the firmware paths stored in its xml, it is not
affected.

#### Inside the guest (not tested)

Right after the install, two packages and one mount:

| Distro | Packages |
|---|---|
| Arch | `spice-vdagent qemu-guest-agent` |
| Fedora | `spice-vdagent qemu-guest-agent` (Workstation has them already) |
| Debian, Ubuntu | `spice-vdagent qemu-guest-agent` |

- `spice-vdagent` gives clipboard sharing with the host and a desktop that
  follows the size of the viewer window; `qemu-guest-agent` lets
  `virsh shutdown` and virt-manager shut the vm down cleanly. Both start on
  their own once installed (`systemctl enable --now qemu-guest-agent` where
  the distro does not).
- The share, in `/etc/fstab` of the guest:
  ```
  share  /mnt/share  virtiofs  defaults  0  0
  ```
  after `sudo mkdir /mnt/share`; the tag `share` is the `target` of step 8.
  Files written from the guest belong to the guest's uid on the host, so a
  guest user with uid 1000 matches the user on the host.
- The 3d acceleration needs nothing, every current distro ships the virgl
  driver in mesa; `glxinfo -B` inside the guest says `virgl`.

Shut down, then `vm-export`.

#### The resolution of the panel and its 165 Hz (not tested)

The guest offers a list of modes that stops below the 2560x1440 of the panel,
with 60 Hz as the only refresh rate, and virt-manager stretches that small
desktop over the whole screen. Nothing is broken: there is no monitor behind
the virtio display, so qemu writes the edid of the guest's screen itself. Its
preferred mode is the `xres`/`yres` pair of the video device, 1280x800 by
default; the rest of the list is the fixed set of standard timings the
generator knows, and 2560x1440 is not one of them; and the refresh rate of the
preferred mode is the one the ui reports to qemu, which spice does not report.
On top of that virt-manager scales the console by default
(`Scale Display > Always`) and does not resize the guest, so the mismatch is
easy to miss.

Three changes, one per layer.

**1. The edid, in the vm xml.** With the vm off, `virsh edit fedora` (or the
XML tab of `Video Virtio` in virt-manager), and add the resolution of the
panel to the model:

```xml
<video>
  <model type="virtio" heads="1" primary="yes">
    <acceleration accel3d="yes"/>
    <resolution x="2560" y="1440"/>
  </model>
</video>
```

libvirt hands it to qemu as `xres=2560,yres=1440`
([libvirt: video devices](https://libvirt.org/formatdomain.html#video-devices)),
which can be checked without starting the vm:

```bash
virsh domxml-to-native --format qemu-argv --domain fedora | tr ' ' '\n' | grep virtio-vga
# {"driver":"virtio-vga-gl","id":"video0",...,"xres":2560,"yres":1440,...}
```

From there the guest comes up at 2560x1440, boot console and login screen
included.

**2. The refresh rate, on the kernel command line of the guest.** The edid
generator of qemu does take a `refresh_rate` property, but only the plain
`VGA` and `bochs-display` devices expose it (compare
`qemu-system-x86_64 -device VGA,help` with `-device virtio-vga-gl,help`), and
neither of them does 3d, which is a bad trade for a desktop. On
`virtio-vga-gl` the rate can only come from the ui, and spice sends none, so
the mode is added inside the guest instead, where the drm layer accepts modes
the edid does not carry ([kernel: modedb](https://docs.kernel.org/fb/modedb.html)):

```
video=Virtual-1:2560x1440MR@165
```

`Virtual-1` is the connector of the virtio gpu (`ls /sys/class/drm` in the
guest shows `card0-Virtual-1`), `M` computes the timings with cvt, `R` asks
for reduced blanking so the pixel clock stays sane, `@165` is the rate. The
timings are fiction, nothing drives a cable: what reaches the host is the
resolution, and what the guest paces its compositor to is the rate. The kernel
only adds the mode when the edid has none with the same resolution *and* rate,
so 2560x1440 ends up in the list twice, at 60 Hz from the edid and at 165 Hz
from here.

Where the line goes depends on the boot loader of the guest: with grub it is
`GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub` followed by
`sudo grub-mkconfig -o /boot/grub/grub.cfg`, with systemd-boot the `options`
line of `/boot/loader/entries/<entry>.conf`, with a unified kernel image
`/etc/kernel/cmdline` and the rebuild of the image. After the reboot of the
guest:

```bash
cat /sys/class/drm/card*-Virtual-1/modes | head     # 2560x1440 twice
```

**3. The viewer.** In virt-manager `View > Scale Display > Never` and
`View > Fullscreen`, so that the console is shown pixel for pixel on the panel
(`View > Resize to VM` does the same for a window). Leave `Auto resize VM with
window` unchecked: with it on, the guest follows the size of the window, which
regenerates the edid on every resize and throws the chosen mode away.

The mode is then picked in the guest like on any machine: `Settings >
Displays` on gnome, the display settings of kde, or
`monitor=Virtual-1,2560x1440@165,0x0,1` in the hyprland config of a guest like
omarchy. `hyprctl monitors`, `wlr-randr` or `xrandr` show what arrived.

`vm-export` after the xml change.

> The 165 Hz is what the guest believes and paces itself to, not a guarantee:
> the frames still travel through virgl and spice to the client window, which
> hyprland presents on the panel at its own 165 Hz. What it removes is the
> 60 Hz ceiling inside the guest, which is what makes the desktop feel like
> the one of the host.

### 4.2 Reuse after a host reinstall (not tested)

The disk is in `/vmstore/images`, the uefi variables in `/vmstore/nvram`
and the definition in `/vmstore/xml`, all referenced by absolute paths that
are the same on the new host. See
[5. After a host reinstall](#5-after-a-host-reinstall). A vm created with
Fedora's firmware needs `edk2-ovmf-fedora` on the new host too.

### 4.3 The dgpu in a linux vm

The hook and libvirt do not care which vm asks for the dgpu, so the two
`<hostdev>` blocks of [3.1](#add-the-dgpu-and-tune-the-vm) work in a linux vm
too. What differs is the screen: Looking Glass has no finished linux host
application, so the vm shows its dgpu output on a monitor plugged into the
hdmi port, or uses the dgpu only for cuda while its desktop stays on the
virtio display. Inside the vm install the distro's nvidia packages, the open
kernel modules for this ampere card.

## 5. After a host reinstall

What survives on its own, given that the install of the new host leaves
`lv_vmstore` and the Samsung nvme alone:

| What | Where |
|---|---|
| Windows itself | The Samsung nvme, `02:00.0`. |
| Linux vm disks | `/vmstore/images/` |
| Isos | `/vmstore/iso/` |
| Files shared with the windows vm | `/vmstore/share/` |
| Uefi variables of every vm | `/vmstore/nvram/<name>_VARS.fd` |
| Tpm state of the windows vm | `/vmstore/tpm/win11/` |
| Definitions of every vm | `/vmstore/xml/<name>.xml`, as long as `vm-export` ran after the last change |

Steps on the fresh host:

1. The whole of [2. Host setup](#2-host-setup), in order. The reboot of 2.5 and
   the logout of 2.6 are needed before any vm with the dgpu starts.
2. Take the definitions back:
   ```bash
   virsh define /vmstore/xml/win11.xml
   virsh define /vmstore/xml/<linux vm>.xml
   virsh pool-refresh default && virsh pool-refresh iso
   ```
3. Start them. Windows finds the same machine uuid (it is in the xml, so the
   activation holds), the same uefi boot entry and the same tpm.

If the host is not Arch, the xml carries a few Arch paths to adapt before
`virsh define`: the firmware in `<loader>` and the nvram template (or delete
both lines and let `firmware="efi"` on the `<os>` tag pick the local one),
`/usr/bin/qemu-system-x86_64` in `<emulator>`, and the `/dev/kvmfr0` device
and hook, which are set up the same way on any distro with the Looking Glass
and libvirt docs linked above.

## 6. What else could be passed through

Every device below is alone in its iommu group, so it can be given to a vm as
a pci device the same way as the nvme, with the host losing it while the vm
runs. None is needed now, this is the list for later.

| Device | PCI address | Use in a vm | Cost for the host |
|---|---|---|---|
| USB controllers `07:00.0`, `07:00.3`, `07:00.4`, `06:00.4` | groups 25, 26, 27, 22 | Real usb ports with hotplug inside the vm, the lowest latency for keyboards, mice, audio interfaces or vr. Find which physical port hangs off which controller with `lsusb -t` and `udevadm info -q path -n /dev/bus/usb/<bus>/<dev>`. | The ports on that controller are gone from the host while the vm runs. |
| USB controller `06:00.3` | group 21 | The internal keyboard (`ASUSTek N-KEY Device`) is on this one. Passing it gives the vm the laptop keyboard directly. | The host loses the keyboard until the vm stops, only do it with an external keyboard at hand. The touchpad is i2c and stays on the host. |
| Realtek 2.5 GbE `04:00.0` | group 17 | A real network card for a vm, for router or firewall distros, or for measuring network performance. | No wired network on the host, the wifi stays. |
| MediaTek MT7922 wifi `03:00.0` | group 16 | Wifi driver testing, wifi captures inside the vm. | No wifi on the host, and the bluetooth of the same module is a usb device that can be passed separately. |
| Ryzen HD audio `06:00.6` | group 24 | The laptop speakers and microphone jack driven directly by windows. | No audio on the host. Spice audio already does the job without it. |

Not candidates: the igpu `06:00.0` drives the panel, the Micron nvme
`05:00.0` is the host, `06:00.2` is the security processor.

For single peripherals a usb device passthrough is simpler than a whole
controller: `Add Hardware > USB Host Device` in virt-manager hands one
device (webcam, bluetooth, game controller, usb stick) to the vm, no iommu
group involved, and it can be attached and detached while the vm runs. A
device listed in the xml has to be plugged in when the vm starts, or the
start fails.

## 7. Troubleshooting

- **`Hook script execution failed` when starting a vm.** Something on the
  host has `/dev/nvidia*` open. `sudo fuser -v /dev/nvidia*` names it. If it
  is `Hyprland`, the egl line of 2.6 is missing or the session was not
  restarted. If it is an app (`rog-control-center`, a cuda program, something
  run with `gpu-run`), close it. `journalctl -u libvirtd` has the message of
  the hook.
- **The dgpu stays awake after the vm** (`dgpu` says `active`, `D0`). Check
  `cat /sys/bus/pci/devices/0000:01:00.0/power/control`: it must be `auto`,
  `echo auto | sudo tee` that file if not; the hook does it on every clean
  stop. Then `sudo fuser -v /dev/nvidia*` for what keeps it busy.
- **`nvidia-powerd` is `failed` with `start-limit-hit`.** Its unit allows
  five starts per boot and every vm cycle uses one. `sudo systemctl
  reset-failed nvidia-powerd && sudo systemctl start nvidia-powerd`; the
  hook does the same.
- **Hyprland holds `/dev/dri/card0` after a vm** (`ls -l /proc/$(pidof
  Hyprland)/fd | grep card0`). The udev rule of 2.6 is missing or was added
  after the card came back; log out and in once, from then on it applies.
- **An xml edit is silently reverted.** libvirt rewrites the xml on save
  and drops what it considers unused, most visibly the `xmlns:qemu`
  namespace when no `<qemu:commandline>` exists yet. Add both in one edit,
  see [3.1](#add-the-dgpu-and-tune-the-vm). A real error (a typo, an
  unknown element) is shown instead, and `virsh edit` offers to reopen the
  editor.
- **The hook does nothing.** libvirt only reads `/etc/libvirt/hooks` when it
  starts: `sudo systemctl restart libvirtd`. Check it is executable.
- **The dgpu does not come back after the vm stops.** `lspci -nnk -s 01:00.0`
  still says `vfio-pci`. Give it back by hand:
  ```bash
  echo 0000:01:00.0 | sudo tee /sys/bus/pci/drivers/vfio-pci/unbind
  echo 0000:01:00.1 | sudo tee /sys/bus/pci/drivers/vfio-pci/unbind
  echo 0000:01:00.0 | sudo tee /sys/bus/pci/drivers_probe
  echo 0000:01:00.1 | sudo tee /sys/bus/pci/drivers_probe
  ```
- **Looking Glass shows `Waiting for host`.** The host service inside windows
  is not running or captures nothing: the desktop must be on the virtual
  display, that display must belong to the dgpu (`friendlyname` in
  `vdd_settings.xml`), and both versions must match. The log of the host
  service is `C:\ProgramData\Looking Glass (host)\looking-glass-host.txt`.
- **`/dev/kvmfr0` is a regular file.** A vm started before the module was
  loaded and qemu created a file in its place. `sudo rm /dev/kvmfr0 && sudo
  modprobe -r kvmfr && sudo modprobe kvmfr`
  ([Looking Glass: kvmfr](https://looking-glass.io/docs/B7/ivshmem_kvmfr/)).
- **Windows sees no network during the install.** The virtio-win cd is not
  attached or the `NetKVM` driver was not loaded, see [3.1](#install-windows).
- **The Samsung drive shows up in `lsblk`.** vfio-pci did not take it: check
  `/etc/modprobe.d/vfio.conf`, that the mkinitcpio drop-in exists, and that
  `mkinitcpio -P` ran after both. A `libkmod: ERROR ... ignoring bad line
  starting with 'MODULES+=('` during `mkinitcpio -P` means the `MODULES` line
  landed in the modprobe file instead of the mkinitcpio one.
- **A linux vm with grub hangs right after the grub menu** (Debian, Fedora,
  RHEL family and their live isos) with `edk2-ovmf` 202505 or newer. Known
  Arch packaging issue; the workaround is Fedora's firmware, see
  [4.1](#if-the-distro-hangs-right-after-the-grub-menu).
- **A linux vm offers neither 2560x1440 nor 165 Hz.** The edid of the virtio
  display is generated by qemu and knows neither: the `<resolution>` element
  of the video model brings the resolution, a
  `video=Virtual-1:2560x1440MR@165` on the kernel command line of the guest
  brings the rate, see
  [4.1](#the-resolution-of-the-panel-and-its-165-hz-not-tested). A guest
  desktop that looks soft instead of small is virt-manager scaling it,
  `View > Scale Display > Never`.
- **Stutter in the windows vm.** Check the pinning is in place
  (`virsh vcpupin win11`), that `memballoon` is `none`, and that hyprland does
  not run something heavy on cpus 4 to 15 (`taskset` can keep it on `0-3`).
  Static huge pages give at most a couple of percent on top and lock the
  memory even while the vm is off, so they are left out
  ([Arch wiki: Huge memory pages](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#Huge_memory_pages)).
