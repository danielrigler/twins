local drymode = {}

local dry_mode = false
local prev_settings = {}

function drymode.set_lfo_reference(lfo_module)
    lfo = lfo_module
end

function drymode.toggle_dry_mode()
    dry_mode_state = not dry_mode_state
    if not dry_mode_state then
        -- Store current settings including LFO states
        prev_settings = {
            granular_gain = {params:get("1granular_gain"), params:get("2granular_gain")},
            speed = {params:get("1speed"), params:get("2speed")},
            reverb_mix = params:get("reverb_mix"),
            delay_mix = params:get("delay_mix"),
            shimmer_mix = params:get("shimmer_mix"),
            tape_mix = params:get("tape_mix"),
            drive = params:get("drive"),
            eq_low_gain = {params:get("1eq_low_gain"), params:get("2eq_low_gain")},
            eq_high_gain = {params:get("1eq_high_gain"), params:get("2eq_high_gain")},
            cutoff = {params:get("1cutoff"), params:get("2cutoff")},
            hpf = {params:get("1hpf"), params:get("2hpf")},
            Width = params:get("Width"),
            monobass_mix = params:get("monobass_mix"),
            sine_mix = params:get("sine_mix"),
            wobble_mix = params:get("wobble_mix"),
            chew_depth = params:get("chew_depth"),
            lossdegrade_mix = params:get("lossdegrade_mix"),
            -- Store complete LFO states
            speed_lfos = {},
            seek_lfos = {},
            volume_lfos = {},
            pan_lfos = {}
        }
        
        -- Store and disable LFOs controlling speed, seek, and pan
        for i = 1, 16 do
            local target = lfo.lfo_targets[params:get(i.."lfo_target")]
            if target then
                if target == "1speed" or target == "2speed" then
                    prev_settings.speed_lfos[i] = {
                        state = params:get(i.."lfo"),
                        target_index = params:get(i.."lfo_target"),
                        shape = params:get(i.."lfo_shape"),
                        depth = params:get(i.."lfo_depth"),
                        offset = params:get(i.."offset"),
                        freq = params:get(i.."lfo_freq")
                    }
                    params:set(i.."lfo", 1) -- Turn off
                elseif target == "1seek" or target == "2seek" then
                    prev_settings.seek_lfos[i] = {
                        state = params:get(i.."lfo"),
                        target_index = params:get(i.."lfo_target"),
                        shape = params:get(i.."lfo_shape"),
                        depth = params:get(i.."lfo_depth"),
                        offset = params:get(i.."offset"),
                        freq = params:get(i.."lfo_freq")
                    }
                    params:set(i.."lfo", 1) -- Turn off
                elseif target and (target == "1pan" or target == "2pan") then
                    prev_settings.pan_lfos[i] = {
                        state = params:get(i.."lfo"),
                        target_index = params:get(i.."lfo_target"),
                        shape = params:get(i.."lfo_shape"),
                        depth = params:get(i.."lfo_depth"),
                        offset = params:get(i.."offset"),
                        freq = params:get(i.."lfo_freq")
                    }
                    params:set(i.."lfo", 1) -- Turn off 
                elseif target and (target == "1volume" or target == "2volume") then
                    prev_settings.volume_lfos[i] = {
                        state = params:get(i.."lfo"),
                        target_index = params:get(i.."lfo_target"),
                        shape = params:get(i.."lfo_shape"),
                        depth = params:get(i.."lfo_depth"),
                        offset = params:get(i.."offset"),
                        freq = params:get(i.."lfo_freq")
                    }
                    params:set(i.."lfo", 1) -- Turn off                     
                end
            end
        end
        
        params:set("1pan", 0)
        params:set("2pan", 0)
        
        -- Set dry mode values
        for i = 1, 2 do
            params:set(i.."granular_gain", 0)
            params:set(i.."speed", 1.0)
            params:set(i.."eq_low_gain", 0)
            params:set(i.."eq_high_gain", 0)
            params:set(i.."cutoff", 20000)
            params:set(i.."hpf", 20)
        end
        params:set("reverb_mix", 0)
        params:set("delay_mix", 0)
        params:set("shimmer_mix", 0)
        params:set("tape_mix", 1)
        params:set("drive", 0)
        params:set("Width", 100)
        params:set("monobass_mix", 1)
        params:set("sine_mix", 0)
        params:set("wobble_mix", 0)
        params:set("chew_depth", 0)
        params:set("lossdegrade_mix", 0)
    else
        -- Restore previous settings
        if next(prev_settings) ~= nil then
            for i = 1, 2 do
                params:set(i.."granular_gain", prev_settings.granular_gain[i])
                params:set(i.."speed", prev_settings.speed[i])
                params:set(i.."eq_low_gain", prev_settings.eq_low_gain[i])
                params:set(i.."eq_high_gain", prev_settings.eq_high_gain[i])
                params:set(i.."cutoff", prev_settings.cutoff[i])
                params:set(i.."hpf", prev_settings.hpf[i])
            end
            params:set("reverb_mix", prev_settings.reverb_mix)
            params:set("delay_mix", prev_settings.delay_mix)
            params:set("shimmer_mix", prev_settings.shimmer_mix)
            params:set("tape_mix", prev_settings.tape_mix)
            params:set("drive", prev_settings.drive)
            params:set("Width", prev_settings.Width)
            params:set("monobass_mix", prev_settings.monobass_mix)
            params:set("sine_mix", prev_settings.sine_mix)
            params:set("wobble_mix", prev_settings.wobble_mix)
            params:set("chew_depth", prev_settings.chew_depth)
            params:set("lossdegrade_mix", prev_settings.lossdegrade_mix)
            
            if prev_settings.pan then
                params:set("1pan", prev_settings.pan[1])
                params:set("2pan", prev_settings.pan[2])
            end
            
            -- Restore LFOs with safety checks
            local function restore_lfos(lfo_table)
                if lfo_table then
                    for i, lfo_data in pairs(lfo_table) do
                        if lfo_data then
                            -- Temporarily disable LFO processing
                            local was_paused = params:get("lfo_pause")
                            params:set("lfo_pause", 1)
                            
                            -- Restore all parameters
                            params:set(i.."lfo_target", lfo_data.target_index)
                            params:set(i.."lfo_shape", lfo_data.shape)
                            params:set(i.."lfo_depth", lfo_data.depth)
                            params:set(i.."offset", lfo_data.offset)
                            params:set(i.."lfo_freq", lfo_data.freq)
                            
                            -- Restore state and re-enable processing
                            params:set(i.."lfo", lfo_data.state)
                            params:set("lfo_pause", was_paused)
                        end
                    end
                end
            end
            
            -- Restore all three types of LFOs
            restore_lfos(prev_settings.speed_lfos)
            restore_lfos(prev_settings.seek_lfos)
            restore_lfos(prev_settings.pan_lfos)
            restore_lfos(prev_settings.volume_lfos)
        end
    end
end

function drymode.toggle_dry_mode2()
    dry_mode_state2 = not dry_mode_state2
    if not dry_mode_state2 then
        prev_settings = {
            granular_gain = {params:get("1granular_gain"), params:get("2granular_gain")},
            speed = {params:get("1speed"), params:get("2speed")}
        }
        for i = 1, 2 do
            params:set(i.."granular_gain", 0)
            params:set(i.."speed", 1.0)
        end
    else
        if next(prev_settings) ~= nil then
            for i = 1, 2 do
                params:set(i.."granular_gain", prev_settings.granular_gain[i])
                params:set(i.."speed", prev_settings.speed[i])
            end
        end
    end
end

return drymode