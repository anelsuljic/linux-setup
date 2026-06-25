#!/bin/bash

echo "Configuring gnome zoom utility ..."

gsettings set org.gnome.desktop.a11y.magnifier focus-tracking 'none'
gsettings set org.gnome.desktop.a11y.magnifier caret-tracking 'none'
gsettings set org.gnome.desktop.a11y.magnifier mouse-tracking 'none'
