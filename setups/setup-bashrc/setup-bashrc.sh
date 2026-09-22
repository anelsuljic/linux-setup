#!/bin/bash


SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
SCRIPT_BASHRC="$SCRIPT_DIR/files/bashrc_custom"
REAL_BASHRC="$HOME/.bashrc_custom"
BASHRC="$HOME/.bashrc"

printf '\n\n\n\n\n%*s\n' 40 '' | tr ' ' '-'
read -p "Do you want to set up .bashrc? [y/n]: " choice
printf '%*s\n\n\n\n\n\n' 40 '' | tr ' ' '-'

[[ "$choice" != "y" ]] && exit 0

[[ -f "$REAL_BASHRC" ]] && rm -rf "$REAL_BASHRC"

ln -s "$SCRIPT_BASHRC" "$REAL_BASHRC"
source "$BASHRC"
