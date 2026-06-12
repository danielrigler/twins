local number_of_outputs = 16
local options = {lfotypes = {"sine", "random", "square", "walk"}}
local LFO_SHAPE_REVERSE = {}
for i, name in ipairs(options.lfotypes) do LFO_SHAPE_REVERSE[name] = i end

local lfo = {}
local assigned_params = {}
local lfo_paused = false
local saved_shapes = {}

lfo.sine_all = false
lfo.on_state_change = nil

local TWO_PI = math.pi * 2
local PHASE_INCREMENT = 1 / 30
local math_sin = math.sin
local math_random = math.random
local util_clamp = util.clamp

local LFO_KEYS, TARGET_KEYS, SHAPE_KEYS, FREQ_KEYS, DEPTH_KEYS, OFFSET_KEYS = {}, {}, {}, {}, {}, {}
for i = 1, number_of_outputs do
    LFO_KEYS[i] = i .. "lfo"
    TARGET_KEYS[i] = i .. "lfo_target"
    SHAPE_KEYS[i] = i .. "lfo_shape"
    FREQ_KEYS[i] = i .. "lfo_freq"
    DEPTH_KEYS[i] = i .. "lfo_depth"
    OFFSET_KEYS[i] = i .. "offset"
end
lfo.keys = {lfo = LFO_KEYS, target = TARGET_KEYS, shape = SHAPE_KEYS, freq = FREQ_KEYS, depth = DEPTH_KEYS, offset = OFFSET_KEYS}

local MusicUtil = require("musicutil")
local scale_array_cache = {}
local snap_lut_cache = {}

local function normalize_scale_name(name)
    if name == "none" or name == "off" then return "none" end
    local map = {["major pent."] = "major pentatonic", ["minor pent."] = "minor pentatonic"}
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
    local lut = snap_lut_cache[scale_name]
    if not lut then lut = {} snap_lut_cache[scale_name] = lut end
    local key = math.floor((60 + value) * 4 + 0.5)
    local out = lut[key]
    if out == nil then
        out = MusicUtil.snap_note_to_array(key * 0.25, arr) - 60
        lut[key] = out
    end
    return out
end

lfo.scale_utils = {normalize = normalize_scale_name, get_array = get_scale_array, quantize = quantize_pitch_to_scale}

local function pget(k)
    if params and params.lookup and params.lookup[k] then return params:get(k) end
    return nil
end

local function pset(k, v)
    if params and params.lookup and params.lookup[k] then params:set(k, v) end
end

function lfo.is_param_locked(track, param_name)
    local key = track .. "lock_" .. param_name
    return params.lookup[key] and pget(key) == 2
end

function lfo.set_pause(paused) lfo_paused = paused end

function lfo.set_sine_all(enabled)
    lfo.sine_all = enabled
    if enabled then
        saved_shapes = {}
        for i = 1, number_of_outputs do
            if params.lookup and params.lookup[LFO_KEYS[i]] and pget(LFO_KEYS[i]) == 2 then
                saved_shapes[i] = pget(SHAPE_KEYS[i])
                pset(SHAPE_KEYS[i], 1)
                lfo[i].shape_int = 1
            end
        end
    else
        for i, shape_idx in pairs(saved_shapes) do
            if params.lookup and params.lookup[SHAPE_KEYS[i]] then
                pset(SHAPE_KEYS[i], shape_idx)
                lfo[i].shape_int = shape_idx
            end
        end
        saved_shapes = {}
    end
end

for i = 1, number_of_outputs do
    lfo[i] = {freq = 0.05, phase = 0, waveform = "walk", shape_int = 4, slope = 0, depth = 50, offset = 0, prev = 0, walk_value = 0, walk_velocity = 0, sync_to = nil, sync_invert = false, active = false, target_idx = 1, target_name = "none", is_pitch = false, is_jitter = false, is_size = false, track_num = "1", last_val = nil}
end

local active_lfos = {}
local function update_active_lfos()
    local count = 0
    for i = 1, number_of_outputs do
        if lfo[i].active and lfo[i].target_name and lfo[i].target_name ~= "none" then
            count = count + 1
            active_lfos[count] = i
        end
    end
    for i = count + 1, #active_lfos do active_lfos[i] = nil end
end

local function classify_target(i, target_idx)
    local obj = lfo[i]
    obj.target_idx = target_idx
    local tname = lfo.lfo_targets[target_idx]
    obj.target_name = tname
    obj.pobj = nil
    obj.last_val = nil
    if tname and tname ~= "none" then
        obj.is_pitch  = (tname:sub(-5) == "pitch")
        obj.is_jitter = (tname:sub(-6) == "jitter")
        obj.is_size   = (tname:sub(-4) == "size")
        obj.track_num = tname:sub(1, 1)
    else
        obj.is_pitch, obj.is_jitter, obj.is_size, obj.track_num = false, false, false, "1"
    end
end

local function is_audio_loaded(track)
    local p = pget(track .. "sample")
    return p and p ~= "" and p ~= "none" and p ~= "-"
end

function lfo.is_param_assigned(name) return assigned_params[name] == true end
function lfo.mark_param_assigned(name) if name then assigned_params[name] = true end end
function lfo.clear_param_assignment(name) if name then assigned_params[name] = nil end end

lfo.lfo_targets = {"none", "1pan", "2pan", "1seek", "2seek", "1jitter", "2jitter", "1spread", "2spread", "1size", "2size", "1density", "2density", "1volume", "2volume", "1pitch", "2pitch", "1cutoff", "2hpf", "1speed", "2speed"}
local LFO_TARGET_REVERSE = {}
for i, t in ipairs(lfo.lfo_targets) do LFO_TARGET_REVERSE[t] = i end

lfo.target_ranges = {
    ["1pan"] = {depth = {25, 90}, offset = {0, 0}, frequency = {0.1, 1}, waveform = {"walk"}, chance = 0.75},
    ["2pan"] = {depth = {25, 90}, offset = {0, 0}, frequency = {0.1, 1}, waveform = {"walk"}, chance = 0.75},
    ["1jitter"] = {depth = {20, 70}, offset = {-1, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.7},
    ["2jitter"] = {depth = {20, 70}, offset = {-1, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.7},
    ["1spread"] = {depth = {10, 30}, offset = {0, 0.3}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.7},
    ["2spread"] = {depth = {10, 30}, offset = {0, 0.3}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.7},
    ["1size"] = {depth = {5, 30}, offset = {0.1, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.7},
    ["2size"] = {depth = {5, 30}, offset = {0.1, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.7},
    ["1density"] = {depth = {5, 40}, offset = {0, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.7},
    ["2density"] = {depth = {5, 40}, offset = {0, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.7},
    ["1volume"] = {depth = {2, 3}, offset = {0, 1}, frequency = {0.1, 0.5}, waveform = {"walk"}, chance = 1.0},
    ["2volume"] = {depth = {2, 3}, offset = {0, 1}, frequency = {0.1, 0.5}, waveform = {"walk"}, chance = 1.0},
    ["1seek"] = {depth = {0, 100}, offset = {0, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.3},
    ["2seek"] = {depth = {0, 100}, offset = {0, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.3},
    ["1speed"] = {depth = {10, 50}, offset = {-1, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.3},
    ["2speed"] = {depth = {10, 50}, offset = {-1, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.3},
    ["1pitch"] = {depth = {5, 30}, offset = {-1, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.0},
    ["2pitch"] = {depth = {5, 30}, offset = {-1, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.0},
}

local param_ranges = {
    ["1pan"] = {-100, 100}, ["2pan"] = {-100, 100},
    ["1seek"] = {0, 100}, ["2seek"] = {0, 100},
    ["1speed"] = {-2, 2}, ["2speed"] = {-2, 2},
    ["1spread"] = {0, 100}, ["2spread"] = {0, 100},
    ["1size"] = {20, 5000}, ["2size"] = {20, 5000},
    ["1density"] = {0.1, 250}, ["2density"] = {0.1, 250},
    ["1volume"] = {-70, 10}, ["2volume"] = {-70, 10},
    ["1pitch"] = {-48, 48}, ["2pitch"] = {-48, 48},
    ["1cutoff"] = {20, 20000}, ["2cutoff"] = {20, 20000},
    ["1hpf"] = {20, 20000}, ["2hpf"] = {20, 20000},
}
local randomize_param_ranges = {["1size"] = {20, 599}, ["2size"] = {20, 599}, ["1density"] = {1, 30}, ["2density"] = {1, 30}}

function lfo.get_parameter_range(param_name, for_randomize)
    if param_name:match("jitter$") then local p = param_name:sub(1, 1) return 0, (p:match("%d") and pget(p .. "max_jitter")) or 4999 end
    if param_name:match("size$") then local p = param_name:sub(1, 1) return 20, (p:match("%d") and pget(p .. "max_size")) or 599 end
    local r = (for_randomize and randomize_param_ranges[param_name]) or param_ranges[param_name]
    if r then return r[1], r[2] end
    return 0, 100
end

function lfo.clear_scale_cache() scale_array_cache = {} snap_lut_cache = {} end
function lfo.scale(v, old_min, old_max, new_min, new_max) return (v - old_min) * (new_max - new_min) / (old_max - old_min) + new_min end

function lfo.clearLFOs(track, param_type, except_param)
    local function matches(target)
        if track and param_type then return target == track .. param_type
        elseif track then return target:match("^" .. track)
        else return true end
    end
    local function excluded(target)
        if not except_param then return false end
        if track then return target == track .. except_param end
        return target:sub(2) == except_param
    end
    local to_clear = {}
    for target in pairs(assigned_params) do if matches(target) and not excluded(target) then to_clear[#to_clear + 1] = target end end
    for _, t in ipairs(to_clear) do assigned_params[t] = nil end
    for i = 1, number_of_outputs do
        if params.lookup[LFO_KEYS[i]] and params.lookup[TARGET_KEYS[i]] then
            local target = lfo.lfo_targets[pget(TARGET_KEYS[i])]
            if target and matches(target) and not excluded(target) then
                local tn, pn = target:sub(1, 1), target:sub(2)
                if not lfo.is_param_locked(tn, pn) then
                    pset(LFO_KEYS[i], 1)
                    pset(TARGET_KEYS[i], 1)
                    lfo[i].sync_to = nil
                    lfo[i].sync_invert = false
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
    lfo.invalidate_lfo_param_cache()
end

local function randomize_lfo(i, target)
    if assigned_params[target] or not lfo.target_ranges[target] then return end
    if target:match("seek$") and pget(target:sub(1, 1) .. "granular_gain") < 100 then return end
    if lfo.get_lfo_for_param(target) then return end
    local target_index = LFO_TARGET_REVERSE[target]
    if not target_index then return end
    local ranges = lfo.target_ranges[target]
    local full_min, full_max = lfo.get_parameter_range(target)
    local rand_min, rand_max = lfo.get_parameter_range(target, true)
    local cur_val = pget(target) or rand_min
    local is_pan = target:match("pan$")
    local is_seek = target:match("seek$")
    local offset
    if is_pan then offset = 0
    elseif is_seek then offset = (math_random() - 0.5)
    else offset = lfo.scale(cur_val, rand_min, rand_max, -1, 1) end
    local depth = math_random(ranges.depth[1], ranges.depth[2])
    local narrow_range = rand_max - rand_min
    local full_range = full_max - full_min
    local half_swing = (depth * 0.01) * narrow_range / 2
    local center = util_clamp(lfo.scale(offset, -1, 1, rand_min, rand_max), rand_min + half_swing, rand_max - half_swing)
    local full_offset = lfo.scale(center, full_min, full_max, -1, 1)
    local full_depth = depth * (narrow_range / full_range)
    lfo[i].depth = full_depth
    lfo[i].offset = full_offset
    pset(DEPTH_KEYS[i], full_depth)
    pset(OFFSET_KEYS[i], full_offset)
    local min_f = math.floor(ranges.frequency[1] * 100)
    local max_f = math.floor(ranges.frequency[2] * 100)
    local freq = math_random(min_f, max_f) / 100
    lfo[i].freq = freq
    pset(FREQ_KEYS[i], freq)
    local wf = ranges.waveform[math_random(#ranges.waveform)]
    if lfo.sine_all then wf = "sine" end
    lfo[i].waveform = wf
    lfo[i].shape_int = LFO_SHAPE_REVERSE[wf] or 4
    local shape_idx = LFO_SHAPE_REVERSE[wf]
    if shape_idx then pset(SHAPE_KEYS[i], shape_idx) end
    pset(TARGET_KEYS[i], target_index)
    pset(LFO_KEYS[i], 2)
    assigned_params[target] = true
    lfo.invalidate_lfo_param_cache()
end

local function mirror_lfo(dst, src, is_pan)
    local obj_s, obj_d = lfo[src], lfo[dst]
    obj_d.freq = obj_s.freq
    obj_d.waveform = obj_s.waveform
    obj_d.shape_int = obj_s.shape_int
    obj_d.depth = obj_s.depth
    obj_d.walk_value = obj_s.walk_value
    obj_d.walk_velocity = obj_s.walk_velocity
    obj_d.sync_to = src
    obj_d.sync_invert = is_pan and true or false
    if is_pan then
        obj_d.phase = (obj_s.phase + 0.5) % 1.0
        obj_d.offset = -obj_s.offset
        pset(OFFSET_KEYS[dst], -obj_s.offset)
    else
        obj_d.phase = obj_s.phase
        obj_d.offset = obj_s.offset
        pset(OFFSET_KEYS[dst], obj_s.offset)
    end
    pset(FREQ_KEYS[dst], obj_s.freq)
    pset(SHAPE_KEYS[dst], LFO_SHAPE_REVERSE[obj_s.waveform])
    pset(DEPTH_KEYS[dst], obj_s.depth)
end

local function free_slots()
    local slots = {}
    for i = 1, number_of_outputs do if params.lookup[LFO_KEYS[i]] and pget(LFO_KEYS[i]) == 1 then slots[#slots + 1] = i end end
    return slots
end

function lfo.assign_to_current_row(current_mode, current_filter_mode)
    local param_map = {seek = "seek", pan = "pan", jitter = "jitter", size = "size", density = "density", spread = "spread", speed = "speed", pitch = "pitch"}
    local param_name = param_map[current_mode]
    if not param_name then return end
    local symmetry = pget("symmetry") == 1
    lfo.clearLFOs("1", param_name)
    lfo.clearLFOs("2", param_name)
    local slots = free_slots()
    if symmetry and not lfo.is_param_locked("1", param_name) and not lfo.is_param_locked("2", param_name) and #slots >= 2 then
        local s1 = table.remove(slots, 1)
        local s2 = table.remove(slots, 1)
        randomize_lfo(s1, "1" .. param_name)
        randomize_lfo(s2, "2" .. param_name)
        mirror_lfo(s2, s1, param_name == "pan")
        return
    end
    if not lfo.is_param_locked("1", param_name) and #slots > 0 then randomize_lfo(table.remove(slots, 1), "1" .. param_name) end
    if not lfo.is_param_locked("2", param_name) and #slots > 0 then randomize_lfo(table.remove(slots, 1), "2" .. param_name) end
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
                    local tn, pn = target:sub(1, 1), target:sub(2)
                    local should_clear = (symmetry and not target:match("volume$") and target:match("^[12]")) or (target:match("^" .. track) and not target:match("volume$"))
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
        local tn, pn = target:sub(1, 1), target:sub(2)
        local ok = (symmetry and not target:match("volume$")) or target:match("^" .. track)
        if ok and not lfo.is_param_locked(tn, pn) and (not target:match("volume$") or allow_volume_lfos) then
            if target:match("seek$") then
                if pget(tn .. "granular_gain") >= 100 and math_random() < ranges.chance then candidates[#candidates + 1] = target end
            elseif math_random() < ranges.chance then candidates[#candidates + 1] = target end
        end
    end
    local slots = free_slots()
    local mirrored = {}
    while #candidates > 0 and #slots > 0 do
        local idx = math_random(#candidates)
        local target = table.remove(candidates, idx)
        if not mirrored[target] then
            local slot = table.remove(slots, math_random(#slots))
            randomize_lfo(slot, target)
            if symmetry and not target:match("volume$") then
                local mirror_target = target:gsub("^(%d)(.*)", function(n, rest) return tostring((tonumber(n) % 2) + 1) .. rest end)
                if #slots > 0 then
                    local slot2 = table.remove(slots, math_random(#slots))
                    randomize_lfo(slot2, mirror_target)
                    mirror_lfo(slot2, slot, target:match("pan$"))
                    mirrored[mirror_target] = true
                end
            end
            mirrored[target] = true
        end
    end
end

local _lfo_param_cache = {}
local _lfo_param_cache_dirty = true

function lfo.invalidate_lfo_param_cache() _lfo_param_cache_dirty = true end

local function rebuild_lfo_param_cache()
    for k in pairs(_lfo_param_cache) do _lfo_param_cache[k] = nil end
    if not params or not params.lookup then _lfo_param_cache_dirty = false return end
    for i = 1, number_of_outputs do
        if params.lookup[LFO_KEYS[i]] and params.lookup[TARGET_KEYS[i]] then
            if pget(LFO_KEYS[i]) == 2 then
                local t = lfo.lfo_targets[pget(TARGET_KEYS[i])]
                if t and t ~= "none" then _lfo_param_cache[t] = i end
            end
        end
    end
    _lfo_param_cache_dirty = false
end

function lfo.get_lfo_for_param(param_name)
    if _lfo_param_cache_dirty then rebuild_lfo_param_cache() end
    return _lfo_param_cache[param_name]
end

function lfo.get_active_param_map()
    if _lfo_param_cache_dirty then rebuild_lfo_param_cache() end
    return _lfo_param_cache
end

local tick_pitch_scale = nil
local tick_max = {}

function lfo.process()
    if lfo_paused or not params or not params.lookup then return end
    if #active_lfos == 0 then return end
    local pget = params.get
    local pset = params.set
    local params_table = params
    local lookup = params_table.lookup
    local param_objs = params_table.params
    local lfo_table = lfo
    local clamp = util_clamp
    local sin = math_sin
    local rnd = math_random
    local phase_inc = PHASE_INCREMENT
    local two_pi = TWO_PI
    local ranges_table = param_ranges

    tick_pitch_scale = nil
    tick_max["1max_jitter"], tick_max["2max_jitter"] = nil, nil
    tick_max["1max_size"], tick_max["2max_size"] = nil, nil

    for idx = 1, #active_lfos do
        local i = active_lfos[idx]
        local obj = lfo_table[i]
        local old_phase = obj.phase
        local phase = (old_phase + obj.freq * phase_inc) % 1.0
        obj.phase = phase
        local wrapped = phase < old_phase
        local slope
        local shape = obj.shape_int

        if shape == 1 then
            slope = sin(phase * two_pi)
        elseif shape == 3 then
            slope = phase < 0.5 and 1 or -1
        elseif shape == 2 then
            if wrapped then obj.prev = rnd() * 2 - 1 end
            slope = obj.prev
        elseif shape == 4 then
            local src = obj.sync_to and lfo_table[obj.sync_to]
            if src then
                obj.walk_value = src.walk_value
                obj.walk_velocity = src.walk_velocity
                obj.prev = obj.sync_invert and -src.prev or src.prev
            else
                local vel = obj.walk_velocity * 0.92 + (rnd() - 0.5) * (obj.freq * 0.4)
                local val = obj.walk_value + vel
                if val > 0.75 then vel = vel - (val - 0.75) * 0.1
                elseif val < -0.75 then vel = vel - (val + 0.75) * 0.1 end
                val = clamp(val, -1, 1)
                obj.walk_velocity = vel
                obj.walk_value = val
                obj.prev = obj.prev * 0.90 + val * 0.10
            end
            slope = obj.prev
        else
            slope = 0
        end

        local mod = slope * (obj.depth * 0.01) + obj.offset
        obj.slope = mod
        local target = obj.target_name

        local mn, mx
        if obj.is_jitter then
            local key = obj.track_num .. "max_jitter"
            local mxv = tick_max[key]
            if mxv == nil then
                mxv = pget(params_table, key) or 4999
                tick_max[key] = mxv
            end
            mn, mx = 0, mxv
        elseif obj.is_size then
            local key = obj.track_num .. "max_size"
            local mxv = tick_max[key]
            if mxv == nil then
                mxv = pget(params_table, key) or 599
                tick_max[key] = mxv
            end
            mn, mx = 20, mxv
        else
            local r = ranges_table[target]
            mn, mx = r and r[1] or 0, r and r[2] or 100
        end
        local value = (mod + 1) * 0.5 * (mx - mn) + mn
        if value < mn then value = mn elseif value > mx then value = mx end
        if obj.is_pitch then
            if tick_pitch_scale == nil then
                tick_pitch_scale = params_table:string("pitch_quantize_scale") or false
            end
            if tick_pitch_scale then value = quantize_pitch_to_scale(value, tick_pitch_scale) end
        end
        if value ~= obj.last_val then
            obj.last_val = value
            local pobj = obj.pobj
            if not pobj then
                local pidx = lookup[target]
                if pidx then pobj = param_objs[pidx] obj.pobj = pobj end
            end
            if pobj then
                if pobj:get() ~= value then pobj:set(value) end
            else
                if pget(params_table, target) ~= value then pset(params_table, target, value) end
            end
        end
    end
end

local lfo_metro = nil
function lfo.init()
    for i = 1, number_of_outputs do
        params:add_separator("LFO " .. i)
        params:add_option(LFO_KEYS[i], i .. " LFO", {"off", "on"}, 1)
        params:set_action(LFO_KEYS[i], function(v) lfo[i].active = (v == 2) lfo[i].last_val = nil update_active_lfos() lfo.invalidate_lfo_param_cache() if lfo.on_state_change then lfo.on_state_change() end end)
        params:add_option(TARGET_KEYS[i], i .. " target", lfo.lfo_targets, 1)
        params:set_action(TARGET_KEYS[i], function(v) classify_target(i, v) update_active_lfos() lfo.invalidate_lfo_param_cache() if lfo.on_state_change then lfo.on_state_change() end end)
        params:add_option(SHAPE_KEYS[i], i .. " shape", options.lfotypes, 4)
        params:set_action(SHAPE_KEYS[i], function(v) lfo[i].waveform = options.lfotypes[v] lfo[i].shape_int = v end)
        params:add_number(DEPTH_KEYS[i], i .. " depth", 0, 100, 50)
        params:set_action(DEPTH_KEYS[i], function(v) lfo[i].depth = v end)
        params:add_control(OFFSET_KEYS[i], i .. " offset", controlspec.new(-0.99, 0.99, "lin", 0.001, 0, ""))
        params:set_action(OFFSET_KEYS[i], function(v) lfo[i].offset = v end)
        params:add_control(FREQ_KEYS[i], i .. " freq", controlspec.new(0.01, 10.00, "lin", 0.01, 0.05, ""))
        params:set_action(FREQ_KEYS[i], function(v) lfo[i].freq = v * (pget("global_lfo_freq_scale") or 1) end)
    end
    for i = 1, number_of_outputs do
        lfo[i].active = pget(LFO_KEYS[i]) == 2
        classify_target(i, pget(TARGET_KEYS[i]) or 1)
    end
    update_active_lfos()
    lfo_metro = metro.init()
    lfo_metro.time = PHASE_INCREMENT
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