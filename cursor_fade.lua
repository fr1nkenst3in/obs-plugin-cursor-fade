-- OBS Cursor Region Fade Script (STABLE VERSION)
-- Fixes jitter caused by OBS tick timing + low precision updates

obs = obslua

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

enabled = true
debug_enabled = false

source_name = ""
filter_name = "Color Correction"

-- region (% of screen)
min_x_pct = 0.0
min_y_pct = 0.0
max_x_pct = 100.0
max_y_pct = 100.0

-- opacity (IMPORTANT: 0.0 - 1.0 normalized)
inside_opacity = 0.0
outside_opacity = 0.02

-- smoothing strength (higher = faster response)
fade_speed = 12.0

--------------------------------------------------
-- STATE
--------------------------------------------------

current_opacity = 0.0
target_opacity = 0.0

last_written_opacity = -1.0

screen_w = 1920
screen_h = 1080

debug_timer = 0.0

--------------------------------------------------
-- WINDOWS API
--------------------------------------------------

ffi = require("ffi")

ffi.cdef[[
typedef struct { long x; long y; } POINT;
int GetCursorPos(POINT* lpPoint);
int GetSystemMetrics(int nIndex);
]]

user32 = ffi.load("user32")

SM_CXSCREEN = 0
SM_CYSCREEN = 1

--------------------------------------------------
-- SCREEN
--------------------------------------------------

function update_screen()
    screen_w = user32.GetSystemMetrics(SM_CXSCREEN)
    screen_h = user32.GetSystemMetrics(SM_CYSCREEN)
end

--------------------------------------------------
-- MOUSE
--------------------------------------------------

function mouse_pos()
    local p = ffi.new("POINT[1]")
    user32.GetCursorPos(p)
    return p[0].x, p[0].y
end

--------------------------------------------------
-- HELPERS
--------------------------------------------------

function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

--------------------------------------------------
-- SMOOTH (FRAME-INDEPENDENT)
--------------------------------------------------
-- This is the key fix:
-- makes fading identical regardless of OBS tick rate
--------------------------------------------------

function exp_smooth(current, target, speed, dt)
    local t = 1 - math.exp(-speed * dt)
    return current + (target - current) * t
end

--------------------------------------------------
-- PERCENT CONVERT
--------------------------------------------------

function pct(v, max)
    if v <= 1.0 then
        return v * max
    end
    return (v / 100.0) * max
end

--------------------------------------------------
-- APPLY FILTER
--------------------------------------------------

function set_opacity(v)

    -- prevent spam updates (IMPORTANT for jitter)
    if math.abs(v - last_written_opacity) < 0.001 then
        return
    end

    last_written_opacity = v

    local src = obs.obs_get_source_by_name(source_name)
    if src == nil then return end

    local filter = obs.obs_source_get_filter_by_name(src, filter_name)
    if filter ~= nil then

        local settings = obs.obs_source_get_settings(filter)

        -- NORMALIZED OPACITY (THIS IS THE CORRECT MODE)
        obs.obs_data_set_double(settings, "opacity", v)

        obs.obs_source_update(filter, settings)

        obs.obs_data_release(settings)
        obs.obs_source_release(filter)
    end

    obs.obs_source_release(src)
end

--------------------------------------------------
-- MAIN LOOP
--------------------------------------------------

function script_tick(seconds)

    if not enabled then return end

    update_screen()

    local mx, my = mouse_pos()

    local min_x = pct(min_x_pct, screen_w)
    local max_x = pct(max_x_pct, screen_w)

    local min_y = pct(min_y_pct, screen_h)
    local max_y = pct(max_y_pct, screen_h)

    local inside =
        mx >= min_x and mx <= max_x and
        my >= min_y and my <= max_y

    if inside then
        target_opacity = inside_opacity
    else
        target_opacity = outside_opacity
    end

    -- STABLE SMOOTHING
    current_opacity =
        exp_smooth(current_opacity, target_opacity, fade_speed, seconds)

    -- snap tiny drift
    if math.abs(current_opacity - target_opacity) < 0.0005 then
        current_opacity = target_opacity
    end

    set_opacity(current_opacity)

    --------------------------------------------------
    -- DEBUG
    --------------------------------------------------

    if debug_enabled then
        debug_timer = debug_timer + seconds

        if debug_timer > 0.25 then
            debug_timer = 0

            obs.script_log(
                obs.LOG_INFO,
                string.format(
                    "[Fade] Mouse=(%d,%d) Inside=%s Opacity=%.4f Target=%.4f",
                    mx, my,
                    tostring(inside),
                    current_opacity,
                    target_opacity
                )
            )
        end
    end
end

--------------------------------------------------
-- UI
--------------------------------------------------

function script_description()
    return "Stable cursor fade for OBS Color Correction (no jitter version)"
end

function script_properties()

    local props = obs.obs_properties_create()

    obs.obs_properties_add_bool(props, "enabled", "Enable")
    obs.obs_properties_add_bool(props, "debug_enabled", "Debug")

    obs.obs_properties_add_text(props, "source_name", "Source", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "filter_name", "Filter", obs.OBS_TEXT_DEFAULT)

    obs.obs_properties_add_float_slider(props, "min_x_pct", "Min X %", 0, 100, 0.1)
    obs.obs_properties_add_float_slider(props, "min_y_pct", "Min Y %", 0, 100, 0.1)
    obs.obs_properties_add_float_slider(props, "max_x_pct", "Max X %", 0, 100, 0.1)
    obs.obs_properties_add_float_slider(props, "max_y_pct", "Max Y %", 0, 100, 0.1)

    -- normalized opacity range (IMPORTANT FIX)
    obs.obs_properties_add_float_slider(props, "inside_opacity", "Inside Opacity", 0.0, 1.0, 0.001)
    obs.obs_properties_add_float_slider(props, "outside_opacity", "Outside Opacity", 0.0, 1.0, 0.001)

    obs.obs_properties_add_float_slider(props, "fade_speed", "Fade Speed", 1, 30, 0.1)

    return props
end

function script_defaults(settings)
    obs.obs_data_set_default_double(settings, "inside_opacity", 0.0)
    obs.obs_data_set_default_double(settings, "outside_opacity", 0.02)
    obs.obs_data_set_default_double(settings, "fade_speed", 12.0)
end

function script_update(settings)
    enabled = obs.obs_data_get_bool(settings, "enabled")
    debug_enabled = obs.obs_data_get_bool(settings, "debug_enabled")

    source_name = obs.obs_data_get_string(settings, "source_name")
    filter_name = obs.obs_data_get_string(settings, "filter_name")

    min_x_pct = obs.obs_data_get_double(settings, "min_x_pct")
    min_y_pct = obs.obs_data_get_double(settings, "min_y_pct")
    max_x_pct = obs.obs_data_get_double(settings, "max_x_pct")
    max_y_pct = obs.obs_data_get_double(settings, "max_y_pct")

    inside_opacity = obs.obs_data_get_double(settings, "inside_opacity")
    outside_opacity = obs.obs_data_get_double(settings, "outside_opacity")

    fade_speed = obs.obs_data_get_double(settings, "fade_speed")

    current_opacity = outside_opacity
end