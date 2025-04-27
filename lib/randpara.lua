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

local function randomize_jpverb_params(steps)
  if params:get("lock_reverb") == 2 then return end
  safe_metro_stop(randomize_metro)
  -- JPVERB
  if math.random() <= 0.6 then targets["t60"] = 3.5 else targets["t60"] = random_float(2, 5) end
  if math.random() <= 0.6 then targets["damp"] = 0 else targets["damp"] = random_float(0, 9) end
  if math.random() <= 0.3 then targets["rsize"] = 1 else targets["rsize"] = random_float(1, 3) end
  if math.random() <= 0.6 then targets["earlyDiff"] = 70.7 else targets["earlyDiff"] = random_float(70.7, 90) end
  if math.random() <= 0.6 then targets["modDepth"] = 10 else targets["modDepth"] = math.random(10, 90) end
  if math.random() <= 0.6 then targets["modFreq"] = 2 else targets["modFreq"] = random_float(1, 3) end
  if math.random() <= 0.6 then targets["low"] = 100 else targets["low"] = math.random(95, 100) end
  if math.random() <= 0.6 then targets["mid"] = 100 else targets["mid"] = math.random(90, 100) end
  if math.random() <= 0.6 then targets["high"] = 100 else targets["high"] = math.random(85, 100) end
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
    if math.random() <= 0.6 then targets[i .. "direction_mod"] = 0 else targets[i .. "direction_mod"] = math.random(0, 20) end
    if math.random() <= 0.5 then targets[i .. "size_variation"] = 0 else targets[i .. "size_variation"] = math.random(0, 40) end
    if math.random() <= 0.5 then targets[i .. "density_mod_amt"] = 0 else targets[i .. "density_mod_amt"] = math.random(0, 75) end
    if math.random() <= 0.5 then targets[i .. "subharmonics_1"] = 0 else targets[i .. "subharmonics_1"] = random_float(0, 0.4) end
    if math.random() <= 0.5 then targets[i .. "subharmonics_2"] = 0 else targets[i .. "subharmonics_2"] = random_float(0, 0.4) end
    if math.random() <= 0.5 then targets[i .. "subharmonics_3"] = 0 else targets[i .. "subharmonics_3"] = random_float(0, 0.4) end
    if math.random() <= 0.5 then targets[i .. "overtones_1"] = 0 else targets[i .. "overtones_1"] = random_float(0, 0.5) end
    if math.random() <= 0.5 then targets[i .. "overtones_2"] = 0 else targets[i .. "overtones_2"] = random_float(0, 0.5) end
    if math.random() <= 0.65 then targets["shimmer_mix"] = 0.0 else targets["shimmer_mix"] = math.random(0, 20) end
    if math.random() <= 0.5 then targets[i .. "pitch_random_plus"] = 0 end
    if math.random() <= 0.5 then targets[i .. "pitch_random_minus"] = 0 end

    for param, _ in pairs(targets) do
        active_interpolations[param] = true
    end
    start_interpolation(steps)
end

local function randomize_eq_params(i)
  if params:get("lock_eq") == 2 then return end
  safe_metro_stop(randomize_metro)
    -- EQ
    if math.random() <= 0.6 then targets["eq_low_gain_" .. i] = 0 else targets["eq_low_gain_" .. i] = random_float(-0.3, 0.2) end
    if math.random() <= 0.4 then targets["eq_high_gain_" .. i] = 0 else targets["eq_high_gain_" .. i] = random_float(0.1, 0.4) end

    for param, _ in pairs(targets) do
        active_interpolations[param] = true
    end
    start_interpolation(steps)
end

local function randomize_delay_params()
  if params:get("lock_delay") == 2 then return end
  safe_metro_stop(randomize_metro)
    -- DELAY
    if math.random() <= 0.3 then targets["delay_h"] = 0 else targets["delay_h"] = math.random(30, 80) end
    if math.random() <= 0.6 then targets["delay_rate"] = random_float(0.2, 1) end
    if math.random() <= 0.6 then targets["delay_feedback"] = math.random(30, 75) end

    for param, _ in pairs(targets) do
        active_interpolations[param] = true
    end
    start_interpolation(steps)
end

local function randomize_tape_params()
  if params:get("lock_tape") == 2 then return end
  safe_metro_stop(randomize_metro)
    -- TAPE
    if math.random() <= 0.6 then targets["sine_wet"] = 0 else targets["sine_wet"] = math.random(5, 10) end
    if math.random() <= 0.6 then targets["sine_drive"] = 0.75 else targets["sine_drive"] = random_float(0.5, 1) end
    if math.random() <= 0.75 then targets["chew_wet"] = 0 else targets["chew_wet"] = math.random(0, 20) end
    if math.random() <= 0.5 then targets["chew_depth"] = 0.3 else targets["chew_depth"] = random_float(0.2, 0.5) end
    if math.random() <= 0.5 then targets["chew_freq"] = 0.3 else targets["chew_freq"] = random_float(0.2, 0.7) end
    if math.random() <= 0.5 then targets["chew_variance"] = 0.4 else targets["chew_variance"] = random_float(0.2, 0.8) end
    if math.random() <= 0.75 then targets["wobble_wet"] = 0 else targets["wobble_wet"] = math.random(0, 25) end
    if math.random() <= 0.75 then targets["wobble_amp"] = 25 else targets["wobble_amp"] = math.random(10, 35) end
    if math.random() <= 0.75 then targets["wobble_rpm"] = 33 else targets["wobble_rpm"] = math.random(30, 90) end
    if math.random() <= 0.75 then targets["flutter_amp"] = 25 else targets["flutter_amp"] = math.random(10, 50) end
    if math.random() <= 0.75 then targets["flutter_freq"] = 6 else targets["flutter_freq"] = math.random(4, 8) end
    if math.random() <= 0.75 then targets["flutter_var"] = 2 else targets["flutter_var"] = math.random(1, 5) end
   
    for param, _ in pairs(targets) do
        active_interpolations[param] = true
    end
    start_interpolation(steps)
end

local function randomize_stereo_params(i)
  safe_metro_stop(randomize_metro)
    --STEREO WIDTH
    if math.random() <= 0.65 then targets[i.."Width"] = 100 else targets[i.."Width"] = math.random(100, 200) end    
    
    for param, _ in pairs(targets) do
        active_interpolations[param] = true
    end
    start_interpolation(steps)
end


local function randomize_params(steps, track_num)
    targets = {}
    active_interpolations = {}
    randomize_tape_params()
    randomize_delay_params()
    randomize_jpverb_params()
    randomize_stereo_params(track_num)
    randomize_eq_params(track_num)
    randomize_granular_params(track_num)
end


return {
    randomize_params = randomize_params,
    randomize_jpverb_params = randomize_jpverb_params,
    randomize_granular_params = randomize_granular_params,
    randomize_delay_params = randomize_delay_params,
    randomize_voice_params = randomize_voice_params,
    randomize_tape_params = randomize_tape_params
}