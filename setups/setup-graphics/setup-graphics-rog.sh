#!/bin/bash

echo -e "\n\n\n\n\n\nIMPORTANT: Ensure you have followed the Asus Linux guidelines before running this script.\n\n"
read -p "Do you want to continue with the setup? [y/n]: " choice

[[ "$choice" != "y" ]] && exit 0

# Plugging or unplugging the charger makes amdgpu re-commit its idle
# optimizations, the panel self refresh transition asserts (a WARNING in
# power_psr.c) and the panel freezes. amdgpu.dcdebugmask=0x10 turns it off.
if ! grep -qF "options amdgpu dcdebugmask=0x10" "/etc/modprobe.d/amdgpu-psr.conf"; then
    echo 'options amdgpu dcdebugmask=0x10' | sudo tee /etc/modprobe.d/amdgpu-psr.conf
    sudo limine-mkinitcpio
fi
