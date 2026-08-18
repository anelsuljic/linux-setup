#!/bin/bash
#
# Replaces the greeter compositor of sddm with hyprland. Read readme.md before
# touching this script, it explains every file and the reasons behind them.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
FILES_DIR="$SCRIPT_DIR/files"
GREETER_CONF="/etc/sddm/hyprland-greeter.lua"

printf '\n\n\n\n\n%*s\n' 40 '' | tr ' ' '-'
read -p "Do you want to set up sddm? [y/n]: " choice
printf '%*s\n\n\n\n\n\n' 40 '' | tr ' ' '-'

[[ "$choice" != "y" ]] && exit 0

if ! command -v start-hyprland &> /dev/null; then
    echo "Error: start-hyprland is missing, install the hyprland package. Without it there would be no login screen."
    exit 1
fi

echo "Installing weston, the fallback greeter used only to recover a broken login screen..."
sudo pacman -S --needed --noconfirm weston


echo "Installing the greeter files..."
sudo install -Dm644 "$FILES_DIR/10-wayland.conf" /etc/sddm.conf.d/10-wayland.conf
sudo install -Dm644 "$FILES_DIR/20-cursor.conf" /etc/sddm.conf.d/20-cursor.conf
sudo install -Dm644 "$FILES_DIR/30-compositor.conf" /etc/sddm.conf.d/30-compositor.conf
sudo install -Dm644 "$FILES_DIR/hyprland-greeter.lua" "$GREETER_CONF"
sudo install -Dm755 "$FILES_DIR/sddm-hyprland" /usr/local/bin/sddm-hyprland


# The greeter runs as the sddm user, which cannot read $HOME, so its cursor
# theme has to be copied where that user can find it.
CURSOR_THEME=$(sed -n 's/^CursorTheme=//p' "$FILES_DIR/20-cursor.conf")

if [[ ! -d "/usr/share/icons/$CURSOR_THEME" ]]; then
    echo "Copying the cursor theme $CURSOR_THEME to /usr/share/icons..."
    sudo cp -r "$HOME/.local/share/icons/$CURSOR_THEME" /usr/share/icons/
    sudo chmod -R a+rX "/usr/share/icons/$CURSOR_THEME"
fi


# A greeter configuration that hyprland cannot parse means no login screen.
if ! Hyprland --verify-config -c "$GREETER_CONF" 2>&1 | grep -q "config ok"; then
    echo "Warning: hyprland cannot parse $GREETER_CONF, fix it before logging out."
fi


echo "The sddm setup is done, log out to apply it."
echo "Never run \"systemctl restart sddm\" to test it, that kills the running session."
echo "Read readme.md if the login screen ever breaks."
