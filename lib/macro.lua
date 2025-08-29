local macro = {}

-- Constants
local INTERPOLATION_SPEED = 1 / 30
local EPSILON = 0.01
local TARGET_DEPTH_PERCENT = 15

-- Cached parameter ranges
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

-- State management
local targets = {}
local active_interpolations = {}
local lfo_cache = {} -- Cache LFO lookups

function macro.set_lfo_reference(lfo_module)
    lfo_ref = lfo_module
    lfo_cache = {} -- Clear cache when reference changes
end

-- Optimized interpolation with early termination
local function interpolate(start_val, end_val, factor)
    local diff = end_val - start_val
    if math.abs(diff) < EPSILON then
        return end_val
    end
    return start_val + diff * (1 - math.exp(-6 * factor))
end

-- Cache LFO lookups to avoid repeated parameter checks
local function get_lfo_for_param(param_name)
    if not lfo_ref then return false, nil end
    
    -- Check cache first
    local cached = lfo_cache[param_name]
    if cached ~= nil then
        -- If cached is false, we know there's no LFO
        if cached == false then
            return false, nil
        end
        -- If cached is a table, verify LFO is still active
        if type(cached) == "table" and cached.lfo_index then
            if params:get(cached.lfo_index .. "lfo") == 2 then
                return true, cached.lfo_index
            else
                -- LFO is no longer active, update cache
                lfo_cache[param_name] = false
                return false, nil
            end
        end
    end
    
    -- Scan for active LFO
    for i = 1, 16 do
        local target_index = params:get(i .. "lfo_target")
        if lfo_ref.lfo_targets[target_index] == param_name and params:get(i .. "lfo") == 2 then
            lfo_cache[param_name] = {lfo_index = i}
            return true, i
        end
    end
    
    lfo_cache[param_name] = false
    return false, nil
end

-- Optimized LFO parameter processing
local function process_lfo_param(param, target, factor, lfo_index)
    local current_value = params:get(param)
    local new_value = interpolate(current_value, target, factor)
    
    -- Get parameter range (cached lookup)
    local min_val, max_val = lfo_ref.get_parameter_range(param)
    local range = max_val - min_val
    
    -- Calculate safe depth
    local target_depth = TARGET_DEPTH_PERCENT * 0.01 * range
    local max_safe_depth = math.min(new_value - min_val, max_val - new_value) * 2
    local safe_depth = math.min(target_depth, max_safe_depth)
    
    -- Update LFO parameters
    local new_depth = safe_depth / range * 100
    local new_offset = util.linlin(min_val, max_val, -1, 1, new_value)
    
    params:set(lfo_index .. "offset", interpolate(params:get(lfo_index .. "offset"), new_offset, factor))
    params:set(lfo_index .. "lfo_depth", interpolate(params:get(lfo_index .. "lfo_depth"), new_depth, factor))
    params:set(param, new_value)
    
    return math.abs(new_value - target) > EPSILON
end

-- Streamlined normal parameter processing
local function process_normal_param(param, target, factor)
    local current_value = params:get(param)
    local new_value = interpolate(current_value, target, factor)
    params:set(param, new_value)
    return math.abs(new_value - target) > EPSILON
end

-- Optimized interpolation loop
local function start_interpolation(steps)
    if not next(targets) then return end -- Early exit if no targets
    
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
                    targets[param] = nil -- Remove completed target immediately
                else
                    params_still_active = true
                end
            end
        end
        
        if not params_still_active then
            randomize_metro:stop()
            -- Clear state
            targets = {}
            lfo_cache = {}
        end
    end
    randomize_metro:start()
end

-- Cached lock status check
local function is_param_locked(param_name)
    local track_num, param = param_name:match("^(%d)(%a+)$")
    return track_num and param and params:get(track_num .. "lock_" .. param) == 2
end

-- Get parameter range with fallback
local function get_param_range(param_name)
    local param = param_name:match("%d(.+)")
    return param_ranges[param] or {min = 0, max = 100}
end

-- Optimized parameter adjustment
local function adjust_params(multiplier)
    -- Stop any running interpolation
    if randomize_metro.running then
        randomize_metro:stop()
    end
    
    -- Clear previous state
    targets = {}
    active_interpolations = {}
    lfo_cache = {}
    
    -- Build target list
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
    
    start_interpolation(params:get("steps"))
end

-- Public interface
function macro.macro_more()
    adjust_params(1.5)
end

function macro.macro_less()
    adjust_params(0.66)
end

return macro