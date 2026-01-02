local number_of_outputs = 16

local options = {lfotypes = { "sine", "random", "square", "walk" }}
local lfo = {}
local assigned_params = {}
local lfo_paused = false
local lfo_cleaning_up = false
local util_clamp = util.clamp
local math_random = math.random
local math_pi = math.pi
local math_sin = math.sin
local math_floor = math.floor
local PHASE_INCREMENT = 1/30
local TWO_PI = math_pi * 2
local LOCKABLE_PARAMS = { "jitter", "size", "density", "spread", "pitch", "pan", "seek", "speed" }
local LOCKABLE_LOOKUP = {}
local RANGE_CACHE = {}
for _, param in ipairs(LOCKABLE_PARAMS) do LOCKABLE_LOOKUP[param] = true end

local function pget(k) 
  if not params or not params.lookup or not params.lookup[k] then return nil end
  return params:get(k) 
end
local function pset(k, v) 
  if not params or not params.lookup or not params.lookup[k] then return end
  params:set(k, v) 
end
function lfo.is_param_locked(track, param_name)
  local lock_param_name = track .. "lock_" .. param_name
  return params.lookup[lock_param_name] and pget(lock_param_name) == 2
end
function lfo.set_pause(paused)
  lfo_paused = paused
end

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
    walk_velocity = 0,
    sync_to = nil
  }
end

local function is_audio_loaded(track_num)
  local file_path = pget(track_num .. "sample")
  return file_path and file_path ~= "" and file_path ~= "none" and file_path ~= "-"
end

function lfo.clearLFOs(track, param_type)
  local target_filter
  if track and param_type then
    target_filter = function(target) return target:match("^" .. track .. param_type .. "$") end
  elseif track then
    target_filter = function(target) return target:match("^" .. track) end
  else
    target_filter = function() return true end
  end

  for target, _ in pairs(assigned_params) do
    if target_filter(target) then assigned_params[target] = nil end
  end

  for i = 1, number_of_outputs do
    if params.lookup[i.."lfo"] and params.lookup[i.."lfo_target"] then
      local t = pget(i.."lfo_target")
      local target_param = lfo.lfo_targets[t]
      if target_param and target_filter(target_param) then
        local track_num, param_name = target_param:sub(1,1), target_param:sub(2)
        if not lfo.is_param_locked(track_num, param_name) then
          pset(i.."lfo", 1)
          pset(i.."lfo_target", 1)
          lfo[i].sync_to = nil
        end
      end
    end
  end

  if not track and not param_type then
    if is_audio_loaded("1") and is_audio_loaded("2") then
      pset("1pan", -15); pset("2pan", 15)
    else
      pset("1pan", 0); pset("2pan", 0)
    end
  end
end

lfo.lfo_targets = {
  "none", "1pan", "2pan", "1seek", "2seek", "1jitter", "2jitter",
  "1spread", "2spread", "1size", "2size", "1density", "2density", "1volume", "2volume",
  "1pitch", "2pitch", "1cutoff", "2cutoff", "1hpf", "2hpf", "1speed", "2speed"
}

lfo.target_ranges = {
  ["1pan"] = { depth = { 25, 90 }, offset = { 0, 0 }, frequency = { 0.1, 0.6 }, waveform = { "sine" }, chance = 0.8 },
  ["2pan"] = { depth = { 25, 90 }, offset = { 0, 0 }, frequency = { 0.1, 0.6 }, waveform = { "sine" }, chance = 0.8 },
  ["1jitter"] = { depth = { 20, 70 }, offset = { -1, 1 }, frequency = { 0.1, 0.4 }, waveform = { "sine" }, chance = 0.6 },
  ["2jitter"] = { depth = { 20, 70 }, offset = { -1, 1 }, frequency = { 0.1, 0.4 }, waveform = { "sine" }, chance = 0.6 },
  ["1spread"] = { depth = { 10, 30 }, offset = { 0, 0.3 }, frequency = { 0.1, 0.4 }, waveform = { "sine" }, chance = 0.6 },
  ["2spread"] = { depth = { 10, 30 }, offset = { 0, 0.3 }, frequency = { 0.1, 0.4 }, waveform = { "sine" }, chance = 0.6},
  ["1size"] = { depth = { 5, 30 }, offset = { 0.1, 1 }, frequency = { 0.1, 0.4 }, waveform = { "sine" }, chance = 0.6 },
  ["2size"] = { depth = { 5, 30 }, offset = { 0.1, 1 }, frequency = { 0.1, 0.4 }, waveform = { "sine" }, chance = 0.6 },
  ["1density"] = { depth = { 5, 40 }, offset = { 0, 1 }, frequency = { 0.1, 0.4 }, waveform = { "sine" }, chance = 0.6 },
  ["2density"] = { depth = { 5, 40 }, offset = { 0, 1 }, frequency = { 0.1, 0.4 }, waveform = { "sine" }, chance = 0.6 },
  ["1volume"] = { depth = { 2, 3 }, offset = { 0, 1 }, frequency = { 0.1, 0.5 }, waveform = { "sine" }, chance = 1.0 },
  ["2volume"] = { depth = { 2, 3 }, offset = { 0, 1 }, frequency = { 0.1, 0.5 }, waveform = { "sine" }, chance = 1.0 },
  ["1seek"] = { depth = { 0, 100 }, offset = { 0, 1 }, frequency = { 0.02, 0.3 }, waveform = { "sine" }, chance = 0.3 },
  ["2seek"] = { depth = { 0, 100 }, offset = { 0, 1 }, frequency = { 0.02, 0.3 }, waveform = { "sine" }, chance = 0.3 },
  ["1speed"] = { depth = { 10, 50 }, offset = { -1, 1 }, frequency = { 0.02, 0.3 }, waveform = { "sine" }, chance = 0.2 },
  ["2speed"] = { depth = { 10, 50 }, offset = { -1, 1 }, frequency = { 0.02, 0.3 }, waveform = { "sine" }, chance = 0.2 }
}

local param_ranges = {
  ["1pan"] = { -100, 100 }, ["2pan"] = { -100, 100 },
  ["1seek"] = { 0, 100 }, ["2seek"] = { 0, 100 },
  ["1speed"] = { -2, 2 }, ["2speed"] = { -2, 2 },
  ["1jitter"] = { 0, 99999 }, ["2jitter"] = { 0, 99999 },
  ["1spread"] = { 0, 100 }, ["2spread"] = { 0, 100 },
  ["1size"] = { 20, 599 }, ["2size"] = { 20, 599 },
  ["1density"] = { 1, 50 }, ["2density"] = { 1, 50 },
  ["1volume"] = { -70, 10 }, ["2volume"] = { -70, 10 },
  ["1pitch"] = { -48, 48 }, ["2pitch"] = { -48, 48 },
  ["1cutoff"] = { 20, 20000 }, ["2cutoff"] = { 20, 20000 },
  ["1hpf"] = { 20, 20000 }, ["2hpf"] = { 20, 20000 }
}

function lfo.get_parameter_range(param_name)
  if RANGE_CACHE[param_name] then return RANGE_CACHE[param_name][1], RANGE_CACHE[param_name][2] end
  if param_name:match("jitter$") then
    local track = param_name:sub(1, 1)
    local max_jitter = pget(track .. "max_jitter") or 4999
    return 0, max_jitter
  end
  local range = param_ranges[param_name]
  if range then RANGE_CACHE[param_name] = range return range[1], range[2] end
  RANGE_CACHE[param_name] = {0, 100}
  return 0, 100
end

function lfo.clear_range_cache() RANGE_CACHE = {} end

function lfo.assign_to_current_row(current_mode, current_filter_mode)
  local param_map = {
    seek = "seek", pan = "pan", jitter = "jitter",
    size = "size", density = "density", spread = "spread", speed = "speed"
  }
  local param_name = param_map[current_mode]
  if not param_name then return end

  local symmetry = pget("symmetry") == 1

  lfo.clearLFOs("1", param_name)
  lfo.clearLFOs("2", param_name)

  local available_slots = {}
  for i = 1, number_of_outputs do
    if params.lookup[i.."lfo"] and pget(i.."lfo") == 1 then available_slots[#available_slots+1] = i end
  end

  if symmetry and not lfo.is_param_locked("1", param_name) and not lfo.is_param_locked("2", param_name) and #available_slots >= 2 then
    local slot1 = table.remove(available_slots, 1)
    local slot2 = table.remove(available_slots, 1)
    randomize_lfo(slot1, "1"..param_name)
    randomize_lfo(slot2, "2"..param_name)
    lfo[slot2].freq = lfo[slot1].freq
    lfo[slot2].waveform = lfo[slot1].waveform
    lfo[slot2].depth = lfo[slot1].depth
    lfo[slot2].walk_value = lfo[slot1].walk_value
    lfo[slot2].walk_velocity = lfo[slot1].walk_velocity
    lfo[slot2].sync_to = slot1
    if param_name == "pan" then
      lfo[slot2].phase = (lfo[slot1].phase + 0.5) % 1.0
      lfo[slot2].offset = -lfo[slot1].offset
      pset(slot2.."offset", -pget(slot1.."offset"))
    else
      lfo[slot2].phase = lfo[slot1].phase
      lfo[slot2].offset = lfo[slot1].offset
      pset(slot2.."offset", pget(slot1.."offset"))
    end
    pset(slot2.."lfo_freq", pget(slot1.."lfo_freq"))
    pset(slot2.."lfo_shape", pget(slot1.."lfo_shape"))
    pset(slot2.."lfo_depth", pget(slot1.."lfo_depth"))
    return
  end

  if not lfo.is_param_locked("1", param_name) and #available_slots > 0 then randomize_lfo(table.remove(available_slots, 1), "1"..param_name) end
  if not lfo.is_param_locked("2", param_name) and #available_slots > 0 then randomize_lfo(table.remove(available_slots, 1), "2"..param_name) end
end

function randomize_lfo(i, target)
  if assigned_params[target] or not lfo.target_ranges[target] then return end
  if target:match("seek$") and pget(target:sub(1,1).."granular_gain") < 100 then return end
  for j = 1, number_of_outputs do
    if j ~= i and params.lookup[j.."lfo"] and pget(j.."lfo") == 2 and lfo.lfo_targets[pget(j.."lfo_target")] == target then return end
  end
  local target_index
  for idx, t in ipairs(lfo.lfo_targets) do if t == target then target_index = idx; break end end
  if not target_index then return end
  pset(i.."lfo_target", target_index)
  local min_val, max_val = lfo.get_parameter_range(target)
  local current_val = pget(target)
  local is_pan = target:match("pan$")
  local is_seek = target:match("seek$")
  
  local initial_offset
  if is_pan then
    initial_offset = 0
  elseif is_seek then
    initial_offset = (math_random() - 0.5)
  else
    initial_offset = lfo.scale(current_val, min_val, max_val, -1, 1)
  end
  
  local ranges = lfo.target_ranges[target]
  local desired_depth = math_random(ranges.depth[1], ranges.depth[2])
  local depth_range = (desired_depth / 100) * (max_val - min_val)
  local center_point = lfo.scale(initial_offset, -1, 1, min_val, max_val)
  local available_above = max_val - center_point
  local available_below = center_point - min_val
  local max_half_depth = math.min(available_above, available_below)
  if depth_range / 2 <= max_half_depth then
    lfo[i].depth = desired_depth
    lfo[i].offset = initial_offset
  else
    lfo[i].depth = desired_depth
    
    local half_depth_range = depth_range / 2
    if available_above > available_below then
      center_point = math.min(max_val - half_depth_range, center_point + (half_depth_range - available_below))
    else
      center_point = math.max(min_val + half_depth_range, center_point - (half_depth_range - available_above))
    end
    center_point = util_clamp(center_point, min_val + half_depth_range, max_val - half_depth_range)
    lfo[i].offset = lfo.scale(center_point, min_val, max_val, -1, 1)
  end
  
  pset(i.."offset", lfo[i].offset)
  pset(i.."lfo_depth", lfo[i].depth)
  
  if ranges.frequency then
    local min_f, max_f = ranges.frequency[1] * 100, ranges.frequency[2] * 100
    if min_f <= max_f then
      lfo[i].freq = math_random(min_f, max_f) / 100
      pset(i.."lfo_freq", lfo[i].freq)
    end
  end
  if ranges.waveform then
    local wf_index = math_random(#ranges.waveform)
    local selected_waveform = ranges.waveform[wf_index]
    lfo[i].waveform = selected_waveform
    -- Find the index of this waveform in options.lfotypes
    local shape_index = 1
    for idx, wf in ipairs(options.lfotypes) do
      if wf == selected_waveform then
        shape_index = idx
        break
      end
    end
    pset(i.."lfo_shape", shape_index)
  end
  pset(i.."lfo", 2)
  assigned_params[target] = true
end

function lfo.assign_volume_lfos()
  lfo.clearLFOs("1", "volume")
  lfo.clearLFOs("2", "volume")
  local free_slots = {}
  for i = 1, number_of_outputs do if params.lookup[i.."lfo"] and pget(i.."lfo") == 1 then free_slots[#free_slots+1] = i end end
  if #free_slots > 0 and not lfo.is_param_locked("1", "volume") then randomize_lfo(table.remove(free_slots, 1), "1volume") end
  if #free_slots > 0 and not lfo.is_param_locked("2", "volume") then randomize_lfo(table.remove(free_slots, 1), "2volume") end
end

function lfo.randomize_lfos(track, allow_volume_lfos)
  local symmetry = pget("symmetry") == 1
  for i = 1, number_of_outputs do
    if params.lookup[i.."lfo"] and params.lookup[i.."lfo_target"] then
      local t_idx = pget(i.."lfo_target")
      if t_idx and t_idx > 0 then
        local target_param = lfo.lfo_targets[t_idx]
        if target_param then
          local track_num = target_param:sub(1,1)
          local param_name = target_param:sub(2)
          local should_clear = (symmetry and not target_param:match("volume$") and target_param:match("^[12]")) or target_param:match("^"..track)
          if should_clear and not lfo.is_param_locked(track_num, param_name) then
            pset(i.."lfo", 1)
            pset(i.."lfo_target", 1)
            assigned_params[target_param] = nil
          end
        end
      end
    end
  end

  local available_targets = {}
  for target, ranges in pairs(lfo.target_ranges) do
    local track_num = tonumber(target:sub(1,1)) or 1
    local param_name = target:sub(2)
    local target_matches = (symmetry and not target:match("volume$")) or target:match("^"..track)
    if target_matches and not lfo.is_param_locked(track_num, param_name) and (not target:match("volume$") or allow_volume_lfos) then
      if target:match("seek$") then
        local t_num = target:sub(1,1)
        if pget(t_num.."granular_gain") >= 100 and math_random() < ranges.chance then table.insert(available_targets, target) end
      elseif math_random() < ranges.chance then table.insert(available_targets, target) end
    end
  end

  local free_slots = {}
  for j = 1, number_of_outputs do if params.lookup[j.."lfo"] and pget(j.."lfo") == 1 then table.insert(free_slots, j) end end

  local mirrored_pairs = {}
  while #available_targets > 0 and #free_slots > 0 do
    local idx = math_random(#available_targets)
    local target = table.remove(available_targets, idx)
    if not mirrored_pairs[target] then
      local slot = table.remove(free_slots, math_random(#free_slots))
      randomize_lfo(slot, target)
      if symmetry and not target:match("volume$") then
        local mirrored_target = target:gsub("^(%d)(.*)", function(num, rest) return (tonumber(num) % 2) + 1 .. rest end)
        if #free_slots > 0 then
          local slot2 = table.remove(free_slots, math_random(#free_slots))
          randomize_lfo(slot2, mirrored_target)
          lfo[slot2].freq = lfo[slot].freq
          lfo[slot2].waveform = lfo[slot].waveform
          lfo[slot2].depth = lfo[slot].depth
          lfo[slot2].walk_value = lfo[slot].walk_value
          lfo[slot2].walk_velocity = lfo[slot].walk_velocity
          lfo[slot2].sync_to = slot
          if target:match("pan$") then
            lfo[slot2].phase = (lfo[slot].phase + 0.5) % 1.0
            lfo[slot2].offset = -lfo[slot].offset
            pset(slot2.."offset", -pget(slot.."offset"))
          else
            lfo[slot2].phase = lfo[slot].phase
            lfo[slot2].offset = lfo[slot].offset
            pset(slot2.."offset", pget(slot.."offset"))
          end
          pset(slot2.."lfo_freq", pget(slot.."lfo_freq"))
          pset(slot2.."lfo_shape", pget(slot.."lfo_shape"))
          pset(slot2.."lfo_depth", pget(slot.."lfo_depth"))
          mirrored_pairs[mirrored_target] = true
        end
      end
      mirrored_pairs[target] = true
    end
  end
end

function lfo.process()
  if lfo_paused or lfo_cleaning_up then return end
  for i = 1, number_of_outputs do
    local lfo_state = pget(i.."lfo")
    if not lfo_state or lfo_state ~= 2 then goto continue end
    local obj = lfo[i]
    obj.phase = (obj.phase + obj.freq * PHASE_INCREMENT) % 1.0
    local slope
    local wf = obj.waveform
    if wf == "sine" then
      slope = math_sin(obj.phase * TWO_PI)
    elseif wf == "square" then
      slope = obj.phase < 0.5 and 1 or -1
    elseif wf == "random" then
      local phase_inc = obj.freq * PHASE_INCREMENT
      if (obj.phase - phase_inc) % 1.0 > obj.phase then
        obj.prev = math_random() * (math_random(0,1) * 2 - 1)
      end
      slope = obj.prev
    elseif wf == "walk" then
      if obj.sync_to and lfo[obj.sync_to] then
        -- Use the synced LFO's walk state
        obj.walk_value = lfo[obj.sync_to].walk_value
        obj.walk_velocity = lfo[obj.sync_to].walk_velocity
        obj.prev = lfo[obj.sync_to].prev
        slope = obj.prev
      else
        -- Generate own random walk
        local step_size = obj.freq * 0.4
        local random_acc = (math_random() - 0.5) * step_size
        obj.walk_velocity = obj.walk_velocity * 0.92 + random_acc
        obj.walk_value = obj.walk_value + obj.walk_velocity
        local bsoft = 0.75
        if obj.walk_value > bsoft then
          obj.walk_velocity = obj.walk_velocity - (obj.walk_value - bsoft) * 0.1
        elseif obj.walk_value < -bsoft then
          obj.walk_velocity = obj.walk_velocity - (obj.walk_value + bsoft) * 0.1
        end
        obj.walk_value = util_clamp(obj.walk_value, -1.0, 1.0)
        local filter_strength = 0.80
        slope = obj.prev * filter_strength + obj.walk_value * (1 - filter_strength)
        obj.prev = slope
      end
    else
      slope = 0
    end
    obj.slope = util_clamp(slope, -1.0, 1.0) * (obj.depth * 0.01) + obj.offset
    local target_param = lfo.lfo_targets[pget(i.."lfo_target")]
    if target_param and target_param ~= "none" and params.lookup[target_param] then
      local min_val, max_val = lfo.get_parameter_range(target_param)
      local modulated_value = util_clamp(lfo.scale(obj.slope, -1.0, 1.0, min_val, max_val), min_val, max_val)
      pset(target_param, modulated_value)
    else
      pset(i.."lfo", 1)
    end
    ::continue::
  end
end

function lfo.scale(old_value, old_min, old_max, new_min, new_max)
  return (old_value - old_min) * (new_max - new_min) / (old_max - old_min) + new_min
end

local lfo_metro = nil

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
    params:set_action(i .. "lfo_freq", function(value) lfo[i].freq = value * params:get("global_lfo_freq_scale") end)
    params:add_option(i .. "lfo", i .. " LFO", { "off", "on" }, 1)
  end

  lfo_metro = metro.init()
  lfo_metro.time = PHASE_INCREMENT
  lfo_metro.count = -1
  lfo_metro.event = lfo.process
  lfo_metro:start()
end

function lfo.cleanup()
  lfo_cleaning_up = true
  if lfo_metro then
    pcall(function()
      lfo_metro:stop()
    end)
    lfo_metro.event = nil
    lfo_metro = nil
  end
end

-- Public functions to manage parameter assignments
function lfo.clear_param_assignment(param_name)
  if param_name then
    assigned_params[param_name] = nil
  end
end

function lfo.is_param_assigned(param_name)
  return assigned_params[param_name] == true
end

function lfo.mark_param_assigned(param_name)
  if param_name then
    assigned_params[param_name] = true
  end
end

function lfo.get_lfo_for_param(param_name)
  for i = 1, number_of_outputs do
    if params.lookup[i.."lfo"] and pget(i.."lfo") == 2 then
      local target_index = pget(i.."lfo_target")
      if lfo.lfo_targets[target_index] == param_name then
        return i
      end
    end
  end
  return nil
end

return lfo