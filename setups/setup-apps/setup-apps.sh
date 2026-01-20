#!/bin/bash

# Define paths to your lists
INSTALL_LIST="$HOME/git-repos/linux-setup/setups/setup-apps/install-list.txt"
REMOVE_LIST="$HOME/git-repos/linux-setup/setups/setup-apps/remove-list.txt"

echo "--- Starting System Restoration ---"

# Step 1: Install
if [ -f "$INSTALL_LIST" ]; then
    echo "Step 1: Installing wanted packages..."
    yay -S --needed --noconfirm - < "$INSTALL_LIST"
else
    echo "Warning: Install list not found at $INSTALL_LIST"
fi

# Step 2: Prune
if [ -f "$REMOVE_LIST" ]; then
    echo "Step 2: Pruning unwanted packages..."
    grep -v '^#' "$REMOVE_LIST" | xargs -r sudo pacman -Rns --noconfirm
else
    echo "Warning: Remove list not found at $REMOVE_LIST"
fi

echo "--- Restoration Complete ---"