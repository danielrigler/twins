local morph = {}
morph.voice_params = {"speed","pitch","jitter","size","density","spread","pan","seek","cutoff","hpf","lpf_gain","granular_gain","subharmonics_3","subharmonics_2","subharmonics_1","overtones_1","overtones_2","smoothbass","ratcheting_prob","size_variation","amp_randomize","direction_mod","density_mod_amt","pitch_random_scale_type","pitch_random_prob","pitch_mode","probability","eq_low_gain","eq_mid_gain","eq_high_gain","eq_tilt","env_select","volume"}
morph.global_params = {"delay_mix","delay_time","delay_feedback","delay_lowpass","delay_highpass","wiggle_depth","wiggle_rate","stereo","reverb_mix","rv_predelay","rv_lffc","rv_lowtime","rv_midtime","rv_hfdamp","lock_shimmer","tape_mix","sine_drive_wet","wobble_mix","wobble_amp","wobble_rpm","flutter_amp","flutter_freq","flutter_var","chew_depth","chew_freq","chew_variance","lossdegrade_mix","Width","dimension_mix","haas","rspeed","monobass_mix","bitcrush_mix","bitcrush_rate","bitcrush_bits","evolution","evolution_range","evolution_rate","lock_eq","lock_tape","lock_reverb","lock_delay","global_lfo_freq_scale","global_lfo_depth_scale","pitch_quantize_scale","pitch_lag","shimmer_mix1","shimmer_oct1","pitchv1","lowpass1","hipass1","fbDelay1","fb1", "glitch_probability", "glitch_ratio", "glitch_mix", "glitch_min_length", "glitch_max_length", "glitch_reverse", "glitch_pitch", "sine_lfos", "shimmer_mod1", "bitcrush_mod", "clock_lfo_div", "clock_lfo_div2", "clock_sync_delay_div", "clock_reseek_div", "resonator_mix", "resonator_decay", "resonator_root", "resonator_tone", "wavefold_mix", "wavefold_drive", "wavefold_sym", "ringmod_mix", "ringmod_rate", "delay_duck", "analogdrive_mix", "analogdrive_drive", "analogdrive_tone", "analogdrive_mode", "analogdrive_mod" }
local param_registry = {}
local registry_count = 0
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
local skip_g = 0
local ENTRY_CAP = 32
local entries = {}
for i = 1, ENTRY_CAP do entries[i] = {} end
local entry_by_target, order, slot_taken, slot_of_target = {}, {}, {}, {}
local live_target, wrote = {}, {}
local assign_valid, sc_changed = false, true
local slots_gen_seen = -1
local _t, _t_inv, _morph_dir, _pitch_scale, _get_range_ref
local _limits_gen = -1
local _has_lfo_tracking = nil
local ITEM_BY_NAME = {}
local moving, moving_count = {}, 0
local simple, simple_count = {}, 0
local special, special_count = {}, 0
local _quantize = nil
local _range_to_norm = nil
local set_morph_range = nil
local _scale_pobj = nil
local _grain_synced, _ready = nil, false
local sc_lfo_count = 0
local sc_entry_count = 0
local sc_targets, sc_target_count = nil, 0
local sc_dirty = true
local sc_a1, sc_a2, sc_b1, sc_b2 = nil, nil, nil, nil

function morph.invalidate_scene_cache() sc_dirty = true end

local function resolve_scenes()
    local s1 = morph.scene_data[1] or EMPTY
    local s2 = morph.scene_data[2] or EMPTY
    local scene1_1, scene1_2 = s1[1] or EMPTY, s1[2] or EMPTY
    local scene2_1, scene2_2 = s2[1] or EMPTY, s2[2] or EMPTY
    if not sc_dirty and scene1_1 == sc_a1 and scene1_2 == sc_a2
       and scene2_1 == sc_b1 and scene2_2 == sc_b2 then
        return scene1_1, scene1_2, scene2_1, scene2_2
    end
    sc_a1, sc_a2, sc_b1, sc_b2 = scene1_1, scene1_2, scene2_1, scene2_2
    sc_dirty = false
    sc_changed = true
    local n, ns, nx = 0, 0, 0
    for ri = 1, registry_count do
        local item = param_registry[ri]
        local p = item.name
        local vA, vB
        if item.t2 then
            vA = scene2_1[p] or scene1_1[p]
            vB = scene2_2[p] or scene1_2[p]
        else
            vA = scene1_1[p] or scene2_1[p]
            vB = scene1_2[p] or scene2_2[p]
        end
        item.vA, item.vB = vA, vB
        local is_moving = item.obj ~= nil and (vA ~= vB) and not (vA == nil and vB == nil)
        item.moving = is_moving
        if is_moving then
            n = n + 1
            moving[n] = item
            if vA ~= nil and vB ~= nil and not item.is_pitch then
                ns = ns + 1
                simple[ns] = item
            else
                nx = nx + 1
                special[nx] = item
            end
        end
    end
    for i = n + 1, #moving do moving[i] = nil end
    for i = ns + 1, #simple do simple[i] = nil end
    for i = nx + 1, #special do special[i] = nil end
    moving_count, simple_count, special_count = n, ns, nx
    local la = (scene1_1.lfo_data or scene2_1.lfo_data) or EMPTY
    local lb = (scene1_2.lfo_data or scene2_2.lfo_data) or EMPTY
    local c = 0
    for i = 1, 16 do
        local a, b = la[i], lb[i]
        if (a and a.enabled) or (b and b.enabled) then c = c + 1 end
    end
    sc_lfo_count = c
    for k in pairs(entry_by_target) do entry_by_target[k] = nil end
    local ec = 0
    for side = 1, 2 do
        local ld = (side == 1) and la or lb
        for i = 1, 16 do
            local e = ld[i]
            if e and e.enabled and type(e.target) == "number"
               and e.target >= 1 and e.target <= sc_target_count then
                local name = sc_targets[e.target]
                if name and name ~= "none" then
                    local it = entry_by_target[name]
                    if not it and ec < ENTRY_CAP then
                        ec = ec + 1
                        it = entries[ec]
                        it.target, it.tidx, it.a, it.b, it.slot = name, e.target, nil, nil, nil
                        it.rgen = -1
                        it.item = ITEM_BY_NAME[name]
                        it.cA = scene1_1[name] or scene2_1[name]
                        it.cB = scene1_2[name] or scene2_2[name]
                        entry_by_target[name] = it
                    end
                    if it then
                        if side == 1 then
                            if not it.a then it.a = e end
                        elseif not it.b then it.b = e end
                    end
                end
            end
        end
    end
    sc_entry_count = ec
    return scene1_1, scene1_2, scene2_1, scene2_2
end

function morph.init(lfo_module, invalidate_fn, clocksync_module)
    lfo_ref = lfo_module
    clocksync_ref = clocksync_module
    invalidate_lfo_cache_ref = invalidate_fn
    _quantize = lfo_ref.scale_utils.quantize
    _get_range_ref = lfo_ref.get_parameter_range
    _grain_synced = clocksync_module and clocksync_module.grain_synced or nil
    _ready = (_get_range_ref ~= nil) and (lfo_ref.lfo_targets ~= nil)
    _range_to_norm = lfo_ref.range_to_norm or function(_, lo, hi, v) return (v - lo) / (hi - lo) end
    set_morph_range = lfo_ref.set_morph_range or function() end
    sc_targets = lfo_ref.lfo_targets
    sc_target_count = #sc_targets
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
    _scale_pobj = obj_of("pitch_quantize_scale")
    param_registry = {}
    OBJ_BY_NAME = {}
    ITEM_BY_NAME = {}
    local n = 0
    local function reg(name, is_pitch, t2)
        local o = obj_of(name)
        OBJ_BY_NAME[name] = o
        n = n + 1
        local eps = nil
        local cs = o and o.controlspec
        if cs and cs.minval and cs.maxval and (not cs.step or cs.step == 0) then
            local span = cs.maxval - cs.minval
            if span < 0 then span = -span end
            if span > 0 and span < math.huge then eps = span * 5e-4 end
        end
        local item = {name = name, is_pitch = is_pitch, t2 = t2, obj = o, eps = eps,
                      setfn = o and o.set or nil, skip_g = -1}
        param_registry[n] = item
        ITEM_BY_NAME[name] = item
    end
    for track = 1, 2 do
        for _, p in ipairs(morph.voice_params) do
            reg(track .. p, p == "pitch", track == 2)
        end
    end
    for _, p in ipairs(morph.global_params) do reg(p, false, false) end
    registry_count = n
    sc_dirty = true
end

function morph.sync_amount(v)
    morph.amount = v
    last_morph_amount = v
end

function morph.store_scene_pair(scene)
    morph.store_scene(1, scene)
    morph.scene_data[2][scene] = morph.scene_data[1][scene]
    sc_dirty = true
end

function morph.store_scene(track, scene)
    morph.scene_data[track][scene] = {}
    local scene_params = morph.scene_data[track][scene]
    for ri = 1, registry_count do
        local item = param_registry[ri]
        local o = item.obj
        if o then scene_params[item.name] = o:get() end
    end
    if clocksync_ref then
        scene_params[DENSITY_DIV_KEYS[1]] = clocksync_ref.grain_division_index(1)
        scene_params[DENSITY_DIV_KEYS[2]] = clocksync_ref.grain_division_index(2)
    end
    sc_dirty = true
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
    assign_valid = false
    for i = 1, 16 do set_morph_range(i, nil) end
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

local function _by_depth(x, y)
    if x.depth ~= y.depth then return x.depth > y.depth end
    return x.target < y.target
end

local function _compute_offset(lfo_offset, const_val, it, t_weight, const_weight, forced_off)
    it.rng_lo = nil
    if forced_off ~= nil then return _morph_clamp(lfo_offset * t_weight + forced_off * const_weight) end
    if not const_val then return _morph_clamp(lfo_offset * t_weight) end
    local min_val, max_val = it.rlo, it.rhi
    if it.rgen ~= _limits_gen then
        min_val, max_val = _get_range_ref(it.target)
        it.rlo, it.rhi, it.rgen = min_val, max_val, _limits_gen
    end
    if not min_val or not max_val or max_val <= min_val then return _morph_clamp(lfo_offset * t_weight) end
    local lo, hi = min_val, max_val
    if const_val < min_val then
        lo = min_val + (const_val - min_val) * const_weight
        it.rng_lo, it.rng_hi = lo, hi
    elseif const_val > max_val then
        hi = max_val + (const_val - max_val) * const_weight
        it.rng_lo, it.rng_hi = lo, hi
    end
    const_val = const_val < lo and lo or (const_val > hi and hi or const_val)
    local tgt_off = _range_to_norm(it.target, lo, hi, const_val) * 2 - 1
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

local function _interp_item(item, ts)
    local obj = item.obj
    local vA, vB = item.vA, item.vB
    local fparam = item.name
    if vA == nil then if vB ~= nil then obj:set(vB) end return end
    if vB == nil then obj:set(vA) return end
    local temp = ts[fparam]
    local new_val
    if not temp then
        if vA == vB then return end
        new_val = vA * _t_inv + vB * _t
    else
        local chased, done = chase_temp(temp, vA, vB)
        if done then
            ts[fparam] = nil
            obj:set(chased)
            return
        end
        new_val = chased
    end
    if item.is_pitch then new_val = _quantize(new_val, _pitch_scale) end
    item.setfn(obj, new_val)
    if temp then
        local diff = new_val - ((_morph_dir > 0 and vB) or vA)
        ts[fparam] = (diff > -0.01 and diff < 0.01) and nil or new_val
    end
end

function morph.apply()
    if not _ready then return end
    local current_time = util_time()
    local morph_direction = morph.amount - last_morph_amount
    if morph_direction == 0 and morph.amount > 0 and morph.amount < 100 then return end
    if morph.amount == 0 or morph.amount == 100 then
        last_morph_amount = morph.amount
        local scene = morph.amount == 0 and 1 or 2
        local sd = morph.scene_data
        local src = (sd[1] and sd[1][scene] and next(sd[1][scene]) ~= nil) and 1 or 2
        morph.recall_scene(src, scene)
        local ts = morph.temp_scene
        for k in pairs(ts) do ts[k] = nil end
        return
    end
    if (current_time - last_morph_update_time) < MORPH_THROTTLE_INTERVAL then return end
    last_morph_update_time = current_time
    last_morph_amount = morph.amount
    _t = morph.amount * 0.01
    _t_inv = 1.0 - _t
    _morph_dir = morph_direction
    _pitch_scale = _scale_pobj and _scale_pobj:string() or "off"
    _limits_gen = lfo_ref.limits_gen or 0
    _synced_density = _grain_synced and _grain_synced() or false
    local scene1_1, scene1_2, scene2_1, scene2_2 = resolve_scenes()
    local has_temp = next(morph.temp_scene) ~= nil
    local lfo_targets = sc_targets
    if _has_lfo_tracking == nil then _has_lfo_tracking = (lfo_ref.clear_param_assignment and true or false) end
    local stable = assign_valid and not sc_changed and sc_entry_count <= 16
                   and lfo_ref.slots_gen == slots_gen_seen
    sc_changed = false
    if not stable then
        for i = 1, 16 do
            local nm = nil
            if O_LFO[i]:get() == 2 then
                nm = lfo_targets[O_TARGET[i]:get()]
                if nm == "none" then nm = nil end
            end
            live_target[i] = nm
        end
    end
    skip_g = skip_g + 1
    if sc_lfo_count == 0 then
        assign_valid = false
        for i = 1, 16 do
            set_morph_range(i, nil)
            local o = O_LFO[i]
            if o:get() == 2 then o:set(1) end
        end
    else
    local ec = sc_entry_count
    for k = 1, ec do
        local it = entries[k]
        local a, b, target = it.a, it.b, it.target
        if a and b then
            it.tidx = a.target
            it.rng_lo = nil
            it.shape = _t < 0.5 and a.shape or b.shape
            it.freq = a.freq * _t_inv + b.freq * _t
            it.depth = a.depth * _t_inv + b.depth * _t
            it.offset = _morph_clamp(a.offset * _t_inv + b.offset * _t)
        elseif a then
            local forced = _synced_density and _density_forced_off(target, scene1_2, scene2_2) or nil
            local const_val = it.cB
            local temp = forced == nil and has_temp and morph.temp_scene[target]
            if temp then
                const_val = chase_temp(temp, it.cA, const_val)
            end
            it.tidx, it.shape, it.freq = a.target, a.shape, a.freq
            it.depth = a.depth * _t_inv
            it.offset = _compute_offset(a.offset, const_val, it, _t_inv, _t, forced)
        else
            local forced = _synced_density and _density_forced_off(target, scene1_1, scene2_1) or nil
            local const_val = it.cA
            local temp = forced == nil and has_temp and morph.temp_scene[target]
            if temp then
                const_val = chase_temp(temp, const_val, it.cB)
            end
            it.tidx, it.shape, it.freq = b.target, b.shape, b.freq
            it.depth = b.depth * _t
            it.offset = _compute_offset(b.offset, const_val, it, _t, _t_inv, forced)
        end
        order[k] = it
    end
    for k = ec + 1, #order do order[k] = nil end
    if ec > 16 then table.sort(order, _by_depth) end
    if not stable then
        local clear_assign = _has_lfo_tracking and lfo_ref.clear_param_assignment or nil
        for k in pairs(slot_of_target) do slot_of_target[k] = nil end
        for i = 1, 16 do
            slot_taken[i] = nil
            local nm = live_target[i]
            if nm then
                if clear_assign then clear_assign(nm) end
                if slot_of_target[nm] == nil then slot_of_target[nm] = i end
            end
        end
        if ec > 16 then table.sort(order, _by_depth) end
        for k = 1, ec do order[k].slot = nil end
        local assign_n = ec < 16 and ec or 16
        for k = 1, assign_n do
            local it = order[k]
            local cur = slot_of_target[it.target]
            if cur and not slot_taken[cur] then
                slot_taken[cur] = true
                it.slot = cur
            end
        end
        local next_free = 1
        for k = 1, assign_n do
            local it = order[k]
            if not it.slot then
                while next_free <= 16 and slot_taken[next_free] do next_free = next_free + 1 end
                if next_free <= 16 then
                    slot_taken[next_free] = true
                    it.slot = next_free
                end
            end
        end
        for i = 1, 16 do
            wrote[i] = nil
            if not slot_taken[i] then
                set_morph_range(i, nil)
                local o = O_LFO[i]
                if o:get() == 2 then o:set(1) end
            end
        end
    end
    for k = 1, ec do
        local it = order[k]
        local slot = it.slot
        if slot then
            if not stable then
                _ensure_unique_assignment(it.target, slot)
                wrote[slot] = it.target
            end
            local mi = it.item
            if mi then mi.skip_g = skip_g end
            write_lfo_slot(slot, it.tidx, it.shape, it.freq, it.depth, it.offset)
            set_morph_range(slot, it.rng_lo, it.rng_hi)
        end
    end
    assign_valid = true
    slots_gen_seen = lfo_ref.slots_gen
    end
    if _synced_density then
        for v = 1, 2 do
            local ditem = ITEM_BY_NAME[DENSITY_KEYS[v]]
            if ditem and ditem.skip_g ~= skip_g then
                local ddiv = DENSITY_DIV_KEYS[v]
                local dA = scene1_1[ddiv] or scene2_1[ddiv]
                local dB = scene1_2[ddiv] or scene2_2[ddiv]
                local idx = _lerp_div_index(dA, dB, _t, _t_inv)
                if idx then clocksync_ref.set_grain_div_index(v, idx) end
                ditem.skip_g = skip_g
            end
        end
    end
    local ts = morph.temp_scene
    local sg = skip_g
    local t, ti, q, ps = _t, _t_inv, _quantize, _pitch_scale
    if has_temp then
        for k = 1, moving_count do
            local item = moving[k]
            if item.skip_g ~= sg then
                if ts[item.name] then
                    _interp_item(item, ts)
                else
                    local vA, vB = item.vA, item.vB
                    if vA == nil then
                        item.setfn(item.obj, vB)
                    elseif vB == nil then
                        item.setfn(item.obj, vA)
                    else
                        local nv = vA * ti + vB * t
                        if item.is_pitch then nv = q(nv, ps) end
                        item.setfn(item.obj, nv)
                    end
                end
            end
        end
        for name in pairs(ts) do
            local item = ITEM_BY_NAME[name]
            if item and not item.moving and item.obj and item.skip_g ~= sg then
                _interp_item(item, ts)
            end
        end
    else
        for k = 1, simple_count do
            local item = simple[k]
            if item.skip_g ~= sg then
                item.setfn(item.obj, item.vA * ti + item.vB * t)
            end
        end
        for k = 1, special_count do
            local item = special[k]
            if item.skip_g ~= sg then
                local vA, vB = item.vA, item.vB
                if vA == nil then
                    item.setfn(item.obj, vB)
                elseif vB == nil then
                    item.setfn(item.obj, vA)
                else
                    item.setfn(item.obj, q(vA * ti + vB * t, ps))
                end
            end
        end
    end
    if invalidate_lfo_cache_ref then invalidate_lfo_cache_ref() end
end

function morph.capture_to_temp_scene(lfo_cache)
    if morph.amount == 0 or morph.amount == 100 then return end
    resolve_scenes()
    local ts = morph.temp_scene
    local t = morph.amount * 0.01
    local t_inv = 1.0 - t
    for ri = 1, registry_count do
        local item = param_registry[ri]
        local o = item.obj
        if o then
            local p = item.name
            if (not lfo_cache or not lfo_cache[p]) then
                local cur = o:get()
                local vA, vB = item.vA, item.vB
                local expected
                if vA == nil then expected = vB
                elseif vB == nil then expected = vA
                else expected = vA * t_inv + vB * t end
                if expected == nil then
                    ts[p] = cur
                else
                    local d = cur - expected
                    local eps = item.eps or 0
                    if d > eps or d < -eps then ts[p] = cur else ts[p] = nil end
                end
            end
        end
    end
end

function morph.auto_save_to_scene()
    if next(morph.temp_scene) ~= nil then return end
    local scene = (morph.amount == 0 and 1) or (morph.amount == 100 and 2)
    if scene then
        morph.store_scene_pair(scene)
        local ts = morph.temp_scene
        for k in pairs(ts) do ts[k] = nil end
    end
end

function morph.initialize_scenes_with_current_params()
    for scene = 1, 2 do morph.store_scene_pair(scene) end
end

return morph