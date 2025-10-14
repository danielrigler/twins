local number_of_outputs = 16

local options = {
  lfotypes = { "sine", "random", "square", "walk" }
}

local lfo = {}
local assigned_params = {}
local lfo_paused = false

-- Constants
local PHASE_INCREMENT = 1/30
local TWO_PI = math.pi * 2
local LOCKABLE_PARAMS = { "jitter", "size", "density", "spread", "pitch", "pan", "seek", "speed" }
local LOCKABLE_LOOKUP = {}

for _, param in ipairs(LOCKABLE_PARAMS) do
  LOCKABLE_LOOKUP[param] = true
end

function lfo.is_param_locked(track, param_name)
  local lock_param_name = track .. "lock_" .. param_name
  return params.lookup[lock_param_name] and params:get(lock_param_name) == 2
end

function lfo.set_pause(paused)
  lfo_paused = paused
end

-- Initialize LFO table
for i = 1, number_of_outputs do
  lfo[i] = { 
    freq = 0.05, 
    phase = 0,
    waveform = "sine",
    slope = 0, 
    depth = 50, 
    offset = 0,
    prev = 0,
    walk_value = 0,
    walk_velocity = 0
  }
end

function is_audio_loaded(track_num)
  local file_path = params:get(track_num .. "sample")
  return file_path and file_path ~= "" and file_path ~= "none" and file_path ~= "-"
end

function lfo.clearLFOs(track, param_type)
  local function clear_targets(target_filter)
    for target, _ in pairs(assigned_params) do
      local track_num = target:sub(1,1)
      local param_name = target:sub(2)
      if target_filter(target) and not lfo.is_param_locked(track_num, param_name) then
        assigned_params[target] = nil
      end
    end
    for i = 1, 16 do
      if params.lookup[i.."lfo"] and params.lookup[i.."lfo_target"] then
        local target_index = params:get(i.."lfo_target")
        local target_param = lfo.lfo_targets[target_index]
        if target_param then
          local track_num = target_param:sub(1,1)
          local param_name = target_param:sub(2)
          if target_filter(target_param) and not lfo.is_param_locked(track_num, param_name) then
            params:set(i.."lfo", 1)
            params:set(i.."lfo_target", 1)
          end
        end
      end
    end
  end
  
  local function reset_pan()
    if is_audio_loaded("1") and is_audio_loaded("2") then
      params:set("1pan", -15)
      params:set("2pan", 15)
    else
      params:set("1pan", 0)
      params:set("2pan", 0)
    end
  end
  
  if track and param_type then
    clear_targets(function(target) return target:match("^"..track..param_type.."$") end)
  elseif track then
    clear_targets(function(target) return target:match("^"..track) end)
  else
    clear_targets(function() return true end)
    reset_pan()
  end
end

lfo.lfo_targets = {
  "none", "1pan", "2pan", "1seek", "2seek", "1jitter", "2jitter", 
  "1spread", "2spread", "1size", "2size", "1density", "2density", "1volume", "2volume", 
  "1pitch", "2pitch", "1cutoff", "2cutoff", "1hpf", "2hpf", "1speed", "2speed"
}

lfo.target_ranges = {
  ["1pan"] = { depth = { 25, 90 }, offset = { 0, 0 }, frequency = { 0.05, 0.6 }, waveform = { "sine" }, chance = 0.8 },
  ["2pan"] = { depth = { 25, 90 }, offset = { 0, 0 }, frequency = { 0.05, 0.6 }, waveform = { "sine" }, chance = 0.8 },
  ["1jitter"] = { depth = { 20, 100 }, offset = { -1, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5 },
  ["2jitter"] = { depth = { 20, 100 }, offset = { -1, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5 },
  ["1spread"] = { depth = { 20, 100 }, offset = { 0, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5 },
  ["2spread"] = { depth = { 20, 100 }, offset = { 0, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5},
  ["1size"] = { depth = { 20, 100 }, offset = { 0, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5 },
  ["2size"] = { depth = { 20, 100 }, offset = { 0, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5 },
  ["1density"] = { depth = { 20, 100 }, offset = { 0, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5 },
  ["2density"] = { depth = { 20, 100 }, offset = { 0, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5 },
  ["1volume"] = { depth = { 2, 3 }, offset = { 0, 1 }, frequency = { 0.1, 0.5 }, waveform = { "sine" }, chance = 1.0 },
  ["2volume"] = { depth = { 2, 3 }, offset = { 0, 1 }, frequency = { 0.1, 0.5 }, waveform = { "sine" }, chance = 1.0 },
  ["1seek"] = { depth = { 50, 100 }, offset = { 0, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.3 },
  ["2seek"] = { depth = { 50, 100 }, offset = { 0, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.3 },
  ["1speed"] = { depth = { 50, 100 }, offset = { -1, 1 }, frequency = { 0.02, 0.5 }, waveform = { "sine" }, chance = 0.2 },
  ["2speed"] = { depth = { 50, 100 }, offset = { -1, 1 }, frequency = { 0.02, 0.5 }, waveform = { "sine" }, chance = 0.2 }
}

local param_ranges = {
  ["1pan"] = { -90, 90 }, ["2pan"] = { -90, 90 },
  ["1seek"] = { 0, 100 }, ["2seek"] = { 0, 100 },
  ["1speed"] = { -0.15, 0.5 }, ["2speed"] = { -0.15, 0.5 },
  ["1jitter"] = { 0, 99999 }, ["2jitter"] = { 0, 99999 },
  ["1spread"] = { 0, 90 }, ["2spread"] = { 0, 90 },
  ["1size"] = { 100, 499 }, ["2size"] = { 100, 499 },
  ["1density"] = { 0, 29 }, ["2density"] = { 0, 29 },
  ["1volume"] = { -70, 10 }, ["2volume"] = { -70, 10 },
  ["1pitch"] = { -12, 12 }, ["2pitch"] = { -12, 12 },
  ["1cutoff"] = { 20, 20000 }, ["2cutoff"] = { 20, 20000 },
  ["1hpf"] = { 20, 20000 }, ["2hpf"] = { 20, 20000 }
}

function lfo.get_parameter_range(param_name)
  if param_name:match("jitter$") then
    local track = param_name:sub(1, 1)
    local max_jitter = params:get(track .. "max_jitter") or 4999
    return 0, max_jitter
  end
  local range = param_ranges[param_name]
  return range and range[1] or 0, range and range[2] or 100
end

function lfo.assign_to_current_row(current_mode, current_filter_mode)
  local param_map = {
    seek = "seek", pan = "pan", jitter = "jitter",
    size = "size", density = "density", spread = "spread", speed = "speed"
  }
  local param_name = param_map[current_mode]
  if not param_name then return end

  local symmetry = params:get("symmetry") == 1
  
  lfo.clearLFOs("1", param_name)
  lfo.clearLFOs("2", param_name)
  
  local available_slots = {}
  for i = 1, 16 do
    if params.lookup[i.."lfo"] and params:get(i.."lfo") == 1 then
      table.insert(available_slots, i)
    end
  end
  
  if symmetry and not lfo.is_param_locked("1", param_name) and 
     not lfo.is_param_locked("2", param_name) and #available_slots >= 2 then
    
    local slot1 = table.remove(available_slots, 1)
    local slot2 = table.remove(available_slots, 1)
    
    randomize_lfo(slot1, "1"..param_name)
    randomize_lfo(slot2, "2"..param_name)
    
    lfo[slot2].freq = lfo[slot1].freq
    lfo[slot2].waveform = lfo[slot1].waveform
    lfo[slot2].depth = lfo[slot1].depth
    
    if param_name == "pan" then
      lfo[slot2].phase = (lfo[slot1].phase + 0.5) % 1.0
      lfo[slot2].offset = -lfo[slot1].offset
      params:set(slot2.."offset", -params:get(slot1.."offset"))
    else
      lfo[slot2].phase = lfo[slot1].phase
      lfo[slot2].offset = lfo[slot1].offset
      params:set(slot2.."offset", params:get(slot1.."offset"))
    end
    
    params:set(slot2.."lfo_freq", params:get(slot1.."lfo_freq"))
    params:set(slot2.."lfo_shape", params:get(slot1.."lfo_shape"))
    params:set(slot2.."lfo_depth", params:get(slot1.."lfo_depth"))
    return
  end
  
  if not lfo.is_param_locked("1", param_name) and #available_slots > 0 then
    randomize_lfo(table.remove(available_slots, 1), "1"..param_name)
  end
  
  if not lfo.is_param_locked("2", param_name) and #available_slots > 0 then
    randomize_lfo(table.remove(available_slots, 1), "2"..param_name)
  end
end

function randomize_lfo(i, target)
  if assigned_params[target] or not lfo.target_ranges[target] then return end
  
  if target:match("seek$") and params:get(target:sub(1,1).."granular_gain") < 100 then
    return
  end
  
  for j = 1, number_of_outputs do
    if j ~= i and params.lookup[j.."lfo"] and params.lookup[j.."lfo_target"] then
      if params:get(j.."lfo") == 2 and lfo.lfo_targets[params:get(j.."lfo_target")] == target then
        return
      end
    end
  end
  
  local target_index
  for idx, t in ipairs(lfo.lfo_targets) do
    if t == target then target_index = idx; break end
  end
  if not target_index then return end
  
  params:set(i.."lfo_target", target_index)
  
  local min_val, max_val = lfo.get_parameter_range(target)
  local current_val = params:get(target)
  local is_pan, is_seek = target:match("pan$"), target:match("seek$")
  
  lfo[i].offset = is_pan and 0 or (is_seek and (math.random() - 0.5) or lfo.scale(current_val, min_val, max_val, -1, 1))
  params:set(i.."offset", lfo[i].offset)
  
  local ranges = lfo.target_ranges[target]
  local max_allowed = math.min(max_val - current_val, current_val - min_val)
  local scaled_max = lfo.scale(max_allowed, 0, max_val - min_val, 0, 100)
  lfo[i].depth = math.max(1, math.min(math.random(ranges.depth[1], ranges.depth[2]), math.floor(scaled_max)))
  params:set(i.."lfo_depth", lfo[i].depth)
  
  if ranges.frequency then
    local min_f, max_f = ranges.frequency[1] * 100, ranges.frequency[2] * 100
    if min_f <= max_f then
      lfo[i].freq = math.random(min_f, max_f) / 100
      params:set(i.."lfo_freq", lfo[i].freq)
    end
  end
  
  if ranges.waveform then
    local wf_index = math.random(#ranges.waveform)
    lfo[i].waveform = ranges.waveform[wf_index]
    params:set(i.."lfo_shape", wf_index)
  end
  
  params:set(i.."lfo", 2)
  assigned_params[target] = true
end

function lfo.assign_volume_lfos()
  lfo.clearLFOs("1", "volume")
  lfo.clearLFOs("2", "volume")
  
  local free_slots = {}
  for i = 1, 16 do
    if params.lookup[i.."lfo"] and params:get(i.."lfo") == 1 then
      table.insert(free_slots, i)
    end
  end
  
  if #free_slots > 0 and not lfo.is_param_locked("1", "volume") then
    randomize_lfo(table.remove(free_slots, 1), "1volume")
  end
  
  if #free_slots > 0 and not lfo.is_param_locked("2", "volume") then
    randomize_lfo(table.remove(free_slots, 1), "2volume")
  end
end

function lfo.randomize_lfos(track, allow_volume_lfos)
  local symmetry = params:get("symmetry") == 1
  
  for i = 1, 16 do
    if params.lookup[i.."lfo"] and params.lookup[i.."lfo_target"] then
      local target_param = lfo.lfo_targets[params:get(i.."lfo_target")]
      if target_param then
        local track_num = target_param:sub(1,1)
        local param_name = target_param:sub(2)
        local should_clear = (symmetry and not target_param:match("volume$") and target_param:match("^[12]")) or
                           target_param:match("^"..track)
        
        if should_clear and not lfo.is_param_locked(track_num, param_name) then
          params:set(i.."lfo", 1)
          params:set(i.."lfo_target", 1)
          assigned_params[target_param] = nil
        end
      end
    end
  end

  local available_targets = {}
  for target, ranges in pairs(lfo.target_ranges) do
    local track_num = target:sub(1,1)
    local param_name = target:sub(2)
    local target_matches = (symmetry and not target:match("volume$")) or target:match("^"..track)
    
    if target_matches and not lfo.is_param_locked(track_num, param_name) and 
       (not target:match("volume$") or allow_volume_lfos) then
      if target:match("seek$") then
        local t_num = target:sub(1,1)
        if params:get(t_num.."granular_gain") >= 100 and math.random() < ranges.chance then
          table.insert(available_targets, target)
        end
      elseif math.random() < ranges.chance then
        table.insert(available_targets, target)
      end
    end
  end

  local free_slots = {}
  for j = 1, 16 do
    if params.lookup[j.."lfo"] and params:get(j.."lfo") == 1 then
      table.insert(free_slots, j)
    end
  end

  local mirrored_pairs = {}
  for _, target in ipairs(available_targets) do
    if #free_slots >= (symmetry and 2 or 1) and not mirrored_pairs[target] then
      local slot1 = table.remove(free_slots, math.random(#free_slots))
      randomize_lfo(slot1, target)
      
      if symmetry and not target:match("volume$") then
        local mirrored_target = target:gsub("^(%d)(.*)", function(num, rest)
          return (tonumber(num) % 2) + 1 .. rest
        end)
        
        if #free_slots > 0 then
          local slot2 = table.remove(free_slots, math.random(#free_slots))
          randomize_lfo(slot2, mirrored_target)
          
          lfo[slot2].freq = lfo[slot1].freq
          lfo[slot2].waveform = lfo[slot1].waveform
          lfo[slot2].depth = lfo[slot1].depth
          
          if target:match("pan$") then
            lfo[slot2].phase = (lfo[slot1].phase + 0.5) % 1.0
            lfo[slot2].offset = -lfo[slot1].offset
            params:set(slot2.."offset", -params:get(slot1.."offset"))
          else
            lfo[slot2].phase = lfo[slot1].phase
            lfo[slot2].offset = lfo[slot1].offset
            params:set(slot2.."offset", params:get(slot1.."offset"))
          end
          
          params:set(slot2.."lfo_freq", params:get(slot1.."lfo_freq"))
          params:set(slot2.."lfo_shape", params:get(slot1.."lfo_shape"))
          params:set(slot2.."lfo_depth", params:get(slot1.."lfo_depth"))
          
          mirrored_pairs[mirrored_target] = true
        end
      end
      mirrored_pairs[target] = true
    end
  end
end

function lfo.process()
  if lfo_paused then
    for i = 1, 16 do
      if params:get(i.."lfo") == 2 then
        local target_param = lfo.lfo_targets[params:get(i.."lfo_target")]
        if target_param and (target_param == "1volume" or target_param == "2volume") then
          local min_val, max_val = lfo.get_parameter_range(target_param)
          local offset = params:get(i.."offset") or 0
          params:set(target_param, lfo.scale(offset, -1.0, 1.0, min_val, max_val))
        end
      end
    end
    return
  end
  
  for i = 1, 16 do
    if params:get(i.."lfo") == 2 then
      local lfo_obj = lfo[i]
      lfo_obj.phase = (lfo_obj.phase + lfo_obj.freq * PHASE_INCREMENT) % 1.0
      
      local slope
      if lfo_obj.waveform == "sine" then
        slope = math.sin(lfo_obj.phase * TWO_PI)
      elseif lfo_obj.waveform == "square" then
        slope = lfo_obj.phase < 0.5 and 1 or -1
      elseif lfo_obj.waveform == "random" then
        local phase_inc = lfo_obj.freq * PHASE_INCREMENT
        if (lfo_obj.phase - phase_inc) % 1.0 > lfo_obj.phase then
          lfo_obj.prev = math.random() * (math.random(0, 1) * 2 - 1)
        end
        slope = lfo_obj.prev
      elseif lfo_obj.waveform == "walk" then
        local step_size = lfo_obj.freq * 0.4
        local random_acceleration = (math.random() - 0.5) * step_size
        local damping = 0.92
        lfo_obj.walk_velocity = lfo_obj.walk_velocity * damping + random_acceleration
        lfo_obj.walk_value = lfo_obj.walk_value + lfo_obj.walk_velocity
        
        local boundary_softness = 0.75
        if lfo_obj.walk_value > boundary_softness then
          lfo_obj.walk_velocity = lfo_obj.walk_velocity - (lfo_obj.walk_value - boundary_softness) * 0.1
        elseif lfo_obj.walk_value < -boundary_softness then
          lfo_obj.walk_velocity = lfo_obj.walk_velocity - (lfo_obj.walk_value + boundary_softness) * 0.1
        end
        
        lfo_obj.walk_value = util.clamp(lfo_obj.walk_value, -1.0, 1.0)
        local filter_strength = 0.80
        slope = lfo_obj.prev * filter_strength + lfo_obj.walk_value * (1 - filter_strength)
        lfo_obj.prev = slope
      end
      
      lfo_obj.slope = util.clamp(slope, -1.0, 1.0) * (lfo_obj.depth * 0.01) + lfo_obj.offset
      
      local target_param = lfo.lfo_targets[params:get(i.."lfo_target")]
      if target_param then
        local min_val, max_val = lfo.get_parameter_range(target_param)
        local modulated_value = util.clamp(
          lfo.scale(lfo_obj.slope, -1.0, 1.0, min_val, max_val), 
          min_val, max_val
        )
        params:set(target_param, modulated_value)
      end
    end
  end
end

function lfo.scale(old_value, old_min, old_max, new_min, new_max)
  return (old_value - old_min) * (new_max - new_min) / (old_max - old_min) + new_min
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
      lfo[i].freq = value * params:get("global_lfo_freq_scale")
    end)
    params:add_option(i .. "lfo", i .. " LFO", { "off", "on" }, 1)
  end
  
  local lfo_metro = metro.init()
  lfo_metro.time = PHASE_INCREMENT
  lfo_metro.count = -1
  lfo_metro.event = lfo.process
  lfo_metro:start()
end

return lfo