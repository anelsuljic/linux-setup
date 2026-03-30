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


To customize grub look:

1. Copy the theme folder you want (for example, `rog`) to `/boot/grub/themes`.
2. Edit `/etc/default/grub` and add the following line after `GRUB_CMDLINE_LINUX`:
    ```bash
    GRUB_THEME=/boot/grub/themes/<theme_folder>/theme.txt
    ```
3. Execute the command `grub-mkconfig -o /boot/grub/grub.cfg`.


To autostart applications on `gnome`:

1. Create the autostart folder (just in case it doesn't exist yet):

    ```bash
    mkdir -p ~/.config/autostart
    ```

2. Copy the application's shortcut into it:

    ```bash
    cp /usr/share/applications/<app-name>.desktop ~/.config/autostart/
    ```


3. Add a one-second delay (or more, if needed) to avoid race conditions in case the application you want to autostart relies on background services that need to be started before.

    1. Open the recently copied `<app-name>.desktop`:
        ```bash
        gte ~/.config/autostart/<app-name>.desktop
        ```

    2. Look for the line `Exec=<app-name>` and change it to:

        ```
        Exec=sh -c "sleep 1 && <app-name>"
        ```

        By wrapping the command in `sh -c`, we are telling `gnome` to open a tiny background shell and execute the command between double colons.

