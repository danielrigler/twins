local number_of_outputs = 16
local options = { lfotypes = { "sine", "random", "square", "walk" } }
local lfo = {}
local assigned_params = {}
local lfo_paused = false
lfo.on_state_change = nil

local TWO_PI = math.pi * 2
local PHASE_INCREMENT = 1 / 30

local LFO_KEYS, TARGET_KEYS, SHAPE_KEYS, FREQ_KEYS, DEPTH_KEYS, OFFSET_KEYS = {}, {}, {}, {}, {}, {}
for i = 1, number_of_outputs do
  LFO_KEYS[i]    = i .. "lfo"
  TARGET_KEYS[i] = i .. "lfo_target"
  SHAPE_KEYS[i]  = i .. "lfo_shape"
  FREQ_KEYS[i]   = i .. "lfo_freq"
  DEPTH_KEYS[i]  = i .. "lfo_depth"
  OFFSET_KEYS[i] = i .. "offset"
end

local MusicUtil = require("musicutil")
local scale_array_cache = {}

local function normalize_scale_name(name)
  if name == "none" or name == "off" then return "none" end
  local map = { ["major pent."] = "major pentatonic", ["minor pent."] = "minor pentatonic" }
  return map[name] or name
end

local function get_scale_array(scale_name)
  scale_name = normalize_scale_name(scale_name)
  if scale_name == "none" then return nil end
  if not scale_array_cache[scale_name] then
    scale_array_cache[scale_name] = MusicUtil.generate_scale_of_length(60 - 48, scale_name, 97)
  end
  return scale_array_cache[scale_name]
end

local function quantize_pitch_to_scale(value, scale_name)
  local arr = get_scale_array(scale_name)
  if not arr then return value end
  return MusicUtil.snap_note_to_array(60 + value, arr) - 60
end

local function pget(k)
  if not params or not params.lookup or not params.lookup[k] then return nil end
  return params:get(k)
end
local function pset(k, v)
  if not params or not params.lookup or not params.lookup[k] then return end
  params:set(k, v)
end

function lfo.is_param_locked(track, param_name)
  local key = track .. "lock_" .. param_name
  return params.lookup[key] and pget(key) == 2
end

function lfo.set_pause(paused) lfo_paused = paused end

for i = 1, number_of_outputs do
  lfo[i] = {
    freq = 0.05, phase = 0, waveform = "sine",
    slope = 0, depth = 50, offset = 0,
    prev = 0, walk_value = 0, walk_velocity = 0,
    sync_to = nil
  }
end

local function is_audio_loaded(track)
  local p = pget(track .. "sample")
  return p and p ~= "" and p ~= "none" and p ~= "-"
end

function lfo.is_param_assigned(name)   return assigned_params[name] == true end
function lfo.mark_param_assigned(name) if name then assigned_params[name] = true end end
function lfo.clear_param_assignment(name) if name then assigned_params[name] = nil end end

lfo.lfo_targets = {
  "none", "1pan", "2pan", "1seek", "2seek", "1jitter", "2jitter",
  "1spread", "2spread", "1size", "2size", "1density", "2density",
  "1volume", "2volume", "1pitch", "2pitch", "1cutoff", "2cutoff",
  "1hpf", "2hpf", "1speed", "2speed"}

local LFO_TARGET_REVERSE = {}
for i, t in ipairs(lfo.lfo_targets) do LFO_TARGET_REVERSE[t] = i end

lfo.target_ranges = {
  ["1pan"]     = { depth = {25,90},  offset = {0,0},    frequency = {0.1,1},   waveform = {"sine"}, chance = 0.75 },
  ["2pan"]     = { depth = {25,90},  offset = {0,0},    frequency = {0.1,1},   waveform = {"sine"}, chance = 0.75 },
  ["1jitter"]  = { depth = {20,70},  offset = {-1,1},   frequency = {0.1,0.6}, waveform = {"sine"}, chance = 0.6  },
  ["2jitter"]  = { depth = {20,70},  offset = {-1,1},   frequency = {0.1,0.6}, waveform = {"sine"}, chance = 0.6  },
  ["1spread"]  = { depth = {10,30},  offset = {0,0.3},  frequency = {0.1,0.6}, waveform = {"sine"}, chance = 0.6  },
  ["2spread"]  = { depth = {10,30},  offset = {0,0.3},  frequency = {0.1,0.6}, waveform = {"sine"}, chance = 0.6  },
  ["1size"]    = { depth = {5,30},   offset = {0.1,1},  frequency = {0.1,0.6}, waveform = {"sine"}, chance = 0.6  },
  ["2size"]    = { depth = {5,30},   offset = {0.1,1},  frequency = {0.1,0.6}, waveform = {"sine"}, chance = 0.6  },
  ["1density"] = { depth = {5,40},   offset = {0,1},    frequency = {0.1,0.6}, waveform = {"sine"}, chance = 0.6  },
  ["2density"] = { depth = {5,40},   offset = {0,1},    frequency = {0.1,0.6}, waveform = {"sine"}, chance = 0.6  },
  ["1volume"]  = { depth = {2,3},    offset = {0,1},    frequency = {0.1,0.5}, waveform = {"sine"}, chance = 1.0  },
  ["2volume"]  = { depth = {2,3},    offset = {0,1},    frequency = {0.1,0.5}, waveform = {"sine"}, chance = 1.0  },
  ["1seek"]    = { depth = {0,100},  offset = {0,1},    frequency = {0.1,0.6}, waveform = {"sine"}, chance = 0.3  },
  ["2seek"]    = { depth = {0,100},  offset = {0,1},    frequency = {0.1,0.6}, waveform = {"sine"}, chance = 0.3  },
  ["1speed"]   = { depth = {10,50},  offset = {-1,1},   frequency = {0.1,0.6}, waveform = {"sine"}, chance = 0.3  },
  ["2speed"]   = { depth = {10,50},  offset = {-1,1},   frequency = {0.1,0.6}, waveform = {"sine"}, chance = 0.3  },
  ["1pitch"]   = { depth = {5,30},   offset = {-1,1},   frequency = {0.1,0.6}, waveform = {"sine"}, chance = 0.0  },
  ["2pitch"]   = { depth = {5,30},   offset = {-1,1},   frequency = {0.1,0.6}, waveform = {"sine"}, chance = 0.0  },
}

local param_ranges = {
  ["1pan"]     = {-100,100}, ["2pan"]     = {-100,100},
  ["1seek"]    = {0,100},    ["2seek"]    = {0,100},
  ["1speed"]   = {-2,2},     ["2speed"]   = {-2,2},
  ["1jitter"]  = {0,99999},  ["2jitter"]  = {0,99999},
  ["1spread"]  = {0,100},    ["2spread"]  = {0,100},
  ["1size"]    = {20,599},   ["2size"]    = {20,599},
  ["1density"] = {1,30},     ["2density"] = {1,30},
  ["1volume"]  = {-70,10},   ["2volume"]  = {-70,10},
  ["1pitch"]   = {-48,48},   ["2pitch"]   = {-48,48},
  ["1cutoff"]  = {20,20000}, ["2cutoff"]  = {20,20000},
  ["1hpf"]     = {20,20000}, ["2hpf"]     = {20,20000},
}

function lfo.get_parameter_range(param_name)
  if param_name:match("jitter$") then
    return 0, pget(param_name:sub(1,1) .. "max_jitter") or 4999
  end
  local r = param_ranges[param_name]
  if r then return r[1], r[2] end
  return 0, 100
end

function lfo.clear_range_cache() end

function lfo.scale(v, old_min, old_max, new_min, new_max)
  return (v - old_min) * (new_max - new_min) / (old_max - old_min) + new_min
end

function lfo.clearLFOs(track, param_type)
  local function matches(target)
    if track and param_type then return target == track .. param_type
    elseif track then return target:match("^" .. track)
    else return true end
  end

  for target in pairs(assigned_params) do
    if matches(target) then assigned_params[target] = nil end
  end

  for i = 1, number_of_outputs do
    if params.lookup[LFO_KEYS[i]] and params.lookup[TARGET_KEYS[i]] then
      local target = lfo.lfo_targets[pget(TARGET_KEYS[i])]
      if target and matches(target) then
        local tn, pn = target:sub(1,1), target:sub(2)
        if not lfo.is_param_locked(tn, pn) then
          pset(LFO_KEYS[i], 1)
          pset(TARGET_KEYS[i], 1)
          lfo[i].sync_to = nil
        end
      end
    end
  end

  if not track and not param_type then
    if is_audio_loaded("1") and is_audio_loaded("2") then
      pset("1pan", -25); pset("2pan", 25)
    else
      pset("1pan", 0); pset("2pan", 0)
    end
  end
end

local function randomize_lfo(i, target)
  if assigned_params[target] or not lfo.target_ranges[target] then return end
  if target:match("seek$") and pget(target:sub(1,1) .. "granular_gain") < 100 then return end

  for j = 1, number_of_outputs do
    if j ~= i and params.lookup[LFO_KEYS[j]] and pget(LFO_KEYS[j]) == 2
       and lfo.lfo_targets[pget(TARGET_KEYS[j])] == target then return end
  end

  local target_index = LFO_TARGET_REVERSE[target]
  if not target_index then return end

  local ranges   = lfo.target_ranges[target]
  local min_val, max_val = lfo.get_parameter_range(target)
  local cur_val  = pget(target) or min_val
  local is_pan   = target:match("pan$")
  local is_seek  = target:match("seek$")

  local offset
  if is_pan then
    offset = 0
  elseif is_seek then
    offset = (math.random() - 0.5)
  else
    offset = lfo.scale(cur_val, min_val, max_val, -1, 1)
  end

  local depth = math.random(ranges.depth[1], ranges.depth[2])

  local center    = lfo.scale(offset, -1, 1, min_val, max_val)
  local half_swing = (depth * 0.01) * (max_val - min_val) / 2
  center = util.clamp(center, min_val + half_swing, max_val - half_swing)
  offset = lfo.scale(center, min_val, max_val, -1, 1)

  lfo[i].depth  = depth
  lfo[i].offset = offset
  pset(DEPTH_KEYS[i],  depth)
  pset(OFFSET_KEYS[i], offset)

  local min_f = math.floor(ranges.frequency[1] * 100)
  local max_f = math.floor(ranges.frequency[2] * 100)
  local freq  = math.random(min_f, max_f) / 100
  lfo[i].freq = freq
  pset(FREQ_KEYS[i], freq)

  local wf    = ranges.waveform[math.random(#ranges.waveform)]
  lfo[i].waveform = wf
  for idx, name in ipairs(options.lfotypes) do
    if name == wf then pset(SHAPE_KEYS[i], idx) break end
  end

  pset(TARGET_KEYS[i], target_index)
  pset(LFO_KEYS[i], 2)
  assigned_params[target] = true
end

local function mirror_lfo(dst, src, is_pan)
  local obj_s, obj_d = lfo[src], lfo[dst]
  obj_d.freq         = obj_s.freq
  obj_d.waveform     = obj_s.waveform
  obj_d.depth        = obj_s.depth
  obj_d.walk_value   = obj_s.walk_value
  obj_d.walk_velocity= obj_s.walk_velocity
  obj_d.sync_to      = src
  if is_pan then
    obj_d.phase  = (obj_s.phase + 0.5) % 1.0
    obj_d.offset = -obj_s.offset
    pset(OFFSET_KEYS[dst], -pget(OFFSET_KEYS[src]))
  else
    obj_d.phase  = obj_s.phase
    obj_d.offset = obj_s.offset
    pset(OFFSET_KEYS[dst], pget(OFFSET_KEYS[src]))
  end
  pset(FREQ_KEYS[dst],  pget(FREQ_KEYS[src]))
  pset(SHAPE_KEYS[dst], pget(SHAPE_KEYS[src]))
  pset(DEPTH_KEYS[dst], pget(DEPTH_KEYS[src]))
end

local function free_slots()
  local slots = {}
  for i = 1, number_of_outputs do
    if params.lookup[LFO_KEYS[i]] and pget(LFO_KEYS[i]) == 1 then
      slots[#slots + 1] = i
    end
  end
  return slots
end

function lfo.assign_to_current_row(current_mode, current_filter_mode)
  local param_map = {
    seek = "seek", pan = "pan", jitter = "jitter",
    size = "size", density = "density", spread = "spread",
    speed = "speed", pitch = "pitch"
  }
  local param_name = param_map[current_mode]
  if not param_name then return end

  local symmetry = pget("symmetry") == 1
  lfo.clearLFOs("1", param_name)
  lfo.clearLFOs("2", param_name)

  local slots = free_slots()

  if symmetry and not lfo.is_param_locked("1", param_name)
              and not lfo.is_param_locked("2", param_name)
              and #slots >= 2 then
    local s1 = table.remove(slots, 1)
    local s2 = table.remove(slots, 1)
    randomize_lfo(s1, "1" .. param_name)
    randomize_lfo(s2, "2" .. param_name)
    mirror_lfo(s2, s1, param_name == "pan")
    return
  end

  if not lfo.is_param_locked("1", param_name) and #slots > 0 then
    randomize_lfo(table.remove(slots, 1), "1" .. param_name)
  end
  if not lfo.is_param_locked("2", param_name) and #slots > 0 then
    randomize_lfo(table.remove(slots, 1), "2" .. param_name)
  end
end

function lfo.assign_volume_lfos()
  lfo.clearLFOs("1", "volume")
  lfo.clearLFOs("2", "volume")
  local slots = free_slots()
  if #slots > 0 and not lfo.is_param_locked("1", "volume") then randomize_lfo(table.remove(slots, 1), "1volume") end
  if #slots > 0 and not lfo.is_param_locked("2", "volume") then randomize_lfo(table.remove(slots, 1), "2volume") end
end

function lfo.randomize_lfos(track, allow_volume_lfos)
  local symmetry = pget("symmetry") == 1

  for i = 1, number_of_outputs do
    if params.lookup[LFO_KEYS[i]] and params.lookup[TARGET_KEYS[i]] then
      local t_idx = pget(TARGET_KEYS[i])
      if t_idx and t_idx > 0 then
        local target = lfo.lfo_targets[t_idx]
        if target then
          local tn, pn = target:sub(1,1), target:sub(2)
          local should_clear = (symmetry and not target:match("volume$") and target:match("^[12]"))
                            or target:match("^" .. track)
          if should_clear and not lfo.is_param_locked(tn, pn) then
            pset(LFO_KEYS[i], 1)
            pset(TARGET_KEYS[i], 1)
            assigned_params[target] = nil
          end
        end
      end
    end
  end

  local candidates = {}
  for target, ranges in pairs(lfo.target_ranges) do
    local tn, pn = target:sub(1,1), target:sub(2)
    local ok = (symmetry and not target:match("volume$")) or target:match("^" .. track)
    if ok and not lfo.is_param_locked(tn, pn)
           and (not target:match("volume$") or allow_volume_lfos) then
      if target:match("seek$") then
        if pget(tn .. "granular_gain") >= 100 and math.random() < ranges.chance then
          candidates[#candidates + 1] = target
        end
      elseif math.random() < ranges.chance then
        candidates[#candidates + 1] = target
      end
    end
  end

  local slots = free_slots()
  local mirrored = {}

  while #candidates > 0 and #slots > 0 do
    local idx    = math.random(#candidates)
    local target = table.remove(candidates, idx)
    if not mirrored[target] then
      local slot = table.remove(slots, math.random(#slots))
      randomize_lfo(slot, target)
      if symmetry and not target:match("volume$") then
        local mirror_target = target:gsub("^(%d)(.*)", function(n, rest)
          return tostring((tonumber(n) % 2) + 1) .. rest
        end)
        if #slots > 0 then
          local slot2 = table.remove(slots, math.random(#slots))
          randomize_lfo(slot2, mirror_target)
          mirror_lfo(slot2, slot, target:match("pan$"))
          mirrored[mirror_target] = true
        end
      end
      mirrored[target] = true
    end
  end
end

function lfo.get_lfo_for_param(param_name)
  for i = 1, number_of_outputs do
    if params.lookup[LFO_KEYS[i]] and pget(LFO_KEYS[i]) == 2 then
      if lfo.lfo_targets[pget(TARGET_KEYS[i])] == param_name then return i end
    end
  end
end

function lfo.process()
  if lfo_paused or not params.lookup then return end

  local targets  = lfo.lfo_targets
  local get_range = lfo.get_parameter_range

  for i = 1, number_of_outputs do
    if params:get(LFO_KEYS[i]) ~= 2 then goto continue end

    local obj = lfo[i]

    obj.phase = (obj.phase + obj.freq * PHASE_INCREMENT) % 1.0

    local slope
    local wf = obj.waveform

    if wf == "sine" then
      slope = math.sin(obj.phase * TWO_PI)

    elseif wf == "square" then
      slope = obj.phase < 0.5 and 1 or -1

    elseif wf == "random" then
      local prev_phase = (obj.phase - obj.freq * PHASE_INCREMENT) % 1.0
      if prev_phase > obj.phase then obj.prev = math.random() * 2 - 1 end
      slope = obj.prev

    elseif wf == "walk" then
      local src = obj.sync_to and lfo[obj.sync_to]
      if src then
        obj.walk_value    = src.walk_value
        obj.walk_velocity = src.walk_velocity
        obj.prev          = src.prev
      else
        local vel = obj.walk_velocity * 0.92 + (math.random() - 0.5) * (obj.freq * 0.4)
        local val = obj.walk_value + vel
        if     val >  0.75 then vel = vel - (val - 0.75) * 0.1
        elseif val < -0.75 then vel = vel - (val + 0.75) * 0.1 end
        val = util.clamp(val, -1, 1)
        obj.walk_velocity = vel
        obj.walk_value    = val
        obj.prev          = obj.prev * 0.80 + val * 0.20
      end
      slope = obj.prev

    else
      slope = 0
    end

    local mod = util.clamp(slope, -1, 1) * (obj.depth * 0.01) + obj.offset
    obj.slope = mod

    local t_idx = params:get(TARGET_KEYS[i])
    local target = t_idx and targets[t_idx]

    if target and target ~= "none" and params.lookup[target] then
      local mn, mx = get_range(target)
      local value  = util.clamp(lfo.scale(mod, -1, 1, mn, mx), mn, mx)
      if target:sub(-5) == "pitch" then
        local scale = params:string("pitch_quantize_scale")
        if scale then value = quantize_pitch_to_scale(value, scale) end
      end
      if params:get(target) ~= value then params:set(target, value) end
    else
      params:set(LFO_KEYS[i], 1)
      if lfo.on_state_change then lfo.on_state_change() end
    end

    ::continue::
  end
end

local lfo_metro = nil

function lfo.init()
  for i = 1, number_of_outputs do
    params:add_separator("LFO " .. i)
    params:add_option(LFO_KEYS[i],    i .. " LFO",    { "off", "on" }, 1)
    params:set_action(LFO_KEYS[i],    function() if lfo.on_state_change then lfo.on_state_change() end end)
    params:add_option(TARGET_KEYS[i], i .. " target",  lfo.lfo_targets, 1)
    params:set_action(TARGET_KEYS[i], function() if lfo.on_state_change then lfo.on_state_change() end end)
    params:add_option(SHAPE_KEYS[i],  i .. " shape",   options.lfotypes, 1)
    params:set_action(SHAPE_KEYS[i],  function(v) lfo[i].waveform = options.lfotypes[v] end)
    params:add_number(DEPTH_KEYS[i],  i .. " depth",   0, 100, 50)
    params:set_action(DEPTH_KEYS[i],  function(v) lfo[i].depth = v end)
    params:add_control(OFFSET_KEYS[i], i .. " offset", controlspec.new(-0.99, 0.99, "lin", 0.01, 0, ""))
    params:set_action(OFFSET_KEYS[i], function(v) lfo[i].offset = v end)
    params:add_control(FREQ_KEYS[i],  i .. " freq",    controlspec.new(0.01, 2.00, "lin", 0.01, 0.05, ""))
    params:set_action(FREQ_KEYS[i],   function(v) lfo[i].freq = v * params:get("global_lfo_freq_scale") end)
  end

  lfo_metro = metro.init()
  lfo_metro.time  = PHASE_INCREMENT
  lfo_metro.count = -1
  lfo_metro.event = lfo.process
  lfo_metro:start()
end

function lfo.cleanup()
  if lfo_metro then
    pcall(function() lfo_metro:stop() end)
    lfo_metro.event = nil
    lfo_metro = nil
  end
end

return lfo