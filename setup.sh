#!/bin/bash

echo "Setting up .bashrc ..."
bash setups/setup-bashrc/setup-bashrc.sh

echo "Reinstalling apps ..."
bash setups/setup-apps/setup-apps.sh

echo "Setting up git ..."
bash setups/setup-git/setup-git.sh