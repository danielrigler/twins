local number_of_outputs = 16
local tau = math.pi * 2

local options = {
  lfotypes = { "sine", "random", "square" }
}

local lfo = {}
local assigned_params = {}

local function is_locked(target)
  local track, param = string.match(target, "(%d)(%a+)")
  local lockable_params = { "jitter", "size", "density", "spread", "pitch", "pan", "seek" }
  
  if table.find(lockable_params, param) then
    return params:get(track .. "lock_" .. param) == 2
  end
  
  return false
end

for i = 1, number_of_outputs do
  lfo[i] = { 
    freq = 0.05, 
    base_freq = 0.05, 
    phase = 0,  -- Track phase separately (0 to 1)
    waveform = options.lfotypes[1], 
    slope = 0, 
    depth = 50, 
    offset = 0,
    prev = 0,  -- Initialize prev for random waveform
    prev_polarity = 1  -- Initialize for sample & hold
  }
end

local function make_sine(n)
  return math.sin(((tau / 100) * lfo[n].counter) - (tau / (lfo[n].freq / 1000)))
end

local function make_square(n)
  return make_sine(n) >= 0 and 1 or -1
end

local function make_sh(n)
  local polarity = make_square(n)
  if lfo[n].prev_polarity ~= polarity then
    lfo[n].prev_polarity = polarity
    lfo[n].prev = math.random() * (math.random(0, 1) == 0 and 1 or -1)
  end
  return lfo[n].prev
end

table.find = function(tbl, value)
  for i, v in ipairs(tbl) do if v == value then return i end end
  return nil
end

local function is_audio_loaded(track_num)
  local file_path = params:get(track_num .. "sample")
  return file_path and file_path ~= "" and file_path ~= "none" and file_path ~= "-"
end

function lfo.clearLFOs(track)
    local function clearSingleLFO(i)
        local target_index = params:get(i .. "lfo_target")
        local target_param = lfo.lfo_targets[target_index]
        if target_param and (not track or string.match(target_param, "^"..track)) and not is_locked(target_param) then
            assigned_params[target_param] = nil
            if params:get(i .. "lfo") == 2 then 
                params:set(i .. "lfo", 1) 
            end
            params:set(i .. "lfo_target", 1)
        end
    end

    local function setPans()
        local loaded1, loaded2 = is_audio_loaded(1), is_audio_loaded(2)
        if loaded1 and loaded2 then
            params:set("1pan", -15)
            params:set("2pan", 15)
        elseif loaded1 or loaded2 then
            params:set("1pan", 0)
            params:set("2pan", 0)
        end
    end

    if not track then
        -- Clear all non-locked params
        for target, _ in pairs(assigned_params) do
            if not is_locked(target) then
                assigned_params[target] = nil
            end
        end

        -- Clear all LFOs
        for i = 1, 16 do
            clearSingleLFO(i)
        end

        setPans()
    else
        -- Clear only LFOs targeting the specified track
        for i = 1, 16 do
            clearSingleLFO(i)
        end
    end
end

lfo.lfo_targets = {
  "none", "1pan", "2pan", "1seek", "2seek", "1jitter", "2jitter", 
  "1spread", "2spread", "1size", "2size", "1density", "2density", "1volume", "2volume", 
  "1pitch", "2pitch", "1cutoff", "2cutoff", "1hpf", "2hpf"
}

lfo.target_ranges = {
  ["1pan"] = { depth = { 25, 80 }, offset = { 0, 0 }, frequency = { 0.05, 0.6 }, waveform = { "sine" }, chance = 0.8 },
  ["2pan"] = { depth = { 25, 80 }, offset = { 0, 0 }, frequency = { 0.05, 0.6 }, waveform = { "sine" }, chance = 0.8 },
  ["1jitter"] = { depth = { 5, 100 }, offset = { -1, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5 },
  ["2jitter"] = { depth = { 5, 100 }, offset = { -1, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5 },
  ["1spread"] = { depth = { 5, 100 }, offset = { -1, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5 },
  ["2spread"] = { depth = { 5, 100 }, offset = { -1, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5},
  ["1size"] = { depth = { 5, 100 }, offset = { -1, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5 },
  ["2size"] = { depth = { 5, 100 }, offset = { -1, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5 },
  ["1density"] = { depth = { 5, 100 }, offset = { -1, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5 },
  ["2density"] = { depth = { 5, 100 }, offset = { -1, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5 },
  ["1volume"] = { depth = { 2, 3 }, offset = { -1, 1 }, frequency = { 0.1, 0.5 }, waveform = { "sine" }, chance = 1.0 },
  ["2volume"] = { depth = { 2, 3 }, offset = { -1, 1 }, frequency = { 0.1, 0.5 }, waveform = { "sine" }, chance = 1.0 },
  ["1seek"] = { depth = { 30, 60 }, offset = { 0, 0 }, frequency = { 0.05, 0.3 }, waveform = { "sine", "random" }, chance = 0.35 },
  ["2seek"] = { depth = { 30, 60 }, offset = { 0, 0 }, frequency = { 0.05, 0.3 }, waveform = { "sine", "random" }, chance = 0.35 }
}

function lfo.get_parameter_range(param_name)
  local param_ranges = {
    ["1pan"] = { -100, 100 }, ["2pan"] = { -100, 100 },
    ["1seek"] = { 0, 100 }, ["2seek"] = { 0, 100 },
    ["1jitter"] = { 1, 1999 }, ["2jitter"] = { 1, 1999 },
    ["1spread"] = { 0, 100 }, ["2spread"] = { 0, 100 },
    ["1size"] = { 0, 599 }, ["2size"] = { 0, 599 },
    ["1density"] = { 0, 16 }, ["2density"] = { 0, 16 },
    ["1volume"] = { -100, 100 }, ["2volume"] = { -100, 100 },
    ["1pitch"] = { -12, 12 }, ["2pitch"] = { -12, 12 },
    ["1cutoff"] = { 20, 20000 }, ["2cutoff"] = { 20, 20000 },
    ["1hpf"] = { 20, 20000 }, ["2hpf"] = { 20, 20000 }
  }
  return param_ranges[param_name][1], param_ranges[param_name][2]
end

function randomize_lfo(i, target)
    -- Early exit if target is already assigned or invalid
    if assigned_params[target] or not lfo.target_ranges[target] then 
        return 
    end

    -- Check if another LFO is already modulating this target
    for j = 1, number_of_outputs do
        if j ~= i then
            local target_param = lfo.lfo_targets[params:get(j .. "lfo_target")]
            if target_param == target and params:get(j .. "lfo") == 2 then
                return
            end
        end
    end

    -- Find target index and validate
    local target_index = table.find(lfo.lfo_targets, target)
    if not target_index then return end

    -- Get parameter ranges and current value
    local min_param_value, max_param_value = lfo.get_parameter_range(target)
    local current_value = params:get(target)

    -- Set target and initialize LFO
    params:set(i .. "lfo_target", target_index)

    -- Calculate offset (special case for pan/seek)
    local is_pan = target:match("pan$")
    local is_seek = target:match("seek$")
    if is_pan then
        lfo[i].offset = 0
    elseif is_seek then
        lfo[i].offset = math.random() * 1.0 - 0.5  -- Random value between -0.5 and 0.5
    else
        lfo[i].offset = lfo.scale(current_value, min_param_value, max_param_value, -1, 1)
    end
    params:set(i .. "offset", lfo[i].offset)

    -- Calculate max allowed depth (clamped to avoid exceeding parameter range)
    local max_allowed_depth = math.min(
        max_param_value - current_value,
        current_value - min_param_value
    )
    local scaled_max_depth = lfo.scale(max_allowed_depth, 0, max_param_value - min_param_value, 0, 100)

    -- Randomize depth (ensure it's within bounds)
    local ranges = lfo.target_ranges[target]
    lfo[i].depth = math.random(math.floor(ranges.depth[1]), math.floor(ranges.depth[2]))
    lfo[i].depth = math.min(lfo[i].depth, math.floor(scaled_max_depth))
    if lfo[i].depth == 0 then  -- Retry if depth=0 (unlikely but possible)
        lfo[i].depth = math.random(math.floor(ranges.depth[1]), math.floor(ranges.depth[2]))
    end
    params:set(i .. "lfo_depth", lfo[i].depth)

    -- Randomize frequency if applicable
    if ranges.frequency then
        local min_freq = math.floor(ranges.frequency[1] * 100)
        local max_freq = math.floor(ranges.frequency[2] * 100)
        if min_freq <= max_freq then  -- Only set if valid range
            lfo[i].freq = math.random(min_freq, max_freq) / 100
            params:set(i .. "lfo_freq", lfo[i].freq)
        end
    end

    -- Randomize waveform if applicable
    if ranges.waveform then
        local waveform_index = math.random(1, #ranges.waveform)
        lfo[i].waveform = ranges.waveform[waveform_index]
        params:set(i .. "lfo_shape", waveform_index)
    end

    -- Activate LFO and mark target as assigned
    params:set(i .. "lfo", 2)
    assigned_params[target] = true
end

function lfo.randomize_lfos(track, allow_volume_lfos)
    local other_track = track == "1" and "2" or "1"
    
    -- Clear all LFOs targeting this track (if not locked)
    for i = 1, 16 do
        local target_index = params:get(i .. "lfo_target")
        local target_param = lfo.lfo_targets[target_index]
        
        -- Clear if targeting this track (including seek) and not locked
        if target_param and string.match(target_param, "^"..track) and not is_locked(target_param) then
            params:set(i .. "lfo", 1)  -- Turn off LFO
            params:set(i .. "lfo_target", 1)  -- Reset target
            assigned_params[target_param] = nil  -- Unassign
        end
    end

    -- Get available targets for this track (weighted by chance)
    local available_targets = {}
    for target, ranges in pairs(lfo.target_ranges) do
        -- Skip volume targets if not allowed
        if (not target:match("volume$") or allow_volume_lfos) then
            if string.match(target, "^"..track) and not is_locked(target) and math.random() < ranges.chance then
                table.insert(available_targets, target)
            end
        end
    end

    -- Find free slots (not affecting the other track and not locked)
    local free_slots = {}
    for j = 1, 16 do
        local target_index = params:get(j .. "lfo_target")
        local target_param = lfo.lfo_targets[target_index]
        
        -- Slot is free if it's not affecting the other track and not locked
        if (not target_param or not string.match(target_param, "^"..other_track)) and 
           not is_locked(target_param) then
            table.insert(free_slots, j)
        end
    end

    -- Assign new LFOs randomly to available targets
    for _, target in ipairs(available_targets) do
        if #free_slots > 0 then
            local slot_index = table.remove(free_slots, math.random(#free_slots))  -- Randomize slot selection
            randomize_lfo(slot_index, target)
        end
    end
end

function lfo.process()
  for i = 1, 16 do
    if params:get(i .. "lfo") == 2 then

      -- Update phase (wrapping at 1.0)
      lfo[i].phase = (lfo[i].phase + lfo[i].freq * (1/30)) % 1.0  -- 1/30 assumes 30Hz metro
      
      local slope
      if lfo[i].waveform == "sine" then
        slope = math.sin(lfo[i].phase * math.pi * 2)  -- 0-1 phase to 0-2π radians
      elseif lfo[i].waveform == "square" then
        slope = lfo[i].phase < 0.5 and 1 or -1
 elseif lfo[i].waveform == "random" then
  local phase_increment = lfo[i].freq * (1/30)
  if (lfo[i].phase - phase_increment) % 1.0 > lfo[i].phase then
    -- Only change value when phase wraps around
    lfo[i].prev = math.random() * (math.random(0, 1) == 0 and 1 or -1)
  end
  -- Ensure we have a valid value (initialize if nil)
  lfo[i].prev = lfo[i].prev or 0
  slope = lfo[i].prev
end
      
      lfo[i].slope = math.max(-1.0, math.min(1.0, slope)) * (lfo[i].depth * 0.01) + lfo[i].offset
      
      local target = params:get(i .. "lfo_target")
      local min_param_value, max_param_value = lfo.get_parameter_range(lfo.lfo_targets[target])
      local modulated_value = lfo.scale(lfo[i].slope, -1.0, 1.0, min_param_value, max_param_value)
      modulated_value = math.max(min_param_value, math.min(max_param_value, modulated_value))
      
      params:set(lfo.lfo_targets[target], modulated_value)
    end
  end
end

function lfo.scale(old_value, old_min, old_max, new_min, new_max)
  local old_range = old_max - old_min
  if old_range == 0 then old_range = new_min end
  local new_range = new_max - new_min
  return (((old_value - old_min) * new_range) / old_range) + new_min
end

function lfo.init()
  for i = 1, number_of_outputs do
    params:add_separator("LFO " .. i)
    params:add_option(i .. "lfo_target", i .. " target", lfo.lfo_targets, 1)
    params:add_option(i .. "lfo_shape", i .. " shape", options.lfotypes, 1)
    params:set_action(i .. "lfo_shape", function(value) lfo[i].waveform = options.lfotypes[value] end)
    params:add_number(i .. "lfo_depth", i .. " depth", 0, 100, 50)
    params:set_action(i .. "lfo_depth", function(value) lfo[i].depth = value end)
    params:add_control(i .. "offset", i .. " offset", controlspec.new(-0.99, 0.99, "lin", 0.01, 0, ""))
    params:set_action(i .. "offset", function(value) lfo[i].offset = value end)
    params:add_control(i .. "lfo_freq", i .. " freq", controlspec.new(0.01, 2.00, "lin", 0.01, 0.05, ""))
    params:set_action(i .. "lfo_freq", function(value)
      lfo[i].base_freq = value
      lfo[i].freq = value * (params:get("global_lfo_freq_scale") or 1.0)
    end)
    params:add_option(i .. "lfo", i .. " LFO", { "off", "on" }, 1)
  end

  local lfo_metro = metro.init()
  lfo_metro.time = 1/30
  lfo_metro.count = -1
  lfo_metro.event = lfo.process
  lfo_metro:start()
end

return lfo