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

Run it as your normal user, it calls `sudo` when it needs to. It expects a fresh
installation, with nouveau and without any proprietary driver, and running it
more than once is safe. It stops if it does not find both gpus. Reboot when it
finishes.

### What it does

1. Finds both gpus by their pci vendor, `0x1002` for amd and `0x10de` for nvidia.
2. Installs `nvidia-open-dkms`, `nvidia-utils`, `nvidia-prime` and `vulkan-radeon`, plus the headers of every installed kernel. `nvidia-open` is the branch recommended for ampere cards and dkms rebuilds it for every kernel.
3. Writes the kernel mode setting and power management options into `/etc/modprobe.d/nvidia.conf`, and blacklists nouveau.
4. Puts both graphics drivers into the initramfs, drops the `kms` hook from `/etc/mkinitcpio.conf` and rebuilds it.
5. Enables the nvidia suspend, resume and hibernate services.
6. Writes `/etc/tmpfiles.d/nvidia-runtime-pm.conf`, which lets the dgpu and its hdmi audio device power off when they are idle.
7. Installs `files/gpu-run` and `files/gpu-mux` into `/usr/local/bin`.
8. Writes the graphics environment of hyprland into `~/.config/hypr/conf/environments/default.lua`.

### How to check that it worked

```bash
dgpu                                    # function of .bashrc_custom: D0 is awake, D3cold is asleep
cat /proc/driver/nvidia/gpus/*/power    # the runtime d3 status should be enabled
gpu-mux status                          # current mux mode
nvidia-smi                              # lists the dgpu, and wakes it up in the process
```

### Things learned the hard way

- **The list of `AQ_DRM_DEVICES` is colon separated.** A path from
  `/dev/dri/by-path` carries its pci address, which contains colons, so it gets
  split into garbage, hyprland finds no gpus and crashes while starting. The
  `/dev/dri/cardN` nodes have no colons, and those are the ones the script
  detects.

- **The runtime power management cannot be set with a udev rule.** nvidia is
  loaded from the initramfs, so its bind event happens before the rules of `/etc`
  exist and the rule never fires. A `systemd-tmpfiles` entry runs later, already
  in the real root, and does work.

- **Hyprland has to manage both gpus, the amd one first.** The hdmi port is wired
  to the dgpu, so without it in the list there is no external screen. With both
  listed and the power control set to auto, the dgpu still reaches D3cold when
  nothing is plugged in.

- **`fbdev=1` is harmless,** it does not keep the dgpu awake. Only the missing
  runtime power management did.

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
  number. Both drivers sit in the initramfs and probe at the same time, so the
  winner changes from boot to boot:

    - amdgpu registers first: the real panel is `eDP-1`, the dead nvidia link is `eDP-2`.
    - nvidia registers first: the dead nvidia link is `eDP-1`, the real panel is `eDP-2`.

  A rule pinned to `eDP-1` therefore lands on the dead connector every other boot
  and the panel comes up with its preferred mode and scale 1.
