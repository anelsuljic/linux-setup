#!/bin/bash

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

bash $SCRIPT_DIR/setups/setup-bashrc/setup-bashrc.sh
bash $SCRIPT_DIR/setups/setup-git/setup-git.sh
bash $SCRIPT_DIR/setups/setup-graphics/setup-graphics.sh
bash $SCRIPT_DIR/setups/setup-apps/setup-apps.sh
bash $SCRIPT_DIR/setups/setup-proglang/setup-proglang.sh
bash $SCRIPT_DIR/setups/setup-simlinks/setup-simlinks.sh
bash $SCRIPT_DIR/setups/setup-time/setup-time.sh