local macro = {}

local TARGET_DEPTH_PERCENT = 15

local param_ranges = {
    speed = {min = -1.99, max = 1.99},
    jitter = {min = 0, max = 1999},
    size = {min = 150, max = 599},
    density = {min = 0.1, max = 49},
}

local TARGET_DEPTH_FACTOR = TARGET_DEPTH_PERCENT * 0.01
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
local lfo_cache = {}
 
function macro.set_lfo_reference(lfo_module)
    lfo_ref = lfo_module
    lfo_cache = {}
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
    local new_value = current_value + (target - current_value) * factor
    
    local min_val, max_val = lfo_ref.get_parameter_range(param)
    local range = max_val - min_val
    
    local target_depth = TARGET_DEPTH_FACTOR * range
    local max_safe_depth = math.min(new_value - min_val, max_val - new_value) * 2
    local safe_depth = math.min(target_depth, max_safe_depth)
    
    local new_depth = safe_depth / range * 100
    local new_offset = util.linlin(min_val, max_val, -1, 1, new_value)
    
    local offset_param = lfo_index .. "offset"
    local depth_param = lfo_index .. "lfo_depth"
    
    local current_offset = params:get(offset_param)
    local current_depth = params:get(depth_param)
    
    params:set(offset_param, current_offset + (new_offset - current_offset) * factor)
    params:set(depth_param, current_depth + (new_depth - current_depth) * factor)
    params:set(param, new_value)
    
    return math.abs(new_value - target) < 0.01
end

local function is_param_locked(track_num, param_suffix)
    return params:get(lock_params[track_num][param_suffix]) == 2
end

local function get_param_range(param_suffix)
    return param_ranges[param_suffix] or {min = 0, max = 100}
end

local function stop_metro_safe(m)
    if m then
        pcall(function() m:stop() end)
        if m then m.event = nil end
    end
end

local function adjust_params(multiplier)
    if randomize_metro.running then
        stop_metro_safe(randomize_metro)
    end
    
    lfo_cache = {}
    
    local upper_multiplier = 0.95
    local lower_multiplier = 1.05
    
    local targets = {}
    
    -- Calculate targets for all unlocked parameters
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
            end
        end
    end
    
    if next(targets) then
        local steps_option = params:get("steps")
        local step_counts = {20, 300, 800}
        local steps = step_counts[steps_option] or 20
        randomize_metro.time = 1 / 30
        randomize_metro.event = function(count)
            local tolerance = 0.01
            local factor = count / steps
            local all_done = true
            
            for param, target in pairs(targets) do
                local has_lfo, lfo_index = get_lfo_for_param(param)
                
                if has_lfo then
                    all_done = process_lfo_param(param, target, factor, lfo_index) and all_done
                else
                    local current = params:get(param)
                    local new_val = current + (target - current) * factor
                    params:set(param, new_val)
                    all_done = all_done and (math.abs(new_val - target) < tolerance)
                end
            end
            
            if all_done then
                stop_metro_safe(randomize_metro)
            end
        end
        randomize_metro:start()
    end
end

function macro.macro_more()
    adjust_params(1.5)
end

function macro.macro_less()
    adjust_params(0.66)
end

return macro