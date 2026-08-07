-- ~/.config/hypr/custom.lua
-- Loaded by hyprland.lua AFTER conf/ml4w.lua, so anything here overrides the
-- stock ML4W defaults and is NOT touched by ML4W dotfile updates.

-- ============================================================================
-- HiDPI toolkit scaling (eDP-1: 2560x1440 @ 15.6")
-- ----------------------------------------------------------------------------
-- The compositor stays at scale 1.0 (sharp, no fractional downscale blur).
-- Instead, Qt and GTK are told to render their own UI 1.25x larger.
--
-- NOTE: these are SESSION-GLOBAL. They apply to every app on every monitor,
-- including any external display you attach later (chosen tradeoff).
-- ============================================================================

-- Qt (Qt5/Qt6) -- crisp fractional scaling, rendered natively at 1.25x
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "0")   -- don't auto-read compositor scale
hl.env("QT_SCALE_FACTOR", "1.25")             -- force a 1.25x global UI scale
hl.env("QT_ENABLE_HIGHDPI_SCALING", "1")     -- enable Qt high-DPI pipeline

-- GTK -- IMPORTANT: GTK4 on Wayland IGNORES GDK_SCALE and GDK_DPI_SCALE.
-- Those only affect GTK3 / GTK4-on-X11, so setting them here does nothing for
-- modern apps (nautilus, gnome-text-editor, pavucontrol are all GTK4) and a
-- GDK_SCALE of 2 would balloon any GTK3 app to 2x. We therefore do NOT set
-- them. GTK4 fractional UI scaling is driven by a dconf setting instead:
--
--     gsettings set org.gnome.desktop.interface text-scaling-factor 1.25
--
-- That persists in dconf (no env var / no relogin needed) and is applied
-- out-of-band, not from this file. Change the 1.25 to taste.
-- GDK_SCALE stays at 1 (inherited from conf/ml4w.lua).

-- ============================================================================
-- Window placement rules (mirrors the ML4W float-and-center convention)
-- ----------------------------------------------------------------------------
-- ML4W's bundled apps land centered because conf/ml4w.lua gives each one an
-- explicit float+center rule. Apps without a rule (e.g. Bochs) just map at the
-- compositor default -- top-left, under Waybar. We add the missing rules here.
-- ============================================================================

-- Bochs x86 emulator. Runs under XWayland (links libX11, not Wayland), so it is
-- matched by its X11 WM_CLASS. The (?i) flag makes the match case-insensitive
-- and the bare "bochs" matches anywhere in the class, so this fires regardless
-- of the exact casing Bochs reports. No size is forced: Bochs sizes its own
-- window to the guest's video mode, and center re-centers it on each map.
hl.window_rule({
    name = "bochs",
    match = {class = "(?i)bochs"},
    float = true,
    -- Valid vars:
    -- window_w/h/x/y, monitor_w/h, cursor_x/y (no `%` op, no `w`/`h` shorthand).
    -- The two coords split on the FIRST space, so NO spaces inside each expr.
    move  = "monitor_w-window_w-100 90"
})
