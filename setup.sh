#!/bin/bash

echo "Setting up .bashrc ..."
bash setups/setup-bashrc/setup-bashrc.sh

echo "Setting up git ..."
bash setups/setup-git/setup-git.sh

echo "Installing graphics drivers ..."
bash setups/setup-graphics/setup-graphics.sh

echo "Installing user apps ..."
bash setups/setup-apps/setup-apps.sh

echo "Setting up programming languages ..."
bash setups/setup-proglang/setup-proglang.sh

echo "Creating simbolic links ..."
bash setups/setup-simlinks/setup-simlinks.sh

echo "Adjusting timezone ..."
bash setups/setup-time/setup-time.sh