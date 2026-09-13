#!/bin/bash
#
# Hybrid graphics setup for the ASUS ROG Strix G513. Read readme.md before
# touching this script, it explains every step and the reasons behind them.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
FILES_DIR="$SCRIPT_DIR/files"

# Card nodes are needed for hyprland.
for dev in /dev/dri/by-path/pci-*-card; do
    pci=$(basename "$dev" | sed -E 's/^pci-(.*)-card$/\1/')
    card=$(basename "$(readlink -f "$dev")")

    case $(cat "/sys/bus/pci/devices/$pci/vendor") in
        0x1002) IGPU_CARD="$card" ;;   # AMD
        0x10de) DGPU_CARD="$card" ;;   # NVIDIA
    esac
done

if [[ -z "$IGPU_CARD" || -z "$DGPU_CARD" ]]; then
    echo "Error: this script needs an AMD igpu and an NVIDIA dgpu, but found ${IGPU_CARD:-none} and ${DGPU_CARD:-none}."
    exit 1
fi

echo "Found the igpu on $IGPU_CARD and the dgpu on $DGPU_CARD."


echo "Installing the nvidia drivers and the amd vulkan driver..."

PACKAGES=(nvidia-open-dkms nvidia-utils nvidia-prime vulkan-radeon vulkan-icd-loader)

# dkms builds the nvidia module against the headers of every installed kernel.
for kernel in linux linux-lts linux-zen linux-hardened; do
    pacman -Qq "$kernel" &> /dev/null && PACKAGES+=("$kernel-headers")
done

sudo pacman -S --needed --noconfirm "${PACKAGES[@]}"


echo "Removing the files of the previous version of this script..."

# They collide with nvidia-laptop-power-cfg or duplicate what nvidia-utils
# ships. Only files that no package owns are removed.
for file in /etc/modprobe.d/nvidia.conf /etc/modprobe.d/nouveau-blacklist.conf \
            /etc/tmpfiles.d/nvidia-runtime-pm.conf /etc/mkinitcpio.conf.d/nvidia.conf; do
    [[ -e "$file" ]] && ! pacman -Qo "$file" &> /dev/null && sudo rm "$file"
done


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
# laptop reports notebook dynamic boost as supported.
sudo systemctl enable --now nvidia-powerd.service


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
echo "After the reboot, check that 'cat /proc/driver/nvidia/gpus/*/power' reports S0ix as enabled."
