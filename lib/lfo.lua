local number_of_outputs = 16
local tau = math.pi * 2

local options = {
  lfotypes = { "sine", "random", "square" }
}

local lfo = {}
local assigned_params = {}

local function is_locked(target)
  local track, param = string.match(target, "(%d)(%a+)")
  local lockable_params = { "jitter", "size", "density", "spread", "pitch", "pan" }
  
  if table.find(lockable_params, param) then
    return params:get(track .. "lock_" .. param) == 2
  end
  
  return false
end

for i = 1, number_of_outputs do
  lfo[i] = { 
    freq = 0.05, 
    base_freq = 0.05, 
    counter = 1, 
    waveform = options.lfotypes[1], 
    slope = 0, 
    depth = 50, 
    offset = 0 
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

function lfo.clearLFOs()
    for target, _ in pairs(assigned_params) do
        if not is_locked(target) then
            assigned_params[target] = nil
        end
    end

    for i = 1, 16 do
        local target_index = params:get(i .. "lfo_target")
        local target_param = lfo.lfo_targets[target_index]
        
        if not is_locked(target_param) then
            if params:get(i .. "lfo") == 2 then 
                params:set(i .. "lfo", 1) 
            end
            params:set(i .. "lfo_target", 1)
        end
    end

    if is_audio_loaded(1) and is_audio_loaded(2) then
        params:set("1pan", -15)
        params:set("2pan", 15)
    elseif is_audio_loaded(1) or is_audio_loaded(2) then
        params:set("1pan", 0)
        params:set("2pan", 0)
    end
end

lfo.lfo_targets = {
  "none", "1pan", "2pan", "1seek", "2seek", "1jitter", "2jitter", 
  "1spread", "2spread", "1size", "2size", "1density", "2density", "1volume", "2volume", 
  "1pitch", "2pitch", "1cutoff", "2cutoff"
}

lfo.target_ranges = {
  ["1pan"] = { depth = { 25, 80 }, offset = { 0, 0 }, frequency = { 0.05, 0.6 }, waveform = { "sine" }, chance = 0.8 },
  ["2pan"] = { depth = { 25, 80 }, offset = { 0, 0 }, frequency = { 0.05, 0.6 }, waveform = { "sine" }, chance = 0.8 },
  ["1jitter"] = { depth = { 5, 100 }, offset = { -1, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.6 },
  ["2jitter"] = { depth = { 5, 100 }, offset = { -1, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.6 },
  ["1spread"] = { depth = { 5, 100 }, offset = { -1, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.6 },
  ["2spread"] = { depth = { 5, 100 }, offset = { -1, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.6},
  ["1size"] = { depth = { 5, 100 }, offset = { -1, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.6 },
  ["2size"] = { depth = { 5, 100 }, offset = { -1, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.6 },
  ["1density"] = { depth = { 5, 100 }, offset = { -1, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.6 },
  ["2density"] = { depth = { 5, 100 }, offset = { -1, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.6 },
  ["1seek"] = { depth = { 100, 100 }, offset = { 0, 0 }, frequency = { 0.1, 0.6 }, waveform = { "random" }, chance = 0.3 },
  ["2seek"] = { depth = { 100, 100 }, offset = { 0, 0 }, frequency = { 0.1, 0.6 }, waveform = { "random" }, chance = 0.3 }
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
    ["1cutoff"] = { 20, 20000 }, ["2cutoff"] = { 20, 20000 }
  }
  return param_ranges[param_name][1], param_ranges[param_name][2]
end

function randomize_lfo(i, target)
    if assigned_params[target] then return end

    for j = 1, number_of_outputs do
        if j ~= i then
            local target_index = params:get(j .. "lfo_target")
            local target_param = lfo.lfo_targets[target_index]
            if target_param == target and params:get(j .. "lfo") == 2 then
                return
            end
        end
    end

    local ranges = lfo.target_ranges[target]
    if not ranges then return end

    local target_index = table.find(lfo.lfo_targets, target)
    if not target_index then return end

    params:set(i .. "lfo_target", target_index)

    local min_param_value, max_param_value = lfo.get_parameter_range(target)
    local current_value = params:get(target)

    if target == "1pan" or target == "2pan" or target == "1seek" or target == "2seek" then
        lfo[i].offset = 0
    else
        lfo[i].offset = lfo.scale(current_value, min_param_value, max_param_value, -1, 1)
    end
    params:set(i .. "offset", lfo[i].offset)

    local max_allowed_depth = math.min(
        math.abs(max_param_value - current_value), 
        math.abs(current_value - min_param_value)
    )
    local scaled_max_depth = lfo.scale(max_allowed_depth, 0, max_param_value - min_param_value, 0, 100)

    lfo[i].depth = math.random(math.floor(ranges.depth[1]), math.floor(ranges.depth[2]))
    if lfo[i].depth > scaled_max_depth then
        lfo[i].depth = math.floor(scaled_max_depth)
    end
    if lfo[i].depth == 0 then
        lfo[i].depth = math.random(math.floor(ranges.depth[1]), math.floor(ranges.depth[2]))
    end
    params:set(i .. "lfo_depth", lfo[i].depth)

    if ranges.frequency then
        local min_freq = math.floor(ranges.frequency[1] * 100)
        local max_freq = math.floor(ranges.frequency[2] * 100)
        if min_freq > max_freq then return end
        lfo[i].freq = math.random(min_freq, max_freq) / 100
        params:set(i .. "lfo_freq", lfo[i].freq)
    end

    if ranges.waveform then
        local waveform_index = math.random(1, #ranges.waveform)
        lfo[i].waveform = ranges.waveform[waveform_index]
        params:set(i .. "lfo_shape", waveform_index)
    end

    params:set(i .. "lfo", 2)
    assigned_params[target] = true
end

function lfo.randomize_lfos()
    for i = 1, number_of_outputs do
        local target_index = params:get(i .. "lfo_target")
        local target_param = lfo.lfo_targets[target_index]

        if not is_locked(target_param) then
            params:set(i .. "lfo", 1)
            params:set(i .. "lfo_target", 1)
            assigned_params[target_param] = nil
        end
    end

    local available_targets = {}
    for target, ranges in pairs(lfo.target_ranges) do
        if not is_locked(target) and math.random() < ranges.chance then
            table.insert(available_targets, target)
        end
    end

    local free_slots = {}
    for j = 1, 16 do
        local target_index = params:get(j .. "lfo_target")
        local target_param = lfo.lfo_targets[target_index]
        
        if not is_locked(target_param) then
            table.insert(free_slots, j)
        end
    end

    for _, target in ipairs(available_targets) do
        if #free_slots > 0 then
            local slot_index = table.remove(free_slots, 1)

            local is_already_assigned = false
            for j = 1, 16 do
                if j ~= slot_index then
                    local target_index = params:get(j .. "lfo_target")
                    local target_param = lfo.lfo_targets[target_index]
                    if target_param == target and params:get(j .. "lfo") == 2 then
                        is_already_assigned = true
                        break
                    end
                end
            end

            if not is_already_assigned then
                randomize_lfo(slot_index, target)
            end
        end
    end
end

function lfo.process()
  for i = 1, 16 do
    if params:get(i .. "lfo") == 2 then
      local target = params:get(i .. "lfo_target")
      local slope
      if lfo[i].waveform == "sine" then
        slope = make_sine(i)
      elseif lfo[i].waveform == "square" then
        slope = make_square(i)
      elseif lfo[i].waveform == "random" then
        slope = make_sh(i)
      end
      lfo[i].slope = math.max(-1.0, math.min(1.0, slope)) * (lfo[i].depth * 0.01) + lfo[i].offset

      local min_param_value, max_param_value = lfo.get_parameter_range(lfo.lfo_targets[target])
      local modulated_value = lfo.scale(lfo[i].slope, -1.0, 1.0, min_param_value, max_param_value)
      modulated_value = math.max(min_param_value, math.min(max_param_value, modulated_value))

      params:set(lfo.lfo_targets[target], modulated_value)

      lfo[i].counter = lfo[i].counter + lfo[i].freq
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