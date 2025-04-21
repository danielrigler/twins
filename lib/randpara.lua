local function random_float(l, h)
    return l + math.random() * (h - l)
end

local function interpolate(start_val, end_val, factor)
    local epsilon = 0.01
    if math.abs(start_val - end_val) < epsilon then
        return end_val
    else
        return start_val + (end_val - start_val) * (1 - math.exp(-4 * factor))
    end
end

local randomize_metro = metro.init()
local targets = {}
local active_interpolations = {}
local interpolation_speed = 1 / 30

local function safe_metro_stop(metro_obj)
    if metro_obj and metro_obj.running then
        metro_obj:stop()
    end
end

local function start_interpolation(steps)
    randomize_metro.time = interpolation_speed
    randomize_metro.count = -1
    randomize_metro.event = function(count)
        local factor = count / steps
        local all_done = true
        for param, target in pairs(targets) do
            if active_interpolations[param] then
                local current_value = params:get(param)
                local new_value = interpolate(current_value, target, factor)
                params:set(param, new_value)

                if math.abs(new_value - target) > 0.00 then
                    all_done = false
                else
                    active_interpolations[param] = nil
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

local function randomize_fverb_params(steps)
  safe_metro_stop(randomize_metro)
    -- FVERB parameters
    targets["reverb_input_amount"] = math.random(40, 95)
    targets["reverb_predelay"] = math.random(0, 250)
    targets["reverb_lowpass_cutoff"] = math.random(4000, 9000)
    targets["reverb_highpass_cutoff"] = math.random(20, 300)
    targets["reverb_diffusion_1"] = math.random(70, 90)
    targets["reverb_diffusion_2"] = math.random(70, 90)
    targets["reverb_tail_density"] = math.random(70, 90)
    targets["reverb_decay"] = math.random(70, 90)
    targets["reverb_damping"] = math.random(1000, 4500)
    targets["reverb_modulator_frequency"] = random_float(0.3, 2)
    targets["reverb_modulator_depth"] = math.random(30, 100)

    for param, _ in pairs(targets) do
        active_interpolations[param] = true
    end
    start_interpolation(steps)
end

local function randomize_voice_params(i)
  safe_metro_stop(randomize_metro)
    -- VOICE-SPECIFIC PARAMETERS
    if math.random() <= 0.6 then targets[i .. "direction_mod"] = 0 else targets[i .. "direction_mod"] = math.random(0, 20) end
    if math.random() <= 0.5 then targets[i .. "size_variation"] = 0 else targets[i .. "size_variation"] = math.random(0, 40) end
    if math.random() <= 0.5 then targets[i .. "density_mod_amt"] = 0 else targets[i .. "density_mod_amt"] = math.random(0, 75) end
    if math.random() <= 0.5 then targets[i .. "subharmonics_1"] = 0 else targets[i .. "subharmonics_1"] = random_float(0, 0.4) end
    if math.random() <= 0.5 then targets[i .. "subharmonics_2"] = 0 else targets[i .. "subharmonics_2"] = random_float(0, 0.4) end
    if math.random() <= 0.5 then targets[i .. "subharmonics_3"] = 0 else targets[i .. "subharmonics_3"] = random_float(0, 0.4) end
    if math.random() <= 0.5 then targets[i .. "overtones_1"] = 0 else targets[i .. "overtones_1"] = random_float(0, 0.5) end
    if math.random() <= 0.5 then targets[i .. "overtones_2"] = 0 else targets[i .. "overtones_2"] = random_float(0, 0.5) end
    if math.random() <= 0.6 then targets["eq_low_gain_" .. i] = 0 else targets["eq_low_gain_" .. i] = random_float(-0.3, 0.2) end
    if math.random() <= 0.4 then targets["eq_high_gain_" .. i] = 0 else targets["eq_high_gain_" .. i] = random_float(0.1, 0.4) end
    -- STEREO WIDTH
    if math.random() <= 0.75 then targets[i.."Width"] = 100 else targets[i.."Width"] = math.random(100, 200) end
    -- OCTAVE VARIATION
    if math.random() <= 0.5 then targets[i .. "pitch_random_plus"] = 0 end
    if math.random() <= 0.5 then targets[i .. "pitch_random_minus"] = 0 end

    for param, _ in pairs(targets) do
        active_interpolations[param] = true
    end
    start_interpolation(steps)
end

local function randomize_global_params()
  safe_metro_stop(randomize_metro)
    -- DELAY (global parameters)
    if math.random() <= 0.3 then targets["delay_h"] = 0 else targets["delay_h"] = math.random(30, 85) end
    if math.random() <= 0.6 then targets["delay_rate"] = random_float(0.2, 1) end
    if math.random() <= 0.6 then targets["delay_feedback"] = math.random(30, 85) end
    -- SHIMMER (global parameter)
    if math.random() <= 0.65 then targets["shimmer_mix"] = 0.0 else targets["shimmer_mix"] = math.random(0, 20) end
    -- TAPE (global parameters)
    if math.random() <= 0.6 then targets["sine_wet"] = 0 else targets["sine_wet"] = math.random(5, 10) end
    if math.random() <= 0.6 then targets["sine_drive"] = 0.75 else targets["sine_drive"] = random_float(0.5, 1) end
    if math.random() <= 0.75 then targets["chew_wet"] = 0 else targets["chew_wet"] = math.random(0, 20) end
    if math.random() <= 0.5 then targets["chew_depth"] = 0.3 else targets["chew_depth"] = random_float(0.2, 0.5) end
    if math.random() <= 0.5 then targets["chew_freq"] = 0.3 else targets["chew_freq"] = random_float(0.2, 0.7) end
    if math.random() <= 0.5 then targets["chew_variance"] = 0.4 else targets["chew_variance"] = random_float(0.2, 0.8) end
    if math.random() <= 0.75 then targets["wobble_wet"] = 0 else targets["wobble_wet"] = math.random(0, 17) end
    if math.random() <= 0.75 then targets["wobble_amp"] = 25 else targets["wobble_amp"] = math.random(15, 35) end
    if math.random() <= 0.75 then targets["wobble_rpm"] = 33 else targets["wobble_rpm"] = math.random(30, 90) end
    if math.random() <= 0.75 then targets["flutter_amp"] = 25 else targets["flutter_amp"] = math.random(15, 35) end
    if math.random() <= 0.75 then targets["flutter_freq"] = 6 else targets["flutter_freq"] = math.random(4, 8) end
    if math.random() <= 0.75 then targets["flutter_var"] = 2 else targets["flutter_var"] = math.random(1, 5) end
    -- LFO scale (global parameter)
    if math.random() <= 0.3 then params:set("global_lfo_freq_scale", 1) else params:set("global_lfo_freq_scale", random_float(0.2, 1.5)) end
end

local function randomize_params(steps, track_num)
    targets = {}
    active_interpolations = {}
    safe_metro_stop(randomize_metro)
    randomize_global_params()
    if track_num then
        randomize_voice_params(track_num)
    else
        randomize_voice_params(1)
        randomize_voice_params(2)
    end
    for param, _ in pairs(targets) do
        active_interpolations[param] = true
    end
    start_interpolation(steps)
end

return {
    randomize_params = randomize_params,
    randomize_fverb_params = randomize_fverb_params,
    randomize_voice_params = randomize_voice_params,
    randomize_tape_params = randomize_tape_params
}