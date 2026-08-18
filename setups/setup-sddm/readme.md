# Sddm setup

`setup-sddm.sh` replaces the greeter compositor of sddm with hyprland, so that
the login screen has a working touchpad and a visible mouse pointer.

Run it as your normal user, it calls `sudo` when it needs to. It assumes that
sddm is already installed, ml4w installs it and writes `/etc/sddm.conf`, so the
script only adds files. Running it more than once is safe.

## The problem it solves

Sddm runs its wayland greeter under weston (`weston --shell=kiosk`). Weston opens
the elan i2c touchpad of this laptop (ASUE1403:00 04F3:319A) but never gets a
single event out of it, so the greeter never receives pointer focus and never
sets a cursor. The login screen ends up without mouse pointer and does not react
to the touchpad at all. Typing still works because the keyboard is another
device.

The fix is to use hyprland as the greeter compositor, which drives that same
touchpad correctly in the user session, and to give the greeter a cursor theme
that it can actually read.

## What it installs

- `files/10-wayland.conf` into `/etc/sddm.conf.d`: makes the greeter run on wayland.
- `files/20-cursor.conf` into `/etc/sddm.conf.d`: cursor theme and size of the greeter.
- `files/30-compositor.conf` into `/etc/sddm.conf.d`: tells sddm to start `sddm-hyprland`.
- `files/sddm-hyprland` into `/usr/local/bin`: sets the graphics and cursor environment and starts hyprland.
- `files/hyprland-greeter.lua` into `/etc/sddm`: the hyprland configuration of the greeter.
- The `weston` package: it does not run the greeter anymore, it is kept only as the fallback that recovers a broken login screen.

It also copies the cursor theme named in `20-cursor.conf` into
`/usr/share/icons`, and warns if hyprland cannot parse the greeter
configuration.

## How to apply it

Log out. Sddm restarts the greeter on its own.

Never run `systemctl restart sddm` to test it, that kills the running session.

The login screen should then have a visible pointer, a working touchpad and no
hyprland warning painted on top of it.

## How to recover a broken login screen

Switch to a tty with `Ctrl + Alt + F2` and run:

```bash
sudo rm /etc/sddm.conf.d/30-compositor.conf
sudo systemctl restart sddm
```

That falls back to the weston greeter of sddm, without pointer and with a dead
touchpad, but you can still log in by typing your password. If even that fails,
remove `/etc/sddm.conf.d/10-wayland.conf` too and restart sddm again: it then
starts the x11 greeter, which depends on nothing of this setup.

## Things learned the hard way

- **The missing pointer was never a rendering problem.** Under a nested weston
  the greeter commits a valid 32x32 cursor and reacts to hover and clicks, so the
  cursor theme, the qt greeter and the kiosk shell were all healthy. What is dead
  is the input: no pointer motion means no `wl_pointer.enter`, and a client that
  is never entered never sets a cursor. Do not go chasing `XCURSOR_*` variables.

- **`/etc/sddm.conf` wins over everything installed here.** Sddm reads
  `/usr/lib/sddm/sddm.conf.d/*.conf`, then `/etc/sddm.conf.d/*.conf`, then
  `/etc/sddm.conf`, and the last value read is the one that counts. Inside
  `/etc/sddm.conf.d` the higher number wins, which is why the compositor file
  starts with `30`. ml4w owns `/etc/sddm.conf` and sets its own
  `GreeterEnvironment` there, so the one of `20-cursor.conf` never reaches the
  greeter, while `CursorTheme` and `CursorSize` are untouched and are the keys
  that matter. When something from `files/` looks ignored, read `/etc/sddm.conf`
  first.

- **Without `30-compositor.conf` weston is back** and the touchpad is dead again,
  so that file is the first thing to check when the login screen misbehaves.

- **Weston 15 removed `fullscreen-shell.so`.** A greeter pointed at that shell
  exits immediately and crash loops. The recovery above works because sddm 0.21
  starts `weston --shell=kiosk` instead.

- **The greeter needs its own `AQ_DRM_DEVICES`,** with the amd card first, or
  hyprland may try to drive the panel from the sleeping nvidia dgpu and there is
  no login screen at all. `sddm-hyprland` resolves the cards by driver name
  rather than by a fixed number, because the numbers are not stable across boots.

- **Hyprland has to be started through `start-hyprland`,** never by calling
  `Hyprland` directly. `start-hyprland` stays in the foreground as the parent
  that watches over the compositor, which is what sddm needs to track it and to
  stop it once the session starts.

- **The greeter configuration has to be a `.lua` file.** The old `.conf` format
  is deprecated since hyprland 0.56 and paints a warning on top of the login
  screen. Its lua api uses underscores, `tap_to_click` and not `tap-to-click`.

- **The cursor theme has to live in `/usr/share/icons`.** ml4w installs Bibata in
  `~/.local/share/icons`, which the `sddm` user cannot read, and the greeter
  silently falls back to the default theme. `/usr/local/share/icons` does not
  work either, it is not in the search path of xcursor.
