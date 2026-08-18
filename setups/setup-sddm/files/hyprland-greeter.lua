-- Configuration of the greeter compositor, installed by setup-sddm.sh.

-- Scale 1 because the greeter is sized for the whole 2560x1440 panel and the
-- CursorSize of 20-cursor.conf is chosen to match it.
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
