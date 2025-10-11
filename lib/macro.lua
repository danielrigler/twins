local macro = {}

local INTERPOLATION_SPEED = 1 / 30
local EPSILON = 0.01
local TARGET_DEPTH_PERCENT = 15

local param_ranges = {
    speed = {min = -1.99, max = 1.99},
    jitter = {min = 0, max = 1999},
    size = {min = 150, max = 599},
    density = {min = 0.1, max = 49},
}

local TARGET_DEPTH_FACTOR = TARGET_DEPTH_PERCENT * 0.01
local INTERPOLATION_CONSTANT = 6
local PARAMS_TO_ADJUST = {"speed", "size", "jitter", "density"}
local NUM_TRACKS = 2

local lock_params = {}
for i = 1, NUM_TRACKS do
    lock_params[i] = {}
    for _, suffix in ipairs(PARAMS_TO_ADJUST) do
        lock_params[i][suffix] = i .. "lock_" .. suffix
    end
end

local lfo_ref = nil
local randomize_metro = metro.init()

local targets = {}
local active_interpolations = {}
local lfo_cache = {}

function macro.set_lfo_reference(lfo_module)
    lfo_ref = lfo_module
    lfo_cache = {}
end

local function interpolate(start_val, end_val, factor)
    local diff = end_val - start_val
    if math.abs(diff) < EPSILON then
        return end_val
    end
    return start_val + diff * (1 - math.exp(-INTERPOLATION_CONSTANT * factor))
end

local function get_lfo_for_param(param_name)
    if not lfo_ref then return false, nil end
    
    local cached = lfo_cache[param_name]
    if cached ~= nil then
        if cached == false then
            return false, nil
        end
        if type(cached) == "table" and cached.lfo_index then
            local lfo_param = cached.lfo_index .. "lfo"
            if params:get(lfo_param) == 2 then
                return true, cached.lfo_index
            else
                lfo_cache[param_name] = false
                return false, nil
            end
        end
    end
    
    local lfo_targets = lfo_ref.lfo_targets
    for i = 1, 16 do
        local target_index = params:get(i .. "lfo_target")
        if lfo_targets[target_index] == param_name and params:get(i .. "lfo") == 2 then
            lfo_cache[param_name] = {lfo_index = i}
            return true, i
        end
    end
    
    lfo_cache[param_name] = false
    return false, nil
end

local function process_lfo_param(param, target, factor, lfo_index)
    local current_value = params:get(param)
    local new_value = interpolate(current_value, target, factor)
    
    local min_val, max_val = lfo_ref.get_parameter_range(param)
    local range = max_val - min_val
    
    local target_depth = TARGET_DEPTH_FACTOR * range
    local max_safe_depth = math.min(new_value - min_val, max_val - new_value) * 2
    local safe_depth = math.min(target_depth, max_safe_depth)
    
    local new_depth = safe_depth / range * 100
    local new_offset = util.linlin(min_val, max_val, -1, 1, new_value)
    
    local offset_param = lfo_index .. "offset"
    local depth_param = lfo_index .. "lfo_depth"
    
    params:set(offset_param, interpolate(params:get(offset_param), new_offset, factor))
    params:set(depth_param, interpolate(params:get(depth_param), new_depth, factor))
    params:set(param, new_value)
    
    return math.abs(new_value - target) > EPSILON
end

local function process_normal_param(param, target, factor)
    local current_value = params:get(param)
    local new_value = interpolate(current_value, target, factor)
    params:set(param, new_value)
    return math.abs(new_value - target) > EPSILON
end

local function start_interpolation(steps)
    if not next(targets) then return end
    
    randomize_metro.time = INTERPOLATION_SPEED
    randomize_metro.count = -1
    randomize_metro.event = function(count)
        local factor = count / steps
        local params_still_active = false
        
        for param, target in pairs(targets) do
            if active_interpolations[param] then
                local has_lfo, lfo_index = get_lfo_for_param(param)
                local still_active
                
                if has_lfo then
                    still_active = process_lfo_param(param, target, factor, lfo_index)
                else
                    still_active = process_normal_param(param, target, factor)
                end
                
                if not still_active then
                    active_interpolations[param] = nil
                    targets[param] = nil
                else
                    params_still_active = true
                end
            end
        end
        
        if not params_still_active then
            randomize_metro:stop()
            targets = {}
            lfo_cache = {}
        end
    end
    randomize_metro:start()
end

local function is_param_locked(track_num, param_suffix)
    return params:get(lock_params[track_num][param_suffix]) == 2
end

local function get_param_range(param_suffix)
    return param_ranges[param_suffix] or {min = 0, max = 100}
end

local function adjust_params(multiplier)
    if randomize_metro.running then
        randomize_metro:stop()
    end
    
    targets = {}
    active_interpolations = {}
    lfo_cache = {}
    
    local upper_multiplier = 0.95
    local lower_multiplier = 1.05
    
    for i = 1, NUM_TRACKS do
        for _, param_suffix in ipairs(PARAMS_TO_ADJUST) do
            if not is_param_locked(i, param_suffix) then
                local param = i .. param_suffix
                local current_value = params:get(param)
                local range = get_param_range(param_suffix)
                
                local target_value
                if multiplier > 1 then
                    target_value = math.min(current_value * multiplier, range.max * upper_multiplier)
                else
                    target_value = math.max(current_value * multiplier, range.min * lower_multiplier)
                end
                
                targets[param] = target_value
                active_interpolations[param] = true
            end
        end
    end
    
    start_interpolation(params:get("steps"))
end

function macro.macro_more()
    adjust_params(1.5)
end

function macro.macro_less()
    adjust_params(0.66)
end

return macro