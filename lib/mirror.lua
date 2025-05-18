-- mirror.lua
local Mirror = {}

function Mirror.init(lfo_ref)
    Mirror.lfo = lfo_ref
end

local function param_exists(name)
    return params.lookup[name] ~= nil
end

local function safe_get(name)
    return param_exists(name) and params:get(name) or 0
end

local function safe_set(name, value)
    if param_exists(name) and value ~= nil then
        params:set(name, value)
    end
end

local function clear_destination_lfos(to_track)
    for lfo_num = 1, 16 do
        local target_index = safe_get(lfo_num.."lfo_target") or 0
        if target_index > 0 then
            local target_name = Mirror.lfo.lfo_targets[target_index] or ""
            if target_name:match("^"..to_track) then
                params:set(lfo_num.."lfo", 1)  -- Disable LFO
            end
        end
    end
end

function Mirror.copy_voice_params(from_track, to_track, mirror_pan)
    -- 1. Clear destination LFOs first
    clear_destination_lfos(to_track)

    -- 2. Copy all voice parameters
    local params_to_copy = {
        "speed", "pitch", "jitter", "spread", "density", "size", "seek", "pan",
        "cutoff", "hpf", "eq_low_gain", "eq_high_gain",
        "granular_gain", "subharmonics_3", "subharmonics_2", "subharmonics_1",
        "overtones_1", "overtones_2", "smoothbass", "pitch_random_plus",
        "pitch_random_minus", "size_variation", "density_mod_amt", "direction_mod",
        "pitch_mode"
    }

    -- Handle volume separately (only copy if no LFO is affecting it)
    local volume_has_lfo = false
    for lfo_num = 1, 16 do
        if safe_get(lfo_num.."lfo") == 2 then
            local target_index = safe_get(lfo_num.."lfo_target") or 0
            if target_index > 0 and (Mirror.lfo.lfo_targets[target_index] or ""):match("^"..from_track.."volume$") then
                volume_has_lfo = true
                break
            end
        end
    end

    if not volume_has_lfo then
        safe_set(to_track.."volume", safe_get(from_track.."volume"))
    end

    -- Copy other parameters
    for _, param in ipairs(params_to_copy) do
        local from_param = from_track..param
        local to_param = to_track..param
        
        if param == "pan" and mirror_pan then
            safe_set(to_param, -safe_get(from_param))
        else
            safe_set(to_param, safe_get(from_param))
        end
    end

    -- 3. Mirror LFOs with perfect phase synchronization
    for src_lfo = 1, 16 do
        if safe_get(src_lfo.."lfo") == 2 then  -- Only active LFOs
            local src_target_index = safe_get(src_lfo.."lfo_target") or 0
            if src_target_index > 0 then
                local src_target_name = Mirror.lfo.lfo_targets[src_target_index] or ""
                local src_track_prefix, src_param_name = src_target_name:match("^(%d+)(.+)$")
                
                if src_track_prefix == from_track then
                    -- Find matching destination parameter
                    local dest_target_name = to_track..src_param_name
                    local dest_target_index = nil
                    
                    for idx, target in ipairs(Mirror.lfo.lfo_targets) do
                        if target == dest_target_name then
                            dest_target_index = idx
                            break
                        end
                    end
                    
                    if dest_target_index then
                        -- Find first available LFO slot
                        local dest_lfo = nil
                        for i = 1, 16 do
                            if safe_get(i.."lfo") ~= 2 then  -- Find inactive LFO
                                dest_lfo = i
                                break
                            end
                        end
                        
                        if dest_lfo then
                            -- Get source parameters
                            local src_shape = safe_get(src_lfo.."lfo_shape")
                            local src_freq = safe_get(src_lfo.."lfo_freq")
                            local src_depth = safe_get(src_lfo.."lfo_depth")
                            local src_offset = safe_get(src_lfo.."offset")
                            
                            -- Get the ACTUAL current phase from running LFO
                            local current_phase = 0
                            if Mirror.lfo[src_lfo] then
                                current_phase = Mirror.lfo[src_lfo].phase or 0
                                -- For smoother sync, capture the exact fractional phase
                                if Mirror.lfo[src_lfo].clock and Mirror.lfo[src_lfo].period then
                                    current_phase = (Mirror.lfo[src_lfo].clock % Mirror.lfo[src_lfo].period) / Mirror.lfo[src_lfo].period
                                end
                            end
                            
                            -- Special handling for mirrored parameters
                            if src_param_name == "pan" and mirror_pan then
                                src_offset = -src_offset
                                current_phase = (current_phase + 0.5) % 1  -- 180° phase shift for pan mirroring
                            elseif src_param_name == "volume" then
                                -- Maintain volume relationship
                                local current_vol = safe_get(from_track.."volume")
                                local vol_offset = current_vol - src_offset
                                safe_set(to_track.."volume", current_vol)
                                src_offset = (current_vol - vol_offset)
                            end
                            
                            -- Set destination LFO parameters
                            safe_set(dest_lfo.."lfo_target", dest_target_index)
                            safe_set(dest_lfo.."lfo_shape", src_shape)
                            safe_set(dest_lfo.."lfo_freq", src_freq)
                            safe_set(dest_lfo.."lfo_depth", src_depth)
                            safe_set(dest_lfo.."offset", src_offset)
                            safe_set(dest_lfo.."lfo_phase", current_phase)  -- Use exact captured phase
                            safe_set(dest_lfo.."lfo", 2)  -- Activate last
                            
                            -- Force immediate engine update with perfect phase sync
                            if Mirror.lfo[dest_lfo] then
                                Mirror.lfo[dest_lfo].target = dest_target_index
                                Mirror.lfo[dest_lfo].shape = src_shape
                                Mirror.lfo[dest_lfo].freq = src_freq
                                Mirror.lfo[dest_lfo].depth = src_depth
                                Mirror.lfo[dest_lfo].offset = src_offset
                                Mirror.lfo[dest_lfo].phase = current_phase
                                Mirror.lfo[dest_lfo].clock = current_phase * (1/src_freq)  -- Set exact position in cycle
                            end
                        end
                    end
                end
            end
        end
    end
end

return Mirror