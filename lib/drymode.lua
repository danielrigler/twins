local drymode = {}

local dry_mode_state = false
local dry_mode_state2 = false
local prev_settings = {}
local lfo

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

local function store_and_disable_lfos(targets, storage)
    for i = 1, 16 do
        local target = lfo.lfo_targets[params:get(i.."lfo_target")]
        if targets[target] then
            storage[i] = {
                state = params:get(i.."lfo"),
                target_index = params:get(i.."lfo_target"),
                shape = params:get(i.."lfo_shape"),
                depth = params:get(i.."lfo_depth"),
                offset = params:get(i.."offset"),
                freq = params:get(i.."lfo_freq")
            }
            params:set(i.."lfo", 1)
        end
    end
end

local function restore_lfos(lfo_table)
    for i, data in pairs(lfo_table or {}) do
        local was_paused = params:get("lfo_pause")
        params:set("lfo_pause", 1)
        params:set(i.."lfo_target", data.target_index)
        params:set(i.."lfo_shape", data.shape)
        params:set(i.."lfo_depth", data.depth)
        params:set(i.."offset", data.offset)
        params:set(i.."lfo_freq", data.freq)
        params:set(i.."lfo", data.state)
        params:set("lfo_pause", was_paused)
    end
end

function drymode.toggle_dry_mode()
    dry_mode_state = not dry_mode_state
    if not dry_mode_state then
        -- Store params
        prev_settings = store_params({
            "granular_gain", "speed", "eq_low_gain", "eq_mid_gain", "eq_high_gain", "cutoff", "hpf"
        }, true)

    for k, v in pairs(store_params({
        "reverb_mix", "delay_mix", "bitcrush_mix", "shimmer_mix", "tape_mix",
        "drive", "Width", "monobass_mix", "sine_drive", "wobble_mix",
        "chew_depth", "lossdegrade_mix", "rspeed", "haas"
    }, false)) do
        prev_settings[k] = v
    end

        prev_settings.speed_lfos, prev_settings.seek_lfos,
        prev_settings.pan_lfos, prev_settings.volume_lfos = {}, {}, {}, {}

        store_and_disable_lfos({["1speed"]=true, ["2speed"]=true}, prev_settings.speed_lfos)
        store_and_disable_lfos({["1seek"]=true, ["2seek"]=true}, prev_settings.seek_lfos)
        store_and_disable_lfos({["1pan"]=true, ["2pan"]=true}, prev_settings.pan_lfos)
        store_and_disable_lfos({["1volume"]=true, ["2volume"]=true}, prev_settings.volume_lfos)

        -- Set dry values
        for i = 1, 2 do
            params:set(i.."granular_gain", 0)
            params:set(i.."speed", 1.0)
            params:set(i.."eq_low_gain", 0)
            params:set(i.."eq_mid_gain", 0)
            params:set(i.."eq_high_gain", 0)
            params:set(i.."cutoff", 20000)
            params:set(i.."hpf", 20)
            params:set(i.."pan", 0)
        end
        params:set("reverb_mix", 0)
        params:set("delay_mix", 0)
        params:set("bitcrush_mix", 0)
        params:set("shimmer_mix", 0)
        params:set("tape_mix", 1)
        params:set("drive", 0)
        params:set("Width", 100)
        params:set("monobass_mix", 1)
        params:set("wobble_mix", 0)
        params:set("chew_depth", 0)
        params:set("lossdegrade_mix", 0)
        params:set("rspeed", 0)
        params:set("haas", 0)
    else
        if next(prev_settings) then
            restore_params({
                granular_gain = prev_settings.granular_gain,
                speed = prev_settings.speed,
                eq_low_gain = prev_settings.eq_low_gain,
                eq_mid_gain = prev_settings.eq_mid_gain,
                eq_high_gain = prev_settings.eq_high_gain,
                cutoff = prev_settings.cutoff,
                hpf = prev_settings.hpf
            }, true)

            restore_params({
                reverb_mix = prev_settings.reverb_mix,
                delay_mix = prev_settings.delay_mix,
                bitcrush_mix = prev_settings.bitcrush_mix,
                shimmer_mix = prev_settings.shimmer_mix,
                tape_mix = prev_settings.tape_mix,
                drive = prev_settings.drive,
                Width = prev_settings.Width,
                monobass_mix = prev_settings.monobass_mix,
                sine_drive = prev_settings.sine_drive,
                wobble_mix = prev_settings.wobble_mix,
                chew_depth = prev_settings.chew_depth,
                lossdegrade_mix = prev_settings.lossdegrade_mix,
                rspeed = prev_settings.rspeed,
                haas = prev_settings.haas
            }, false)

            restore_lfos(prev_settings.speed_lfos)
            restore_lfos(prev_settings.seek_lfos)
            restore_lfos(prev_settings.pan_lfos)
            restore_lfos(prev_settings.volume_lfos)
        end
    end
end

function drymode.toggle_dry_mode2()
    dry_mode_state2 = not dry_mode_state2
    if not dry_mode_state2 then
        prev_settings = store_params({"granular_gain", "speed"}, true)
        for i = 1, 2 do
            params:set(i.."granular_gain", 0)
            params:set(i.."speed", 1.0)
        end
    else
        if next(prev_settings) then
            restore_params(prev_settings, true)
        end
    end
end

return drymode