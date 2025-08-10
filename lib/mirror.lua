local Mirror = {}

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
            local target_name = lfo.lfo_targets[target_index] or ""
            if target_name:match("^"..to_track) then
                params:set(lfo_num.."lfo", 1)
            end
        end
    end
end

function Mirror.copy_voice_params(from_track, to_track, mirror_pan)
    clear_destination_lfos(to_track)
    local params_to_copy = {
        "speed", "pitch", "jitter", "spread", "density", "size", "seek", "pan",
        "cutoff", "hpf", "eq_low_gain", "eq_high_gain",
        "granular_gain", "subharmonics_3", "subharmonics_2", "subharmonics_1",
        "overtones_1", "overtones_2", "smoothbass", "pitch_random_plus",
        "pitch_random_minus", "size_variation", "density_mod_amt", "direction_mod",
        "pitch_mode", "trig_mode", "probability"
    }
    local volume_has_lfo = false
    for lfo_num = 1, 16 do
        if safe_get(lfo_num.."lfo") == 2 then
            local target_index = safe_get(lfo_num.."lfo_target") or 0
            if target_index > 0 and (lfo.lfo_targets[target_index] or ""):match("^"..from_track.."volume$") then
                volume_has_lfo = true
                break
            end
        end
    end
    if not volume_has_lfo then
        safe_set(to_track.."volume", safe_get(from_track.."volume"))
    end
    for _, param in ipairs(params_to_copy) do
        local from_param = from_track..param
        local to_param = to_track..param
        if param == "pan" and mirror_pan then
            safe_set(to_param, -safe_get(from_param))
        else
            safe_set(to_param, safe_get(from_param))
        end
    end
    for src_lfo = 1, 16 do
        if safe_get(src_lfo.."lfo") == 2 then
            local src_target_index = safe_get(src_lfo.."lfo_target") or 0
            if src_target_index > 0 then
                local src_target_name = lfo.lfo_targets[src_target_index] or ""
                local src_track_prefix, src_param_name = src_target_name:match("^(%d+)(.+)$")
                if src_track_prefix == from_track then
                    local dest_target_name = to_track..src_param_name
                    local dest_target_index = nil
                    for idx, target in ipairs(lfo.lfo_targets) do
                        if target == dest_target_name then
                            dest_target_index = idx
                            break
                        end
                    end
                    if dest_target_index then
                        local dest_lfo = nil
                        for i = 1, 16 do
                            if safe_get(i.."lfo") ~= 2 then
                                dest_lfo = i
                                break
                            end
                        end
                        if dest_lfo then
                            local src_shape = safe_get(src_lfo.."lfo_shape")
                            local src_freq = safe_get(src_lfo.."lfo_freq")
                            local src_depth = safe_get(src_lfo.."lfo_depth")
                            local src_offset = safe_get(src_lfo.."offset")
                            local current_phase = (lfo[src_lfo] and lfo[src_lfo].phase) or 0
                            if src_param_name == "pan" and mirror_pan then
                                src_offset = -src_offset
                                current_phase = (current_phase + 0.5) % 1
                            elseif src_param_name == "volume" then
                                local current_vol = safe_get(from_track.."volume")
                                local vol_offset = current_vol - src_offset
                                safe_set(to_track.."volume", current_vol)
                                src_offset = (current_vol - vol_offset)
                            end
                            safe_set(dest_lfo.."lfo_target", dest_target_index)
                            safe_set(dest_lfo.."lfo_shape", src_shape)
                            safe_set(dest_lfo.."lfo_freq", src_freq)
                            safe_set(dest_lfo.."lfo_depth", src_depth)
                            safe_set(dest_lfo.."offset", src_offset)
                            safe_set(dest_lfo.."lfo", 2)
                            if lfo[dest_lfo] then
                                lfo[dest_lfo].target = dest_target_index
                                lfo[dest_lfo].shape = src_shape
                                lfo[dest_lfo].freq = src_freq
                                lfo[dest_lfo].depth = src_depth
                                lfo[dest_lfo].offset = src_offset
                                lfo[dest_lfo].phase = current_phase
                            end
                        end
                    end
                end
            end
        end
    end
end

return Mirror