local macro = {}
local utils = include("lib/utils")

local TARGET_DEPTH_PERCENT = 15

local MACRO_RANGES = {
    speed   = {min = -1.99, max = 1.99},
    jitter  = {min = 0,     max = 1999},
    size    = {min = 150,   max = 599},
    density = {min = 0.1,   max = 49}}

local TARGET_DEPTH_FACTOR = TARGET_DEPTH_PERCENT * 0.01
local PARAMS_TO_ADJUST    = {"speed", "size", "jitter", "density"}
local NUM_TRACKS          = 2
local param_limits = {}
for suffix, r in pairs(MACRO_RANGES) do
    local span   = r.max - r.min
    local margin = span * 0.05
    param_limits[suffix] = {
        lo = r.min + margin,
        hi = r.max - margin}
end

local lock_params = {}
for i = 1, NUM_TRACKS do
    lock_params[i] = {}
    for _, suffix in ipairs(PARAMS_TO_ADJUST) do
        lock_params[i][suffix] = i .. "lock_" .. suffix
    end
end

local lfo_ref          = nil
local randomize_metro  = metro.init()
local stop_metro_safe  = utils.stop_metro_safe

function macro.set_lfo_reference(lfo_module) lfo_ref = lfo_module end

local function is_param_locked(track_num, param_suffix)
    return params:get(lock_params[track_num][param_suffix]) == 2
end

local function process_lfo_param(param, target, factor, lfo_index, min_val, max_val)
    local current_value  = params:get(param)
    local new_value      = current_value + (target - current_value) * factor
    local range          = max_val - min_val
    local target_depth   = TARGET_DEPTH_FACTOR * range
    local max_safe_depth = math.min(new_value - min_val, max_val - new_value) * 2
    local safe_depth     = math.min(target_depth, max_safe_depth)
    local new_depth      = safe_depth / range * 100
    local new_offset     = util.linlin(min_val, max_val, -1, 1, new_value)
    local offset_param   = lfo_index .. "offset"
    local depth_param    = lfo_index .. "lfo_depth"
    params:set(offset_param, params:get(offset_param) + (new_offset - params:get(offset_param)) * factor)
    params:set(depth_param,  params:get(depth_param)  + (new_depth  - params:get(depth_param))  * factor)
    params:set(param, new_value)
    return math.abs(new_value - target) < 0.01
end

local function adjust_params(multiplier)
    stop_metro_safe(randomize_metro)
    randomize_metro.event = nil
    local going_up = multiplier > 1
    local targets  = {}
    local lfo_ranges = {}
    for i = 1, NUM_TRACKS do
        for _, param_suffix in ipairs(PARAMS_TO_ADJUST) do
            if not is_param_locked(i, param_suffix) then
                local param         = i .. param_suffix
                local current_value = params:get(param)
                local limits        = param_limits[param_suffix]
                local lo, hi        = limits.lo, limits.hi
                local lfo_min, lfo_max
                if lfo_ref then
                    lfo_min, lfo_max = lfo_ref.get_parameter_range(param)
                    if lfo_min and lfo_min > lo then lo = lfo_min end
                    if lfo_max and lfo_max < hi then hi = lfo_max end
                end
                local target_value
                if going_up then
                    target_value = math.min(current_value * multiplier, hi)
                else
                    target_value = math.max(current_value * multiplier, lo)
                end
                targets[param] = target_value
                if lfo_ref then
                    local lfo_index = lfo_ref.get_lfo_for_param(param)
                    if lfo_index then
                        lfo_ranges[param] = {lfo_index = lfo_index, min = lfo_min, max = lfo_max}
                    end
                end
            end
        end
    end

    if not next(targets) then return end

    local steps_option = params:get("steps")
    local step_counts  = {20, 300, 800}
    local steps        = step_counts[steps_option] or 20

    randomize_metro.time  = 1 / 30
    randomize_metro.event = function(count)
        local tolerance = 0.01
        local factor    = count / steps
        local all_done  = true

        for param, target in pairs(targets) do
            local lfo_data = lfo_ranges[param]
            if lfo_data then
                local done = process_lfo_param(
                    param, target, factor,
                    lfo_data.lfo_index, lfo_data.min, lfo_data.max
                )
                if not done then all_done = false end
            else
                local current = params:get(param)
                local new_val = current + (target - current) * factor
                params:set(param, new_val)
                if math.abs(new_val - target) >= tolerance then all_done = false end
            end
        end

        if all_done then stop_metro_safe(randomize_metro) end
    end
    utils.metro_start(randomize_metro)
end

function macro.macro_more() adjust_params(1.5)  end
function macro.macro_less() adjust_params(0.66) end

return macro