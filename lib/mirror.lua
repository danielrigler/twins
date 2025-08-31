local Mirror = {}

-- Cache frequently accessed values
local params_lookup = nil
local lfo_targets = nil

function Mirror.init(osc_positions_ref, lfo_ref)
    Mirror.osc_positions = osc_positions_ref or {}
    Mirror.lfo = lfo_ref
    
    -- Cache references for performance
    params_lookup = params.lookup
    lfo_targets = lfo_ref and lfo_ref.lfo_targets
end

-- Optimized parameter functions with reduced lookups
local function param_exists(name)
    return params_lookup[name] ~= nil
end

local function safe_get(name)
    return params_lookup[name] and params:get(name) or 0
end

local function safe_set(name, value)
    if params_lookup[name] and value ~= nil then
        params:set(name, value)
    end
end

-- Pre-compiled pattern for better performance
local track_pattern_cache = {}
local function get_track_pattern(track)
    if not track_pattern_cache[track] then
        track_pattern_cache[track] = "^" .. track
    end
    return track_pattern_cache[track]
end

local function clear_destination_lfos(to_track)
    local track_pattern = get_track_pattern(to_track)
    
    for lfo_num = 1, 16 do
        local target_index = safe_get(lfo_num .. "lfo_target")
        if target_index > 0 then
            local target_name = lfo_targets[target_index]
            if target_name and target_name:match(track_pattern) then
                params:set(lfo_num .. "lfo", 1)
            end
        end
    end
end

function Mirror.copy_voice_params(from_track, to_track, mirror_pan)
    -- Clear destination LFOs first
    clear_destination_lfos(to_track)
    
    -- Copy the OSC position (actual playback position)
    if Mirror.osc_positions[tonumber(from_track)] then
        Mirror.osc_positions[tonumber(to_track)] = Mirror.osc_positions[tonumber(from_track)]
    end
    
    -- Parameter list (static, no table creation each call)
    local static_params = {
        "speed", "pitch", "jitter", "spread", "density", "size", "pan",
        "cutoff", "hpf", "eq_low_gain", "eq_high_gain",
        "granular_gain", "subharmonics_3", "subharmonics_2", "subharmonics_1",
        "overtones_1", "overtones_2", "smoothbass", "pitch_random_plus",
        "pitch_random_minus", "size_variation", "density_mod_amt", "direction_mod",
        "pitch_mode", "trig_mode", "probability"
    }

    -- Check for volume LFO more efficiently
    local volume_has_lfo = false
    local from_volume_target = from_track .. "volume"
    
    for lfo_num = 1, 16 do
        if safe_get(lfo_num .. "lfo") == 2 then
            local target_index = safe_get(lfo_num .. "lfo_target")
            if target_index > 0 then
                local target_name = lfo_targets[target_index]
                if target_name == from_volume_target then
                    volume_has_lfo = true
                    break
                end
            end
        end
    end
    
    -- Handle volume if no LFO
    if not volume_has_lfo then
        safe_set(to_track .. "volume", safe_get(from_track .. "volume"))
    end

    -- Copy regular parameters with batch operations
    for i = 1, #static_params do
        local param = static_params[i]
        local from_param = from_track .. param
        local to_param = to_track .. param
        local value = safe_get(from_param)
        
        if param == "pan" and mirror_pan then
            safe_set(to_param, -value)
        else
            safe_set(to_param, value)
        end
    end

    -- Handle seek
    local seek_value = safe_get(from_track .. "seek")
    safe_set(to_track .. "seek", seek_value)
    local normalized = seek_value * 0.01
    engine.seek(to_track, normalized)

    -- Optimized LFO mirroring with early exits and cached lookups
    local from_track_pattern = get_track_pattern(from_track)
    local to_track_len = #to_track
    local global_freq_scale = params:get("global_lfo_freq_scale") or 1
    
    -- Build target lookup table for faster searching
    local target_lookup = {}
    for idx, target in ipairs(lfo_targets) do
        target_lookup[target] = idx
    end
    
    -- Find available LFO slots once
    local available_lfos = {}
    for i = 1, 16 do
        if safe_get(i .. "lfo") ~= 2 then
            available_lfos[#available_lfos + 1] = i
        end
    end
    local next_available = 1
    
    for src_lfo = 1, 16 do
        if safe_get(src_lfo .. "lfo") == 2 then
            local src_target_index = safe_get(src_lfo .. "lfo_target")
            if src_target_index > 0 then
                local src_target_name = lfo_targets[src_target_index]
                if src_target_name and src_target_name:sub(1, to_track_len) == from_track then
                    local src_param_name = src_target_name:sub(to_track_len + 1)
                    local dest_target_name = to_track .. src_param_name
                    local dest_target_index = target_lookup[dest_target_name]
                    
                    if dest_target_index and next_available <= #available_lfos then
                        local dest_lfo = available_lfos[next_available]
                        next_available = next_available + 1
                        
                        -- Batch read source LFO parameters
                        local src_shape = safe_get(src_lfo .. "lfo_shape")
                        local src_freq = safe_get(src_lfo .. "lfo_freq")
                        local src_depth = safe_get(src_lfo .. "lfo_depth")
                        local src_offset = safe_get(src_lfo .. "offset")
                        local current_phase = (Mirror.lfo[src_lfo] and Mirror.lfo[src_lfo].phase) or 0
                        
                        -- Handle special parameter cases
                        if src_param_name == "pan" and mirror_pan then
                            src_offset = -src_offset
                            current_phase = (current_phase + 0.5) % 1
                        elseif src_param_name == "volume" then
                            local current_vol = safe_get(from_track .. "volume")
                            local vol_offset = current_vol - src_offset
                            safe_set(to_track .. "volume", current_vol)
                            src_offset = current_vol - vol_offset
                        end
                        
                        -- Batch set destination LFO parameters
                        safe_set(dest_lfo .. "lfo_target", dest_target_index)
                        safe_set(dest_lfo .. "lfo_shape", src_shape)
                        safe_set(dest_lfo .. "lfo_freq", src_freq)
                        safe_set(dest_lfo .. "lfo_depth", src_depth)
                        safe_set(dest_lfo .. "offset", src_offset)
                        safe_set(dest_lfo .. "lfo", 2)
                        
                        -- Update LFO object efficiently
                        local dest_lfo_obj = Mirror.lfo[dest_lfo]
                        if dest_lfo_obj then
                            dest_lfo_obj.target = dest_target_index
                            dest_lfo_obj.shape = src_shape
                            dest_lfo_obj.freq = src_freq * global_freq_scale
                            dest_lfo_obj.depth = src_depth
                            dest_lfo_obj.offset = src_offset
                            dest_lfo_obj.phase = current_phase
                            dest_lfo_obj.base_freq = src_freq
                        end
                    end
                end
            end
        end
    end
end

return Mirror