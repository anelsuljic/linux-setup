#!/bin/bash
#
# setup-sddm.sh
# ---------------------------------------------------------------------------
# SDDM greeter fix for the ASUS ROG Strix G513 (AMD Radeon 680M iGPU +
# NVIDIA RTX 3070 Ti dGPU) on Arch + Hyprland (Wayland, SDDM, ml4w/HyprMod).
#
# PROBLEM: with the SDDM Wayland greeter running under weston (as configured by
# setup-graphics-rog.sh section 6), the ELAN I2C touchpad
# (ASUE1403:00 04F3:319A) is opened by weston but never emits a single event.
# The greeter therefore never gets pointer focus and never sets a cursor, so the
# login screen shows NO MOUSE POINTER and does not react to the touchpad at all.
# Typing still works, because the keyboard you type on is a different device
# (AT Translated Set 2 keyboard, event3).
#
# FIX: replace weston with Hyprland as the greeter compositor -- it drives the
# very same touchpad correctly in the user session -- and give the greeter an
# explicit cursor theme it can actually read.
#
# Run it as your NORMAL USER (it calls sudo where needed). It is idempotent and
# ASSUMES AN EXISTING SDDM SETUP (sddm installed, DisplayServer=wayland already
# configured by setup-graphics-rog.sh). It only ADDS/overrides files.
#
# === LESSONS FROM A LONG DEBUG SESSION — do NOT "simplify" these away =======
#  1. The missing pointer was NEVER a rendering bug. Cursor theme, Qt greeter and
#     kiosk-shell were all verified healthy: under a nested weston the greeter
#     commits a valid 32x32 ARGB cursor via wl_pointer.set_cursor and hover/click
#     work. It is dead INPUT: no pointer motion -> no wl_pointer.enter -> the
#     client never sets a cursor. Do NOT go chasing XCURSOR_*/cursor planes.
#  2. 30-compositor.conf beats 10-wayland.conf (written by setup-graphics-rog.sh)
#     ONLY BY SORT ORDER, since both set [Wayland] CompositorCommand. Keep the
#     30- prefix. If that drop-in ever disappears, weston returns and the
#     touchpad dies again -- that is the first place to look.
#  3. AQ_DRM_DEVICES must be set for the GREETER too, AMD first, or Hyprland may
#     try to drive the panel from the dormant NVIDIA dGPU and you get no login
#     screen. Colon-separated /dev/dri/cardN nodes only -- never /dev/dri/by-path
#     (see setup-graphics-rog.sh lesson #1). sddm-hyprland resolves this at
#     runtime by DRIVER NAME, because card numbering is not stable across boots.
#  4. Launch via `start-hyprland -- -c <config>`, never `Hyprland` directly:
#     Hyprland warns about it, and start-hyprland stays in the FOREGROUND as the
#     watchdog parent, which is exactly what SDDM needs to track and stop the
#     compositor when you log in. A launcher that forked away would break SDDM.
#  5. The greeter config MUST be .lua. The classic .conf format is deprecated in
#     Hyprland 0.56 and produces a warning overlay ON THE LOGIN SCREEN. Note the
#     Lua API uses underscores (input.touchpad.tap_to_click), not tap-to-click.
#  6. Bibata lives in ~/.local/share/icons, which the `sddm` user CANNOT read.
#     It must be copied to /usr/share/icons or the greeter silently falls back to
#     the default theme. /usr/local/share/icons does NOT work: it is not on the
#     Xcursor search path.
#  7. Never `systemctl restart sddm` to test -- it kills the running session.
#     Log out instead; SDDM restarts the greeter on its own.
# ===========================================================================

(
  printf '\n\n\n\n\n%*s\n' 40 '' | tr ' ' '-'
  read -p "Do you want to set up sddm? [y/n]: " choice
  printf '%*s\n\n\n\n\n\n' 40 '' | tr ' ' '-'

  [[ "$choice" != "y" ]] && exit 0
  
  set -euo pipefail

  log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
  warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
  die()  { printf '\n\033[1;31m[error]\033[0m %s\n' "$*"; exit 1; }

  [ "$(id -u)" -eq 0 ] && warn "Run this as your normal user, not root, or the cursor theme will be taken from /root."

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  SRC_DIR="$SCRIPT_DIR/files"
  GREETER_CONF="/etc/sddm/hyprland-greeter.lua"

  # --- 0. Sanity checks ------------------------------------------------------
  log "Checking prerequisites"
  [ -d "$SRC_DIR" ] || die "Source directory not found: $SRC_DIR"
  pacman -Qq sddm >/dev/null 2>&1 || die "sddm is not installed — this script assumes an existing SDDM setup."
  command -v start-hyprland >/dev/null 2>&1 \
    || die "start-hyprland not found — the greeter wrapper needs it (package: hyprland)."

  # DisplayServer=wayland normally comes from 10-wayland.conf (setup-graphics-rog.sh).
  if ! grep -rqs '^DisplayServer=wayland' /etc/sddm.conf /etc/sddm.conf.d/ 2>/dev/null; then
    warn "DisplayServer=wayland is not configured (usually set by setup-graphics-rog.sh)."
    warn "Without it SDDM starts an X11 greeter and this compositor config is ignored."
  fi

  # --- 1. Install the files into their corresponding paths -------------------
  # Format: "<file in sddm/>|<destination>|<mode>"
  FILES=(
    "20-cursor.conf|/etc/sddm.conf.d/20-cursor.conf|644"
    "30-compositor.conf|/etc/sddm.conf.d/30-compositor.conf|644"
    "hyprland-greeter.lua|${GREETER_CONF}|644"
    "sddm-hyprland|/usr/local/bin/sddm-hyprland|755"
  )

  log "Installing greeter files"
  for entry in "${FILES[@]}"; do
    IFS='|' read -r name dest mode <<<"$entry"
    src="$SRC_DIR/$name"
    [ -f "$src" ] || die "Missing source file: $src"

    # Keep a timestamped backup if we are about to change an existing file.
    if [ -e "$dest" ] && ! sudo cmp -s "$src" "$dest"; then
      sudo cp -a "$dest" "${dest}.bak.$(date +%s)"
      warn "$dest differed — previous version backed up alongside it."
    fi

    sudo install -Dm"$mode" "$src" "$dest"
    printf '    %-40s -> %s (%s)\n' "$name" "$dest" "$mode"
  done

  # --- 2. Cursor theme, readable by the `sddm` user --------------------------
  # 20-cursor.conf names a theme; it must exist under /usr/share/icons, because
  # the greeter runs as `sddm` and cannot read $HOME (lesson #6).
  CURSOR_THEME="$(sed -n 's/^CursorTheme=//p' "$SRC_DIR/20-cursor.conf" | head -n1)"
  if [ -n "$CURSOR_THEME" ]; then
    if [ -d "/usr/share/icons/$CURSOR_THEME" ]; then
      log "Cursor theme '$CURSOR_THEME' already installed system-wide"
    elif [ -d "$HOME/.local/share/icons/$CURSOR_THEME" ]; then
      log "Installing cursor theme '$CURSOR_THEME' system-wide (the sddm user cannot read \$HOME)"
      sudo cp -r "$HOME/.local/share/icons/$CURSOR_THEME" /usr/share/icons/
      sudo chown -R root:root "/usr/share/icons/$CURSOR_THEME"
      sudo chmod -R a+rX "/usr/share/icons/$CURSOR_THEME"
    else
      warn "Cursor theme '$CURSOR_THEME' found neither in /usr/share/icons nor in ~/.local/share/icons."
      warn "The greeter will fall back to the default cursor. Install the theme and re-run."
    fi
  fi

  # --- 3. Verify -------------------------------------------------------------
  log "Verifying the greeter config parses"
  if Hyprland --verify-config -c "$GREETER_CONF" 2>&1 | grep -q 'config ok'; then
    printf '    %s: config ok\n' "$GREETER_CONF"
  else
    warn "Hyprland could NOT parse $GREETER_CONF."
    warn "Fix it before logging out, or you will get no login screen (recovery below)."
  fi

  # Warn if something still points the greeter at weston (lesson #2).
  if grep -rqs 'CompositorCommand=.*weston' /etc/sddm.conf /etc/sddm.conf.d/ 2>/dev/null; then
    printf '    weston CompositorCommand still present in a lower drop-in (expected: 10-wayland.conf);\n'
    printf '    30-compositor.conf overrides it by sort order.\n'
  fi

  # --- done ------------------------------------------------------------------
  log "SDDM greeter setup complete."
  cat <<EOF

  Apply it by LOGGING OUT (not a reboot, and never 'systemctl restart sddm' —
  that kills your running session). SDDM restarts the greeter on logout.

  You should get: a visible Bibata pointer, a working touchpad, and no Hyprland
  warning overlay on the login screen.

  If the login screen ever breaks: switch to a TTY (Ctrl+Alt+F2) and run
    sudo rm /etc/sddm.conf.d/30-compositor.conf && sudo systemctl restart sddm
  That falls back to weston — cursor-less and with a dead touchpad, but you can
  still log in by typing your password.
EOF
) || printf '\n\033[1;31msetup-sddm.sh failed (see messages above).\033[0m\n'
