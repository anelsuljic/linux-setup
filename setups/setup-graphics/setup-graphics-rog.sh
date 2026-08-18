#!/bin/bash
#
# setup-graphics-rog.sh
# ---------------------------------------------------------------------------
# Hybrid GPU setup for the ASUS ROG Strix G513 (AMD Radeon 680M iGPU +
# NVIDIA RTX 3070 Ti dGPU) on Arch + Hyprland (Wayland, SDDM, ml4w/HyprMod).
#
# Goal: install the NVIDIA stack but keep the dGPU DORMANT (D3cold) for daily
# use — no wake-lag, good battery — and use it on demand:
#   * ML / CUDA            : just run your program (the dGPU wakes automatically)
#   * GL / Vulkan apps     : `gpu-run <app>`
#   * HDMI / external screen: just plug it in (the HDMI port is wired to the dGPU)
#   * max performance      : `gpu-mux ultimate` + reboot
#
# Run it as your NORMAL USER (it calls sudo where needed). It is idempotent and
# meant for a FRESH install (nouveau, no proprietary driver yet). It is `source`d
# by setup-graphics.sh, so the body runs in a subshell to keep `set -e`/`exit`
# from killing the parent shell.
#
# === LESSONS FROM A MANUAL RUN — do NOT "simplify" these away ===============
#  1. AQ_DRM_DEVICES is COLON-separated. A /dev/dri/by-path value (its PCI
#     address contains ':') gets split into garbage -> "Found no gpus" -> Hyprland
#     crashes at CBackend::create(). We use the colon-free /dev/dri/cardN nodes,
#     auto-detected by PCI vendor.
#  2. weston >= 15 REMOVED fullscreen-shell.so. The SDDM Wayland greeter must use
#     kiosk-shell.so, or weston exits instantly and the greeter crash-loops.
#  3. The dGPU runtime-PM udev "bind" rule NEVER fires: nvidia is loaded from the
#     initramfs, so the bind event happens before /etc udev rules exist. Use a
#     systemd-tmpfiles entry (runs in the real root) to set power/control=auto.
#  4. The HDMI port is on the dGPU, so Hyprland must manage BOTH GPUs (AMD first)
#     or it cannot drive the external screen. With both listed + control=auto the
#     dGPU still reaches D3cold when undocked.
#  5. fbdev=1 is fine (it does NOT pin the GPU); D3cold was blocked only by #3.
#  6. The Vulkan ICD filename varies (radeon_icd.json vs radeon_icd.x86_64.json,
#     depending on multilib). Detect it instead of hardcoding.
#  7. CONSEQUENCE OF #4: once Hyprland manages both GPUs, connector names such as
#     `eDP-1` are NO LONGER STABLE ACROSS BOOTS, so monitor rules must not use
#     them. The kernel's connector suffix (drm connector_type_id) comes from a
#     counter SHARED BY ALL DRM DEVICES, handed out in driver-registration order
#     -- nvidia's first DisplayPort shows up as `DP-6` because amdgpu already
#     took DP-1..DP-5. Both GPUs expose an eDP connector (the dGPU's is the
#     MUX'd-off panel link: permanently "disconnected" in hybrid mode, but it
#     still consumes a number), and because §3 puts amdgpu AND nvidia_drm in the
#     initramfs they probe concurrently, so the winner alternates between boots:
#       amdgpu first -> real panel = eDP-1, dead nvidia link = eDP-2
#       nvidia first -> dead nvidia link = eDP-1, real panel = eDP-2
#     A `monitor=eDP-1,...` rule therefore lands on the dead connector every
#     other boot and the panel comes up at its preferred mode / scale 1. Match on
#     the EDID description instead (`monitor=desc:<make> <model>,...`), which is
#     tied to the physical display. §9 below checks for this and prints the exact
#     replacement rule.
# ===========================================================================

(
  set -euo pipefail

  log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
  warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
  die()  { printf '\n\033[1;31m[error]\033[0m %s\n' "$*"; exit 1; }

  [ "$(id -u)" -eq 0 ] && warn "Run this as your normal user, not root, or the Hyprland config will land in /root."

  # --- 0. Detect the two GPUs (by PCI vendor) --------------------------------
  log "Detecting GPUs"
  IGPU_PCI=""; DGPU_PCI=""; IGPU_CARD=""; DGPU_CARD=""
  for d in /dev/dri/by-path/pci-*-card; do
    [ -e "$d" ] || continue
    pci=$(basename "$d" | sed -E 's/^pci-(.*)-card$/\1/')
    vendor=$(cat "/sys/bus/pci/devices/$pci/vendor" 2>/dev/null || echo "")
    card=$(basename "$(readlink -f "$d")")
    case "$vendor" in
      0x1002) IGPU_PCI="$pci"; IGPU_CARD="$card" ;;   # AMD
      0x10de) DGPU_PCI="$pci"; DGPU_CARD="$card" ;;   # NVIDIA
    esac
  done
  [ -n "$DGPU_CARD" ] || die "No NVIDIA dGPU (0x10de) found — this script is for the ROG AMD+NVIDIA hybrid."
  [ -n "$IGPU_CARD" ] || warn "No AMD iGPU (0x1002) found; AMD-primary assumptions may not hold."
  log "iGPU: ${IGPU_CARD:-none} @ ${IGPU_PCI:-?}    dGPU: ${DGPU_CARD} @ ${DGPU_PCI}"

  # --- 1. Packages -----------------------------------------------------------
  # All official (extra) -> plain pacman, no AUR/yay needed. nvidia-open is the
  # recommended branch for Turing+ (Ampere). DKMS covers every installed kernel.
  log "Installing NVIDIA stack + AMD Vulkan (RADV) + weston"
  PKGS=(nvidia-open-dkms nvidia-utils nvidia-prime vulkan-radeon weston)
  for k in linux linux-lts linux-zen linux-hardened; do
    pacman -Qq "$k" >/dev/null 2>&1 && PKGS+=("${k}-headers") || true
  done
  sudo pacman -S --needed --noconfirm "${PKGS[@]}"

  # --- 2. NVIDIA modprobe options + blacklist nouveau ------------------------
  log "Writing /etc/modprobe.d/{nvidia,nouveau-blacklist}.conf"
  sudo install -d /etc/modprobe.d
  sudo tee /etc/modprobe.d/nvidia.conf >/dev/null <<'EOF'
# DRM kernel mode setting (required for Wayland / PRIME).
options nvidia_drm modeset=1 fbdev=1
# Fine-grained runtime power management (dGPU -> D3cold when idle) and preserve
# VRAM across system suspend/resume.
options nvidia NVreg_DynamicPowerManagement=0x02 NVreg_PreserveVideoMemoryAllocations=1
EOF
  sudo tee /etc/modprobe.d/nouveau-blacklist.conf >/dev/null <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

  # --- 3. initramfs: GPU modules early, drop the kms hook --------------------
  log "Configuring mkinitcpio and rebuilding the initramfs"
  sudo install -d /etc/mkinitcpio.conf.d
  # Append via a drop-in so we never have to rewrite the main MODULES line.
  sudo tee /etc/mkinitcpio.conf.d/nvidia.conf >/dev/null <<'EOF'
# amdgpu drives the laptop panel; the nvidia modules are needed for KMS/PRIME.
MODULES+=(amdgpu nvidia nvidia_modeset nvidia_uvm nvidia_drm)
EOF
  # Remove the `kms` hook from the main conf so nouveau can't be baked into the
  # initramfs at build time (we supply the GPU modules explicitly above).
  if grep -qE '^HOOKS=.*\bkms\b' /etc/mkinitcpio.conf; then
    sudo cp -a /etc/mkinitcpio.conf "/etc/mkinitcpio.conf.bak.$(date +%s)"
    sudo sed -i -E '/^HOOKS=\(/ { s/\bkms\b//; s/  +/ /g; s/\( /(/; s/ \)/)/ }' /etc/mkinitcpio.conf
  fi
  sudo mkinitcpio -P

  # --- 4. NVIDIA suspend/resume services -------------------------------------
  log "Enabling nvidia suspend/resume services"
  sudo systemctl enable nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service \
    || warn "some nvidia-*.service units were missing (continuing)"

  # --- 5. dGPU runtime PM via tmpfiles (see lesson #3) -----------------------
  log "Enabling dGPU runtime power management (control=auto via tmpfiles)"
  DGPU_AUDIO="${DGPU_PCI%.*}.1"   # HDMI-audio function of the dGPU
  sudo tee /etc/tmpfiles.d/nvidia-runtime-pm.conf >/dev/null <<EOF
# Enable PCI runtime PM so the NVIDIA dGPU reaches D3cold when idle. A udev
# 'bind' rule does NOT work: nvidia loads in the initramfs, before /etc udev
# rules exist. systemd-tmpfiles runs in the real root, after bind.
w /sys/bus/pci/devices/${DGPU_PCI}/power/control - - - - auto
w /sys/bus/pci/devices/${DGPU_AUDIO}/power/control - - - - auto
EOF
  sudo systemd-tmpfiles --create /etc/tmpfiles.d/nvidia-runtime-pm.conf || true

  # --- 6. SDDM Wayland greeter (weston) --------------------------------------
  if pacman -Qq sddm >/dev/null 2>&1; then
    # weston >=15 dropped fullscreen-shell.so; kiosk-shell is its replacement.
    WESTON_SHELL="kiosk-shell.so"
    [ -e "/usr/lib/weston/${WESTON_SHELL}" ] || WESTON_SHELL="desktop-shell.so"
    log "Configuring SDDM Wayland greeter (weston --shell=${WESTON_SHELL})"
    sudo install -d /etc/sddm.conf.d
    sudo tee /etc/sddm.conf.d/10-wayland.conf >/dev/null <<EOF
[General]
DisplayServer=wayland
EOF
  else
    warn "sddm not installed — skipping greeter config"
  fi

  # --- 7. gpu-run / gpu-mux helpers ------------------------------------------
  log "Installing gpu-run / gpu-mux into /usr/local/bin"
  sudo tee /usr/local/bin/gpu-run >/dev/null <<'EOF'
#!/bin/sh
# gpu-run <command...> : run a GL/Vulkan app on the NVIDIA dGPU (render offload).
# Not needed for CUDA/compute (those open the NVIDIA device directly).
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/nvidia_icd.json
export LIBVA_DRIVER_NAME=nvidia
exec "$@"
EOF
  sudo tee /usr/local/bin/gpu-mux >/dev/null <<'EOF'
#!/bin/sh
# gpu-mux {ultimate|hybrid|status} : switch the hardware GPU MUX (reboot needed).
#   ultimate : dGPU drives everything (best for HDMI/external + gaming)
#   hybrid   : default Optimus (AMD drives the panel, dGPU dormant/on-demand)
set -e
case "${1:-}" in
  ultimate|dgpu)  asusctl armoury set gpu_mux_mode 0; echo "MUX -> Ultimate. REBOOT to apply." ;;
  hybrid|optimus) asusctl armoury set gpu_mux_mode 1; echo "MUX -> Hybrid.   REBOOT to apply." ;;
  status)         asusctl armoury get gpu_mux_mode ;;
  *) echo "usage: gpu-mux {ultimate|hybrid|status}  (reboot required after a change)"; exit 1 ;;
esac
EOF
  sudo chmod +x /usr/local/bin/gpu-run /usr/local/bin/gpu-mux

  # --- 8. Hyprland GPU environment (per-user) --------------------------------
  # Default Vulkan/VA-API to AMD so apps never wake the dGPU; pin the compositor
  # to the AMD iGPU but keep the NVIDIA dGPU in the list so it can drive HDMI.
  RADEON_ICD=""   # join all radeon ICDs (handles multilib 32-bit) with ':'; avoid `ls` (may be aliased)
  for f in /usr/share/vulkan/icd.d/radeon_icd*.json; do
    [ -e "$f" ] && RADEON_ICD="${RADEON_ICD:+$RADEON_ICD:}$f"
  done
  RADEON_ICD=${RADEON_ICD:-/usr/share/vulkan/icd.d/radeon_icd.json}
  AQ="/dev/dri/${IGPU_CARD:-card0}:/dev/dri/${DGPU_CARD}"
  ENV_DIR="$HOME/.config/hypr/conf/environments"

  if [ -d "$HOME/.config/hypr" ]; then
    log "Writing Hyprland GPU env ($ENV_DIR/default.lua)"
    mkdir -p "$ENV_DIR"
    cat > "$ENV_DIR/default.lua" <<EOF
-- GPU policy (managed by setup-graphics-rog.sh). The AMD iGPU renders the
-- desktop; the NVIDIA dGPU stays dormant (D3cold) until explicitly used.

-- aquamarine device list: COLON-separated, PRIMARY FIRST. Use card NODES, never
-- /dev/dri/by-path (its ':' breaks the parser -> Hyprland crash). Detected by
-- PCI vendor at setup time: ${IGPU_CARD}=AMD (primary), ${DGPU_CARD}=NVIDIA (HDMI).
hl.env("AQ_DRM_DEVICES", "${AQ}")

-- Default Vulkan + VA-API to AMD so normal apps never wake the dGPU.
-- (\`gpu-run\` overrides these to use NVIDIA on demand.)
hl.env("VK_DRIVER_FILES", "${RADEON_ICD}")
hl.env("LIBVA_DRIVER_NAME", "radeonsi")
EOF
  else
    warn "Hyprland config ($HOME/.config/hypr) not found — set these env vars manually:"
    warn "  env = AQ_DRM_DEVICES,${AQ}"
    warn "  env = VK_DRIVER_FILES,${RADEON_ICD}"
    warn "  env = LIBVA_DRIVER_NAME,radeonsi"
  fi

  # --- 9. Guard: monitor rules pinned to connector names (see lesson #7) -----
  # Managing both GPUs (needed for HDMI) makes `eDP-N` names alternate between
  # boots. Anything that pins a monitor by name breaks on half of them, so flag
  # it and hand the user the description-based rule to paste in its place.
  log "Checking Hyprland monitor rules for unstable connector names"
  HYPR_DIR="$HOME/.config/hypr"
  OFFENDERS=""
  [ -d "$HYPR_DIR" ] && OFFENDERS=$(grep -rlE '^[^#-]*(monitor *= *eDP-[0-9]|output *= *"eDP-[0-9])' "$HYPR_DIR" 2>/dev/null || true)

  if [ -n "$OFFENDERS" ]; then
    # The panel's EDID description is stable; read it from a live session if we
    # have one, else from the connected eDP connector on the AMD card.
    PANEL_DESC=""
    if command -v hyprctl >/dev/null 2>&1; then
      PANEL_DESC=$(hyprctl monitors 2>/dev/null \
        | awk '/description:/ { sub(/^[[:space:]]*description:[[:space:]]*/, ""); print; exit }' || true)
    fi
    if [ -z "$PANEL_DESC" ] && command -v edid-decode >/dev/null 2>&1; then
      for c in /sys/class/drm/${IGPU_CARD}-eDP-*; do
        [ -r "$c/edid" ] && [ "$(cat "$c/status" 2>/dev/null)" = "connected" ] || continue
        PANEL_DESC=$(edid-decode <"$c/edid" 2>/dev/null | awk -F': ' '/Manufacturer|Display Product Name/ {print $2}' | paste -sd' ' || true)
        break
      done
    fi

    warn "These files pin a monitor rule to an 'eDP-N' connector name:"
    printf '%s\n' "$OFFENDERS" | sed 's/^/          /'
    warn "That name alternates between boots now that Hyprland manages both GPUs"
    warn "(lesson #7 at the top of this script). Match the panel by description:"
    if [ -n "$PANEL_DESC" ]; then
      printf '          monitor=desc:%s,<mode>,<position>,<scale>\n' "$PANEL_DESC"
      printf '          hl.monitor({ output = "desc:%s", ... })   -- Lua form\n' "$PANEL_DESC"
    else
      warn "  (run 'hyprctl monitors' in a session to read the panel's description)"
      printf '          monitor=desc:<make> <model>,<mode>,<position>,<scale>\n'
    fi
    warn "Put it in a file loaded AFTER monitors.lua (e.g. custom.lua) so it wins"
    warn "and survives nwg-displays regenerating monitors.lua/monitors.conf."
  else
    log "No name-pinned monitor rules found (or no Hyprland config yet)."
  fi

  # --- done ------------------------------------------------------------------
  log "NVIDIA ROG setup complete. REBOOT to activate."
  cat <<EOF

  After reboot, verify / use:
    * dormancy (undocked, idle): cat /sys/bus/pci/devices/${DGPU_PCI}/power_state   -> D3cold
    * dGPU on demand           : nvidia-smi   |   gpu-run <app>   |   just run CUDA
    * external HDMI display    : plug it in (Hyprland manages it live)
    * full dGPU (gaming/dock)  : gpu-mux ultimate   (then reboot; gpu-mux hybrid to return)

  If the login screen ever breaks: switch to a TTY (Ctrl+Alt+F2) and run
    sudo rm /etc/sddm.conf.d/10-wayland.conf && sudo systemctl restart sddm
EOF
) || printf '\n\033[1;31msetup-graphics-rog.sh failed (see messages above).\033[0m\n'
