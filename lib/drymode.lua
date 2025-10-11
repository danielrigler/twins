local drymode = {}

local dry_mode_state = false
local dry_mode_state2 = false
local prev_settings = {}
local lfo

local DRY_VALUES = {
    filter_lock_ratio = 0,
    reverb_mix = 0,
    delay_mix = 0,
    bitcrush_mix = 0,
    shimmer_mix = 0,
    tape_mix = 1,
    drive = 0,
    Width = 100,
    monobass_mix = 1,
    wobble_mix = 0,
    chew_depth = 0,
    lossdegrade_mix = 0,
    rspeed = 0,
    haas = 0,
    tascam = 0,
    sine_drive = 0,
    dimension_mix = 0
}

local DRY_VALUES_STEREO = {
    granular_gain = 0,
    speed = 1.0,
    eq_low_gain = 0,
    eq_mid_gain = 0,
    eq_high_gain = 0,
    cutoff = 20000,
    hpf = 20,
    lpfgain = 0,
    pan = 0
}

local STEREO_PARAMS = {"granular_gain", "speed", "eq_low_gain", "eq_mid_gain", "eq_high_gain", "cutoff", "hpf", "lpfgain"}
local MONO_PARAMS = {"filter_lock_ratio", "reverb_mix", "delay_mix", "bitcrush_mix", "shimmer_mix", "tape_mix", 
                     "drive", "Width", "monobass_mix", "sine_drive", "wobble_mix", "chew_depth", "lossdegrade_mix", 
                     "rspeed", "haas", "tascam", "dimension_mix"}

local LFO_TARGETS = {
    speed = {["1speed"] = true, ["2speed"] = true},
    seek = {["1seek"] = true, ["2seek"] = true},
    pan = {["1pan"] = true, ["2pan"] = true},
    volume = {["1volume"] = true, ["2volume"] = true}
}

local LFO_TARGET_TYPES = {"speed", "seek", "pan", "volume"}

function drymode.set_lfo_reference(lfo_module)
    lfo = lfo_module
end

local function store_params(param_list, stereo)
    local t = {}
    if stereo then
        for _, p in ipairs(param_list) do
            t[p] = {params:get("1"..p), params:get("2"..p)}
        end
    else
        for _, p in ipairs(param_list) do
            t[p] = params:get(p)
        end
    end
    return t
end

local function restore_params(settings, stereo)
    if not settings then return end
    
    if stereo then
        for p, vals in pairs(settings) do
            if vals and #vals >= 2 then
                params:set("1"..p, vals[1])
                params:set("2"..p, vals[2])
            end
        end
    else
        for p, v in pairs(settings) do
            if v ~= nil then
                params:set(p, v)
            end
        end
    end
end

local function set_stereo_params(values)
    for param, value in pairs(values) do
        params:set("1"..param, value)
        params:set("2"..param, value)
    end
end

local function store_and_disable_lfos(targets, storage)
    if not lfo or not lfo.lfo_targets then return end
    
    for i = 1, 16 do
        local target_index = params:get(i.."lfo_target")
        local target = lfo.lfo_targets[target_index]
        
        if targets[target] then
            storage[i] = {
                state = params:get(i.."lfo"),
                target_index = target_index,
                shape = params:get(i.."lfo_shape"),
                depth = params:get(i.."lfo_depth"),
                offset = params:get(i.."offset"),
                freq = params:get(i.."lfo_freq")
            }
            params:set(i.."lfo", 1) -- Disable LFO
        end
    end
end

local function restore_lfos(lfo_table)
    if not lfo_table then return end
    
    local was_paused = params:get("lfo_pause")
    params:set("lfo_pause", 1)
    
    for i, data in pairs(lfo_table) do
        if data then
            params:set(i.."lfo_target", data.target_index)
            params:set(i.."lfo_shape", data.shape)
            params:set(i.."lfo_depth", data.depth)
            params:set(i.."offset", data.offset)
            params:set(i.."lfo_freq", data.freq)
            params:set(i.."lfo", data.state)
        end
    end
    
    params:set("lfo_pause", was_paused)
end

function drymode.toggle_dry_mode()
    dry_mode_state = not dry_mode_state
    
    if not dry_mode_state then
        -- Entering dry mode - store current settings
        prev_settings = store_params(STEREO_PARAMS, true)
        
        -- Store mono parameters
        local mono_settings = store_params(MONO_PARAMS, false)
        for k, v in pairs(mono_settings) do
            prev_settings[k] = v
        end

        -- Store and disable LFOs for all target types
        for _, target_type in ipairs(LFO_TARGET_TYPES) do
            prev_settings[target_type.."_lfos"] = {}
            store_and_disable_lfos(LFO_TARGETS[target_type], prev_settings[target_type.."_lfos"])
        end

        -- Apply dry settings
        for param, value in pairs(DRY_VALUES) do
            params:set(param, value)
        end
        
        set_stereo_params(DRY_VALUES_STEREO)
        
    else
        -- Exiting dry mode - restore settings
        if next(prev_settings) then
            -- Restore stereo parameters
            local stereo_settings = {}
            for _, param in ipairs(STEREO_PARAMS) do
                if prev_settings[param] then
                    stereo_settings[param] = prev_settings[param]
                end
            end
            restore_params(stereo_settings, true)

            -- Restore mono parameters
            local mono_settings = {}
            for _, param in ipairs(MONO_PARAMS) do
                if prev_settings[param] ~= nil then
                    mono_settings[param] = prev_settings[param]
                end
            end
            restore_params(mono_settings, false)

            -- Restore LFOs
            for _, target_type in ipairs(LFO_TARGET_TYPES) do
                restore_lfos(prev_settings[target_type.."_lfos"])
            end
        end
    end
end

function drymode.toggle_dry_mode2()
    dry_mode_state2 = not dry_mode_state2
    
    if not dry_mode_state2 then
        -- Entering simple dry mode
        prev_settings = store_params({"granular_gain", "speed"}, true)
        set_stereo_params({granular_gain = 0, speed = 1.0})
    else
        -- Exiting simple dry mode
        if next(prev_settings) then
            restore_params(prev_settings, true)
        end
    end
end

-- Utility functions for external use
function drymode.get_dry_mode_state()
    return dry_mode_state
end

function drymode.get_dry_mode2_state()
    return dry_mode_state2
end

function drymode.is_any_dry_mode_active()
    return dry_mode_state or dry_mode_state2
end

return drymode