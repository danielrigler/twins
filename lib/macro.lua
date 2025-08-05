local macro = {}

local INTERPOLATION_SPEED = 1 / 30
local EPSILON = 0.01
local TARGET_DEPTH_PERCENT = 15

local param_ranges = {
    speed = {min = -1.99, max = 1.99},
    jitter = {min = 0, max = 1999},
    size = {min = 150, max = 599},
    density = {min = 0.1, max = 49},
    spread = {min = 0, max = 99}
}

local params_to_adjust = {"speed", "size", "jitter", "spread", "density"}
local lfo_ref = nil
local randomize_metro = metro.init()
local targets = {}
local active_interpolations = {}

function macro.set_lfo_reference(lfo_module)
    lfo_ref = lfo_module
end

local function interpolate(start_val, end_val, factor)
    if math.abs(start_val - end_val) < EPSILON then
        return end_val
    end
    return start_val + (end_val - start_val) * (1 - math.exp(-6 * factor))
end

local function safe_metro_stop(metro_obj)
    if metro_obj and metro_obj.running then
        metro_obj:stop()
    end
end

local function has_active_lfo(param_name)
    if not lfo_ref then return false, nil end
    for i = 1, 16 do
        local target_index = params:get(i .. "lfo_target")
        if lfo_ref.lfo_targets[target_index] == param_name and params:get(i .. "lfo") == 2 then
            return true, i
        end
    end
    return false, nil
end

local function get_param_range(param_name)
    local param = param_name:match("%d(.+)")
    return param_ranges[param] or {min = 0, max = 100}
end

local function process_lfo_param(param, target, factor, lfo_index)
    local current_value = params:get(param)
    local new_value = interpolate(current_value, target, factor)
    local min_val, max_val = lfo_ref.get_parameter_range(param)
    local range = max_val - min_val
    local target_depth = TARGET_DEPTH_PERCENT / 100 * range
    local max_safe_depth = math.min(new_value - min_val, max_val - new_value) * 2
    local safe_depth = math.min(target_depth, max_safe_depth)
    local new_depth = safe_depth / range * 100
    local new_offset = util.linlin(min_val, max_val, -1, 1, new_value)
    params:set(lfo_index .. "offset", interpolate(params:get(lfo_index .. "offset"), new_offset, factor))
    params:set(lfo_index .. "lfo_depth", interpolate(params:get(lfo_index .. "lfo_depth"), new_depth, factor))
    params:set(param, new_value)
    return math.abs(new_value - target) > EPSILON
end

local function process_normal_param(param, target, factor)
    local new_value = interpolate(params:get(param), target, factor)
    params:set(param, new_value)
    return math.abs(new_value - target) > EPSILON
end

local function start_interpolation(steps)
    randomize_metro.time = INTERPOLATION_SPEED
    randomize_metro.count = -1
    randomize_metro.event = function(count)
        local factor = count / steps
        local all_done = true
        for param, target in pairs(targets) do
            if active_interpolations[param] then
                local has_lfo, lfo_index = has_active_lfo(param)
                local still_active = has_lfo and process_lfo_param(param, target, factor, lfo_index)
                                      or process_normal_param(param, target, factor)
                if not still_active then
                    active_interpolations[param] = nil
                else
                    all_done = false
                end
            end
        end
        if all_done then
            safe_metro_stop(randomize_metro)
            targets = {}
        end
    end
    randomize_metro:start()
end

local function is_param_locked(param_name)
    local track_num, param = param_name:match("^(%d)(%a+)$")
    return track_num and param and params:get(track_num .. "lock_" .. param) == 2
end

local function adjust_params(multiplier)
    safe_metro_stop(randomize_metro)
    targets = {}
    for i = 1, 2 do
        for _, param_suffix in ipairs(params_to_adjust) do
            local param = i .. param_suffix
            if not is_param_locked(param) then
                local current_value = params:get(param)
                local range = get_param_range(param)
                local target_value
                if multiplier > 1 then
                    target_value = math.min(current_value * multiplier, range.max * 0.95)
                else
                    target_value = math.max(current_value * multiplier, range.min * 1.05)
                end
                targets[param] = target_value
                active_interpolations[param] = true
            end
        end
    end
    if next(targets) ~= nil then
        start_interpolation(params:get("steps"))
    end
end

function macro.macro_more()
    adjust_params(1.5)
end

function macro.macro_less()
    adjust_params(0.66)
end

return macro