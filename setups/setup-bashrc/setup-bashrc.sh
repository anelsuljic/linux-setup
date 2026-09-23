#!/bin/bash


SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

SCRIPT_BASHRC_CUSTOM="$SCRIPT_DIR/files/bashrc_custom"
SCRIPT_BASHRC="$SCRIPT_DIR/files/bashrc"
REAL_BASHRC_CUSTOM="$HOME/.bashrc_custom"
REAL_BASHRC="$HOME/.bashrc"

SEARCH_STRING="source ~/.bashrc_custom"

printf '\n\n\n\n\n%*s\n' 40 '' | tr ' ' '-'
read -p "Do you want to set up .bashrc? [y/n]: " choice
printf '%*s\n\n\n\n\n\n' 40 '' | tr ' ' '-'

[[ "$choice" != "y" ]] && exit 0

! grep -qF "$SEARCH_STRING" "$REAL_BASHRC" && cat "$SCRIPT_BASHRC" >> "$REAL_BASHRC"

[[ -f "$REAL_BASHRC_CUSTOM" ]] && rm -rf "$REAL_BASHRC_CUSTOM"

ln -s "$SCRIPT_BASHRC_CUSTOM" "$REAL_BASHRC_CUSTOM"
source "$REAL_BASHRC"
