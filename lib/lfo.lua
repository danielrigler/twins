local number_of_outputs = 16
local options = {lfotypes = {"sine", "random", "square", "walk"}}
local LFO_SHAPE_REVERSE = {}
for i, name in ipairs(options.lfotypes) do LFO_SHAPE_REVERSE[name] = i end
local lfo = {}
local utils = include("lib/utils")
local mirror_param_name = utils.mirror_param_name
local assigned_params = {}
local lfo_paused = false
local saved_shapes = {}
local lfo_metro = nil
local lfo_metro_running = false
local active_count_ref = 0
local function update_metro_run()
    if not lfo_metro then return end
    local want = (active_count_ref > 0) and not lfo_paused
    if want == lfo_metro_running then return end
    lfo_metro_running = want
    if want then lfo_metro:start() else pcall(function() lfo_metro:stop() end) end
end
lfo.sine_all = false
local global_depth_scale = 1
function lfo.set_global_depth_scale(v) global_depth_scale = v or 1 end
local clocksync_ref = nil
local size_cap_fn = nil
function lfo.set_context(ctx)
    clocksync_ref = ctx.clocksync
    local arp = ctx.arp
    if arp then size_cap_fn = arp.max_size_ms end
end
local TWO_PI = math.pi * 2
local PHASE_INCREMENT = 1 / 30
local math_sin = math.sin
local math_random = math.random
local math_log = math.log
local util_clamp = util.clamp
local LFO_KEYS, TARGET_KEYS, SHAPE_KEYS, FREQ_KEYS, DEPTH_KEYS, OFFSET_KEYS = {}, {}, {}, {}, {}, {}
for i = 1, number_of_outputs do
    LFO_KEYS[i]    = i .. "lfo"
    TARGET_KEYS[i] = i .. "lfo_target"
    SHAPE_KEYS[i]  = i .. "lfo_shape"
    FREQ_KEYS[i]   = i .. "lfo_freq"
    DEPTH_KEYS[i]  = i .. "lfo_depth"
    OFFSET_KEYS[i] = i .. "offset"
end
lfo.keys = {lfo = LFO_KEYS, target = TARGET_KEYS, shape = SHAPE_KEYS, freq = FREQ_KEYS, depth = DEPTH_KEYS, offset = OFFSET_KEYS}
local function pget(k)
    if params and params.lookup and params.lookup[k] then return params:get(k) end
    return nil
end
local function pset(k, v)
    if params and params.lookup and params.lookup[k] then params:set(k, v) end
end
local _SPLIT_CACHE = {}
local function split_target(target)
    local c = _SPLIT_CACHE[target]
    if not c then c = {target:sub(1, 1), target:sub(2)} _SPLIT_CACHE[target] = c end
    return c[1], c[2]
end
local _LIMIT_KEYS = {}
local function limit_keys(track, suffix)
    local tk = _LIMIT_KEYS[track]
    if not tk then tk = {} _LIMIT_KEYS[track] = tk end
    local k = tk[suffix]
    if not k then k = {track .. "min_" .. suffix, track .. "max_" .. suffix} tk[suffix] = k end
    return k[1], k[2]
end
lfo.is_param_locked = utils.is_param_locked
local function is_audio_loaded(track)
    local p = pget(track .. "sample")
    return p and p ~= "" and p ~= "none" and p ~= "-"
end
local MusicUtil = require("musicutil")
local scale_array_cache = {}
local snap_lut_cache = {}
local SCALE_ALIASES = {["major pent."] = "major pentatonic", ["minor pent."] = "minor pentatonic"}
local function normalize_scale_name(name)
    if name == "none" or name == "off" then return "none" end
    return SCALE_ALIASES[name] or name
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
local intervals_cache = {}
local function get_scale_intervals(scale_name)
    scale_name = normalize_scale_name(scale_name)
    if scale_name == "none" then return nil end
    local ivs = intervals_cache[scale_name]
    if not ivs then
        local ok, r = pcall(MusicUtil.generate_scale, 0, scale_name, 1)
        ivs = (ok and r) or MusicUtil.generate_scale(0, "major", 1)
        intervals_cache[scale_name] = ivs
    end
    return ivs
end
local function step_in_scale(pitch_value, scale_name, direction)
    local scale_array = get_scale_array(scale_name)
    if not scale_array then return pitch_value + direction end
    local midi_note = MusicUtil.snap_note_to_array(60 + pitch_value, scale_array)
    local current_idx
    for i, note in ipairs(scale_array) do
        if note == midi_note then current_idx = i break end
    end
    if not current_idx then return pitch_value end
    local next_idx = util_clamp(current_idx + (direction > 0 and 1 or -1), 1, #scale_array)
    return scale_array[next_idx] - 60
end
lfo.scale_utils = {normalize = normalize_scale_name, get_array = get_scale_array, quantize = quantize_pitch_to_scale, intervals = get_scale_intervals, step = step_in_scale}
function lfo.scale(v, old_min, old_max, new_min, new_max) return (v - old_min) * (new_max - new_min) / (old_max - old_min) + new_min end
function lfo.set_pause(paused) lfo_paused = paused update_metro_run() end
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
lfo.lfo_targets = {"none", "1pan", "2pan", "1seek", "2seek", "1jitter", "2jitter", "1spread", "2spread", "1size", "2size", "1density", "2density", "1volume", "2volume", "1pitch", "2pitch", "1cutoff", "2hpf", "1speed", "2speed", "1hpf", "2cutoff", "1eq_tilt", "2eq_tilt"}
local LFO_TARGET_REVERSE = {}
for i, t in ipairs(lfo.lfo_targets) do LFO_TARGET_REVERSE[t] = i end
lfo.target_index = LFO_TARGET_REVERSE
lfo.PRESERVE_ON_RANDOMIZE = { volume = true }
lfo.target_ranges = {
    ["1pan"] = {depth = {25, 90}, offset = {0, 0}, frequency = {0.1, 1}, waveform = {"walk"}, chance = 0.75},
    ["2pan"] = {depth = {25, 90}, offset = {0, 0}, frequency = {0.1, 1}, waveform = {"walk"}, chance = 0.75},
    ["1jitter"] = {depth = {20, 70}, offset = {0, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.7},
    ["2jitter"] = {depth = {20, 70}, offset = {0, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.7},
    ["1spread"] = {depth = {10, 30}, offset = {0, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.7},
    ["2spread"] = {depth = {10, 30}, offset = {0, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.7},
    ["1size"] = {depth = {5, 40}, offset = {0.1, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.7},
    ["2size"] = {depth = {5, 40}, offset = {0.1, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.7},
    ["1density"] = {depth = {5, 75}, offset = {0, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.7},
    ["2density"] = {depth = {5, 75}, offset = {0, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.7},
    ["1volume"] = {depth = {2, 3}, offset = {0, 1}, frequency = {0.1, 0.3}, waveform = {"sine"}, chance = 1.0},
    ["2volume"] = {depth = {2, 3}, offset = {0, 1}, frequency = {0.1, 0.3}, waveform = {"sine"}, chance = 1.0},
    ["1seek"] = {depth = {0, 100}, offset = {0, 1}, frequency = {0.1, 0.4}, waveform = {"walk"}, chance = 0.3},
    ["2seek"] = {depth = {0, 100}, offset = {0, 1}, frequency = {0.1, 0.4}, waveform = {"walk"}, chance = 0.3},
    ["1speed"] = {depth = {10, 50}, offset = {-1, 1}, frequency = {0.1, 0.5}, waveform = {"walk"}, chance = 0.3},
    ["2speed"] = {depth = {10, 50}, offset = {-1, 1}, frequency = {0.1, 0.5}, waveform = {"walk"}, chance = 0.3},
    ["1pitch"] = {depth = {5, 30}, offset = {-1, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.0},
    ["2pitch"] = {depth = {5, 30}, offset = {-1, 1}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.0},
    ["1cutoff"] = {depth = {5, 30}, offset = {0.01, 0.9}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.15},
    ["2cutoff"] = {depth = {5, 30}, offset = {0.01, 0.9}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.15},
    ["1hpf"] = {depth = {5, 25}, offset = {0.01, 0.9}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.15},
    ["2hpf"] = {depth = {5, 25}, offset = {0.01, 0.9}, frequency = {0.1, 0.6}, waveform = {"walk"}, chance = 0.15},
    ["1eq_tilt"] = {depth = {5, 30}, offset = {0, 0}, frequency = {0.1, 0.6}, waveform = {"sine"}, chance = 0.3},
    ["2eq_tilt"] = {depth = {5, 50}, offset = {0, 0}, frequency = {0.1, 0.6}, waveform = {"sine"}, chance = 0.3},
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
    ["1cutoff"] = {20, 19999}, ["2cutoff"] = {20, 19999},
    ["1hpf"] = {21, 20000}, ["2hpf"] = {21, 20000},
    ["1eq_tilt"] = {-1, 1}, ["2eq_tilt"] = {-1, 1},
}
local randomize_param_ranges = {["1size"] = {20, 599}, ["2size"] = {20, 599}, ["1density"] = {1, 30}, ["2density"] = {1, 30}}
local LOG_RANGE_TARGETS = {["1cutoff"] = true, ["2cutoff"] = true, ["1hpf"] = true, ["2hpf"] = true}
lfo.log_range_targets = LOG_RANGE_TARGETS
function lfo.range_to_norm(param_name, lo, hi, v)
    if hi <= lo then return 0 end
    if LOG_RANGE_TARGETS[param_name] and lo > 0 and v > 0 then
        return math_log(v / lo) / math_log(hi / lo)
    end
    return (v - lo) / (hi - lo)
end
function lfo.norm_to_range(param_name, lo, hi, n)
    if hi <= lo then return lo end
    if LOG_RANGE_TARGETS[param_name] and lo > 0 then
        return lo * ((hi / lo) ^ n)
    end
    return lo + n * (hi - lo)
end
local USER_LIMIT_PARAMS = {
    seek = true, jitter = true, spread = true, size = true,
    density = true, pitch = true, speed = true,
}
local USER_LIMIT_DEFAULTS = {
    jitter  = {0, 4999},
    size    = {20, 999},
    density = {0.1, 50},
    spread  = {0, 100},
    pitch   = {-48, 48},
    speed   = {-2, 2},
    seek    = {0, 100},
}
function lfo.get_parameter_range(param_name, for_randomize)
    local track, suffix = split_target(param_name)
    local lo, hi
    if track:match("%d") and USER_LIMIT_PARAMS[suffix] then
        local min_key, max_key = limit_keys(track, suffix)
        lo = pget(min_key)
        hi = pget(max_key)
        local d = USER_LIMIT_DEFAULTS[suffix]
        if lo == nil then lo = d and d[1] or 0 end
        if hi == nil then hi = d and d[2] or 100 end
    else
        local r = param_ranges[param_name]
        if r then lo, hi = r[1], r[2] else lo, hi = 0, 100 end
    end
    if lo > hi then lo, hi = hi, lo end
    if for_randomize then
        local rr = randomize_param_ranges[param_name]
        if rr then
            local rlo = rr[1] > lo and rr[1] or lo
            local rhi = rr[2] < hi and rr[2] or hi
            if rlo <= rhi then return rlo, rhi end
        end
    end
    return lo, hi
end
for i = 1, number_of_outputs do
    lfo[i] = {freq = 0.05, phase = 0, waveform = "walk", shape_int = 4, depth = 50, offset = 0, prev = 0, walk_value = 0, walk_velocity = 0, sync_to = nil, sync_invert = false, active = false, target_idx = 1, target_name = "none", kind = 0, no_gdepth = false, track_num = "1", last_val = nil, has_user_limits = false, min_key = nil, max_key = nil, def_min = 0, def_max = 100, lim_lo = 0, lim_hi = 100, lim_ratio = 1, lim_dirty = false}
end
local KIND_SIZE, KIND_FILTER, KIND_VOLUME, KIND_PITCH, KIND_DENSITY = 1, 2, 3, 4, 5
local KIND_BY_SUFFIX = {size = KIND_SIZE, cutoff = KIND_FILTER, hpf = KIND_FILTER, volume = KIND_VOLUME, pitch = KIND_PITCH, density = KIND_DENSITY}
local function classify_target(i, target_idx)
    local obj = lfo[i]
    obj.target_idx = target_idx
    local tname = lfo.lfo_targets[target_idx]
    obj.target_name = tname
    obj.pobj = nil
    obj.last_val = nil
    if tname and tname ~= "none" then
        local track, suffix = split_target(tname)
        obj.track_num = track
        obj.kind = KIND_BY_SUFFIX[suffix] or 0
        obj.no_gdepth = (suffix == "volume" or suffix == "pan")
        if USER_LIMIT_PARAMS[suffix] then
            local d = USER_LIMIT_DEFAULTS[suffix]
            obj.has_user_limits = true
            obj.min_key, obj.max_key = limit_keys(track, suffix)
            obj.def_min = d and d[1] or 0
            obj.def_max = d and d[2] or 100
            obj.lim_dirty = true
        else
            obj.has_user_limits = false
            obj.min_key, obj.max_key = nil, nil
            obj.lim_dirty = false
            local r = param_ranges[tname]
            obj.lim_lo = r and r[1] or 0
            obj.lim_hi = r and r[2] or 100
            obj.lim_ratio = (obj.lim_lo > 0 and obj.lim_hi > obj.lim_lo) and (obj.lim_hi / obj.lim_lo) or 1
        end
    else
        obj.track_num = "1"
        obj.kind = 0
        obj.no_gdepth = false
        obj.has_user_limits = false
        obj.min_key, obj.max_key = nil, nil
        obj.lim_dirty = false
        obj.lim_lo, obj.lim_hi = 0, 100
    end
end
function lfo.invalidate_limits()
    for i = 1, number_of_outputs do
        local o = lfo[i]
        if o.has_user_limits then o.lim_dirty = true end
    end
end
local active_lfos = {}
local active_count = 0
local has_size1, has_size2, has_density_lfo = false, false, false
local function update_active_lfos()
    local count = 0
    local hs1, hs2, hd = false, false, false
    for i = 1, number_of_outputs do
        local o = lfo[i]
        if o.active and o.target_name and o.target_name ~= "none" then
            local k = o.kind
            if k == KIND_SIZE then
                if o.track_num == "2" then hs2 = true else hs1 = true end
            elseif k == KIND_DENSITY then
                hd = true
            end
            if not o.sync_to then
                count = count + 1
                active_lfos[count] = i
            end
        end
    end
    for i = 1, number_of_outputs do
        local o = lfo[i]
        if o.active and o.target_name and o.target_name ~= "none" and o.sync_to then
            count = count + 1
            active_lfos[count] = i
        end
    end
    for i = count + 1, #active_lfos do active_lfos[i] = nil end
    active_count = count
    active_count_ref = count
    has_size1, has_size2, has_density_lfo = hs1, hs2, hd
    update_metro_run()
end
function lfo.rebuild_order() update_active_lfos() end
function lfo.is_param_assigned(name) return assigned_params[name] == true end
function lfo.mark_param_assigned(name) if name then assigned_params[name] = true end end
function lfo.clear_param_assignment(name) if name then assigned_params[name] = nil end end
local function clear_slot(i)
    pset(LFO_KEYS[i], 1)
    pset(TARGET_KEYS[i], 1)
    lfo[i].sync_to = nil
    lfo[i].sync_invert = false
end
function lfo.clearLFOs(track, param_type, except_param)
    if track ~= nil then track = tostring(track) end
    local function matches(target)
        if track and param_type then return target == track .. param_type
        elseif track then return target:sub(1, 1) == track
        else return true end
    end
    local function excluded(target)
        if not except_param then return false end
        if type(except_param) == "table" then return except_param[target:sub(2)] == true end
        if track then return target == track .. except_param end
        return target:sub(2) == except_param
    end
    local to_clear = {}
    for target in pairs(assigned_params) do
        if matches(target) and not excluded(target) then to_clear[#to_clear + 1] = target end
    end
    for _, t in ipairs(to_clear) do assigned_params[t] = nil end
    for i = 1, number_of_outputs do
        if params.lookup[LFO_KEYS[i]] and params.lookup[TARGET_KEYS[i]] then
            local target = lfo.lfo_targets[pget(TARGET_KEYS[i])]
            if target and matches(target) and not excluded(target) then
                local tn, pn = split_target(target)
                if not lfo.is_param_locked(tn, pn) then clear_slot(i) end
            end
        end
    end
    if not track and not param_type then
        local p1, p2 = utils.default_pans(is_audio_loaded("1") and is_audio_loaded("2"))
        pset("1pan", p1); pset("2pan", p2)
    end
    lfo.invalidate_lfo_param_cache()
end
local function randomize_lfo(i, target)
    if assigned_params[target] or not lfo.target_ranges[target] then return end
    local track = target:sub(1, 1)
    if target:match("seek$") and pget(track .. "granular_gain") < 100 then return end
    if target:match("seek$") and clocksync_ref and clocksync_ref.reseek_active() then return end
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
    else offset = lfo.range_to_norm(target, rand_min, rand_max, cur_val) * 2 - 1 end
    local depth = math_random(ranges.depth[1], ranges.depth[2])
    local half_swing = depth * 0.005
    local ncenter = util_clamp((offset + 1) * 0.5, half_swing, 1 - half_swing)
    local center = lfo.norm_to_range(target, rand_min, rand_max, ncenter)
    local full_offset = lfo.range_to_norm(target, full_min, full_max, center) * 2 - 1
    local narrow_span, full_span
    if LOG_RANGE_TARGETS[target] and full_min > 0 and rand_min > 0 then
        narrow_span, full_span = math_log(rand_max / rand_min), math_log(full_max / full_min)
    else
        narrow_span, full_span = rand_max - rand_min, full_max - full_min
    end
    local full_depth = (full_span > 0) and (depth * (narrow_span / full_span)) or depth
    if clocksync_ref and clocksync_ref.grain_synced() and target:sub(2) == "density" then full_offset = clocksync_ref.grain_division_norm(track) * 2 - 1 end
    local obj = lfo[i]
    obj.sync_to = nil
    obj.sync_invert = false
    obj.depth = full_depth
    obj.offset = full_offset
    pset(DEPTH_KEYS[i], full_depth)
    pset(OFFSET_KEYS[i], full_offset)
    local min_f = math.floor(ranges.frequency[1] * 100)
    local max_f = math.floor(ranges.frequency[2] * 100)
    local freq = math_random(min_f, max_f) / 100
    pset(FREQ_KEYS[i], freq)
    lfo.recompute_freq(i)
    obj.phase = math_random()
    obj.walk_value = (math_random() - 0.5) * 1.5
    obj.walk_velocity = 0
    obj.prev = obj.walk_value
    local wf = ranges.waveform[math_random(#ranges.waveform)]
    if lfo.sine_all then wf = "sine" end
    obj.waveform = wf
    obj.shape_int = LFO_SHAPE_REVERSE[wf] or 4
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
    pset(FREQ_KEYS[dst], pget(FREQ_KEYS[src]))
    pset(SHAPE_KEYS[dst], LFO_SHAPE_REVERSE[obj_s.waveform])
    pset(DEPTH_KEYS[dst], obj_s.depth)
    update_active_lfos()
end
local function free_slots()
    local slots = {}
    for i = 1, number_of_outputs do
        if params.lookup[LFO_KEYS[i]] and pget(LFO_KEYS[i]) == 1 then slots[#slots + 1] = i end
    end
    return slots
end
function lfo.assign_to_current_row(current_mode, current_filter_mode)
    local param_map = {seek = "seek", pan = "pan", jitter = "jitter", size = "size", density = "density", spread = "spread", speed = "speed", pitch = "pitch", eq = "eq_tilt"}
    local param_name = param_map[current_mode]
    if not param_name then return end
    if param_name == "seek" and clocksync_ref and clocksync_ref.reseek_active() then return end
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
    track = tostring(track)
    local symmetry = pget("symmetry") == 1
    for i = 1, number_of_outputs do
        if params.lookup[LFO_KEYS[i]] and params.lookup[TARGET_KEYS[i]] then
            local t_idx = pget(TARGET_KEYS[i])
            if t_idx and t_idx > 0 then
                local target = lfo.lfo_targets[t_idx]
                if target then
                    local tn, pn = split_target(target)
                    local is_vol = lfo.PRESERVE_ON_RANDOMIZE[pn]
                    local t1 = target:sub(1, 1)
                    local should_clear = (symmetry and not is_vol and (t1 == "1" or t1 == "2")) or (t1 == track and not is_vol)
                    if should_clear and not lfo.is_param_locked(tn, pn) then
                        clear_slot(i)
                        assigned_params[target] = nil
                    end
                end
            end
        end
    end
    local candidates = {}
    for target, ranges in pairs(lfo.target_ranges) do
        local tn, pn = split_target(target)
        local is_vol = target:match("volume$")
        local ok = (symmetry and not is_vol) or (target:sub(1, 1) == track)
        if ok and not lfo.is_param_locked(tn, pn) and (not is_vol or allow_volume_lfos) then
            if target:match("seek$") then
                if pget(tn .. "granular_gain") >= 100 and math_random() < ranges.chance then candidates[#candidates + 1] = target end
            elseif math_random() < ranges.chance then
                candidates[#candidates + 1] = target
            end
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
                local mirror_target = mirror_param_name(target)
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
        if params.lookup[LFO_KEYS[i]] and params.lookup[TARGET_KEYS[i]] and pget(LFO_KEYS[i]) == 2 then
            local t = lfo.lfo_targets[pget(TARGET_KEYS[i])]
            if t and t ~= "none" then _lfo_param_cache[t] = i end
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
local function windowed_value(mn, mx, cap, offset, mod, dn)
    local wh = (cap - mn) * 0.5
    local en = mod - offset
    local maxen = dn
    if maxen > 1 then
        en = en / maxen
        maxen = 1
    end
    local half = maxen * wh
    local center = (offset + 1) * (mx - mn) * 0.5 + mn
    local lo, hi = mn + half, cap - half
    if center < lo then center = lo elseif center > hi then center = hi end
    local v = center + en * wh
    if v > cap then v = cap end
    return v
end
local tick_pitch_scale = nil
local MATH_HUGE = math.huge
local pitch_scale_pobj = nil
function lfo.invalidate_pitch_scale_obj() pitch_scale_pobj = nil end
function lfo.process()
    if lfo_paused or not params or not params.lookup then return end
    if active_count == 0 then return end
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
    local gdepth = global_depth_scale
    tick_pitch_scale = nil
    local huge = MATH_HUGE
    local size_cap1, size_cap2 = huge, huge
    if size_cap_fn then
        if has_size1 then size_cap1 = size_cap_fn("1") or huge end
        if has_size2 then size_cap2 = size_cap_fn("2") or huge end
    end
    local grain_synced = has_density_lfo and clocksync_ref ~= nil and clocksync_ref.grain_synced()
    for idx = 1, active_count do
        local i = active_lfos[idx]
        local obj = lfo_table[i]
        local old_phase = obj.phase
        local freq = obj.freq
        local phase = (old_phase + freq * phase_inc) % 1.0
        obj.phase = phase
        local kind = obj.kind
        if obj.lim_dirty then
            local min_key, max_key = obj.min_key, obj.max_key
            local lo = (lookup[min_key] and pget(params_table, min_key)) or obj.def_min
            local hi = (lookup[max_key] and pget(params_table, max_key)) or obj.def_max
            if lo > hi then lo, hi = hi, lo end
            obj.lim_lo, obj.lim_hi = lo, hi
            obj.lim_ratio = (lo > 0 and hi > lo) and (hi / lo) or 1
            obj.lim_dirty = false
        end
        if obj.sync_to and kind ~= KIND_VOLUME and not (kind == KIND_DENSITY and grain_synced) then
            local s = lfo_table[obj.sync_to]
            if s and s.active and not s.sync_to and s.last_val ~= nil then
                if obj.shape_int == 4 then
                    obj.walk_value = s.walk_value
                    obj.walk_velocity = s.walk_velocity
                    obj.prev = obj.sync_invert and -s.prev or s.prev
                end
                local mn, mx = obj.lim_lo, obj.lim_hi
                local value = obj.sync_invert and -s.last_val or s.last_val
                if value < mn then value = mn elseif value > mx then value = mx end
                if value ~= obj.last_val then
                    obj.last_val = value
                    local pobj = obj.pobj
                    if not pobj then
                        local pidx = lookup[obj.target_name]
                        if pidx then pobj = param_objs[pidx] obj.pobj = pobj end
                    end
                    if pobj then pobj:set(value) end
                end
                goto continue_lfo
            end
        end
        local slope
        local shape = obj.shape_int
        if shape == 4 then
            local src = obj.sync_to and lfo_table[obj.sync_to]
            if src and src.active and not src.sync_to then
                obj.walk_value = src.walk_value
                obj.walk_velocity = src.walk_velocity
                obj.prev = obj.sync_invert and -src.prev or src.prev
            else
                local rate = freq
                if rate < 0.01 then rate = 0.01 elseif rate > 10.0 then rate = 10.0 end
                if obj._walk_rate ~= rate then
                    obj._walk_rate = rate
                    local loss = clamp(0.15 * rate, 0.01, 1.0)
                    obj._walk_damp = 1.0 - loss
                    obj._walk_noise = 0.5 * math.sqrt(loss)
                    obj._walk_spring = clamp(0.2 * rate, 0.01, 1.0)
                end
                local spring = obj._walk_spring
                local vel = obj.walk_velocity * obj._walk_damp + (rnd() - 0.5) * obj._walk_noise
                local val = obj.walk_value + vel
                if val > 0.75 then vel = vel - (val - 0.75) * spring
                elseif val < -0.75 then vel = vel - (val + 0.75) * spring end
                if val < -1 then val = -1 elseif val > 1 then val = 1 end
                obj.walk_velocity = vel
                obj.walk_value = val
                local prev = obj.prev
                obj.prev = prev + (val - prev) * spring
            end
            slope = obj.prev
        elseif shape == 1 then
            slope = sin(phase * two_pi)
        elseif shape == 3 then
            slope = phase < 0.5 and 1 or -1
        elseif shape == 2 then
            if phase < old_phase then obj.prev = rnd() * 2 - 1 end
            slope = obj.prev
        else
            slope = 0
        end
        local d = obj.depth
        if not obj.no_gdepth then d = d * gdepth end
        local dn = d * 0.01
        local offset = obj.offset
        local mod = slope * dn + offset
        local target = obj.target_name
        if kind == KIND_DENSITY and grain_synced then
            local nt = (mod + 1) * 0.5
            if nt < 0 then nt = 0 elseif nt > 1 then nt = 1 end
            clocksync_ref.set_grain_div_norm(obj.track_num, nt)
            goto continue_lfo
        end
        local mn, mx = obj.lim_lo, obj.lim_hi
        local value = (mod + 1) * 0.5 * (mx - mn) + mn
        if kind == KIND_SIZE then
            local size_cap = (obj.track_num == "2") and size_cap2 or size_cap1
            if size_cap < mx then value = windowed_value(mn, mx, size_cap, offset, mod, dn) end
        elseif kind == KIND_FILTER then
            local ratio = obj.lim_ratio
            if ratio > 1 then
                local n = windowed_value(0, 1, 1, offset, mod, dn)
                if n < 0 then n = 0 elseif n > 1 then n = 1 end
                value = mn * (ratio ^ n)
            else
                value = windowed_value(mn, mx, mx, offset, mod, dn)
            end
        end
        if value < mn then value = mn elseif value > mx then value = mx end
        if kind == KIND_VOLUME then
            if offset <= -0.9875 then value = -70 end
        elseif kind == KIND_PITCH then
            if tick_pitch_scale == nil then
                if not pitch_scale_pobj then
                    local pi = lookup["pitch_quantize_scale"]
                    pitch_scale_pobj = pi and param_objs[pi] or false
                end
                tick_pitch_scale = (pitch_scale_pobj and pitch_scale_pobj:string()) or false
            end
            if tick_pitch_scale then
                value = quantize_pitch_to_scale(value, tick_pitch_scale)
                if value < mn then value = mn elseif value > mx then value = mx end
            end
        end
        if obj.sync_to then
            local s = lfo_table[obj.sync_to]
            if s and s.active and not s.sync_to and kind ~= KIND_VOLUME and s.last_val ~= nil then
                value = obj.sync_invert and -s.last_val or s.last_val
                if value < mn then value = mn elseif value > mx then value = mx end
            end
        end
        if value ~= obj.last_val then
            obj.last_val = value
            local pobj = obj.pobj
            if not pobj then
                local pidx = lookup[target]
                if pidx then pobj = param_objs[pidx] obj.pobj = pobj end
            end
            if pobj then
                pobj:set(value)
            elseif pget(params_table, target) ~= value then
                pset(params_table, target, value)
            end
        end
        ::continue_lfo::
    end
end
local sync_hz1, sync_hz2 = nil, nil
local freq_scale_pobj = nil
function lfo.recompute_freq(i)
    if freq_scale_pobj == nil then
        local fi = params and params.lookup and params.lookup["global_lfo_freq_scale"]
        freq_scale_pobj = fi and params.params[fi] or false
    end
    local gs = (freq_scale_pobj and freq_scale_pobj:get()) or 1
    local base
    if sync_hz1 then
        base = (lfo[i].track_num == "2") and sync_hz2 or sync_hz1
    else
        base = pget(FREQ_KEYS[i]) or 0.05
    end
    lfo[i].freq = base * gs
end
function lfo.apply_clock_sync(hz1, hz2)
    sync_hz1 = hz1
    sync_hz2 = hz1 and (hz2 or hz1) or nil
    for i = 1, number_of_outputs do
        lfo.recompute_freq(i)
    end
end
function lfo.reset_phases()
    for idx = 1, active_count do
        local o = lfo[active_lfos[idx]]
        o.phase = 0
        o.last_val = nil
    end
end
function lfo.snapshot_phases()
    local snap = {}
    for i = 1, number_of_outputs do
        local o = lfo[i]
        snap[i] = {o.phase, o.walk_value, o.walk_velocity, o.prev}
    end
    return snap
end
function lfo.restore_phases(snap)
    if type(snap) ~= "table" then return end
    for i = 1, number_of_outputs do
        local s = snap[i]
        if type(s) == "table" then
            local o = lfo[i]
            o.phase = s[1] or 0
            o.walk_value = s[2] or 0
            o.walk_velocity = s[3] or 0
            o.prev = s[4] or 0
        end
    end
end
function lfo.init()
    for i = 1, number_of_outputs do
        params:add_separator("LFO " .. i)
        params:add_option(LFO_KEYS[i], i .. " LFO", {"off", "on"}, 1)
        params:set_action(LFO_KEYS[i], function(v)
            lfo[i].active = (v == 2)
            lfo[i].last_val = nil
            update_active_lfos()
            lfo.invalidate_lfo_param_cache()
        end)
        params:add_option(TARGET_KEYS[i], i .. " target", lfo.lfo_targets, 1)
        params:set_action(TARGET_KEYS[i], function(v)
            classify_target(i, v)
            update_active_lfos()
            lfo.invalidate_lfo_param_cache()
        end)
        params:add_option(SHAPE_KEYS[i], i .. " shape", options.lfotypes, 4)
        params:set_action(SHAPE_KEYS[i], function(v)
            lfo[i].waveform = options.lfotypes[v]
            lfo[i].shape_int = v
            lfo[i].last_val = nil
        end)
        params:add_number(DEPTH_KEYS[i], i .. " depth", 0, 100, 50)
        params:set_action(DEPTH_KEYS[i], function(v) lfo[i].depth = v end)
        params:add_control(OFFSET_KEYS[i], i .. " offset", controlspec.new(-0.99, 0.99, "lin", 0.001, 0, ""))
        params:set_action(OFFSET_KEYS[i], function(v) lfo[i].offset = v end)
        params:add_control(FREQ_KEYS[i], i .. " freq", controlspec.new(0.01, 10.00, "lin", 0.01, 0.05, ""))
        params:set_action(FREQ_KEYS[i], function(v) lfo.recompute_freq(i) end)
    end
    for i = 1, number_of_outputs do
        lfo[i].active = pget(LFO_KEYS[i]) == 2
        classify_target(i, pget(TARGET_KEYS[i]) or 1)
    end
    lfo_metro = metro.init()
    lfo_metro.time = PHASE_INCREMENT
    lfo_metro.count = -1
    lfo_metro.event = lfo.process
    update_active_lfos()
    update_metro_run()
end
function lfo.cleanup()
    if lfo_metro then
        pcall(function() lfo_metro:stop() end)
        lfo_metro.event = nil
        lfo_metro = nil
        lfo_metro_running = false
    end
end
return lfo
