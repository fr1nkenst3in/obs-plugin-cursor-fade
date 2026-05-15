-- OBS Cursor Region Fade Script (ADVANCED EASING VERSION)
-- Smooth customizable fade curves for fade-in and fade-out

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

-- opacity (0.0 - 1.0)
inside_opacity = 0.0
outside_opacity = 0.02

--------------------------------------------------
-- NEW FADE SETTINGS
--------------------------------------------------

fade_in_speed = 3.0
fade_out_speed = 8.0

-- easing modes:
-- "linear"
-- "smoothstep"
-- "smootherstep"
-- "ease_in"
-- "ease_out"
-- "ease_in_out"

fade_in_easing = "ease_out"
fade_out_easing = "ease_in_out"

--------------------------------------------------
-- STATE
--------------------------------------------------

current_opacity = 0.0
start_opacity = 0.0
target_opacity = 0.0

fade_progress = 1.0

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

function lerp(a, b, t)
    return a + (b - a) * t
end

--------------------------------------------------
-- EASING FUNCTIONS
--------------------------------------------------

function apply_easing(t, mode)

    t = clamp(t, 0.0, 1.0)

    if mode == "linear" then
        return t

    elseif mode == "smoothstep" then
        return t * t * (3 - 2 * t)

    elseif mode == "smootherstep" then
        return t * t * t * (t * (t * 6 - 15) + 10)

    elseif mode == "ease_in" then
        return t * t

    elseif mode == "ease_out" then
        return 1 - ((1 - t) * (1 - t))

    elseif mode == "ease_in_out" then
        if t < 0.5 then
            return 2 * t * t
        else
            return 1 - math.pow(-2 * t + 2, 2) / 2
        end
    end

    return t
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

    -- prevent spam updates
    if math.abs(v - last_written_opacity) < 0.001 then
        return
    end

    last_written_opacity = v

    local src = obs.obs_get_source_by_name(source_name)
    if src == nil then return end

    local filter = obs.obs_source_get_filter_by_name(src, filter_name)

    if filter ~= nil then

        local settings = obs.obs_source_get_settings(filter)

        obs.obs_data_set_double(settings, "opacity", v)

        obs.obs_source_update(filter, settings)

        obs.obs_data_release(settings)
        obs.obs_source_release(filter)
    end

    obs.obs_source_release(src)
end

--------------------------------------------------
-- START NEW FADE
--------------------------------------------------

function begin_fade(new_target)

    if new_target == target_opacity then
        return
    end

    start_opacity = current_opacity
    target_opacity = new_target

    fade_progress = 0.0
end

--------------------------------------------------
-- MAIN LOOP
--------------------------------------------------

function script_tick(seconds)

    if not enabled then
        return
    end

    update_screen()

    local mx, my = mouse_pos()

    local min_x = pct(min_x_pct, screen_w)
    local max_x = pct(max_x_pct, screen_w)

    local min_y = pct(min_y_pct, screen_h)
    local max_y = pct(max_y_pct, screen_h)

    local inside =
        mx >= min_x and mx <= max_x and
        my >= min_y and my <= max_y

    local desired_opacity

    if inside then
        desired_opacity = inside_opacity
    else
        desired_opacity = outside_opacity
    end

    --------------------------------------------------
    -- START NEW TRANSITION
    --------------------------------------------------

    if desired_opacity ~= target_opacity then
        begin_fade(desired_opacity)
    end

    --------------------------------------------------
    -- UPDATE FADE
    --------------------------------------------------

    local speed
    local easing

    if target_opacity > current_opacity then
        speed = fade_out_speed
        easing = fade_out_easing
    else
        speed = fade_in_speed
        easing = fade_in_easing
    end

    fade_progress =
        clamp(fade_progress + seconds * speed, 0.0, 1.0)

    local eased = apply_easing(fade_progress, easing)

    current_opacity =
        lerp(start_opacity, target_opacity, eased)

    --------------------------------------------------
    -- SNAP END
    --------------------------------------------------

    if fade_progress >= 1.0 then
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
                    "[Fade] Mouse=(%d,%d) Inside=%s Opacity=%.4f Target=%.4f Progress=%.2f",
                    mx,
                    my,
                    tostring(inside),
                    current_opacity,
                    target_opacity,
                    fade_progress
                )
            )
        end
    end
end

--------------------------------------------------
-- UI
--------------------------------------------------

function script_description()
    return "Advanced OBS cursor fade with customizable easing curves"
end

function script_properties()

    local props = obs.obs_properties_create()

    obs.obs_properties_add_bool(props, "enabled", "Enable")
    obs.obs_properties_add_bool(props, "debug_enabled", "Debug")

    obs.obs_properties_add_text(
        props,
        "source_name",
        "Source",
        obs.OBS_TEXT_DEFAULT
    )

    obs.obs_properties_add_text(
        props,
        "filter_name",
        "Filter",
        obs.OBS_TEXT_DEFAULT
    )

    obs.obs_properties_add_float_slider(props, "min_x_pct", "Min X %", 0, 100, 0.1)
    obs.obs_properties_add_float_slider(props, "min_y_pct", "Min Y %", 0, 100, 0.1)
    obs.obs_properties_add_float_slider(props, "max_x_pct", "Max X %", 0, 100, 0.1)
    obs.obs_properties_add_float_slider(props, "max_y_pct", "Max Y %", 0, 100, 0.1)

    obs.obs_properties_add_float_slider(
        props,
        "inside_opacity",
        "Inside Opacity",
        0.0,
        1.0,
        0.001
    )

    obs.obs_properties_add_float_slider(
        props,
        "outside_opacity",
        "Outside Opacity",
        0.0,
        1.0,
        0.001
    )

    --------------------------------------------------
    -- NEW CONTROLS
    --------------------------------------------------

    obs.obs_properties_add_float_slider(
        props,
        "fade_in_speed",
        "Fade In Speed",
        0.1,
        20.0,
        0.1
    )

    obs.obs_properties_add_float_slider(
        props,
        "fade_out_speed",
        "Fade Out Speed",
        0.1,
        20.0,
        0.1
    )

    local p1 = obs.obs_properties_add_list(
        props,
        "fade_in_easing",
        "Fade In Easing",
        obs.OBS_COMBO_TYPE_LIST,
        obs.OBS_COMBO_FORMAT_STRING
    )

    local p2 = obs.obs_properties_add_list(
        props,
        "fade_out_easing",
        "Fade Out Easing",
        obs.OBS_COMBO_TYPE_LIST,
        obs.OBS_COMBO_FORMAT_STRING
    )

    local modes = {
        "linear",
        "smoothstep",
        "smootherstep",
        "ease_in",
        "ease_out",
        "ease_in_out"
    }

    for _, mode in ipairs(modes) do
        obs.obs_property_list_add_string(p1, mode, mode)
        obs.obs_property_list_add_string(p2, mode, mode)
    end

    return props
end

--------------------------------------------------
-- DEFAULTS
--------------------------------------------------

function script_defaults(settings)

    obs.obs_data_set_default_bool(settings, "enabled", true)

    obs.obs_data_set_default_double(settings, "inside_opacity", 0.0)
    obs.obs_data_set_default_double(settings, "outside_opacity", 0.02)

    obs.obs_data_set_default_double(settings, "fade_in_speed", 3.0)
    obs.obs_data_set_default_double(settings, "fade_out_speed", 8.0)

    obs.obs_data_set_default_string(settings, "fade_in_easing", "ease_out")
    obs.obs_data_set_default_string(settings, "fade_out_easing", "ease_in_out")
end

--------------------------------------------------
-- UPDATE
--------------------------------------------------

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

    fade_in_speed = obs.obs_data_get_double(settings, "fade_in_speed")
    fade_out_speed = obs.obs_data_get_double(settings, "fade_out_speed")

    fade_in_easing = obs.obs_data_get_string(settings, "fade_in_easing")
    fade_out_easing = obs.obs_data_get_string(settings, "fade_out_easing")

    current_opacity = outside_opacity
    start_opacity = current_opacity
    target_opacity = current_opacity
end