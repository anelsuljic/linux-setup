#!/bin/bash

printf '\n\n\n\n\n%*s\n' 40 '' | tr ' ' '-'
read -p "Do you want to set up nvidia drivers? [y/n]: " choice
printf '%*s\n\n\n\n\n\n' 40 '' | tr ' ' '-'

[[ "$choice" != "y" ]] && exit 0

echo "Tell which gpu you want to set up (1070ti, 3070ti, skip)"
read model

if [[ $model == "1070ti" ]]; then
    yay -S --needed --noconfirm nvidia-580xx-dkms nvidia-580xx-utils nvidia-580xx-settings
elif [[ $model == "3070ti" ]]; then
    yay -S --needed --noconfirm nvidia-open-dkms nvidia-utils nvidia-settings
else
    echo "Installation skipped"
fi