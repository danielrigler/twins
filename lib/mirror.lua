local Mirror = {}

local params_lookup = nil
local lfo_targets = nil
local target_lookup = nil

local _LFO_KEYS, _TARGET_KEYS, _SHAPE_KEYS, _FREQ_KEYS, _DEPTH_KEYS, _OFFSET_KEYS = {}, {}, {}, {}, {}, {}
for _i = 1, 16 do
  _LFO_KEYS[_i]    = _i .. "lfo"
  _TARGET_KEYS[_i] = _i .. "lfo_target"
  _SHAPE_KEYS[_i]  = _i .. "lfo_shape"
  _FREQ_KEYS[_i]   = _i .. "lfo_freq"
  _DEPTH_KEYS[_i]  = _i .. "lfo_depth"
  _OFFSET_KEYS[_i] = _i .. "offset"
end

local function param_exists(name) return params_lookup[name] ~= nil end
local function safe_get(name) return params_lookup[name] and params:get(name) or 0 end
local function safe_set(name, value) if params_lookup[name] and value ~= nil then params:set(name, value) end end

local track_pattern_cache = {}
local function get_track_pattern(track)
    local pattern = track_pattern_cache[track]
    if not pattern then
        pattern = "^" .. track
        track_pattern_cache[track] = pattern
    end
    return pattern
end

function Mirror.init(osc_positions_ref, lfo_ref)
    Mirror.osc_positions = osc_positions_ref or {}
    Mirror.lfo = lfo_ref
    params_lookup = params.lookup
    lfo_targets = lfo_ref and lfo_ref.lfo_targets
    target_lookup = {}
    if lfo_targets then
        for idx, t in ipairs(lfo_targets) do target_lookup[t] = idx end
    end
end
 
function Mirror.copy_voice_params(from_track, to_track, mirror_pan)
    local function clear_destination_lfos(to_track_num)
        local pattern = get_track_pattern(to_track_num)
        for lfo_num = 1, 16 do
            local t_index = safe_get(_TARGET_KEYS[lfo_num])
            if t_index > 0 then
                local tname = lfo_targets[t_index]
                if tname and tname:match(pattern) then
                    params:set(_LFO_KEYS[lfo_num], 1)
                end
            end
        end
    end

    clear_destination_lfos(to_track)

    local from_num = tonumber(from_track)
    local to_num = tonumber(to_track)
    if Mirror.osc_positions[from_num] then Mirror.osc_positions[to_num] = Mirror.osc_positions[from_num] end

    local volume_has_lfo = false
    local from_volume_target = from_track .. "volume"
    for i = 1, 16 do
        if safe_get(_LFO_KEYS[i]) == 2 then
            local t_idx = safe_get(_TARGET_KEYS[i])
            if t_idx > 0 then
                local target_name = lfo_targets[t_idx]
                if target_name == from_volume_target then volume_has_lfo = true; break end
            end
        end
    end

    if not volume_has_lfo then
        safe_set(to_track .. "volume", safe_get(from_track .. "volume"))
    end

    local static_params = { "speed", "pitch", "jitter", "size", "density", "spread", "pan", "seek",
                             "cutoff", "hpf", "lpfgain", "granular_gain", "subharmonics_3", "subharmonics_2",
                             "subharmonics_1", "overtones_1", "overtones_2", "smoothbass",
                             "pitch_walk_rate", "pitch_walk_step", "ratcheting_prob",
                             "size_variation", "direction_mod", "density_mod_amt", "pitch_random_scale_type", "pitch_random_prob",
                             "pitch_mode", "trig_mode", "probability", "eq_low_gain", "eq_mid_gain", "eq_high_gain", "env_select", "volume" }

    for _, param in ipairs(static_params) do
        local value = safe_get(from_track .. param)
        if param == "pan" and mirror_pan then
            safe_set(to_track .. param, -value)
        else
            safe_set(to_track .. param, value)
        end
    end

    local available_lfos = {}
    for i = 1, 16 do if safe_get(_LFO_KEYS[i]) ~= 2 then available_lfos[#available_lfos + 1] = i end end
    local next_available = 1

    local from_len = #from_track
    local global_freq_scale = params:get("global_lfo_freq_scale") or 1

    for src_lfo = 1, 16 do
        if safe_get(_LFO_KEYS[src_lfo]) == 2 then
            local src_target_index = safe_get(_TARGET_KEYS[src_lfo])
            if src_target_index > 0 then
                local src_target_name = lfo_targets[src_target_index]
                if src_target_name and src_target_name:sub(1, from_len) == from_track then
                    local src_param_name = src_target_name:sub(from_len + 1)
                    local dest_target_name = to_track .. src_param_name
                    local dest_target_index = target_lookup[dest_target_name]
                    if dest_target_index and next_available <= #available_lfos then
                        local dest_lfo = available_lfos[next_available]; next_available = next_available + 1

                        local src_shape = safe_get(_SHAPE_KEYS[src_lfo])
                        local src_freq = safe_get(_FREQ_KEYS[src_lfo])
                        local src_depth = safe_get(_DEPTH_KEYS[src_lfo])
                        local src_offset = safe_get(_OFFSET_KEYS[src_lfo])
                        local current_phase = (Mirror.lfo[src_lfo] and Mirror.lfo[src_lfo].phase) or 0

                        if src_param_name == "pan" and mirror_pan then
                            src_offset = -src_offset
                            current_phase = (current_phase + 0.5) % 1
                        elseif src_param_name == "volume" then
                            local current_vol = safe_get(from_track .. "volume")
                            local vol_offset = current_vol - src_offset
                            safe_set(to_track .. "volume", current_vol)
                            src_offset = current_vol - vol_offset
                        end

                        safe_set(_TARGET_KEYS[dest_lfo], dest_target_index)
                        safe_set(_SHAPE_KEYS[dest_lfo], src_shape)
                        safe_set(_FREQ_KEYS[dest_lfo], src_freq)
                        safe_set(_DEPTH_KEYS[dest_lfo], src_depth)
                        safe_set(_OFFSET_KEYS[dest_lfo], src_offset)
                        safe_set(_LFO_KEYS[dest_lfo], 2)

                        local d_obj = Mirror.lfo[dest_lfo]
                        if d_obj then
                            d_obj.target = dest_target_index
                            d_obj.shape = src_shape
                            d_obj.freq = src_freq * global_freq_scale
                            d_obj.depth = src_depth
                            d_obj.offset = src_offset
                            d_obj.phase = current_phase
                            d_obj.base_freq = src_freq
                        end
                    end
                end
            end
        end
    end
end

return Mirror