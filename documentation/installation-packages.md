# Packages installed during the installation

Every package that `arch-linux-installation.md` installs, in the order of the
guide, with one sentence saying what it is. When something is only useful
because of a later step of the setup, that step is named.

## Step 8: `pacstrap`

- `base`: the meta package that pulls the minimum for a bootable Arch system: `bash`, `coreutils`, `systemd`, `pacman`, `util-linux`, `iproute2`, `pciutils`, `shadow`, `glibc`... It contains no kernel, no firmware and no editor.

## Step 13: additional packages

- `base-devel`: the tools needed to build packages with `makepkg` (`gcc`, `make`, `binutils`, `fakeroot`, `patch`, `pkgconf`...); required to build `yay` and any AUR package in the post-install.
- `amd-ucode`: the microcode updates for AMD cpus, loaded at boot by the `microcode` hook of the initramfs; both machines are Ryzen.
- `cryptsetup`: the userspace tool for LUKS/dm-crypt, used to format and open the encrypted partition; the `sd-encrypt` hook needs it inside the initramfs.
- `dosfstools`: `mkfs.fat` and `fsck.fat`, used to format the EFI partition and to check it at boot.
- `mtools`: utilities to read and write FAT filesystems without mounting them (`mcopy`, `mdir`...); only `grub-mkrescue` uses them, nothing in the guide does.
- `lvm2`: the Logical Volume Manager userspace (`pvcreate`, `vgcreate`, `lvcreate`...), needed to create the volumes and by the `lvm2` hook to activate them at boot.
- `grub`: the bootloader that shows the boot menu and loads the kernel.
- `efibootmgr`: edits the UEFI boot entries; `grub-install` uses it to register the GRUB entry in the firmware.
- `os-prober`: scans the other disks for other operating systems so that `grub-mkconfig` can add them to the menu; it only runs if `GRUB_DISABLE_OS_PROBER=false` is set in `/etc/default/grub`, which the guide does not do.
- `nano`: a small terminal text editor, the one used to edit the config files in the guide.
- `sudo`: lets the users of the `wheel` group run commands as root; every setup script relies on it.
- `networkmanager`: the daemon that manages wired and wifi connections (`nmcli`, `nmtui`); it pulls `wpa_supplicant` for wifi.
- `openssh`: the ssh client and the `sshd` server, used to finish the setup from another computer.
- `git`: version control, needed to clone `yay` and this repository in the post-install.
- `bluez`: the bluetooth daemon (`bluetoothd`) and the kernel-side protocol stack support.
- `bluez-utils`: the tools to use bluetooth from the terminal, mainly `bluetoothctl`.
- `bluez-deprecated-tools`: the old tools that bluez no longer maintains (`hcitool`, `hciconfig`, `rfcomm`...); everything they did is done by `bluetoothctl`.
- `pipewire`: the audio and video server that replaces PulseAudio and JACK; the base daemon alone does not handle audio.
- `wireplumber`: the session manager of pipewire, it decides which device is the default and routes the streams; without it pipewire does nothing.
- `pipewire-audio`: the meta package that adds audio support to pipewire (ALSA card profiles, bluetooth codecs, echo cancellation...); `pipewire-alsa` and `pipewire-pulse` pull it anyway.
- `pipewire-alsa`: makes the programs that talk directly to ALSA go through pipewire instead.
- `pipewire-pulse`: the PulseAudio compatible server, needed by nearly every desktop app (browsers, players, `pavucontrol`...).
- `pipewire-jack`: the JACK compatible server for professional audio programs (DAWs, Ardour...); nothing in the setup uses it.
- `ntfs-3g`: FUSE driver and tools (`mkfs.ntfs`, `ntfsfix`) for Windows NTFS disks; the kernel has its own `ntfs3` driver since 5.15, so this is mostly for the tools.
- `exfatprogs`: `mkfs.exfat` and `fsck.exfat` for exFAT disks, the format of most large USB sticks and SD cards; the kernel has the driver, this is only the tools.
- `xdg-user-dirs`: creates and manages the standard home folders (`Desktop`, `Documents`, `Downloads`...); the post-install runs `xdg-user-dirs-update`.
- `cups`: the printing server; `other/printing.md` installs it again together with `avahi` and the scanner tools, so it is not needed here.
- `man-db`: the `man` command and the database it searches.
- `man-pages`: the manual pages of the kernel and the C library (sections 2, 3, 4, 5, 7); the pages of each program come with the program itself.
- `reflector`: a script that downloads the mirror list and sorts it by speed or country; nothing in the guide runs it, the mirror list of the installed system is copied from the live ISO by `pacstrap`.

## Step 14: kernel

- `linux`: the current stable kernel and its modules.
- `linux-headers`: the headers of `linux`, only needed to build out-of-tree modules with dkms (the nvidia driver in `setup-graphics`).
- `linux-lts`: the long term support kernel, kept as a fallback boot entry in case `linux` breaks something.
- `linux-lts-headers`: the headers of `linux-lts`, same reason as `linux-headers`.
- `linux-firmware`: the firmware blobs the kernel loads into the hardware (wifi and bluetooth cards, gpus, sound codecs...); it is a meta package that pulls every vendor split (`linux-firmware-amdgpu`, `linux-firmware-realtek`, `linux-firmware-nvidia`...).

## Step 15: gpu drivers

- `mesa`: the open source OpenGL and Vulkan userspace drivers for AMD, Intel and nouveau; on the laptop it drives the AMD igpu, on the desktop it is only used until the nvidia driver is installed.
- `libva-mesa-driver`: the VA-API video decoding and encoding driver of mesa (hardware video playback on the AMD igpu); since mesa 24.2 it is part of the `mesa` package itself, so this name now installs nothing extra.

## Step 16: graphical user interface

The post-install installs `ml4w` (Hyprland) instead, so none of these are
installed in the current flow. Listed so that the section can be read.

**GNOME:**

- `gnome-shell`: the GNOME desktop itself (panel, activities, window management).
- `gnome-control-center`: the GNOME settings app.
- `gdm`: the GNOME display manager, the graphical login screen.
- `nautilus`: the GNOME file manager.
- `gnome-console`: the GNOME terminal emulator.
- `gnome-text-editor`: the GNOME text editor (`setup-simlinks.sh` links it as `gte`).
- `gnome-tweaks`: settings that GNOME hides from its settings app (fonts, startup apps, window buttons...).
- `gnome`: the package group with the standard GNOME desktop and its default apps.
- `gnome-extra`: the package group with every other GNOME application and game.

**KDE Plasma:**

- `plasma-desktop`: the Plasma desktop itself (panel, launcher, window management).
- `plasma-x11-session`: lets Plasma be started on X11 instead of Wayland.
- `sddm`: the display manager used by KDE, the graphical login screen (`setup-sddm` reuses it with a Hyprland greeter).
- `plasma-nm`: the Plasma applet for NetworkManager.
- `plasma-pa`: the Plasma applet for the audio volume.
- `powerdevil`: the Plasma power management (screen dimming, suspend, battery profiles).
- `bluedevil`: the Plasma bluetooth integration.
- `konsole`: the KDE terminal emulator.
- `dolphin`: the KDE file manager.
- `plasma`: the package group with the full Plasma desktop.
- `kde-system`: the package group with the KDE system tools (partition manager, system monitor...).
- `kde-utilities`: the package group with the KDE utilities (archiver, calculator, text editor...).
- `kde-applications`: the package group with every KDE application.
