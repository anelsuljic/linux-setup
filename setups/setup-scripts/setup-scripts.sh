#!/bin/bash

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
FILES_DIR="$SCRIPT_DIR/files"

printf '\n\n\n\n\n%*s\n' 40 '' | tr ' ' '-'
read -p "Do you want to set up automation scripts? [y/n]: " choice
printf '%*s\n\n\n\n\n\n' 40 '' | tr ' ' '-'

[[ "$choice" != "y" ]] && exit 0

echo "Installing the abort-update, confirm-update and safe-update commands..."
sudo install -Dm755 "$FILES_DIR/abort-update" /usr/local/bin/abort-update
sudo install -Dm755 "$FILES_DIR/confirm-update" /usr/local/bin/confirm-update
sudo install -Dm755 "$FILES_DIR/safe-update" /usr/local/bin/safe-update
