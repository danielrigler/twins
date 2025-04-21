local number_of_outputs = 16
local tau = math.pi * 2

local options = {
  lfotypes = { "sine", "random", "square" }
}

local lfo = {}
local assigned_params = {}

local function is_locked(target)
  local track, param = string.match(target, "(%d)(%a+)")
  local lockable_params = { "jitter", "size", "density", "spread", "pitch", "pan", "seek", "speed" }
  if table.find(lockable_params, param) then
    return params:get(track .. "lock_" .. param) == 2
  end
  return false
end

function lfo.is_param_locked(track, param_name)
    return params:get(track.."lock_"..param_name) == 2
end

for i = 1, number_of_outputs do
  lfo[i] = { 
    freq = 0.05, 
    base_freq = 0.05, 
    phase = 0,
    waveform = options.lfotypes[1], 
    slope = 0, 
    depth = 50, 
    offset = 0,
    prev = 0,
    prev_polarity = 1
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

function lfo.clearLFOs(track, param_type)
    local function clear_targets(target_filter)
        for target, _ in pairs(assigned_params) do
            if target_filter(target) and not is_locked(target) then
                assigned_params[target] = nil
            end
        end
        for i = 1, 16 do
            local target_index = params:get(i .. "lfo_target")
            local target_param = lfo.lfo_targets[target_index]
            if target_param and target_filter(target_param) and not is_locked(target_param) then
                params:set(i .. "lfo", 1)
                params:set(i .. "lfo_target", 1)
            end
        end
    end
    local function reset_pan()
        local track1_loaded = is_audio_loaded("1")
        local track2_loaded = is_audio_loaded("2")
        if track1_loaded and track2_loaded then
            params:set("1pan", -15)
            params:set("2pan", 15)
        else
            params:set("1pan", 0)
            params:set("2pan", 0)
        end
    end
    if track and param_type then
        clear_targets(function(target) 
            return string.match(target, "^"..track..param_type.."$")
        end)
    elseif track then
        clear_targets(function(target) 
            return string.match(target, "^"..track) 
        end)
    else
        clear_targets(function() return true end)
    end
    if not param_type then
        reset_pan()
    end
end

lfo.lfo_targets = {
  "none", "1pan", "2pan", "1seek", "2seek", "1jitter", "2jitter", 
  "1spread", "2spread", "1size", "2size", "1density", "2density", "1volume", "2volume", 
  "1pitch", "2pitch", "1cutoff", "2cutoff", "1hpf", "2hpf", "1speed", "2speed"
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
  ["1seek"] = { depth = { 30, 60 }, offset = { 0, 0 }, frequency = { 0.05, 0.3 }, waveform = { "sine", "random" }, chance = 0.4 },
  ["2seek"] = { depth = { 30, 60 }, offset = { 0, 0 }, frequency = { 0.05, 0.3 }, waveform = { "sine", "random" }, chance = 0.4 },
  ["1speed"] = { depth = { 5, 100 }, offset = { -1, 1 }, frequency = { 0.02, 0.1 }, waveform = { "sine" }, chance = 0.1 },
  ["2speed"] = { depth = { 5, 100 }, offset = { -1, 1 }, frequency = { 0.02, 0.1 }, waveform = { "sine" }, chance = 0.1 }
}

function lfo.get_parameter_range(param_name)
  local param_ranges = {
    ["1pan"] = { -100, 100 }, ["2pan"] = { -100, 100 },
    ["1seek"] = { 0, 100 }, ["2seek"] = { 0, 100 },
    ["1speed"] = { -2, 2 }, ["2speed"] = { -2, 2 },
    ["1jitter"] = { 1, 1999 }, ["2jitter"] = { 1, 1999 },
    ["1spread"] = { 0, 100 }, ["2spread"] = { 0, 100 },
    ["1size"] = { 0, 599 }, ["2size"] = { 0, 599 },
    ["1density"] = { 0, 20 }, ["2density"] = { 0, 20 },
    ["1volume"] = { -100, 100 }, ["2volume"] = { -100, 100 },
    ["1pitch"] = { -12, 12 }, ["2pitch"] = { -12, 12 },
    ["1cutoff"] = { 20, 20000 }, ["2cutoff"] = { 20, 20000 },
    ["1hpf"] = { 20, 20000 }, ["2hpf"] = { 20, 20000 }
  }
  return param_ranges[param_name][1], param_ranges[param_name][2]
end

function lfo.assign_to_current_row(current_mode, current_filter_mode)
    local param_map = {
        seek = "seek",
        pan = "pan",
        jitter = "jitter",
        size = "size",
        density = "density",
        spread = "spread",
        speed = "speed"
    }
    local param_name = param_map[current_mode]
    if not param_name then return end

    lfo.clearLFOs("1", param_name)
    lfo.clearLFOs("2", param_name)
    local available_slots = {}
    for i = 1, 16 do
        if params:get(i.."lfo") == 1 then
            table.insert(available_slots, i)
        end
    end
    if not lfo.is_param_locked("1", param_name) and #available_slots > 0 then
        local slot = table.remove(available_slots, 1)
        randomize_lfo(slot, "1"..param_name)
    end
    if not lfo.is_param_locked("2", param_name) and #available_slots > 0 then
        local slot = table.remove(available_slots, 1)
        randomize_lfo(slot, "2"..param_name)
    end
end

function randomize_lfo(i, target)
    if assigned_params[target] or not lfo.target_ranges[target] then return end
    if target:match("seek$") and params:get(target:sub(1,1).."granular_gain") < 100 then
        return
    end
    for j = 1, number_of_outputs do
        if j ~= i and params:get(j.."lfo") == 2 and lfo.lfo_targets[params:get(j.."lfo_target")] == target then
            return
        end
    end
    local target_index = table.find(lfo.lfo_targets, target)
    if not target_index then return end
    local min_val, max_val = lfo.get_parameter_range(target)
    local current_val = params:get(target)
    params:set(i.."lfo_target", target_index)
    local is_pan, is_seek = target:match("pan$"), target:match("seek$")
    lfo[i].offset = is_pan and 0 or (is_seek and (math.random() - 0.5) or lfo.scale(current_val, min_val, max_val, -1, 1))
    params:set(i.."offset", lfo[i].offset)
    local ranges = lfo.target_ranges[target]
    local max_allowed = math.min(max_val - current_val, current_val - min_val)
    local scaled_max = lfo.scale(max_allowed, 0, max_val - min_val, 0, 100)
    lfo[i].depth = math.min(math.random(ranges.depth[1], ranges.depth[2]), math.floor(scaled_max))
    if lfo[i].depth == 0 then
        lfo[i].depth = math.random(ranges.depth[1], ranges.depth[2])
    end
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

function lfo.randomize_lfos(track, allow_volume_lfos)
    local other_track = track == "1" and "2" or "1"
    local track_pattern = "^"..track
    for i = 1, 16 do
        local target_param = lfo.lfo_targets[params:get(i.."lfo_target")]
        if target_param and target_param:match(track_pattern) and not is_locked(target_param) then
            params:set(i.."lfo", 1)
            params:set(i.."lfo_target", 1)
            assigned_params[target_param] = nil
        end
    end
    local available_targets = {}
    for target, ranges in pairs(lfo.target_ranges) do
        if (not target:match("volume$") or allow_volume_lfos) and target:match(track_pattern) and not is_locked(target) then
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
    local other_pattern = "^"..other_track
    for j = 1, 16 do
        local target_param = lfo.lfo_targets[params:get(j.."lfo_target")]
        if (not target_param or not target_param:match(other_pattern)) and not is_locked(target_param) then
            table.insert(free_slots, j)
        end
    end
    for _, target in ipairs(available_targets) do
        if #free_slots > 0 then
            randomize_lfo(table.remove(free_slots, math.random(#free_slots)), target)
        end
    end
end

function lfo.process()
    for i = 1, 16 do
        if params:get(i.."lfo") == 2 then
            lfo[i].phase = (lfo[i].phase + lfo[i].freq * (1/30)) % 1.0
            local slope
            local wf = lfo[i].waveform
            if wf == "sine" then
                slope = math.sin(lfo[i].phase * math.pi * 2)
            elseif wf == "square" then
                slope = lfo[i].phase < 0.5 and 1 or -1
            elseif wf == "random" then
                local phase_inc = lfo[i].freq * (1/30)
                if (lfo[i].phase - phase_inc) % 1.0 > lfo[i].phase then
                    lfo[i].prev = math.random() * (math.random(2) - 1)  -- -1 or 1
                end
                lfo[i].prev = lfo[i].prev or 0
                slope = lfo[i].prev
            end
            lfo[i].slope = util.clamp(slope, -1.0, 1.0) * (lfo[i].depth * 0.01) + lfo[i].offset
            local target_index = params:get(i.."lfo_target")
            if target_index and lfo.lfo_targets[target_index] then
                local target_param = lfo.lfo_targets[target_index]
                local min_val, max_val = lfo.get_parameter_range(target_param)
                local modulated_value = lfo.scale(lfo[i].slope, -1.0, 1.0, min_val, max_val)
                modulated_value = util.clamp(modulated_value, min_val, max_val)
                params:set(target_param, modulated_value)
            end
        end
    end
end

function lfo.scale(old_value, old_min, old_max, new_min, new_max)
    local old_range = old_max - old_min
    return (old_value - old_min) * (new_max - new_min) / old_range + new_min
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

function lfo.cleanup()
  if lfo_metro then
    lfo_metro:stop()
  end
end

return lfo