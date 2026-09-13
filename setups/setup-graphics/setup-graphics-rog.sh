#!/bin/bash
#
# Hybrid graphics setup for the ASUS ROG Strix G513. Read readme.md before
# touching this script, it explains every step and the reasons behind them.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
FILES_DIR="$SCRIPT_DIR/files"

# Both gpus are found on the pci bus by their vendor, so no graphics driver
# needs to be loaded for this check.
for dev in /sys/bus/pci/devices/*; do
    [[ $(cat "$dev/class") == 0x03* ]] || continue   # display controllers only

    case $(cat "$dev/vendor") in
        0x1002) IGPU_PCI=$(basename "$dev") ;;   # AMD
        0x10de) DGPU_PCI=$(basename "$dev") ;;   # NVIDIA
    esac
done

if [[ -z "$IGPU_PCI" || -z "$DGPU_PCI" ]]; then
    echo "Error: this script needs an AMD igpu and an NVIDIA dgpu, but found ${IGPU_PCI:-none} and ${DGPU_PCI:-none}."
    exit 1
fi

echo "Found the igpu at $IGPU_PCI and the dgpu at $DGPU_PCI."


echo "Installing the nvidia drivers and the amd vulkan driver..."

PACKAGES=(nvidia-open-dkms nvidia-utils nvidia-prime vulkan-radeon vulkan-icd-loader)

# dkms builds the nvidia module against the headers of every installed kernel.
for kernel in linux linux-lts linux-zen linux-hardened; do
    pacman -Qq "$kernel" &> /dev/null && PACKAGES+=("$kernel-headers")
done

sudo pacman -S --needed --noconfirm "${PACKAGES[@]}"


echo "Installing nvidia-laptop-power-cfg..."

# The asus-linux package with the nvidia power management: the module options
# in /etc/modprobe.d/nvidia.conf and the udev rule that lets the dgpu power off
# when it is idle. Its hdmi audio device is handled by snd_hda_intel itself.
if ! pacman -Qq nvidia-laptop-power-cfg &> /dev/null; then
    BUILD_DIR=$(mktemp -d)
    git clone https://gitlab.com/asus-linux/nvidia-laptop-power-cfg.git "$BUILD_DIR"
    (cd "$BUILD_DIR" && makepkg -sfi --noconfirm)
    rm -rf "$BUILD_DIR"
fi


echo "Rebuilding the initramfs without nouveau..."

# Only amdgpu is loaded early. nvidia loads later from the real root, so that
# the udev rule of nvidia-laptop-power-cfg sees it bind.
sudo tee /etc/mkinitcpio.conf.d/graphics.conf > /dev/null << 'EOF'
MODULES+=(amdgpu)
EOF

# The kms hook would put nouveau into the initramfs, the module above replaces
# it. The original file is kept as /etc/mkinitcpio.conf.bak.
if grep -qE '^HOOKS=.*\bkms\b' /etc/mkinitcpio.conf; then
    sudo sed -i.bak -E '/^HOOKS=\(/ { s/\bkms\b//; s/  +/ /g; s/\( /(/; s/ \)/)/ }' /etc/mkinitcpio.conf
fi

sudo mkinitcpio -P


echo "Enabling the nvidia suspend services and the dynamic boost daemon..."
sudo systemctl enable nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service

# nvidia-powerd shifts the power budget between the cpu and the dgpu, this
# laptop reports notebook dynamic boost as supported. It needs the nvidia
# driver, so on the first run it only starts after the reboot.
sudo systemctl enable nvidia-powerd.service
[[ -d /sys/module/nvidia ]] && sudo systemctl start nvidia-powerd.service


echo "Disabling the panel self refresh of the igpu..."

# Plugging or unplugging the charger makes amdgpu re-commit its idle
# optimizations, the panel self refresh transition asserts (a WARNING in
# power_psr.c) and the panel freezes. amdgpu.dcdebugmask=0x10 turns it off.
# The original file is kept as /etc/default/grub.bak.
if [[ ! -e /etc/default/grub ]]; then
    echo "Warning: no grub found, add amdgpu.dcdebugmask=0x10 to the kernel command line yourself."
elif ! grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=.*amdgpu\.dcdebugmask=0x10' /etc/default/grub; then
    sudo sed -i.bak -E '/^GRUB_CMDLINE_LINUX_DEFAULT="/ s/"$/ amdgpu.dcdebugmask=0x10"/' /etc/default/grub
    sudo grub-mkconfig -o /boot/grub/grub.cfg
fi


echo "Keeping nvidia-powerd running on battery..."

# asusd stops nvidia-powerd on battery and starts it again on ac, which opens
# the dgpu one more time at every charger event, while the sbios disables the
# dynamic boost on battery anyway. asusd writes asusd.ron on its first start.
ASUSD_CONF=/etc/asusd/asusd.ron

if [[ ! -e "$ASUSD_CONF" ]]; then
    echo "Warning: $ASUSD_CONF does not exist, install asusctl and run this script again."
elif grep -qE '^\s*disable_nvidia_powerd_on_battery:\s*true,' "$ASUSD_CONF"; then
    sudo sed -i -E 's/^(\s*disable_nvidia_powerd_on_battery:\s*)true,/\1false,/' "$ASUSD_CONF"
    sudo systemctl restart asusd.service
fi


echo "Installing the gpu-run and gpu-mux commands..."
sudo install -Dm755 "$FILES_DIR/gpu-run" /usr/local/bin/gpu-run
sudo install -Dm755 "$FILES_DIR/gpu-mux" /usr/local/bin/gpu-mux


echo "Writing the graphics environment of hyprland..."

# Every radeon icd, their names depend on multilib being installed or not.
RADEON_ICD=""
for icd in /usr/share/vulkan/icd.d/radeon_icd*.json; do
    [[ -e "$icd" ]] && RADEON_ICD="${RADEON_ICD:+$RADEON_ICD:}$icd"
done

ENVIRONMENTS_DIR="$HOME/.config/hypr/conf/environments"

mkdir -p "$ENVIRONMENTS_DIR"
cat > "$ENVIRONMENTS_DIR/default.lua" << EOF
-- Written by setup-graphics-rog.sh.

-- Gpus that hyprland manages, the amd igpu first so that it drives the panel
-- and the nvidia dgpu stays asleep. The cards are resolved by driver name at
-- every start because their numbers are not stable, and the list is colon
-- separated, so it needs card nodes and never paths from /dev/dri/by-path.
local amd, other = {}, {}
for n = 0, 9 do
    local uevent = io.open("/sys/class/drm/card" .. n .. "/device/uevent", "r")
    if uevent then
        local driver
        for line in uevent:lines() do
            driver = line:match("^DRIVER=(.*)$") or driver
        end
        uevent:close()
        table.insert(driver == "amdgpu" and amd or other, "/dev/dri/card" .. n)
    end
end
for _, dev in ipairs(other) do table.insert(amd, dev) end
if #amd > 0 then hl.env("AQ_DRM_DEVICES", table.concat(amd, ":")) end

-- Vulkan and va-api default to amd so that apps do not wake up the dgpu.
hl.env("VK_DRIVER_FILES", "$RADEON_ICD")
hl.env("LIBVA_DRIVER_NAME", "radeonsi")
EOF


echo "The graphics setup is done, reboot to apply it. Read readme.md to know how to use the dgpu."
echo "After the reboot, check that 'cat /proc/driver/nvidia/gpus/*/power' reports S0ix as enabled."
