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

local function stop_interpolation_for_param(param)
    targets[param] = nil
    active_interpolations[param] = nil
end

local function manual_adjust(param, value)
    -- Clear any active interpolation for this parameter
    stop_interpolation_for_param(param)
    params:set(param, value)
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
                    -- Remove from active interpolations when target is reached
                    active_interpolations[param] = nil
                end
            end
        end

        if all_done then
            safe_metro_stop(randomize_metro)
            -- Clear all targets when done
            targets = {}
        end
    end
    randomize_metro:start()
end

local function randomize_fverb_params(steps)
  safe_metro_stop(randomize_metro)
    -- FVERB parameters
    targets["reverb_input_amount"] = math.random(50, 100)
    targets["reverb_predelay"] = math.random(0, 250)
    targets["reverb_lowpass_cutoff"] = math.random(4000, 9000)
    targets["reverb_highpass_cutoff"] = math.random(20, 300)
    targets["reverb_diffusion_1"] = math.random(70, 90)
    targets["reverb_diffusion_2"] = math.random(70, 90)
    targets["reverb_tail_density"] = math.random(70, 90)
    targets["reverb_decay"] = math.random(65, 90)
    targets["reverb_damping"] = math.random(1000, 4500)
    targets["reverb_modulator_frequency"] = random_float(0.1, 2.5)
    targets["reverb_modulator_depth"] = math.random(30, 100)

    for param, _ in pairs(targets) do
        active_interpolations[param] = true
    end
    start_interpolation(steps)
end

local function randomize_greyhole_params(steps)
  safe_metro_stop(randomize_metro)
    -- GREYHOLE parameters
    targets["time"] = random_float(3, 8)
    targets["size"] = random_float(3, 5)
    targets["mod_depth"] = random_float(0.3, 1)
    targets["mod_freq"] = random_float(0.1, 2.5)
    targets["diff"] = random_float(0.10, 0.95)
    targets["feedback"] = random_float(0.1, 0.7)
    targets["damp"] = random_float(0.05, 0.7)

    for param, _ in pairs(targets) do
        active_interpolations[param] = true
    end
    start_interpolation(steps)
end

local function randomize_voice_params(i)
  safe_metro_stop(randomize_metro)
    -- VOICE-SPECIFIC PARAMETERS
    if math.random() <= 0.9 then targets[i .. "granular_gain"] = 100 else targets[i .. "granular_gain"] = math.random(75, 100) end
    if math.random() <= 0.4 then targets[i .. "direction_mod"] = 0 else targets[i .. "direction_mod"] = math.random(0, 35) end
    if math.random() <= 0.5 then targets[i .. "size_variation"] = 0 else targets[i .. "size_variation"] = math.random(0, 40) end
    if math.random() <= 0.6 then targets[i .. "density_mod_amt"] = 0 else targets[i .. "density_mod_amt"] = math.random(0, 45) end
    if math.random() <= 0.5 then targets[i .. "subharmonics_1"] = 0 else targets[i .. "subharmonics_1"] = random_float(0, 0.4) end
    if math.random() <= 0.4 then targets[i .. "subharmonics_2"] = 0 else targets[i .. "subharmonics_2"] = random_float(0, 0.4) end
    if math.random() <= 0.4 then targets[i .. "subharmonics_3"] = 0 else targets[i .. "subharmonics_3"] = random_float(0, 0.4) end
    if math.random() <= 0.5 then targets[i .. "overtones_1"] = 0 else targets[i .. "overtones_1"] = random_float(0, 0.5) end
    if math.random() <= 0.4 then targets[i .. "overtones_2"] = 0 else targets[i .. "overtones_2"] = random_float(0, 0.5) end
    if math.random() <= 0.6 then targets["eq_low_gain_" .. i] = 0 else targets["eq_low_gain_" .. i] = random_float(0, 0.3) end
    if math.random() <= 0.4 then targets["eq_high_gain_" .. i] = 0 else targets["eq_high_gain_" .. i] = random_float(0, 0.5) end
    if math.random() <= 0.8 then targets[i .. "pitch_random_plus"] = 0 else targets[i .. "pitch_random_plus"] = math.random(0, 100) end
    if math.random() <= 0.8 then targets[i .. "pitch_random_minus"] = 0 else targets[i .. "pitch_random_minus"] = math.random(0, 100) end
    -- VOICE SPECIFIC TAPE
    if math.random() <= 0.9 then targets[i .. "chew_wet"] = 0 else targets[i .. "chew_wet"] = math.random(0, 85) end      

    for param, _ in pairs(targets) do
        active_interpolations[param] = true
    end
    start_interpolation(steps)
end

local function randomize_global_params()
  safe_metro_stop(randomize_metro)
    -- DELAY (global parameters)
    if math.random() <= 0.3 then targets["delay_h"] = 0 else targets["delay_h"] = math.random(25, 80) end
    if math.random() <= 0.25 then targets["delay_rate"] = random_float(0.2, 1) end
    targets["delay_feedback"] = math.random(30, 85)
    -- TAPE
    if math.random() <= 0.6 then targets["sine_wet"] = 0 else targets["sine_wet"] = math.random(1, 10) end
    if math.random() <= 0.6 then targets["sine_drive"] = 0.75 else targets["sine_drive"] = random_float(0.5, 1.25) end
    if math.random() <= 0.5 then targets["chew_depth"] = 0.3 else targets["chew_depth"] = random_float(0.2, 0.75) end
    if math.random() <= 0.5 then targets["chew_freq"] = 0.4 else targets["chew_freq"] = random_float(0.2, 0.8) end
    if math.random() <= 0.5 then targets["chew_variance"] = 0.5 else targets["chew_variance"] = random_float(0.2, 0.8) end
    -- LFO scale (global parameter)
    if math.random() <= 0.5 then params:set("global_lfo_freq_scale", 1) else params:set("global_lfo_freq_scale", random_float(0.2, 2)) end
end

local function randomize_params(steps, track_num)
    -- Clear previous state
    targets = {}
    active_interpolations = {}
    safe_metro_stop(randomize_metro)

    -- Set up new randomizations
    randomize_global_params()
    randomize_fverb_params(steps)
    randomize_greyhole_params(steps)
    
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
    manual_adjust = manual_adjust,
    stop_interpolation_for_param = stop_interpolation_for_param,
    randomize_fverb_params = randomize_fverb_params,
    randomize_voice_params = randomize_voice_params,
    randomize_greyhole_params = randomize_greyhole_params
}