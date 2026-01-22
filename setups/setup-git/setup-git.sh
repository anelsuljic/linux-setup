#!/bin/bash

printf '\n\n\n\n\n%*s\n' 40 '' | tr ' ' '-'
read -p "Do you want to set up git? [y/n]: " choice
printf '%*s\n\n\n\n\n\n' 40 '' | tr ' ' '-'

[[ "$choice" != "y" ]] && exit 0

git config --global user.name "Anel Ademovic"
git config --global user.email asuljic48@gmail.com
git config --global init.defaultBranch main
git config --global core.editor "code --wait"
git config --global core.autocrlf input
git config --global diff.tool vscode
git config --global difftool.vscode.cmd "code --wait --diff \$LOCAL \$REMOTE"

echo "Use \"git config --global -e\" to open the config file and check that everything is correct."