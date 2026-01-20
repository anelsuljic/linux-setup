#!/bin/bash

echo "Tell which gpu you want to set up (1070ti, 3070ti, skip)"
read model

if [[ $model == "1070ti" ]]; then
    yay -S --needed --noconfirm nvidia-580xx-dkms nvidia-580xx-utils nvidia-580xx-settings
elif [[ $model == "3070ti" ]]; then
    yay -S --needed --noconfirm nvidia-open-dkms nvidia-utils nvidia-settings
else
    echo "Installation skipped"
fi