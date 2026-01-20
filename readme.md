# Linux automatic setup repository

This repository contains scripts that automatize the setup of a clean arch linux installation.

To do so, you just need to execute:

```bash
bash setup.sh
```

To create custom shortcuts for gnome console, you must go to `Settings -> Keyboard -> View and Customize Shortcuts -> Custom Shortcuts` and do the following:

- Create the shortcut for opening gnome terminal: 
    - Command: `kgx`
    - Shortcut: `Ctrl + Alt + T`

- Create the shortcut for opening a new tab of gnome terminal:
    - Command: `kgx --tab`
    - Shortcut: `Ctrl + Alt + N`