local number_of_outputs = 16

local options = {
  lfotypes = { "sine", "random", "square" }
}

local lfo = {}
local assigned_params = {}
local lfo_paused = false

-- Helper to check param existence before accessing
local function param_exists(name)
    return params.lookup and params.lookup[name] ~= nil
end

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

function lfo.set_pause(paused)
    lfo_paused = paused
end

for i = 1, number_of_outputs do
  lfo[i] = { 
    freq = 0.05, 
    phase = 0,
    waveform = options.lfotypes[1], 
    slope = 0, 
    depth = 50, 
    offset = 0,
    prev = 0,
    prev_polarity = 1
  }
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
            local lfo_param = i.."lfo"
            local lfo_target_param = i.."lfo_target"
            if param_exists(lfo_param) and param_exists(lfo_target_param) then
                local target_index = params:get(lfo_target_param)
                local target_param = lfo.lfo_targets[target_index]
                if target_param and target_filter(target_param) and not is_locked(target_param) then
                    params:set(lfo_param, 1)
                    params:set(lfo_target_param, 1)
                end
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
    if not track and not param_type then
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
  ["1jitter"] = { depth = { 20, 100 }, offset = { 0, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5 },
  ["2jitter"] = { depth = { 20, 100 }, offset = { 0, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5 },
  ["1spread"] = { depth = { 20, 100 }, offset = { 0, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5 },
  ["2spread"] = { depth = { 20, 100 }, offset = { 0, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5},
  ["1size"] = { depth = { 10, 100 }, offset = { 0, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5 },
  ["2size"] = { depth = { 10, 100 }, offset = { 0, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5 },
  ["1density"] = { depth = { 10, 100 }, offset = { 0, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5 },
  ["2density"] = { depth = { 10, 100 }, offset = { 0, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.5 },
  ["1volume"] = { depth = { 2, 3 }, offset = { 0, 1 }, frequency = { 0.1, 0.5 }, waveform = { "sine" }, chance = 1.0 },
  ["2volume"] = { depth = { 2, 3 }, offset = { 0, 1 }, frequency = { 0.1, 0.5 }, waveform = { "sine" }, chance = 1.0 },
  ["1seek"] = { depth = { 50, 100 }, offset = { 0, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.3 },
  ["2seek"] = { depth = { 50, 100 }, offset = { 0, 1 }, frequency = { 0.05, 0.3 }, waveform = { "sine" }, chance = 0.3 },
  ["1speed"] = { depth = { 50, 100 }, offset = { -1, 1 }, frequency = { 0.02, 0.5 }, waveform = { "sine" }, chance = 0.2 },
  ["2speed"] = { depth = { 50, 100 }, offset = { -1, 1 }, frequency = { 0.02, 0.5 }, waveform = { "sine" }, chance = 0.2 }
}

function lfo.get_parameter_range(param_name)
  local param_ranges = {
    ["1pan"] = { -90, 90 }, ["2pan"] = { -90, 90 },
    ["1seek"] = { 0.01, 0.99 }, ["2seek"] = { 0.01, 0.99 },
    ["1speed"] = { -0.14, 0.49 }, ["2speed"] = { -0.14, 0.49 },
    ["1jitter"] = { 101, 998 }, ["2jitter"] = { 101, 998 },
    ["1spread"] = { 0, 100 }, ["2spread"] = { 0, 100 },
    ["1size"] = { 101, 499 }, ["2size"] = { 101, 499 },
    ["1density"] = { 0, 29 }, ["2density"] = { 0, 29 },
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

    local symmetry = params:get("symmetry") == 1
    
    -- Clear existing LFOs for this parameter
    lfo.clearLFOs("1", param_name)
    lfo.clearLFOs("2", param_name)
    
    -- Get available LFO slots
    local available_slots = {}
    for i = 1, 16 do
        local lfo_param = i.."lfo"
        if param_exists(lfo_param) and params:get(lfo_param) == 1 then
            table.insert(available_slots, i)
        end
    end
    
    -- Assign LFOs with symmetry handling
    if symmetry then
        -- Try to assign to both voices with phase relationship
        if not lfo.is_param_locked("1", param_name) and 
           not lfo.is_param_locked("2", param_name) and 
           #available_slots >= 2 then
            
            local slot1 = table.remove(available_slots, 1)
            local slot2 = table.remove(available_slots, 1)
            
            -- Assign to voice 1
            randomize_lfo(slot1, "1"..param_name)
            
            -- Assign to voice 2 with mirrored settings
            randomize_lfo(slot2, "2"..param_name)
            
            -- Sync settings between voices
            lfo[slot2].freq = lfo[slot1].freq
            lfo[slot2].waveform = lfo[slot1].waveform
            lfo[slot2].depth = lfo[slot1].depth
            
            -- Special phase handling for pan (invert phase)
            if param_name == "pan" then
                lfo[slot2].phase = (lfo[slot1].phase + 0.5) % 1.0  -- 180° phase shift
                lfo[slot2].offset = -lfo[slot1].offset  -- Invert offset
                params:set(slot2.."offset", -params:get(slot1.."offset"))
            else
                -- For other parameters, keep identical phase
                lfo[slot2].phase = lfo[slot1].phase
                lfo[slot2].offset = lfo[slot1].offset
                params:set(slot2.."offset", params:get(slot1.."offset"))
            end
            
            -- Update other parameters
            params:set(slot2.."lfo_freq", params:get(slot1.."lfo_freq"))
            params:set(slot2.."lfo_shape", params:get(slot1.."lfo_shape"))
            params:set(slot2.."lfo_depth", params:get(slot1.."lfo_depth"))
            
            return  -- Done with symmetry assignment
        end
    end
    
    -- Fallback to individual assignments if symmetry isn't enabled or couldn't be applied
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
        local lfo_param = j.."lfo"
        local lfo_target_param = j.."lfo_target"
        if j ~= i and param_exists(lfo_param) and param_exists(lfo_target_param) and params:get(lfo_param) == 2 and lfo.lfo_targets[params:get(lfo_target_param)] == target then
            return
        end
    end
    local target_index = table.find(lfo.lfo_targets, target)
    if not target_index then return end
    local min_val, max_val = lfo.get_parameter_range(target)
    local current_val = params:get(target)
    local lfo_target_param = i.."lfo_target"
    if param_exists(lfo_target_param) then
        params:set(lfo_target_param, target_index)
    end
    local is_pan, is_seek = target:match("pan$"), target:match("seek$")
    lfo[i].offset = is_pan and 0 or (is_seek and (math.random() - 0.5) or lfo.scale(current_val, min_val, max_val, -1, 1))
    if param_exists(i.."offset") then
        params:set(i.."offset", lfo[i].offset)
    end
    local ranges = lfo.target_ranges[target]
    local max_allowed = math.min(max_val - current_val, current_val - min_val)
    local scaled_max = lfo.scale(max_allowed, 0, max_val - min_val, 0, 100)
    lfo[i].depth = math.min(math.random(ranges.depth[1], ranges.depth[2]), math.floor(scaled_max))
    if lfo[i].depth == 0 then
        lfo[i].depth = math.random(ranges.depth[1], ranges.depth[2])
    end
    if param_exists(i.."lfo_depth") then
        params:set(i.."lfo_depth", lfo[i].depth)
    end
    if ranges.frequency then
        local min_f, max_f = ranges.frequency[1] * 100, ranges.frequency[2] * 100
        if min_f <= max_f then
            lfo[i].freq = math.random(min_f, max_f) / 100
            if param_exists(i.."lfo_freq") then
                params:set(i.."lfo_freq", lfo[i].freq)
            end
        end
    end
    if ranges.waveform then
        local wf_index = math.random(#ranges.waveform)
        lfo[i].waveform = ranges.waveform[wf_index]
        if param_exists(i.."lfo_shape") then
            params:set(i.."lfo_shape", wf_index)
        end
    end
    if param_exists(i.."lfo") then
        params:set(i.."lfo", 2)
    end
    assigned_params[target] = true
end

function lfo.randomize_lfos(track, allow_volume_lfos)
    local other_track = track == "1" and "2" or "1"
    local symmetry = params:get("symmetry") == 1
    if math.random() <= 0.5 then params:set("global_lfo_freq_scale", 0.75) else params:set("global_lfo_freq_scale", 0.1 + math.random() * (1.8 - 0.1)) end
    
    -- Clear existing LFOs for both tracks in symmetry mode
    for i = 1, 16 do
        local lfo_param = i.."lfo"
        local lfo_target_param = i.."lfo_target"
        if param_exists(lfo_param) and param_exists(lfo_target_param) then
            local target_param = lfo.lfo_targets[params:get(lfo_target_param)]
            if target_param then
                local should_clear = false
                if symmetry and not target_param:match("volume$") then
                    should_clear = target_param:match("^[12]")
                else
                    should_clear = target_param:match("^"..track)
                end
                
                if should_clear and not is_locked(target_param) then
                    params:set(lfo_param, 1)
                    params:set(lfo_target_param, 1)
                    assigned_params[target_param] = nil
                end
            end
        end
    end

    -- Find available targets
    local available_targets = {}
    for target, ranges in pairs(lfo.target_ranges) do
        if (symmetry and not target:match("volume$")) or target:match("^"..track) then
            if not is_locked(target) and (not target:match("volume$") or allow_volume_lfos) then
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
    end

    -- Find free slots
    local free_slots = {}
    for j = 1, 16 do
        local lfo_param = j.."lfo"
        if param_exists(lfo_param) and params:get(lfo_param) == 1 then
            table.insert(free_slots, j)
        end
    end

    -- Assign LFOs with mirroring
    local mirrored_pairs = {}
    for _, target in ipairs(available_targets) do
        if #free_slots >= (symmetry and 2 or 1) and not mirrored_pairs[target] then
            -- Assign primary LFO
            local slot1 = table.remove(free_slots, math.random(#free_slots))
            randomize_lfo(slot1, target)
            
            if symmetry and not target:match("volume$") then
                -- Find mirrored parameter
                local mirrored_target = target:gsub("^(%d)(.*)", function(num, rest)
                    return (tonumber(num) % 2) + 1 .. rest
                end)
                
                -- Find slot for mirrored LFO
                if #free_slots > 0 then
                    local slot2 = table.remove(free_slots, math.random(#free_slots))
                    randomize_lfo(slot2, mirrored_target)
                    
                    -- Mirror LFO settings
                    lfo[slot2].freq = lfo[slot1].freq
                    lfo[slot2].waveform = lfo[slot1].waveform
                    lfo[slot2].depth = lfo[slot1].depth
                    
                    -- Special handling for pan
                    if target:match("pan$") then
                        -- Invert phase by 180 degrees (0.5 in 0-1 range)
                        lfo[slot2].phase = (lfo[slot1].phase + 0.5) % 1.0
                        -- Invert offset
                        lfo[slot2].offset = -lfo[slot1].offset
                        if param_exists(slot2.."offset") and param_exists(slot1.."offset") then
                            params:set(slot2.."offset", -params:get(slot1.."offset"))
                        end
                    else
                        -- Keep phase and offset identical
                        lfo[slot2].phase = lfo[slot1].phase
                        lfo[slot2].offset = lfo[slot1].offset
                        if param_exists(slot2.."offset") and param_exists(slot1.."offset") then
                            params:set(slot2.."offset", params:get(slot1.."offset"))
                        end
                    end
                    
                    -- Update other parameters
                    if param_exists(slot2.."lfo_freq") and param_exists(slot1.."lfo_freq") then
                        params:set(slot2.."lfo_freq", params:get(slot1.."lfo_freq"))
                    end
                    if param_exists(slot2.."lfo_shape") and param_exists(slot1.."lfo_shape") then
                        params:set(slot2.."lfo_shape", params:get(slot1.."lfo_shape"))
                    end
                    if param_exists(slot2.."lfo_depth") and param_exists(slot1.."lfo_depth") then
                        params:set(slot2.."lfo_depth", params:get(slot1.."lfo_depth"))
                    end
                    mirrored_pairs[mirrored_target] = true
                end
            end
            mirrored_pairs[target] = true
        end
    end
end

function lfo.process()
    if lfo_paused then
        -- When paused, only process volume LFO offsets
        for i = 1, 16 do
            local lfo_target_param = i.."lfo_target"
            local lfo_param = i.."lfo"
            if param_exists(lfo_target_param) and param_exists(lfo_param) and params:get(lfo_target_param) and params:get(lfo_param) == 2 then
                local target_param = lfo.lfo_targets[params:get(lfo_target_param)]
                if target_param and (target_param == "1volume" or target_param == "2volume") then
                    local min_val, max_val = lfo.get_parameter_range(target_param)
                    local offset_param = i.."offset"
                    local modulated_value = lfo.scale(param_exists(offset_param) and params:get(offset_param) or 0, -1.0, 1.0, min_val, max_val)
                    if param_exists(target_param) then
                        params:set(target_param, modulated_value)
                    end
                end
            end
        end
        return
    end
    
    for i = 1, 16 do
        local lfo_param = i.."lfo"
        local lfo_target_param = i.."lfo_target"
        if param_exists(lfo_param) and param_exists(lfo_target_param) and params:get(lfo_param) == 2 and params:get(lfo_target_param) then
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
                    lfo[i].prev = math.random() * (math.random(0, 1))  -- -1 or 1
                end
                slope = lfo[i].prev
            end
            lfo[i].slope = util.clamp(slope, -1.0, 1.0) * (lfo[i].depth * 0.01) + lfo[i].offset
            local target_index = params:get(lfo_target_param)
            if target_index and lfo.lfo_targets[target_index] then
                local target_param = lfo.lfo_targets[target_index]
                local min_val, max_val = lfo.get_parameter_range(target_param)
                local modulated_value = lfo.scale(lfo[i].slope, -1.0, 1.0, min_val, max_val)
                modulated_value = util.clamp(modulated_value, min_val, max_val)
                if param_exists(target_param) then
                    params:set(target_param, modulated_value)
                end
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
      lfo[i].freq = value * params:get("global_lfo_freq_scale")
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
  lfo_paused = false
  if lfo_metro then
    lfo_metro:stop()
  end
end

return lfo