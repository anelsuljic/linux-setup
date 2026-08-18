#!/bin/bash
#
# setup-sddm.sh
# ---------------------------------------------------------------------------
# THE one place where SDDM is configured, for the ASUS ROG Strix G513 (AMD
# Radeon 680M iGPU + NVIDIA RTX 3070 Ti dGPU) on Arch + Hyprland (Wayland,
# SDDM, ml4w/HyprMod). setup-graphics-rog.sh used to write the Wayland drop-in
# and pull in weston; both moved here, so the login screen can be changed,
# verified and rolled back without touching the GPU setup.
#
# What it installs:
#   10-wayland.conf      -> /etc/sddm.conf.d   DisplayServer=wayland
#   20-cursor.conf       -> /etc/sddm.conf.d   cursor theme/size + greeter env
#   30-compositor.conf   -> /etc/sddm.conf.d   greeter compositor = sddm-hyprland
#   sddm-hyprland        -> /usr/local/bin     GPU + cursor env, execs Hyprland
#   hyprland-greeter.lua -> /etc/sddm          the greeter's own Hyprland config
#   weston               (package)             fallback compositor, recovery only
#
# PROBLEM: with the SDDM Wayland greeter running under weston (SDDM's shipped
# default, `weston --shell=kiosk`), the ELAN I2C touchpad (ASUE1403:00
# 04F3:319A) is opened by weston but never emits a single event. The greeter
# therefore never gets pointer focus and never sets a cursor, so the login
# screen shows NO MOUSE POINTER and does not react to the touchpad at all.
# Typing still works, because the keyboard you type on is a different device
# (AT Translated Set 2 keyboard, event3).
#
# FIX: replace weston with Hyprland as the greeter compositor -- it drives the
# very same touchpad correctly in the user session -- and give the greeter an
# explicit cursor theme it can actually read.
#
# Run it as your NORMAL USER (it calls sudo where needed). It is idempotent and
# ASSUMES SDDM IS ALREADY INSTALLED (ml4w/HyprMod pulls it in and writes
# /etc/sddm.conf). It only ADDS/overrides files.
#
# === LESSONS FROM A LONG DEBUG SESSION — do NOT "simplify" these away =======
#  1. The missing pointer was NEVER a rendering bug. Cursor theme, Qt greeter and
#     kiosk-shell were all verified healthy: under a nested weston the greeter
#     commits a valid 32x32 ARGB cursor via wl_pointer.set_cursor and hover/click
#     work. It is dead INPUT: no pointer motion -> no wl_pointer.enter -> the
#     client never sets a cursor. Do NOT go chasing XCURSOR_*/cursor planes.
#  2. CONFIG PRECEDENCE, per sddm.conf(5): /usr/lib/sddm/sddm.conf.d/*.conf,
#     then /etc/sddm.conf.d/*.conf, then /etc/sddm.conf -- THE LAST ONE READ
#     WINS. So 30-compositor.conf beats sddm's shipped default.conf
#     (CompositorCommand=weston --shell=kiosk), and within /etc/sddm.conf.d the
#     higher number wins: keep the 30- prefix. Beware /etc/sddm.conf: ml4w owns
#     that file and every key it sets silently overrides the drop-ins installed
#     here -- §4 flags the overlap. If 30-compositor.conf ever disappears,
#     weston is back and the touchpad is dead again: look there first.
#  3. weston >= 15 REMOVED fullscreen-shell.so, and a greeter pointed at it exits
#     instantly and crash-loops. sddm 0.21 ships `--shell=kiosk`, which is what
#     makes the recovery at the end of this script (delete 30-compositor.conf)
#     land on a working -- if cursor-less -- greeter. §4 warns if that changes.
#  4. AQ_DRM_DEVICES must be set for the GREETER too, AMD first, or Hyprland may
#     try to drive the panel from the dormant NVIDIA dGPU and you get no login
#     screen. Colon-separated /dev/dri/cardN nodes only -- never /dev/dri/by-path
#     (see setup-graphics-rog.sh lesson #1). sddm-hyprland resolves this at
#     runtime by DRIVER NAME, because card numbering is not stable across boots.
#  5. Launch via `start-hyprland -- -c <config>`, never `Hyprland` directly:
#     Hyprland warns about it, and start-hyprland stays in the FOREGROUND as the
#     watchdog parent, which is exactly what SDDM needs to track and stop the
#     compositor when you log in. A launcher that forked away would break SDDM.
#  6. The greeter config MUST be .lua. The classic .conf format is deprecated in
#     Hyprland 0.56 and produces a warning overlay ON THE LOGIN SCREEN. Note the
#     Lua API uses underscores (input.touchpad.tap_to_click), not tap-to-click.
#  7. Bibata lives in ~/.local/share/icons, which the `sddm` user CANNOT read.
#     It must be copied to /usr/share/icons or the greeter silently falls back to
#     the default theme. /usr/local/share/icons does NOT work: it is not on the
#     Xcursor search path.
#  8. Never `systemctl restart sddm` to test -- it kills the running session.
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

  # --- 1. Fallback compositor ------------------------------------------------
  # weston does NOT run the greeter here — replacing it is the whole point of
  # this script — but SDDM falls back to it as soon as 30-compositor.conf is
  # gone, which is the documented way to recover a broken login screen. It used
  # to be installed by setup-graphics-rog.sh; it belongs with the greeter.
  log "Installing weston (SDDM's fallback greeter compositor, for recovery only)"
  sudo pacman -S --needed --noconfirm weston \
    || warn "could not install weston — the recovery fallback at the end of this script would not work."

  # --- 2. Install the files into their corresponding paths -------------------
  # Format: "<file in files/>|<destination>|<mode>"
  FILES=(
    "10-wayland.conf|/etc/sddm.conf.d/10-wayland.conf|644"
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

  # --- 3. Cursor theme, readable by the `sddm` user --------------------------
  # 20-cursor.conf names a theme; it must exist under /usr/share/icons, because
  # the greeter runs as `sddm` and cannot read $HOME (lesson #7).
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

  # --- 4. Verify -------------------------------------------------------------
  log "Verifying the greeter config parses"
  if Hyprland --verify-config -c "$GREETER_CONF" 2>&1 | grep -q 'config ok'; then
    printf '    %s: config ok\n' "$GREETER_CONF"
  else
    warn "Hyprland could NOT parse $GREETER_CONF."
    warn "Fix it before logging out, or you will get no login screen (recovery below)."
  fi

  # /etc/sddm.conf is read AFTER every drop-in and therefore wins (lesson #2).
  # ml4w owns that file, so a key it happens to set silently overrides what was
  # just installed. Report the overlap rather than rewriting somebody else's file.
  if [ -f /etc/sddm.conf ]; then
    CLASHES=""
    for src in "$SRC_DIR"/*.conf; do
      while IFS='=' read -r key ours; do
        theirs="$(sed -n "s/^[[:space:]]*${key}[[:space:]]*=//p" /etc/sddm.conf | tail -n1)"
        if [ -n "$theirs" ] && [ "$theirs" != "$ours" ]; then
          CLASHES="${CLASHES}      ${key}= (from $(basename "$src")) -> /etc/sddm.conf wins with '${theirs}'\n"
        fi
      done < <(grep -E '^[A-Za-z][A-Za-z0-9]*=' "$src")
    done
    if [ -n "$CLASHES" ]; then
      warn "/etc/sddm.conf has the highest precedence and overrides settings installed here:"
      printf '%b' "$CLASHES"
      warn "Delete those keys from /etc/sddm.conf, or fold their values into files/*.conf."
    fi
  fi

  # The recovery below lands on sddm's own compositor command; make sure that is
  # still a shell weston actually ships (lesson #3).
  # `|| true`: pipefail is on, and grep exits non-zero when the file or the key
  # is absent, which would abort the whole script over a purely informative check.
  FALLBACK="$(grep -hs '^[[:space:]]*CompositorCommand=' /usr/lib/sddm/sddm.conf.d/*.conf | tail -n1 || true)"
  FALLBACK="${FALLBACK#*=}"
  case "$FALLBACK" in
    *fullscreen-shell*)
      warn "SDDM's fallback compositor is '$FALLBACK', but weston >= 15 dropped"
      warn "fullscreen-shell.so — that fallback would crash-loop instead of letting"
      warn "you log in. Add /etc/sddm.conf.d/25-weston-fallback.conf containing:"
      warn "    [Wayland]"
      warn "    CompositorCommand=weston --shell=kiosk-shell.so"
      ;;
    *)
      printf '    weston fallback: %s\n' "${FALLBACK:-sddm built-in default}"
      ;;
  esac

  # --- done ------------------------------------------------------------------
  log "SDDM setup complete."
  cat <<EOF

  Apply it by LOGGING OUT (not a reboot, and never 'systemctl restart sddm' —
  that kills your running session). SDDM restarts the greeter on logout.

  You should get: a visible Bibata pointer, a working touchpad, and no Hyprland
  warning overlay on the login screen.

  If the login screen ever breaks: switch to a TTY (Ctrl+Alt+F2) and run
    sudo rm /etc/sddm.conf.d/30-compositor.conf && sudo systemctl restart sddm
  That falls back to sddm's own weston greeter — cursor-less and with a dead
  touchpad, but you can still log in by typing your password. If even that fails,
  remove /etc/sddm.conf.d/10-wayland.conf as well and restart sddm: it then
  starts the X11 greeter, which depends on none of this.
EOF
) || printf '\n\033[1;31msetup-sddm.sh failed (see messages above).\033[0m\n'
