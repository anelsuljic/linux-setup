# Graphics setup

`setup-graphics.sh` asks which gpu to set up:

- `1070ti`: installs the legacy nvidia 580xx drivers from the aur.
- `3070ti`: runs `setup-graphics-rog.sh`.

## setup-graphics-rog.sh

Sets up the hybrid graphics of the ASUS ROG Strix G513, an amd radeon 680m igpu
together with an nvidia rtx 3070 ti dgpu, on Arch with hyprland.

The idea is to install the whole nvidia stack but keep the dgpu asleep (D3cold)
while nothing needs it, so there is no wake up lag and the battery lasts longer.
Once it is set up, the dgpu is used like this:

- Machine learning and cuda: just run the program, the dgpu wakes up on its own.
- Opengl and vulkan apps: `gpu-run <app>`.
- External screen: just plug it in, the hdmi port is wired to the dgpu.
- Maximum performance: `gpu-mux ultimate` and reboot.

Run it as your normal user, it calls `sudo` when it needs to. It is run by
`setup.sh` on a fresh installation of Arch with this hyprland environment, after
the asus-linux guide has been followed except for its nvidia section, so
`asusctl` is present and `asusd` is running, and every package it needs besides
the graphics ones is already installed. Running it again on a finished setup is
safe: every step either finds its work done and skips it, or rewrites a file
with the same content, and nothing is left behind apart from the initramfs
rebuild. It stops if it does not find both gpus. Reboot when it finishes.

It follows the nvidia section of the [asus-linux guide for Arch](https://opengamingcollective.github.io/asusctl/distributions/arch.html):
`nvidia-open-dkms` for an ampere card, `nvidia-laptop-power-cfg`, the nvidia
services and the vulkan packages. The guide warns that some ampere laptops crash
with the open driver because of gsp firmware issues; this one does not, so the
proprietary `nvidia-580xx-dkms` from the aur is only the fallback if
`journalctl -k | grep -i gsp` ever shows such crashes.

### What it does

1. Checks that both gpus are on the pci bus, display class `0x03` with vendor `0x1002` for amd and `0x10de` for nvidia. No graphics driver needs to be loaded for this.
2. Installs `nvidia-open-dkms`, `nvidia-utils`, `nvidia-prime`, `vulkan-radeon` and `vulkan-icd-loader`, plus the headers of every installed kernel. `nvidia-open` is the branch recommended for ampere cards and dkms rebuilds it for every kernel. nouveau is blacklisted by `/usr/lib/modprobe.d/nvidia-utils.conf`, nothing else is needed for that.
3. Builds and installs [`nvidia-laptop-power-cfg`](https://gitlab.com/asus-linux/nvidia-laptop-power-cfg) with `makepkg`. It ships `/etc/modprobe.d/nvidia.conf` (`nvidia_drm modeset=1 fbdev=0`, `NVreg_EnableS0ixPowerManagement=1`, `NVreg_DynamicPowerManagement=0x02`) and `/usr/lib/udev/rules.d/80-nvidia-pm.rules`, which sets the runtime power management of the dgpu to `auto` when the driver binds and removes the usb functions some nvidia cards expose. The hdmi audio function needs nothing, `snd_hda_intel` enables its runtime power management on its own. Skipped when the package is already installed.
4. Puts `amdgpu` into the initramfs, drops the `kms` hook from `/etc/mkinitcpio.conf` (it would pull nouveau in, the original is kept as `/etc/mkinitcpio.conf.bak`) and rebuilds it. nvidia is loaded later from the real root.
5. Enables the nvidia suspend, resume and hibernate services, and `nvidia-powerd` for the dynamic boost. `nvidia-powerd` is only started right away when the nvidia driver is loaded, on the first run it starts after the reboot.
6. Adds `amdgpu.dcdebugmask=0x10` to `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub` and regenerates `grub.cfg`, which disables the panel self refresh of the igpu. Skipped when the parameter is already there, and the original file is kept as `/etc/default/grub.bak`.
7. Sets `disable_nvidia_powerd_on_battery: false` in `/etc/asusd/asusd.ron` and restarts `asusd`. Skipped when it is already false, and it warns instead if the file does not exist yet.
8. Installs `files/gpu-run` and `files/gpu-mux` into `/usr/local/bin`.
9. Writes the graphics environment of hyprland into `~/.config/hypr/conf/environments/default.lua`. The file resolves the card nodes by driver name every time hyprland starts, the same way `sddm-hyprland` does for the greeter, so it contains no card numbers.

### How to check that it worked

```bash
dgpu                                    # function of .bashrc_custom: D0 is awake, D3cold is asleep
cat /proc/driver/nvidia/gpus/*/power    # runtime d3 and the s0ix status should be enabled
gpu-mux status                          # current mux mode
nvidia-smi                              # lists the dgpu, and wakes it up in the process
grep -o 'amdgpu.dcdebugmask=0x10' /proc/cmdline          # panel self refresh is off
grep disable_nvidia_powerd_on_battery /etc/asusd/asusd.ron  # false
```

### Things learned the hard way

- **The list of `AQ_DRM_DEVICES` is colon separated.** A path from
  `/dev/dri/by-path` carries its pci address, which contains colons, so it gets
  split into garbage, hyprland finds no gpus and crashes while starting. The
  `/dev/dri/cardN` nodes have no colons, so those are used.

- **Card numbers cannot be written down by the script.** They depend on which
  drivers are loaded and in which order: on the first run nouveau is bound to
  the dgpu, after the reboot nvidia loads late and gets a different number. On
  this laptop nvidia is `card0` and amdgpu `card1` even though amdgpu loads
  first, because `simpledrm` holds minor 0 during early boot, amdgpu takes
  minor 1, and nvidia inherits the freed minor 0 once it loads from the real
  root. So `default.lua` looks the cards up by the `DRIVER=` line of
  `/sys/class/drm/cardN/device/uevent` at every start, amd first, and hands the
  result to `AQ_DRM_DEVICES`.

- **nvidia must not be loaded from the initramfs.** The runtime power
  management is set by a udev rule on the bind event of the driver. When nvidia
  sat in the initramfs that bind happened before the rules of the real root
  existed and a rule matching only `bind` never fired, which is why an older
  version of this script used a `systemd-tmpfiles` entry instead. Now only
  `amdgpu` is early loaded, nvidia binds in the real root and the rule of
  `nvidia-laptop-power-cfg` sees it.

- **Hyprland has to manage both gpus, the amd one first.** The hdmi port is wired
  to the dgpu, so without it in the list there is no external screen. With both
  listed and the power control set to auto, the dgpu still reaches D3cold when
  nothing is plugged in.

- **S0ix has to be turned on by hand.** The dgpu reports its platform support
  as supported but leaves the status disabled until
  `NVreg_EnableS0ixPowerManagement=1` is set, which `nvidia-laptop-power-cfg`
  does. This laptop only offers `s2idle` in `/sys/power/mem_sleep`, so without
  it the dgpu stays powered during sleep.

- **`fbdev` does not matter for power.** The package sets `fbdev=0`, and
  `fbdev=1` did not keep the dgpu awake either. Only the missing runtime power
  management did.

- **Plugging or unplugging the charger froze the screen,** and a power off
  during the freeze needed a hardware reset. Three things happen at every
  charger event. The nvidia driver wakes the dgpu for a few seconds on its own,
  `nv-acpi.c` listens to the ac adapter and calls
  `rm_power_source_change_event`; this is by design and harmless. asusd
  switches the platform profile and, with `disable_nvidia_powerd_on_battery`
  on, stops or starts `nvidia-powerd`, which opens the dgpu one more time; the
  sbios disables the dynamic boost on battery anyway, so the setting saves
  nothing and is turned off. And amdgpu, the igpu that drives the panel,
  re-commits its idle optimizations and the panel self refresh transition
  asserts, `WARNING ... power_psr.c:236 mod_power_set_psr_event`, 12 to 19
  seconds after each event in the journal; that is the freeze, and
  `amdgpu.dcdebugmask=0x10` disables the panel self refresh for good.
  `rog-control-center` is only a gui over asusd and plays no part.

- **The name of the radeon vulkan icd changes** between `radeon_icd.json` and
  `radeon_icd.x86_64.json` depending on multilib, so the script looks it up
  instead of hardcoding it.

- **Connector names like `eDP-1` are not stable across boots** once hyprland
  manages both gpus, so no monitor rule may use them. Match the panel by its edid
  description instead, `monitor=desc:<make> <model>,...` or
  `hl.monitor({ output = "desc:<make> <model>", ... })` in lua, and read that
  description with `hyprctl monitors`. The rule of this laptop lives in
  `hyprland/asus-rog/config/hypr/custom.lua`, which is loaded after
  `monitors.lua` and therefore survives nwg-displays regenerating it.

  The reason they move is that the connector number comes from a counter shared
  by every drm device, handed out in the order the drivers register, which is why
  the first displayport of nvidia is `DP-6`: amdgpu already took `DP-1` to
  `DP-5`. Both gpus expose an eDP connector, the one of the dgpu being the panel
  link that the mux keeps disconnected in hybrid mode, and it still takes a
  number. When both drivers sat in the initramfs they probed at the same time
  and the winner changed from boot to boot:

    - amdgpu registers first: the real panel is `eDP-1`, the dead nvidia link is `eDP-2`.
    - nvidia registers first: the dead nvidia link is `eDP-1`, the real panel is `eDP-2`.

  A rule pinned to `eDP-1` therefore landed on the dead connector every other
  boot and the panel came up with its preferred mode and scale 1. With nvidia
  loading from the real root amdgpu should always register first, but the
  `desc:` rule does not depend on that and stays.
