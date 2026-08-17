-- Minimal Hyprland configuration for the SDDM greeter.
--
-- Runs as the `sddm` user. SDDM starts this compositor, waits for its Wayland
-- socket, then launches sddm-greeter-qt6 as an ordinary client. Weston was
-- replaced here because it opened this machine's ELAN I2C touchpad
-- (ASUE1403:00 04F3:319A) but never delivered a single event from it, so the
-- greeter never received pointer focus and therefore never set a cursor.

-- Scale 1: the greeter is sized for the full 2560x1440 panel, and SDDM's
-- CursorSize=32 is chosen to match that.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

hl.config({
    general = {
        gaps_in     = 0,
        gaps_out    = 0,
        border_size = 0,
    },

    decoration = {
        rounding = 0,
        blur     = { enabled = false },
        shadow   = { enabled = false },
    },

    animations = {
        enabled = false,
    },

    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        disable_autoreload       = true,
        force_default_wallpaper  = 0,
    },

    cursor = {
        no_hardware_cursors = true,
    },

    input = {
        touchpad = {
            natural_scroll = false,
            tap_to_click   = true,
        },
    },
})
