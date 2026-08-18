#!/bin/bash

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

INSTALL_LIST="$SCRIPT_DIR/install-list.txt"
REMOVE_LIST="$SCRIPT_DIR/remove-list.txt"

printf '\n\n\n\n\n%*s\n' 40 '' | tr ' ' '-'
read -p "Do you want to install apps and remove bloatware? [y/n]: " choice
printf '%*s\n\n\n\n\n\n' 40 '' | tr ' ' '-'

[[ "$choice" != "y" ]] && exit 0


if [ -f "$INSTALL_LIST" ]; then
    echo "Installing wanted packages..."
    yay -S --needed --noconfirm - < "$INSTALL_LIST"

    echo "Marking packages as explicitly installed to prevent auto-removal..."
    grep -v '^#' "$INSTALL_LIST" | sed '/^$/d' | xargs -r sudo pacman -D --asexplicit
else
    echo "Warning: Install list not found at $INSTALL_LIST"
fi
