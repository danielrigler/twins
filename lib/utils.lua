local utils = {}

utils.system_param_exclude = {
    reverb = true, rev_eng_input = true,
    rev_pre_delay = true, rev_lf_fc = true, rev_low_time = true,
    rev_mid_time = true, rev_hf_damping = true,
    monitor_level = true, input_level = true, input_level_l = true, input_level_r = true,
    output_level = true, headphone_level = true, screen_brightness = true,
    clock_source = true, clock_tempo = true, clock_crow_in_div = true,
    clock_crow_out_div = true, clock_link_quantum = true, clock_link_start_stop_sync = true,
    midi_out_clock = true, midi_in_clock = true,
    enc_sens_default = true, key_repeat_initial = true, key_repeat_period = true,
}

local T_SEPARATOR, T_FILE, T_TRIGGER, T_GROUP, T_TEXT = 0, 4, 6, 7, 8

function utils.capturable(p)
    local t = p.t
    if t == T_SEPARATOR or t == T_FILE or t == T_TRIGGER or t == T_GROUP or t == T_TEXT then
        return false
    end
    if p.behavior and p.behavior ~= "toggle" then return false end
    return true
end

local running_metros = {}

function utils.metro_start(m)
    running_metros[m] = true
    m:start()
end

function utils.stop_metro_safe(m)
    if m and running_metros[m] then
        running_metros[m] = nil
        pcall(function() m:stop() end)
        m.event = nil
    end
end

function utils.deep_copy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do copy[k] = utils.deep_copy(v) end
    return copy
end

function utils.clear_table(t)
    for k in pairs(t) do t[k] = nil end
end

function utils.random_float(l, h)
    return l + math.random() * (h - l)
end

function utils.capture_lfo_slot(i, keys)
    return {
        state  = params:get(keys.lfo[i]),
        target = params:get(keys.target[i]),
        shape  = params:get(keys.shape[i]),
        freq   = params:get(keys.freq[i]),
        depth  = params:get(keys.depth[i]),
        offset = params:get(keys.offset[i]),
    }
end

function utils.apply_lfo_slot(i, keys, data)
    params:set(keys.target[i], data.target)
    params:set(keys.shape[i],  data.shape)
    params:set(keys.freq[i],   data.freq)
    params:set(keys.depth[i],  data.depth)
    params:set(keys.offset[i], data.offset)
    params:set(keys.lfo[i],    data.state)
end

local _mirror_cache = {}
function utils.mirror_param_name(param)
    local m = _mirror_cache[param]
    if m then return m end
    m = param:gsub("^(%d)(.*)", function(n, rest)
        return tostring((tonumber(n) % 2) + 1) .. rest
    end)
    _mirror_cache[param] = m
    return m
end

return utils