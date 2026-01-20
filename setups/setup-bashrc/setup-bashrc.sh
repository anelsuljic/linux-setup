#!/bin/bash

SETUP_BASH="$HOME/git-repos/linux-setup/setups/setup-bashrc/setup-bashrc.txt"
BASHRC="$HOME/.bashrc"

cat "$SETUP_BASH" >> "$BASHRC"
source "$BASHRC"