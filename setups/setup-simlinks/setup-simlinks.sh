#!/bin/bash

printf '\n\n\n\n\n%*s\n' 40 '' | tr ' ' '-'
read -p "Do you want to set up symbolic links? [y/n]: " choice
printf '%*s\n\n\n\n\n\n' 40 '' | tr ' ' '-'

[[ "$choice" != "y" ]] && exit 0

echo "Creating simbolic link for gnome-text-editor named as gte ..."
sudo ln -s /usr/bin/gnome-text-editor /usr/local/bin/gte