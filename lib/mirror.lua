local Mirror = {}

local params_lookup = nil
local lfo_targets = nil

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
end

function Mirror.copy_voice_params(from_track, to_track, mirror_pan)
    -- Clear destination LFOs first
    local function clear_destination_lfos(to_track_num)
        local pattern = get_track_pattern(to_track_num)
        for lfo_num = 1, 16 do
            local t_index = safe_get(lfo_num .. "lfo_target")
            if t_index > 0 then
                local tname = lfo_targets[t_index]
                if tname and tname:match(pattern) then
                    params:set(lfo_num .. "lfo", 1)
                end
            end
        end
    end

    clear_destination_lfos(to_track)

    local from_num = tonumber(from_track)
    local to_num = tonumber(to_track)
    if Mirror.osc_positions[from_num] then Mirror.osc_positions[to_num] = Mirror.osc_positions[from_num] end

    -- Check volume LFO existence
    local volume_has_lfo = false
    local from_volume_target = from_track .. "volume"
    for i = 1, 16 do
        if safe_get(i .. "lfo") == 2 then
            local t_idx = safe_get(i .. "lfo_target")
            if t_idx > 0 then
                local target_name = lfo_targets[t_idx]
                if target_name == from_volume_target then volume_has_lfo = true; break end
            end
        end
    end

    if not volume_has_lfo then
        safe_set(to_track .. "volume", safe_get(from_track .. "volume"))
    end

    local static_params = {
        "speed", "pitch", "jitter", "spread", "density", "size", "pan",
        "cutoff", "hpf", "eq_low_gain", "eq_high_gain",
        "granular_gain", "subharmonics_3", "subharmonics_2", "subharmonics_1",
        "overtones_1", "overtones_2", "smoothbass", "pitch_random_plus",
        "pitch_random_minus", "size_variation", "density_mod_amt", "direction_mod",
        "pitch_mode", "trig_mode", "probability", "pitch_walk_mode","pitch_walk_scale","pitch_walk_rate","pitch_walk_step"
    }

    for _, param in ipairs(static_params) do
        local value = safe_get(from_track .. param)
        if param == "pan" and mirror_pan then
            safe_set(to_track .. param, -value)
        else
            safe_set(to_track .. param, value)
        end
    end

    -- Seek copy and engine seek
    local seek_value = safe_get(from_track .. "seek")
    safe_set(to_track .. "seek", seek_value)
    engine.seek(to_num, seek_value * 0.01)

    -- Build a lookup for target names -> index
    local target_lookup = {}
    for idx, t in ipairs(lfo_targets) do target_lookup[t] = idx end

    -- Find free LFO slots once, gather them
    local available_lfos = {}
    for i = 1, 16 do if safe_get(i .. "lfo") ~= 2 then available_lfos[#available_lfos + 1] = i end end
    local next_available = 1

    local from_len = #from_track
    local global_freq_scale = params:get("global_lfo_freq_scale") or 1

    -- Copy LFOs from source to destination for params that match (1xxx -> 2xxx)
    for src_lfo = 1, 16 do
        if safe_get(src_lfo .. "lfo") == 2 then
            local src_target_index = safe_get(src_lfo .. "lfo_target")
            if src_target_index > 0 then
                local src_target_name = lfo_targets[src_target_index]
                if src_target_name and src_target_name:sub(1, from_len) == from_track then
                    local src_param_name = src_target_name:sub(from_len + 1)
                    local dest_target_name = to_track .. src_param_name
                    local dest_target_index = target_lookup[dest_target_name]
                    if dest_target_index and next_available <= #available_lfos then
                        local dest_lfo = available_lfos[next_available]; next_available = next_available + 1

                        -- Read source LFO parameters
                        local src_shape = safe_get(src_lfo .. "lfo_shape")
                        local src_freq = safe_get(src_lfo .. "lfo_freq")
                        local src_depth = safe_get(src_lfo .. "lfo_depth")
                        local src_offset = safe_get(src_lfo .. "offset")
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

                        -- Batch set destination LFO params
                        safe_set(dest_lfo .. "lfo_target", dest_target_index)
                        safe_set(dest_lfo .. "lfo_shape", src_shape)
                        safe_set(dest_lfo .. "lfo_freq", src_freq)
                        safe_set(dest_lfo .. "lfo_depth", src_depth)
                        safe_set(dest_lfo .. "offset", src_offset)
                        safe_set(dest_lfo .. "lfo", 2)

                        -- Update mirror's LFO object if present
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