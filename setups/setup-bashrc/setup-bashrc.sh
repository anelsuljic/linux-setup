#!/bin/bash


SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
SETUP_BASH="$SCRIPT_DIR/setup-bashrc.txt"
BASHRC="$HOME/.bashrc"

printf '\n\n\n\n\n%*s\n' 40 '' | tr ' ' '-'
read -p "Do you want to set up .bashrc? [y/n]: " choice
printf '%*s\n\n\n\n\n\n' 40 '' | tr ' ' '-'

[[ "$choice" != "y" ]] && exit 0

cat "$SETUP_BASH" >> "$BASHRC"
source "$BASHRC"