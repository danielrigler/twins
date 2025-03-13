local function random_float(l, h)
    return l + math.random() * (h - l)
end

local function interpolate(start_val, end_val, factor)
    -- Exponential interpolation to avoid slowdown near the end
    local epsilon = 0.01  -- Small value to ensure we reach the target
    if math.abs(start_val - end_val) < epsilon then
        return end_val  -- If we're close enough, just return the target value
    else
        -- Exponential interpolation
        return start_val + (end_val - start_val) * (1 - math.exp(-3 * factor))
    end
end

local randomize_metro = metro.init() -- Initialize the metro here
local targets = {} -- Stores target values for interpolation
local active_interpolations = {} -- Tracks which parameters are being interpolated
local interpolation_speed = 1 / 30 -- Metro time (30 FPS, same as in twins.lua)

-- Function to stop interpolation for a specific parameter
local function stop_interpolation_for_param(param)
    targets[param] = nil -- Remove the parameter from the interpolation targets
    active_interpolations[param] = nil -- Mark the parameter as no longer being interpolated
end

-- Function to handle manual parameter adjustments
local function manual_adjust(param, value)
    stop_interpolation_for_param(param) -- Stop interpolation for this parameter
    params:set(param, value) -- Set the parameter to the new value
end

local function randomize_params(steps, i)
    -- Clear previous targets and stop any ongoing interpolation
    targets = {}
    active_interpolations = {}
    if randomize_metro then
        randomize_metro:stop() -- Stop the metro if it's running
    end

    -- Set target values for each parameter
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
    if math.random() <= 0.5 then targets["sine_drive"] = 1 else targets["sine_drive"] = random_float(0.5, 1.75) end
    if math.random() <= 0.75 then targets["chew_wet"] = 0 else targets["chew_wet"] = math.random(0, 25) end
    if math.random() <= 0.5 then targets["chew_depth"] = 0.4 else targets["chew_depth"] = random_float(0.2, 0.5) end
    if math.random() <= 0.5 then targets["chew_freq"] = 0.4 else targets["chew_freq"] = random_float(0.2, 0.5) end
    if math.random() <= 0.5 then targets["chew_variance"] = 0.5 else targets["chew_variance"] = random_float(0.4, 0.8) end

    -- VOICE-SPECIFIC PARAMETERS
    if i then
        -- Only randomize parameters for the specified voice (i)
        if math.random() <= 0.4 then targets[i .. "direction_mod"] = 0 else targets[i .. "direction_mod"] = math.random(0, 30) end
        if math.random() <= 0.8 then targets[i .. "granular_gain"] = 100 else targets[i .. "granular_gain"] = math.random(80, 100) end
        if math.random() <= 0.4 then targets[i .. "size_variation"] = 0 else targets[i .. "size_variation"] = math.random(0, 30) end

        -- EXTRAS (voice-specific parameters)
        if math.random() <= 0.7 then targets[i .. "density_mod_amt"] = 0 else targets[i .. "density_mod_amt"] = math.random(0, 40) end
        if math.random() <= 0.7 then targets[i .. "subharmonics_1"] = 0 else targets[i .. "subharmonics_1"] = random_float(0, 0.4) end
        if math.random() <= 0.7 then targets[i .. "subharmonics_2"] = 0 else targets[i .. "subharmonics_2"] = random_float(0, 0.4) end
        if math.random() <= 0.7 then targets[i .. "overtones_1"] = 0 else targets[i .. "overtones_1"] = random_float(0, 0.4) end
        if math.random() <= 0.7 then targets[i .. "overtones_2"] = 0 else targets[i .. "overtones_2"] = random_float(0, 0.4) end
    else
        -- Randomize parameters for both voices if no specific voice is provided
        if math.random() <= 0.4 then targets["1direction_mod"] = 0 else targets["1direction_mod"] = math.random(0, 30) end
        if math.random() <= 0.4 then targets["2direction_mod"] = 0 else targets["2direction_mod"] = math.random(0, 30) end
        if math.random() <= 0.8 then targets["1granular_gain"] = 100 else targets["1granular_gain"] = math.random(85, 100) end
        if math.random() <= 0.8 then targets["2granular_gain"] = 100 else targets["2granular_gain"] = math.random(85, 100) end
        if math.random() <= 0.4 then targets["1size_variation"] = 0 else targets["1size_variation"] = math.random(0, 30) end
        if math.random() <= 0.4 then targets["2size_variation"] = 0 else targets["2size_variation"] = math.random(0, 30) end

        -- EXTRAS (voice-specific parameters for both voices)
        if math.random() <= 0.7 then targets["1density_mod_amt"] = 0 else targets["1density_mod_amt"] = math.random(0, 40) end
        if math.random() <= 0.7 then targets["2density_mod_amt"] = 0 else targets["2density_mod_amt"] = math.random(0, 40) end
        if math.random() <= 0.7 then targets["1subharmonics_1"] = 0 else targets["1subharmonics_1"] = random_float(0, 0.4) end
        if math.random() <= 0.7 then targets["2subharmonics_1"] = 0 else targets["2subharmonics_1"] = random_float(0, 0.4) end
        if math.random() <= 0.7 then targets["1subharmonics_2"] = 0 else targets["1subharmonics_2"] = random_float(0, 0.4) end
        if math.random() <= 0.7 then targets["2subharmonics_2"] = 0 else targets["2subharmonics_2"] = random_float(0, 0.4) end
        if math.random() <= 0.7 then targets["1overtones_1"] = 0 else targets["1overtones_1"] = random_float(0, 0.4) end
        if math.random() <= 0.7 then targets["2overtones_1"] = 0 else targets["2overtones_1"] = random_float(0, 0.4) end
        if math.random() <= 0.7 then targets["1overtones_2"] = 0 else targets["1overtones_2"] = random_float(0, 0.4) end
        if math.random() <= 0.7 then targets["2overtones_2"] = 0 else targets["2overtones_2"] = random_float(0, 0.4) end
    end

    -- Mark all parameters as being interpolated
    for param, _ in pairs(targets) do
        active_interpolations[param] = true
    end

    -- Start the interpolation metro
    randomize_metro.time = interpolation_speed
    randomize_metro.count = -1
    randomize_metro.event = function(count)
        local factor = count / steps  -- Use the actual steps parameter here
        local all_done = true

        for param, target in pairs(targets) do
            if active_interpolations[param] then -- Only interpolate if the parameter is still marked as active
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
    manual_adjust = manual_adjust, -- Expose the manual_adjust function for external use
    stop_interpolation_for_param = stop_interpolation_for_param -- Expose this function for external use
}