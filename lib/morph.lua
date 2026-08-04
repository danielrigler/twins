local morph = {}
morph.voice_params = {"speed","pitch","jitter","size","density","spread","pan","seek","cutoff","hpf","lpf_gain","granular_gain","subharmonics_3","subharmonics_2","subharmonics_1","overtones_1","overtones_2","smoothbass","ratcheting_prob","size_variation","amp_randomize","direction_mod","density_mod_amt","pitch_random_scale_type","pitch_random_prob","pitch_mode","probability","eq_low_gain","eq_mid_gain","eq_high_gain","eq_tilt","env_select","volume"}
morph.global_params = {"delay_mix","delay_time","delay_feedback","delay_lowpass","delay_highpass","wiggle_depth","wiggle_rate","stereo","reverb_mix","rv_predelay","rv_lffc","rv_lowtime","rv_midtime","rv_hfdamp","lock_shimmer","tape_mix","sine_drive_wet","wobble_mix","wobble_amp","wobble_rpm","flutter_amp","flutter_freq","flutter_var","chew_depth","chew_freq","chew_variance","lossdegrade_mix","Width","dimension_mix","haas","rspeed","monobass_mix","bitcrush_mix","bitcrush_rate","bitcrush_bits","evolution","evolution_range","evolution_rate","lock_eq","lock_tape","lock_reverb","lock_delay","global_lfo_freq_scale","global_lfo_depth_scale","pitch_quantize_scale","pitch_lag","shimmer_mix1","shimmer_oct1","pitchv1","lowpass1","hipass1","fbDelay1","fb1", "glitch_probability", "glitch_ratio", "glitch_mix", "glitch_min_length", "glitch_max_length", "glitch_reverse", "glitch_pitch", "sine_lfos", "shimmer_mod1", "bitcrush_mod", "clock_lfo_div", "clock_lfo_div2", "clock_sync_delay_div", "clock_reseek_div", "resonator_mix", "resonator_decay", "resonator_root", "resonator_tone", "wavefold_mix", "wavefold_drive", "wavefold_sym", "ringmod_mix", "ringmod_rate", "delay_duck", "analogdrive_mix", "analogdrive_drive", "analogdrive_tone", "analogdrive_mode", "analogdrive_mod" }
local param_registry = {}
local legacy_rev = {rev_pre_delay=true, rev_lf_fc=true, rev_low_time=true, rev_mid_time=true, rev_hf_damping=true}
morph.amount = 0
morph.scene_mode = "off"
morph.scene_data = {[1] = {[1] = {}, [2] = {}}, [2] = {[1] = {}, [2] = {}}}
morph.temp_scene = {}
local m_min, m_abs, m_floor = math.min, math.abs, math.floor
local util_time = util.time
local EMPTY = {}
local DENSITY_KEYS     = {"1density", "2density"}
local DENSITY_DIV_KEYS = {"1density_div", "2density_div"}
local DENSITY_DIV_OF   = {["1density"] = "1density_div", ["2density"] = "2density_div"}
local last_morph_amount = 0
local last_morph_update_time = 0
local MORPH_THROTTLE_INTERVAL = 0.03
local lfo_ref = nil
local clocksync_ref = nil
local _synced_density = false
local invalidate_lfo_cache_ref = nil
local MORPH_LFO_KEYS, MORPH_TARGET_KEYS, MORPH_SHAPE_KEYS, MORPH_FREQ_KEYS, MORPH_DEPTH_KEYS, MORPH_OFFSET_KEYS
local O_LFO, O_TARGET, O_SHAPE, O_FREQ, O_DEPTH, O_OFFSET = {}, {}, {}, {}, {}, {}
local OBJ_BY_NAME = {}
local skip_param_set = {}
local used_slots = {}
local pending = {}
for i = 1, 16 do pending[i] = {lfo = nil, param = nil} end
local _t, _t_inv, _morph_dir, _pitch_scale, _get_range_ref
local _has_lfo_tracking = nil

function morph.init(lfo_module, invalidate_fn, clocksync_module)
    lfo_ref = lfo_module
    clocksync_ref = clocksync_module
    invalidate_lfo_cache_ref = invalidate_fn
    MORPH_LFO_KEYS    = lfo_ref.keys.lfo
    MORPH_TARGET_KEYS = lfo_ref.keys.target
    MORPH_SHAPE_KEYS  = lfo_ref.keys.shape
    MORPH_FREQ_KEYS   = lfo_ref.keys.freq
    MORPH_DEPTH_KEYS  = lfo_ref.keys.depth
    MORPH_OFFSET_KEYS = lfo_ref.keys.offset
    local function obj_of(name)
        local idx = params.lookup[name]
        return idx and params.params[idx] or nil
    end
    for i = 1, 16 do
        O_LFO[i]    = obj_of(MORPH_LFO_KEYS[i])
        O_TARGET[i] = obj_of(MORPH_TARGET_KEYS[i])
        O_SHAPE[i]  = obj_of(MORPH_SHAPE_KEYS[i])
        O_FREQ[i]   = obj_of(MORPH_FREQ_KEYS[i])
        O_DEPTH[i]  = obj_of(MORPH_DEPTH_KEYS[i])
        O_OFFSET[i] = obj_of(MORPH_OFFSET_KEYS[i])
    end
    param_registry = {}
    OBJ_BY_NAME = {}
    local n = 0
    local function reg(name, is_pitch, t2)
        local o = obj_of(name)
        OBJ_BY_NAME[name] = o
        n = n + 1
        param_registry[n] = {name = name, is_pitch = is_pitch, t2 = t2, obj = o}
    end
    for track = 1, 2 do
        for _, p in ipairs(morph.voice_params) do
            reg(track .. p, p == "pitch", track == 2)
        end
    end
    for _, p in ipairs(morph.global_params) do reg(p, false, false) end
end

function morph.sync_amount(v)
    morph.amount = v
    last_morph_amount = v
end

function morph.store_scene(track, scene)
    morph.scene_data[track][scene] = {}
    local scene_params = morph.scene_data[track][scene]
    for _, item in ipairs(param_registry) do
        local o = item.obj
        if o then scene_params[item.name] = o:get() end
    end
    if clocksync_ref then
        scene_params[DENSITY_DIV_KEYS[1]] = clocksync_ref.grain_division_index(1)
        scene_params[DENSITY_DIV_KEYS[2]] = clocksync_ref.grain_division_index(2)
    end
    local lfo_data = {}
    scene_params.lfo_data = lfo_data
    for i = 1, 16 do
        if O_LFO[i]:get() == 2 then
            lfo_data[i] = {
                enabled = true,
                target = O_TARGET[i]:get(),
                shape = O_SHAPE[i]:get(),
                freq = O_FREQ[i]:get(),
                depth = O_DEPTH[i]:get(),
                offset = O_OFFSET[i]:get()}
        else
            lfo_data[i] = {enabled = false}
        end
    end
end

function morph.recall_scene(track, scene)
    local scene_params = morph.scene_data[track][scene]
    if not scene_params then return end
    for i = 1, 16 do O_LFO[i]:set(1) end
    for param_name, value in pairs(scene_params) do
        if param_name ~= "lfo_data" and not legacy_rev[param_name] then
            local o = OBJ_BY_NAME[param_name]
            if o == nil then
                local idx = params.lookup[param_name]
                o = idx and params.params[idx] or nil
            end
            if o then o:set(value) end
        end
    end
    local lfo_data = scene_params.lfo_data
    if lfo_data then
        for i = 1, 16 do
            local e = lfo_data[i]
            if e and e.enabled then
                O_TARGET[i]:set(e.target)
                O_SHAPE[i]:set(e.shape)
                O_FREQ[i]:set(e.freq)
                O_DEPTH[i]:set(e.depth)
                O_OFFSET[i]:set(e.offset)
                O_LFO[i]:set(2)
            end
        end
    end
    if clocksync_ref and clocksync_ref.grain_synced() then
        for v = 1, 2 do
            local dv = scene_params[DENSITY_DIV_KEYS[v]]
            if dv then clocksync_ref.set_grain_div_index(v, dv) end
        end
    end
    if invalidate_lfo_cache_ref then invalidate_lfo_cache_ref() end
end

local function _lerp_div_index(dA, dB, t, t_inv)
    if dA and dB then return m_floor(dA * t_inv + dB * t + 0.5) end
end

function morph.restore_synced_divisions()
    if not (clocksync_ref and clocksync_ref.grain_synced()) then return end
    local s1 = morph.scene_data[1] or EMPTY
    local s2 = morph.scene_data[2] or EMPTY
    local scene1_1, scene1_2 = s1[1] or EMPTY, s1[2] or EMPTY
    local scene2_1, scene2_2 = s2[1] or EMPTY, s2[2] or EMPTY
    local t = (morph.amount or 0) * 0.01
    local t_inv = 1.0 - t
    for v = 1, 2 do
        local key = DENSITY_DIV_KEYS[v]
        local dA = scene1_1[key] or scene2_1[key]
        local dB = scene1_2[key] or scene2_2[key]
        local idx = _lerp_div_index(dA, dB, t, t_inv) or dA or dB
        if idx then clocksync_ref.set_grain_div_index(v, idx) end
    end
end

local function _morph_clamp(x) return x < -1 and -1 or (x > 1 and 1 or x) end

local function _compute_offset(lfo_offset, const_val, target, t_weight, const_weight, forced_off)
    if forced_off ~= nil then return _morph_clamp(lfo_offset * t_weight + forced_off * const_weight) end
    if not const_val then return _morph_clamp(lfo_offset * t_weight) end
    local min_val, max_val = _get_range_ref(target)
    if not min_val or not max_val or max_val <= min_val then return _morph_clamp(lfo_offset * t_weight) end
    const_val = const_val < min_val and min_val or (const_val > max_val and max_val or const_val)
    local tgt_off = ((const_val - min_val) / (max_val - min_val)) * 2 - 1
    return _morph_clamp(lfo_offset * t_weight + tgt_off * const_weight)
end

local function _density_forced_off(target, c1, c2)
    if not _synced_density then return nil end
    local dkey = DENSITY_DIV_OF[target]
    if not dkey then return nil end
    local dv = (c1 and c1[dkey]) or (c2 and c2[dkey])
    if not dv then return nil end
    return _morph_clamp(clocksync_ref.div_index_to_norm(dv) * 2 - 1)
end

local DEPTH_THRESHOLD = 0.01

local function _ensure_unique_assignment(target, slot)
    if not _has_lfo_tracking or not target then return end
    if lfo_ref.is_param_assigned(target) then
        local other = lfo_ref.get_lfo_for_param(target)
        if other and other ~= slot then O_LFO[other]:set(1) end
    end
    lfo_ref.mark_param_assigned(target)
end

local function chase_temp(temp, val_a, val_b)
    local is_forward = _morph_dir > 0
    local tgt = is_forward and val_b or val_a
    local dist = is_forward and (100 - morph.amount) or morph.amount
    if dist <= 0 then return tgt, true end
    local progress = m_min(m_abs(_morph_dir) / dist, 1.0)
    return temp + (tgt - temp) * progress, false
end

local function write_lfo_slot(slot, target, shape, freq, depth, offset)
    O_TARGET[slot]:set(target)
    O_SHAPE[slot]:set(shape)
    O_FREQ[slot]:set(freq)
    O_DEPTH[slot]:set(depth)
    O_OFFSET[slot]:set(offset)
    O_LFO[slot]:set((depth >= DEPTH_THRESHOLD or (morph.amount > 0 and morph.amount < 100)) and 2 or 1)
end

local function _interp_prebuilt(item, valA, valB)
    local obj = item.obj
    if not obj then return end
    local fparam = item.name
    if not valA and not valB then return end
    if not valA then obj:set(valB) return end
    if not valB then obj:set(valA) return end
    local temp = morph.temp_scene[fparam]
    local new_val
    if not temp then
        if valA == valB then return end
        new_val = valA * _t_inv + valB * _t
    else
        local chased, done = chase_temp(temp, valA, valB)
        if done then
            morph.temp_scene[fparam] = nil
            obj:set(chased)
            return
        end
        new_val = chased
    end
    if item.is_pitch then new_val = lfo_ref.scale_utils.quantize(new_val, _pitch_scale) end
    obj:set(new_val)
    if temp then
        local diff = new_val - ( (_morph_dir > 0 and valB) or valA )
        morph.temp_scene[fparam] = (diff > -0.01 and diff < 0.01) and nil or new_val
    end
end

function morph.apply()
    if not lfo_ref or not lfo_ref.get_parameter_range or not lfo_ref.lfo_targets then return end
    local current_time = util_time()
    local morph_direction = morph.amount - last_morph_amount
    last_morph_amount = morph.amount
    if morph_direction == 0 and morph.amount > 0 and morph.amount < 100 then return end
    if morph.amount == 0 or morph.amount == 100 then
        local scene = morph.amount == 0 and 1 or 2
        for track = 1, 2 do morph.recall_scene(track, scene) end
        local ts = morph.temp_scene
        for k in pairs(ts) do ts[k] = nil end
        return
    end
    if (current_time - last_morph_update_time) < MORPH_THROTTLE_INTERVAL then return end
    last_morph_update_time = current_time
    _t = morph.amount * 0.01
    _t_inv = 1.0 - _t
    _morph_dir = morph_direction
    _pitch_scale = params:string("pitch_quantize_scale")
    _get_range_ref = lfo_ref.get_parameter_range
    _synced_density = clocksync_ref and clocksync_ref.grain_synced() or false
    local s1 = morph.scene_data[1] or EMPTY
    local s2 = morph.scene_data[2] or EMPTY
    local scene1_1, scene1_2 = s1[1] or EMPTY, s1[2] or EMPTY
    local scene2_1, scene2_2 = s2[1] or EMPTY, s2[2] or EMPTY
    local lfo_data_A = (scene1_1.lfo_data or scene2_1.lfo_data) or EMPTY
    local lfo_data_B = (scene1_2.lfo_data or scene2_2.lfo_data) or EMPTY
    local lfo_targets = lfo_ref.lfo_targets
    local lfo_targets_count = #lfo_targets
    if _has_lfo_tracking == nil then _has_lfo_tracking = (lfo_ref.clear_param_assignment and true or false) end
    if _has_lfo_tracking then
        for i = 1, 16 do
            if O_LFO[i]:get() == 2 then
                local target_param = lfo_targets[O_TARGET[i]:get()]
                if target_param and target_param ~= "none" then lfo_ref.clear_param_assignment(target_param) end
            end
        end
    end
    for k in pairs(skip_param_set) do skip_param_set[k] = nil end
    for i = 1, 16 do used_slots[i] = nil end
    local pending_count = 0
    for i = 1, 16 do
        local lfo_A, lfo_B = lfo_data_A[i], lfo_data_B[i]
        local lfo_A_enabled, lfo_B_enabled = (lfo_A and lfo_A.enabled), (lfo_B and lfo_B.enabled)
        if not (lfo_A_enabled or lfo_B_enabled) then
            local o = O_LFO[i]
            if o:get() == 2 then o:set(1) end
            goto continue
        end
        used_slots[i] = true
        local target_A = lfo_A_enabled and lfo_A.target and lfo_targets[lfo_A.target]
        local target_B = lfo_B_enabled and lfo_B.target and lfo_targets[lfo_B.target]
        if lfo_A_enabled and (lfo_A.target < 1 or lfo_A.target > lfo_targets_count) then lfo_A_enabled = false; target_A = nil end
        if lfo_B_enabled and (lfo_B.target < 1 or lfo_B.target > lfo_targets_count) then lfo_B_enabled = false; target_B = nil end
        if lfo_A_enabled and lfo_B_enabled and target_A ~= target_B and target_B and target_B ~= "none" then
            pending_count = pending_count + 1
            local m = pending[pending_count]
            m.lfo, m.param = lfo_B, target_B
        end
        local target = target_A or target_B
        if not target or target == "none" then goto continue end
        _ensure_unique_assignment(target, i)
        skip_param_set[target] = true
        if lfo_A_enabled and lfo_B_enabled and target_A == target_B then
            write_lfo_slot(i, lfo_A.target,
                _t < 0.5 and lfo_A.shape or lfo_B.shape,
                lfo_A.freq * _t_inv + lfo_B.freq * _t,
                lfo_A.depth * _t_inv + lfo_B.depth * _t,
                _morph_clamp(lfo_A.offset * _t_inv + lfo_B.offset * _t))
        elseif lfo_A_enabled and target_A == target then
            local forced = _density_forced_off(target, scene1_2, scene2_2)
            local const_val = scene1_2[target] or scene2_2[target]
            local temp = forced == nil and morph.temp_scene[target]
            if temp then
                const_val = chase_temp(temp, scene1_1[target] or scene2_1[target], const_val)
            end
            write_lfo_slot(i, lfo_A.target, lfo_A.shape, lfo_A.freq,
                lfo_A.depth * _t_inv,
                _compute_offset(lfo_A.offset, const_val, target, _t_inv, _t, forced))
        else
            local lfo_val = (lfo_B_enabled and lfo_B) or (lfo_A_enabled and lfo_A)
            if not lfo_val then goto continue end
            local forced = _density_forced_off(target, scene1_1, scene2_1)
            local const_val = scene1_1[target] or scene2_1[target]
            local temp = forced == nil and morph.temp_scene[target]
            if temp then
                const_val = chase_temp(temp, const_val, scene1_2[target] or scene2_2[target])
            end
            write_lfo_slot(i, lfo_val.target, lfo_val.shape, lfo_val.freq,
                lfo_val.depth * _t,
                _compute_offset(lfo_val.offset, const_val, target, _t, _t_inv, forced))
        end
        ::continue::
    end
    if pending_count > 0 then
        for idx = 1, pending_count do
            local m = pending[idx]
            local slot
            for i = 1, 16 do if not used_slots[i] then slot = i; used_slots[i] = true; break end end
            if slot then
                _ensure_unique_assignment(m.param, slot)
                skip_param_set[m.param] = true
                local forced = _density_forced_off(m.param, scene1_1, scene2_1)
                local const_val = scene1_1[m.param] or scene2_1[m.param]
                local temp = forced == nil and morph.temp_scene[m.param]
                if temp then
                    const_val = chase_temp(temp, const_val, scene1_2[m.param] or scene2_2[m.param])
                end
                write_lfo_slot(slot, m.lfo.target, m.lfo.shape, m.lfo.freq,
                    m.lfo.depth * _t,
                    _compute_offset(m.lfo.offset, const_val, m.param, _t, _t_inv, forced))
            end
        end
    end
    if _synced_density then
        for v = 1, 2 do
            local dkey = DENSITY_KEYS[v]
            if not skip_param_set[dkey] then
                local ddiv = DENSITY_DIV_KEYS[v]
                local dA = scene1_1[ddiv] or scene2_1[ddiv]
                local dB = scene1_2[ddiv] or scene2_2[ddiv]
                local idx = _lerp_div_index(dA, dB, _t, _t_inv)
                if idx then clocksync_ref.set_grain_div_index(v, idx) end
            end
            skip_param_set[dkey] = true
        end
    end
    for _, item in ipairs(param_registry) do
        local p = item.name
        if not skip_param_set[p] then
            local sA, sB
            if item.t2 then
                sA = scene2_1[p] or scene1_1[p]
                sB = scene2_2[p] or scene1_2[p]
            else
                sA = scene1_1[p] or scene2_1[p]
                sB = scene1_2[p] or scene2_2[p]
            end
            _interp_prebuilt(item, sA, sB)
        end
    end
    if invalidate_lfo_cache_ref then invalidate_lfo_cache_ref() end
end

function morph.capture_to_temp_scene(lfo_cache)
    if morph.amount == 0 or morph.amount == 100 then return end
    local ts = morph.temp_scene
    for _, item in ipairs(param_registry) do
        local o = item.obj
        if o then
            local p = item.name
            if (not lfo_cache or not lfo_cache[p]) then ts[p] = o:get() end
        end
    end
end

function morph.auto_save_to_scene()
    if next(morph.temp_scene) ~= nil then return end
    local scene = (morph.amount == 0 and 1) or (morph.amount == 100 and 2)
    if scene then
        for track = 1, 2 do morph.store_scene(track, scene) end
        local ts = morph.temp_scene
        for k in pairs(ts) do ts[k] = nil end
    end
end

function morph.initialize_scenes_with_current_params()
    for track = 1, 2 do for scene = 1, 2 do morph.store_scene(track, scene) end end
end

return morph