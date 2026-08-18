#!/bin/bash
#
# Hybrid graphics setup for the ASUS ROG Strix G513. Read readme.md before
# touching this script, it explains every step and the reasons behind them.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
FILES_DIR="$SCRIPT_DIR/files"

# Card nodes are needed for hyprland and the pci address for the power management.
for dev in /dev/dri/by-path/pci-*-card; do
    pci=$(basename "$dev" | sed -E 's/^pci-(.*)-card$/\1/')
    card=$(basename "$(readlink -f "$dev")")

    case $(cat "/sys/bus/pci/devices/$pci/vendor") in
        0x1002) IGPU_CARD="$card" ;;                    # AMD
        0x10de) DGPU_CARD="$card"; DGPU_PCI="$pci" ;;   # NVIDIA
    esac
done

if [[ -z "$IGPU_CARD" || -z "$DGPU_CARD" ]]; then
    echo "Error: this script needs an AMD igpu and an NVIDIA dgpu, but found ${IGPU_CARD:-none} and ${DGPU_CARD:-none}."
    exit 1
fi

echo "Found the igpu on $IGPU_CARD and the dgpu on $DGPU_CARD."


echo "Installing the nvidia drivers and the amd vulkan driver..."

PACKAGES=(nvidia-open-dkms nvidia-utils nvidia-prime vulkan-radeon)

for kernel in linux linux-lts linux-zen linux-hardened; do
    pacman -Qq "$kernel" &> /dev/null && PACKAGES+=("$kernel-headers")
done

sudo pacman -S --needed --noconfirm "${PACKAGES[@]}"


echo "Writing the module options and blacklisting nouveau..."

sudo tee /etc/modprobe.d/nvidia.conf > /dev/null << 'EOF'
# Kernel mode setting, needed by wayland.
options nvidia_drm modeset=1 fbdev=1

# Let the dgpu power off when it is idle and keep its memory across suspend.
options nvidia NVreg_DynamicPowerManagement=0x02 NVreg_PreserveVideoMemoryAllocations=1
EOF

sudo tee /etc/modprobe.d/nouveau-blacklist.conf > /dev/null << 'EOF'
blacklist nouveau
options nouveau modeset=0
EOF


echo "Rebuilding the initramfs with both graphics drivers..."

sudo tee /etc/mkinitcpio.conf.d/nvidia.conf > /dev/null << 'EOF'
MODULES+=(amdgpu nvidia nvidia_modeset nvidia_uvm nvidia_drm)
EOF

# The kms hook would put nouveau back into the initramfs, the modules above
# replace it. The original file is kept as /etc/mkinitcpio.conf.bak.
if grep -qE '^HOOKS=.*\bkms\b' /etc/mkinitcpio.conf; then
    sudo sed -i.bak -E '/^HOOKS=\(/ { s/\bkms\b//; s/  +/ /g; s/\( /(/; s/ \)/)/ }' /etc/mkinitcpio.conf
fi

sudo mkinitcpio -P


echo "Enabling the nvidia suspend services..."
sudo systemctl enable nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service


echo "Enabling the runtime power management of the dgpu..."

DGPU_AUDIO="${DGPU_PCI%.*}.1"   # hdmi audio function of the dgpu

sudo tee /etc/tmpfiles.d/nvidia-runtime-pm.conf > /dev/null << EOF
w /sys/bus/pci/devices/$DGPU_PCI/power/control - - - - auto
w /sys/bus/pci/devices/$DGPU_AUDIO/power/control - - - - auto
EOF

sudo systemd-tmpfiles --create /etc/tmpfiles.d/nvidia-runtime-pm.conf


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

-- Gpus that hyprland manages, the primary one first. The list is colon
-- separated, so it needs card nodes and never paths from /dev/dri/by-path.
hl.env("AQ_DRM_DEVICES", "/dev/dri/$IGPU_CARD:/dev/dri/$DGPU_CARD")

-- Vulkan and va-api default to amd so that apps do not wake up the dgpu.
hl.env("VK_DRIVER_FILES", "$RADEON_ICD")
hl.env("LIBVA_DRIVER_NAME", "radeonsi")
EOF


echo "The graphics setup is done, reboot to apply it. Read readme.md to know how to use the dgpu."
