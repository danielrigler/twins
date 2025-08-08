local symmetry_enabled = false

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

                -- Handle symmetric parameter if symmetry is enabled
                if symmetry_enabled then
                    local mirrored_param = param:gsub("^(%d)(.*)", function(num, rest)
                        return (tonumber(num) % 2) + 1 .. rest
                    end)
                    if params.lookup[mirrored_param] then
                        local mirrored_target = targets[mirrored_param] or target
                        local mirrored_current = params:get(mirrored_param)
                        local mirrored_new = interpolate(mirrored_current, mirrored_target, factor)
                        params:set(mirrored_param, mirrored_new)
                        
                        if math.abs(mirrored_new - mirrored_target) > 0.00 then
                            all_done = false
                        end
                    end
                end

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

local function randomize_jpverb_params(steps)
  if params:get("lock_reverb") == 2 then return end
  safe_metro_stop(randomize_metro)
  -- JPVERB
  if math.random() <= 0.5 then targets["t60"] = 4 else targets["t60"] = random_float(2, 6) end
  if math.random() <= 0.6 then targets["damp"] = 0 else targets["damp"] = random_float(0, 20) end
  if math.random() <= 0.3 then targets["rsize"] = 1 else targets["rsize"] = random_float(1, 3) end
  if math.random() <= 0.6 then targets["earlyDiff"] = 70.7 else targets["earlyDiff"] = random_float(70.7, 90) end
  if math.random() <= 0.6 then targets["modDepth"] = 10 else targets["modDepth"] = math.random(10, 90) end
  if math.random() <= 0.6 then targets["modFreq"] = 2 else targets["modFreq"] = random_float(1, 3) end
  if math.random() <= 0.6 then targets["low"] = 1 else targets["low"] = random_float(0.9, 1) end
  if math.random() <= 0.6 then targets["mid"] = 1 else targets["mid"] = random_float(0.8, 1) end
  if math.random() <= 0.6 then targets["high"] = 1 else targets["high"] = random_float(0.6, 1) end
  if math.random() <= 0.6 then targets["lowcut"] = 500 else targets["lowcut"] = math.random(250, 750) end
  if math.random() <= 0.6 then targets["highcut"] = 2000 else targets["highcut"] = math.random(1500, 3500) end

  for param, _ in pairs(targets) do
      active_interpolations[param] = true
  end
  start_interpolation(steps)
end

local function randomize_granular_params(i)
  if params:get("lock_granular") == 2 then return end
  safe_metro_stop(randomize_metro)
    -- GRANULAR
    if math.random() <= 0.5 then targets[i .. "direction_mod"] = 0 else targets[i .. "direction_mod"] = math.random(0, 20) end
    if math.random() <= 0.5 then targets[i .. "size_variation"] = 0 else targets[i .. "size_variation"] = math.random(0, 40) end
    if math.random() <= 0.5 then targets[i .. "density_mod_amt"] = 0 else targets[i .. "density_mod_amt"] = math.random(0, 75) end
    if math.random() <= 0.5 then targets[i .. "subharmonics_1"] = 0 else targets[i .. "subharmonics_1"] = random_float(0, 0.6) end
    if math.random() <= 0.5 then targets[i .. "subharmonics_2"] = 0 else targets[i .. "subharmonics_2"] = random_float(0, 0.6) end
    if math.random() <= 0.5 then targets[i .. "subharmonics_3"] = 0 else targets[i .. "subharmonics_3"] = random_float(0, 0.6) end
    if math.random() <= 0.5 then targets[i .. "overtones_1"] = 0 else targets[i .. "overtones_1"] = random_float(0, 0.6) end
    if math.random() <= 0.5 then targets[i .. "overtones_2"] = 0 else targets[i .. "overtones_2"] = random_float(0, 0.6) end
    if math.random() <= 0.8 then targets[i .. "pitch_random_plus"] = 0 else targets[i .. "pitch_random_plus"] = math.random(0, 25) end
    if math.random() <= 0.8 then targets[i .. "pitch_random_minus"] = 0 else targets[i .. "pitch_random_minus"] = math.random(0, 25) end

    for param, _ in pairs(targets) do
        active_interpolations[param] = true
    end
    start_interpolation(steps)
end

local function randomize_shimmer_params()
  if params:get("lock_shimmer") == 2 then return end
  safe_metro_stop(randomize_metro)
    -- SHIMMER
    if math.random() <= 0.9 then params:set("o2", 1)  else params:set("o2", 2) end
    if math.random() <= 0.5 then targets["pitchv"] = 0.0 else targets["pitchv"] = math.random(0, 2) end
    if math.random() <= 0.5 then targets["lowpass"] = 13000 else targets["lowpass"] = math.random(6000, 15000) end
    if math.random() <= 0.5 then targets["hipass"] = 1300 else targets["hipass"] = math.random(400, 1500) end
    if math.random() <= 0.7 then targets["fb"] = 15 else targets["fb"] = math.random(10, 25) end
    if math.random() <= 0.7 then targets["fbDelay"] = 0.2 else targets["fbDelay"] = random_float(0.15, 0.35) end
  
    for param, _ in pairs(targets) do
        active_interpolations[param] = true
    end
    start_interpolation(steps)
end

local function randomize_eq_params(i)
  if params:get("lock_eq") == 2 then return end
  safe_metro_stop(randomize_metro)
    -- EQ
    if math.random() <= 0.4 then targets[i.."eq_low_gain"] = 0 else targets[i.."eq_low_gain"] = random_float(-0.35, 0.25) end
    if math.random() <= 0.4 then targets[i.."eq_high_gain"] = 0.25 else targets[i.."eq_high_gain"] = random_float(-0.2, 0.5) end

    for param, _ in pairs(targets) do
        active_interpolations[param] = true
    end
    start_interpolation(steps)
end

local function randomize_delay_params()
  if params:get("lock_delay") == 2 then return end
  safe_metro_stop(randomize_metro)
    -- DELAY
    if math.random() <= 0.5 then targets["delay_mix"] = 0 else targets["delay_mix"] = math.random(0, 90) end
    if math.random() <= 0.3 then params:set("delay_time", 0.5) else params:set("delay_time", random_float(0.15, 1)) end
    if math.random() <= 0.5 then targets["delay_feedback"] = math.random(20, 80) end
    if math.random() <= 0.6 then targets["stereo"] = 27 else targets["stereo"] = math.random(0, 70) end
    targets["delay_lowpass"] = math.random(1000, 20000)
    targets["delay_highpass"] = math.random(20, 300)
    if math.random() <= 0.7 then targets["wiggle_depth"] = 0 else targets["wiggle_depth"] = math.random(0, 10) end
    if math.random() <= 0.6 then targets["wiggle_rate"] = 2 else targets["wiggle_rate"] = random_float(0.5, 4) end

    for param, _ in pairs(targets) do
        active_interpolations[param] = true
    end
    start_interpolation(steps)
end

local function randomize_tape_params()
  if params:get("lock_tape") == 2 then return end
  safe_metro_stop(randomize_metro)
    -- TAPE
    if math.random() <= 0.4 then targets["wobble_amp"] = 10 else targets["wobble_amp"] = math.random(1, 15) end
    if math.random() <= 0.4 then targets["wobble_rpm"] = 33 else targets["wobble_rpm"] = math.random(30, 70) end
    if math.random() <= 0.4 then targets["flutter_amp"] = 15 else targets["flutter_amp"] = math.random(1, 30) end
    if math.random() <= 0.4 then targets["flutter_freq"] = 6 else targets["flutter_freq"] = math.random(2, 10) end
    if math.random() <= 0.4 then targets["flutter_var"] = 2 else targets["flutter_var"] = math.random(1, 5) end
    
    for param, _ in pairs(targets) do
        active_interpolations[param] = true
    end
    start_interpolation(steps)
end

local function randomize_params(steps, track_num)
    targets = {}
    active_interpolations = {}
    symmetry_enabled = params:get("symmetry") == 1
    
    -- Store which track we're randomizing first
    local primary_track = track_num
    
    -- For each randomization function, if symmetry is enabled, we'll set targets for both tracks
    if symmetry_enabled then
        -- For each parameter group, we'll randomize both tracks with mirrored values
        randomize_tape_params()
        randomize_delay_params()
        randomize_jpverb_params()
        randomize_shimmer_params()
        randomize_eq_params(1)
        randomize_eq_params(2)
        randomize_granular_params(1)
        randomize_granular_params(2)
    else
        -- Original behavior when symmetry is off
        randomize_tape_params()
        randomize_delay_params()
        randomize_jpverb_params()
        randomize_shimmer_params()
        randomize_eq_params(track_num)
        randomize_granular_params(track_num)
    end
    
    -- If symmetry is enabled, mirror the targets from the primary track to the other track
    if symmetry_enabled then
        local new_targets = {}
        for param, target in pairs(targets) do
            -- Only process parameters from the primary track
            if param:sub(1,1) == tostring(primary_track) then
                local mirrored_param = param:gsub("^(%d)(.*)", function(num, rest)
                    return (tonumber(num) % 2) + 1 .. rest
                end)
                if params.lookup[mirrored_param] then
                    new_targets[mirrored_param] = target
                    active_interpolations[mirrored_param] = true
                end
            end
        end
        -- Merge the mirrored targets with the original targets
        for param, target in pairs(new_targets) do
            targets[param] = target
        end
    end
    
    start_interpolation(steps)
end

return {
    randomize_params = randomize_params,
    randomize_jpverb_params = randomize_jpverb_params,
    randomize_granular_params = randomize_granular_params,
    randomize_delay_params = randomize_delay_params,
    randomize_shimmer_params = randomize_shimmer_params,
    randomize_tape_params = randomize_tape_params,
    symmetry_enabled = symmetry_enabled
}