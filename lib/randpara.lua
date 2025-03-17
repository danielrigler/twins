local function random_float(l, h)
    return l + math.random() * (h - l)
end

local function interpolate(start_val, end_val, factor)
    local epsilon = 0.01
    if math.abs(start_val - end_val) < epsilon then
        return end_val
    else
        return start_val + (end_val - start_val) * (1 - math.exp(-3 * factor))
    end
end

local randomize_metro = metro.init()
local targets = {}
local active_interpolations = {}
local interpolation_speed = 1 / 30

local function stop_interpolation_for_param(param)
    targets[param] = nil
    active_interpolations[param] = nil
end

-- Function to handle manual parameter adjustments
local function manual_adjust(param, value)
    stop_interpolation_for_param(param)
    params:set(param, value)
end

local function randomize_params(steps, i)
    -- Clear previous targets and stop any ongoing interpolation
    targets = {}
    active_interpolations = {}
    if randomize_metro then
        randomize_metro:stop()
    end

    -- DELAY (global parameters)
    if math.random() <= 0.3 then targets["delay_h"] = 0 else targets["delay_h"] = math.random(15, 85) end
    targets["delay_rate"] = random_float(0.2, 1)
    targets["delay_feedback"] = math.random(30, 80)

    -- GREYHOLE (global parameters)
    targets["greyhole_mix"] = random_float(0, 0.7)
    targets["time"] = random_float(2, 8)
    targets["size"] = random_float(2, 5)
    targets["mod_depth"] = random_float(0.2, 1)
    targets["mod_freq"] = random_float(0.1, 2)
    targets["diff"] = random_float(0.30, 0.95)
    targets["feedback"] = random_float(0.1, 0.6)
    targets["damp"] = random_float(0.05, 0.4)

    -- FVERB (global parameters)
    targets["reverb_mix"] = math.random(0, 40)
    targets["reverb_predelay"] = math.random(0, 150)
    targets["reverb_lowpass_cutoff"] = math.random(2000, 11000)
    targets["reverb_highpass_cutoff"] = math.random(20, 300)
    targets["reverb_diffusion_1"] = math.random(50, 95)
    targets["reverb_diffusion_2"] = math.random(50, 95)
    targets["reverb_tail_density"] = math.random(40, 95)
    targets["reverb_decay"] = math.random(40, 90)
    targets["reverb_damping"] = math.random(2500, 8500)
    targets["reverb_modulator_frequency"] = random_float(0.1, 2.5)
    targets["reverb_modulator_depth"] = math.random(20, 100)

    -- TAPE (global parameters)
    if math.random() <= 0.5 then targets["sine_wet"] = 0 else targets["sine_wet"] = math.random(1, 20) end
    if math.random() <= 0.5 then targets["sine_drive"] = 0.75 else targets["sine_drive"] = random_float(0.5, 1.8) end
    if math.random() <= 0.75 then targets["chew_wet"] = 0 else targets["chew_wet"] = math.random(0, 30) end
    if math.random() <= 0.5 then targets["chew_depth"] = 0.3 else targets["chew_depth"] = random_float(0.2, 0.5) end
    if math.random() <= 0.5 then targets["chew_freq"] = 0.3 else targets["chew_freq"] = random_float(0.2, 0.5) end
    if math.random() <= 0.5 then targets["chew_variance"] = 0.5 else targets["chew_variance"] = random_float(0.4, 0.8) end

    -- VOICE-SPECIFIC PARAMETERS
    if i then
        if math.random() <= 0.4 then targets[i .. "direction_mod"] = 0 else targets[i .. "direction_mod"] = math.random(0, 35) end
        if math.random() <= 0.9 then targets[i .. "granular_gain"] = 100 else targets[i .. "granular_gain"] = math.random(80, 100) end
        if math.random() <= 0.4 then targets[i .. "size_variation"] = 0 else targets[i .. "size_variation"] = math.random(0, 35) end
        if math.random() <= 0.7 then targets[i .. "density_mod_amt"] = 0 else targets[i .. "density_mod_amt"] = math.random(0, 45) end
        if math.random() <= 0.7 then targets[i .. "subharmonics_1"] = 0 else targets[i .. "subharmonics_1"] = random_float(0, 0.4) end
        if math.random() <= 0.7 then targets[i .. "subharmonics_2"] = 0 else targets[i .. "subharmonics_2"] = random_float(0, 0.4) end
        if math.random() <= 0.7 then targets[i .. "overtones_1"] = 0 else targets[i .. "overtones_1"] = random_float(0, 0.4) end
        if math.random() <= 0.7 then targets[i .. "overtones_2"] = 0 else targets[i .. "overtones_2"] = random_float(0, 0.4) end
        if math.random() <= 0.6 then targets[i .. "shimmer"] = 0 else targets[i .. "shimmer"] = math.random(10, 35) end
        if math.random() <= 0.6 then targets[i .. "shimmer"] = 0 else targets[i .. "shimmer"] = math.random(10, 35) end
        if math.random() <= 0.9 then targets[i .. "shimmerpitchdev"] = 0 else targets[i .. "shimmerpitchdev"] = math.random(1, 5) end
        if math.random() <= 0.9 then targets[i .. "shimmerpitchdev"] = 0 else targets[i .. "shimmerpitchdev"] = math.random(1, 5) end
        if math.random() <= 0.5 then targets["eq_low_gain_" .. i] = 0 else targets["eq_low_gain_" .. i] = random_float(0, 0.1) end
        if math.random() <= 0.5 then targets["eq_high_gain_" .. i] = 0 else targets["eq_high_gain_" .. i] = random_float(-0.1, 0.6) end
        else 
          for i=1,2 do
            if math.random() <= 0.4 then targets[i .. "direction_mod"] = 0 else targets[i .. "direction_mod"] = math.random(0, 35) end
            if math.random() <= 0.9 then targets[i .. "granular_gain"] = 100 else targets[i .. "granular_gain"] = math.random(80, 100) end
            if math.random() <= 0.4 then targets[i .. "size_variation"] = 0 else targets[i .. "size_variation"] = math.random(0, 35) end
            if math.random() <= 0.7 then targets[i .. "density_mod_amt"] = 0 else targets[i .. "density_mod_amt"] = math.random(0, 45) end
            if math.random() <= 0.7 then targets[i .. "subharmonics_1"] = 0 else targets[i .. "subharmonics_1"] = random_float(0, 0.4) end
            if math.random() <= 0.7 then targets[i .. "subharmonics_2"] = 0 else targets[i .. "subharmonics_2"] = random_float(0, 0.4) end
            if math.random() <= 0.7 then targets[i .. "overtones_1"] = 0 else targets[i .. "overtones_1"] = random_float(0, 0.4) end
            if math.random() <= 0.7 then targets[i .. "overtones_2"] = 0 else targets[i .. "overtones_2"] = random_float(0, 0.4) end
            if math.random() <= 0.6 then targets[i .. "shimmer"] = 0 else targets[i .. "shimmer"] = math.random(20, 50) end
            if math.random() <= 0.6 then targets[i .. "shimmer"] = 0 else targets[i .. "shimmer"] = math.random(20, 50) end
            if math.random() <= 0.9 then targets[i .. "shimmerpitchdev"] = 0 else targets[i .. "shimmerpitchdev"] = math.random(1, 15) end
            if math.random() <= 0.9 then targets[i .. "shimmerpitchdev"] = 0 else targets[i .. "shimmerpitchdev"] = math.random(1, 15) end  
            if math.random() <= 0.5 then targets["eq_low_gain_" .. i] = 0 else targets["eq_low_gain_" .. i] = random_float(0, 0.1) end
            if math.random() <= 0.5 then targets["eq_high_gain_" .. i] = 0 else targets["eq_high_gain_" .. i] = random_float(-0.1, 0.6) end
          end
    end
    
    for param, _ in pairs(targets) do
        active_interpolations[param] = true
    end

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

                if math.abs(new_value - target) > 0.01 then
                    all_done = false
                end
            end
        end

        if all_done then
            randomize_metro:stop()
        end
    end
    randomize_metro:start()
end

return {
    randomize_params = randomize_params,
    manual_adjust = manual_adjust,
    stop_interpolation_for_param = stop_interpolation_for_param
}