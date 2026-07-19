local drymode = {}
local utils = include("lib/utils")
local dry_mode_state = false
local dry_mode_state2 = false
local stereo_dry = false
local prev_settings = nil
local prev_settings2 = nil
local lfo

local DRY_VALUES = {
    reverb_mix = -40,
    delay_mix = 0,
    bitcrush_mix = 0,
    glitch_ratio = 0,
    glitch_mix = 0,
    shimmer_mix1 = 0,
    tape_mix = 1,
    analogdrive_mix = 0,
    Width = 100,
    monobass_mix = 1,
    wobble_mix = 0,
    chew_depth = 0,
    lossdegrade_mix = 0,
    rspeed = 0,
    haas = 0,
    sine_drive_wet = 0,
    dimension_mix = 0,
    resonator_mix = 0,
    wavefold_mix = 0,
    ringmod_mix = 0,
    clock_sync = 1,
    arp_on = 1
}

local DRY_VALUES_STEREO = {
    granular_gain = 0,
    speed = 1.0,
    eq_low_gain = 0,
    eq_mid_gain = 0,
    eq_high_gain = 0,
    eq_tilt = 0,
    cutoff = 20000,
    hpf = 20,
    lpf_gain = 0.05,
    pan = 0
}

local STEREO_PARAMS = {} for k in pairs(DRY_VALUES_STEREO) do STEREO_PARAMS[#STEREO_PARAMS + 1] = k end
local MONO_PARAMS = {} for k in pairs(DRY_VALUES) do MONO_PARAMS[#MONO_PARAMS + 1] = k end

local SEEK_PARAMS = {"1seek", "2seek"}

local LFO_TARGETS = {
    speed = {["1speed"] = true, ["2speed"] = true},
    seek = {["1seek"] = true, ["2seek"] = true},
    pan = {["1pan"] = true, ["2pan"] = true},
    volume = {["1volume"] = true, ["2volume"] = true},
    cutoff = {["1cutoff"] = true, ["2cutoff"] = true},
    hpf = {["1hpf"] = true, ["2hpf"] = true}
}

local LFO_TARGET_TYPES = {"speed", "seek", "pan", "volume", "cutoff", "hpf"}

function drymode.set_context(ctx) lfo = ctx.lfo end

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
            params:set("1"..p, vals[1])
            params:set("2"..p, vals[2])
        end
    else
        for p, v in pairs(settings) do
            params:set(p, v)
        end
    end
end

local function set_stereo_params(values, v1, v2)
    for param, value in pairs(values) do
        if v1 ~= false then params:set("1"..param, value) end
        if v2 ~= false then params:set("2"..param, value) end
    end
end

local function store_and_disable_lfos(targets, storage)
    if not lfo or not lfo.lfo_targets then return end
    local keys = lfo.keys

    for i = 1, 16 do
        local target_index = params:get(keys.target[i])
        local target = lfo.lfo_targets[target_index]

        if targets[target] then
            storage[i] = utils.capture_lfo_slot(i, keys)
            params:set(keys.lfo[i], 1)
        end
    end
end

local function restore_lfos(lfo_table)
    if not lfo_table then return end
    local keys = lfo.keys

    local was_paused = params:get("lfo_pause")
    params:set("lfo_pause", 1)

    for i, data in pairs(lfo_table) do
        if data then
            utils.apply_lfo_slot(i, keys, data)
        end
    end

    params:set("lfo_pause", was_paused)
end

function drymode.reset_dry(v1, v2, fx)
    local targets = {}
    for _, t in ipairs(LFO_TARGET_TYPES) do
        if v1 then targets["1"..t] = true end
        if v2 then targets["2"..t] = true end
    end
    store_and_disable_lfos(targets, {})
    set_stereo_params(DRY_VALUES_STEREO, v1, v2)
    if fx then
        for param, value in pairs(DRY_VALUES) do
            if param ~= "reverb_mix" then params:set(param, value) end
        end
    end
end

function drymode.set_dry_mode(on)
    if on == dry_mode_state then return end
    dry_mode_state = on

    if on then
        local snap = {
            stereo = store_params(STEREO_PARAMS, true),
            mono = store_params(MONO_PARAMS, false),
            seek = {},
            lfos = {}
        }
        for _, param in ipairs(SEEK_PARAMS) do
            snap.seek[param] = params:get(param)
        end
        for _, target_type in ipairs(LFO_TARGET_TYPES) do
            snap.lfos[target_type] = {}
            store_and_disable_lfos(LFO_TARGETS[target_type], snap.lfos[target_type])
        end
        prev_settings = snap

        for param, value in pairs(DRY_VALUES) do
            params:set(param, value)
        end
        set_stereo_params(DRY_VALUES_STEREO)

    else
        if prev_settings then
            restore_params(prev_settings.stereo, true)
            restore_params(prev_settings.mono, false)
            for param, v in pairs(prev_settings.seek) do
                params:set(param, v)
            end
            for _, target_type in ipairs(LFO_TARGET_TYPES) do
                restore_lfos(prev_settings.lfos[target_type])
            end
        end
    end
end

function drymode.set_dry_mode2(on)
    if on == dry_mode_state2 then return end
    dry_mode_state2 = on

    if on then
        prev_settings2 = {stereo = store_params({"granular_gain", "speed"}, true)}
        stereo_dry = true
        set_stereo_params({granular_gain = 0, speed = 1.0})
    else
        stereo_dry = false
        if prev_settings2 then
            restore_params(prev_settings2.stereo, true)
        end
    end
    params:lookup_param("1speed"):bang()
    params:lookup_param("2speed"):bang()
end

function drymode.stereo_dry_active() return stereo_dry end

return drymode