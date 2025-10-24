--
--
--   __ __|         _)          
--      | \ \  \  / |  \ |  (_< 
--      |  \_/\_/ _| _| _| __/ 
--            by: @dddstudio                       
-- 
--                          
--                           v0.46
-- E1: Master Volume
-- K1+E2/E3: Volume 1/2
-- Hold K1: Mode Select
-- K1+E1: Crossfade/Morph
-- K2/K3: Navigate
-- E2/E3: Adjust Parameters
-- K2+K3: Lock Parameters
-- K2+K3: HP/LP Filter 
-- K1+K2/K3: Randomize 1/2
--
--
--
--
--              
--
--
--
--
-- Thanks to:
-- @infinitedigits @cfdrake 
-- @justmat @artfwo @nzimas
-- @sonoCircuit @graymazes
-- @Higaru @NiklasKramer
-- @xmacex @vehka
--
-- If you like this,
-- buy them a beer :)
--
--                    Daniel Rigler

installer_ = include("lib/scinstaller/scinstaller")
installer = installer_:new{requirements = {"AnalogTape", "AnalogChew", "AnalogLoss", "AnalogDegrade"},
    zip = "https://github.com/schollz/portedplugins/releases/download/v0.4.6/PortedPlugins-RaspberryPi.zip"}
engine.name = installer:ready() and 'twins' or nil
local presets = include("lib/presets")
local randpara = include("lib/randpara")
local lfo = include("lib/lfo")
local Mirror = include("lib/mirror") Mirror.init(osc_positions, lfo)
local macro = include("lib/macro") macro.set_lfo_reference(lfo)
local drymode = include("lib/drymode") drymode.set_lfo_reference(lfo)
local randomize_metro = { [1] = nil, [2] = nil }
local ui_metro = nil
local key_state = {} for n = 1, 3 do key_state[n] = false end
local current_mode = "seek"
local current_filter_mode = "lpf"
local tap_times = {}
local TAP_TIMEOUT = 2
local initial_monitor_level
local initial_reverb_onoff
local filter_lock_ratio = false
local filter_differences = {[1] = 0, [2] = 0}
local audio_active = {[1] = false, [2] = false}
local morph_amount = 0
local valid_audio_exts = {[".wav"]=true,[".aif"]=true,[".aiff"]=true,[".flac"]=true}
local mode_list = {"pitch","spread","density","size","jitter","lpf","pan","speed","seek"}
local mode_indices = {}; for i,v in ipairs(mode_list) do mode_indices[v]=i end
local mode_list2 = {"seek","speed","pan","lpf","jitter","size","density","spread","pitch"}
local mode_indices2 = {}; for i,v in ipairs(mode_list2) do mode_indices2[v]=i end
local key1_press_time = nil
local key1_long_press_triggered = false
local key1_monitor_metro = nil
local key1_has_other_interaction = false
local KEY1_LONG_PRESS_THRESHOLD = 1 
local current_scene_mode = "off"
local preset_loading = false
local scene_data = {[1] = {[1] = {}, [2] = {}}, [2] = {[1] = {}, [2] = {}}}
local evolution_animation_phase = 0
local evolution_animation_time = 0
local patterns = {[0] = {}, [1] = {{6,0}}, [2] = {{6,0}, {8,0}}, [3] = {{6,0}, {8,0}, {10,0}}, [4] = {{6,0}, {8,0}}, [5] = {{6,0}}}
local grain_positions = {[1] = {}, [2] = {}}
local osc_positions = {[1] = 0, [2] = 0}
local rec_positions = {[1] = 0, [2] = 0}
local param_modes = {
    speed = {param = "speed", delta = 0.5, engine = true, has_lock = true},
    seek = {param = "seek", delta = 1, engine = true, has_lock = true},
    pan = {param = "pan", delta = 5, engine = true, has_lock = true, invert = true},
    lpf = {param = "cutoff", delta = 1, engine = true, has_lock = false},
    hpf = {param = "hpf", delta = 1, engine = true, has_lock = false},
    jitter = {param = "jitter", delta = 2, engine = true, has_lock = true},
    size = {param = "size", delta = 2, engine = true, has_lock = true},
    density = {param = "density", delta = 2, engine = true, has_lock = true},
    spread = {param = "spread", delta = 2, engine = true, has_lock = true},
    pitch = {param = "pitch", delta = 1, engine = true, has_lock = true}}
local param_rows = {
    {y = 11, label = "jitter:    ", mode = "jitter", param1 = "1jitter", param2 = "2jitter"},
    {y = 21, label = "size:     ", mode = "size", param1 = "1size", param2 = "2size"},
    {y = 31, label = "density:  ", mode = "density", param1 = "1density", param2 = "2density", hz = true},
    {y = 41, label = "spread:   ", mode = "spread", param1 = "1spread", param2 = "2spread"},
    {y = 51, label = "pitch:    ", mode = "pitch", param1 = "1pitch", param2 = "2pitch", st = true}}
local animation_x = 0 animation_y = -64 animation_speed = 100 animation_complete = false animation_start_time = nil animation_directions = {"top", "bottom", "left", "right"} current_animation_direction = "top"

local function table_find(tbl, value) for i = 1, #tbl do if tbl[i] == value then return i end end return nil end
local function is_audio_loaded(track_num) local file_path = params:get(track_num .. "sample") return (file_path and file_path ~= "-") or audio_active[track_num] end
local function random_float(l, h) return l + math.random() * (h - l) end
local function stop_metro_safe(m) if m then local ok, err = pcall(function() m:stop() end) if m then m.event = nil end end end
local function update_evolution_animation() if params:get("evolution") == 1 then evolution_animation_time = evolution_animation_time + (1/60) local cycle_duration = 0.3 evolution_animation_phase = math.floor((evolution_animation_time / cycle_duration) % 6) else evolution_animation_time = 0 evolution_animation_phase = 0 end end
local function is_param_locked(track_num, param) return params:get(track_num .. "lock_" .. param) == 2 end
local function is_lfo_active_for_param(param_name) for i = 1, 16 do local target_index = params:get(i.. "lfo_target") if lfo.lfo_targets[target_index] == param_name and params:get(i.. "lfo") == 2 then return true, i end end    return false, nil end
local function update_pan_positioning() local loaded1 = is_audio_loaded(1) local loaded2 = is_audio_loaded(2) if not is_param_locked(1, "pan") and not is_lfo_active_for_param("1pan") then params:set("1pan", loaded2 and -15 or 0) end if not is_param_locked(2, "pan") and not is_lfo_active_for_param("2pan") then params:set("2pan", loaded1 and 15 or 0) end end

local function setup_ui_metro()
    current_animation_direction = animation_directions[math.random(4)]
    ui_metro = metro.init()
    ui_metro.time = 1/60
    ui_metro.event = function()
        update_evolution_animation()
        if animation_complete then redraw() return end
        animation_start_time = animation_start_time or util.time()
        local elapsed = util.time() - animation_start_time
        local progress = util.clamp(elapsed * animation_speed / 64, 0, 1)
        local eased = 1 - (1 - progress) * (1 - progress) * (1 - progress)
        if current_animation_direction == "top" then animation_y = -64 + (eased * 64) animation_x = 0
        elseif current_animation_direction == "bottom" then animation_y = 64 - (eased * 64) animation_x = 0
        elseif current_animation_direction == "left" then animation_x = -128 + (eased * 128) animation_y = 0
        elseif current_animation_direction == "right" then animation_x = 128 - (eased * 128) animation_y = 0 end
        if progress >= 1 then animation_complete = true animation_x = 0 animation_y = 0 end
        redraw()
    end
    ui_metro:start()
end

local morph_voice_params = { "speed", "pitch", "jitter", "size", "density", "spread", "pan", "seek",
                             "cutoff", "hpf", "lpfgain", "granular_gain", "subharmonics_3", "subharmonics_2",
                             "subharmonics_1", "overtones_1", "overtones_2", "smoothbass",
                             "pitch_walk_rate", "pitch_walk_step", "ratcheting_prob",
                             "size_variation", "direction_mod", "density_mod_amt", "pitch_random_scale_type", "pitch_random_prob",
                             "pitch_mode", "trig_mode", "probability", "eq_low_gain", "eq_mid_gain", "eq_high_gain", "env_select", "volume" }
                       
local morph_global_params = { "delay_mix", "delay_time", "delay_feedback", "delay_lowpass", "delay_highpass", "wiggle_depth", "wiggle_rate", "stereo", 
                              "reverb_mix", "t60", "damp", "rsize", "earlyDiff", "modDepth", "modFreq", "low", "mid", "high", "lowcut", "highcut", 
                              "shimmer_mix", "o2", "pitchv", "lowpass", "hipass", "fbDelay", "fb", "lock_shimmer",
                              "tape_mix", "sine_drive", "drive", "wobble_mix", "wobble_amp", "wobble_rpm", "flutter_amp", "flutter_freq", "flutter_var", "chew_depth", "chew_freq", "chew_variance", "lossdegrade_mix", 
                              "Width", "dimension_mix", "haas", "rspeed", "monobass_mix", 
                              "bitcrush_mix", "bitcrush_rate", "bitcrush_bits",
                              "evolution", "evolution_range", "evolution_rate",
                              "lock_eq", "lock_tape", "lock_reverb", "lock_delay", "global_lfo_freq_scale" }

local morph_voice_params_count = #morph_voice_params
local morph_global_params_count = #morph_global_params

local function store_scene(track, scene)
    scene_data[track][scene] = {}
    local scene_params = scene_data[track][scene]
    for i = 1, morph_voice_params_count do
        local param = morph_voice_params[i]
        local full_param = track .. param
        if params.lookup[full_param] then
            scene_params[full_param] = params:get(full_param)
        end
    end
    for i = 1, morph_global_params_count do
        local param = morph_global_params[i]
        if params.lookup[param] then
            scene_params[param] = params:get(param)
        end
    end
    scene_params.lfo_data = {}
    for i = 1, 16 do
        if params:get(i.."lfo") == 2 then
            scene_params.lfo_data[i] = {
                target = params:get(i.."lfo_target"),
                shape = params:get(i.."lfo_shape"),
                freq = params:get(i.."lfo_freq"),
                depth = params:get(i.."lfo_depth"),
                offset = params:get(i.."offset")}
        end
    end
end

local function recall_scene(track, scene)
    if not scene_data[track] or not scene_data[track][scene] then return end
    for i = 1, 16 do
        params:set(i.."lfo", 1)
    end
    local scene_params = scene_data[track][scene]
    for param_name, value in pairs(scene_params) do
        if param_name ~= "lfo_data" and params.lookup[param_name] then
            params:set(param_name, value)
        end
    end
    if scene_params.lfo_data then
        for i = 1, 16 do
            if scene_params.lfo_data[i] then
                local lfo_entry = scene_params.lfo_data[i]
                params:set(i.."lfo_target", lfo_entry.target)
                params:set(i.."lfo_shape", lfo_entry.shape)
                params:set(i.."lfo_freq", lfo_entry.freq)
                params:set(i.."lfo_depth", lfo_entry.depth)
                params:set(i.."offset", lfo_entry.offset)
                params:set(i.."lfo", 2)
            end
        end
    end
end

local function apply_morph()
    if preset_loading then return end
    local t = morph_amount * 0.01
    if morph_amount == 0 then 
        recall_scene(1, 1) 
        recall_scene(2, 1) 
        return
    elseif morph_amount == 100 then 
        recall_scene(1, 2) 
        recall_scene(2, 2) 
        return
    end
    local scene1_track1 = scene_data[1] and scene_data[1][1] or {}
    local scene2_track1 = scene_data[1] and scene_data[1][2] or {}
    local scene1_track2 = scene_data[2] and scene_data[2][1] or {}
    local scene2_track2 = scene_data[2] and scene_data[2][2] or {}
    local t_inv = 1.0 - t
    local skip_param_set = {}
    for i = 1, 16 do
        local lfo_A_track1 = scene1_track1.lfo_data and scene1_track1.lfo_data[i]
        local lfo_B_track1 = scene2_track1.lfo_data and scene2_track1.lfo_data[i]
        local lfo_A_track2 = scene1_track2.lfo_data and scene1_track2.lfo_data[i]
        local lfo_B_track2 = scene2_track2.lfo_data and scene2_track2.lfo_data[i]
        local lfo_data_A = lfo_A_track1 or lfo_A_track2
        local lfo_data_B = lfo_B_track1 or lfo_B_track2
        if lfo_data_A or lfo_data_B then
            local target_param = nil
            if lfo_data_A then
                target_param = lfo.lfo_targets[lfo_data_A.target]
            elseif lfo_data_B then
                target_param = lfo.lfo_targets[lfo_data_B.target]
            end
            if target_param and target_param ~= "none" then
                skip_param_set[target_param] = true
                params:set(i.."lfo", 2)
                if lfo_data_A and lfo_data_B then
                    local freq = lfo_data_A.freq * t_inv + lfo_data_B.freq * t
                    local depth = lfo_data_A.depth * t_inv + lfo_data_B.depth * t
                    local offset = lfo_data_A.offset * t_inv + lfo_data_B.offset * t
                    params:set(i.."lfo_target", lfo_data_A.target)
                    params:set(i.."lfo_shape", lfo_data_A.shape)
                    params:set(i.."lfo_freq", freq)
                    params:set(i.."lfo_depth", depth)
                    params:set(i.."offset", offset)
                elseif lfo_data_A then
                    params:set(i.."lfo_target", lfo_data_A.target)
                    params:set(i.."lfo_shape", lfo_data_A.shape)
                    params:set(i.."lfo_freq", lfo_data_A.freq)
                    local depth = lfo_data_A.depth * t_inv
                    params:set(i.."lfo_depth", depth)
                    local scene2_data = (scene2_track1[target_param] ~= nil) and scene2_track1 or scene2_track2
                    local constant_value = scene2_data[target_param]
                    if constant_value then
                        local min_val, max_val = lfo.get_parameter_range(target_param)
                        if min_val and max_val then
                            local range = max_val - min_val
                            local target_offset = ((constant_value - min_val) / range) * 2 - 1
                            local offset = lfo_data_A.offset * t_inv + target_offset * t
                            params:set(i.."offset", offset)
                        else
                            params:set(i.."offset", lfo_data_A.offset)
                        end
                    else
                        params:set(i.."offset", lfo_data_A.offset)
                    end
                elseif lfo_data_B then
                    local scene1_data = (scene1_track1[target_param] ~= nil) and scene1_track1 or scene1_track2
                    local constant_value = scene1_data[target_param]
                    params:set(i.."lfo_target", lfo_data_B.target)
                    params:set(i.."lfo_shape", lfo_data_B.shape)
                    params:set(i.."lfo_freq", lfo_data_B.freq)
                    local depth = lfo_data_B.depth * t
                    params:set(i.."lfo_depth", depth)
                    if constant_value then
                        local min_val, max_val = lfo.get_parameter_range(target_param)
                        if min_val and max_val then
                            local range = max_val - min_val
                            local source_offset = ((constant_value - min_val) / range) * 2 - 1
                            local offset = source_offset * t_inv + lfo_data_B.offset * t
                            params:set(i.."offset", offset)
                        else
                            params:set(i.."offset", lfo_data_B.offset)
                        end
                    else
                        params:set(i.."offset", lfo_data_B.offset)
                    end
                end
            end
        else
            if params:get(i.."lfo") == 2 then params:set(i.."lfo", 1) end
        end
    end
    for track = 1, 2 do
        local scene1_data = track == 1 and scene1_track1 or scene1_track2
        local scene2_data = track == 1 and scene2_track1 or scene2_track2
        for i = 1, morph_voice_params_count do
            local param_name = morph_voice_params[i]
            local full_param = track .. param_name
            if not skip_param_set[full_param] and params.lookup[full_param] then
                local valueA = scene1_data[full_param]
                local valueB = scene2_data[full_param]
                if valueA and valueB then
                    params:set(full_param, valueA * t_inv + valueB * t)
                elseif valueA then
                    params:set(full_param, valueA)
                elseif valueB then
                    params:set(full_param, valueB)
                end
            end
        end
    end
    for i = 1, morph_global_params_count do
        local param = morph_global_params[i]
        if not skip_param_set[param] and params.lookup[param] then
            local valueA = scene1_track1[param] 
            local valueB = scene2_track1[param]
            if valueA and valueB then
                params:set(param, valueA * t_inv + valueB * t)
            end
        end
    end
end

local function auto_save_to_scene()
    if current_scene_mode ~= "on" then return end
    if morph_amount == 0 then 
        store_scene(1, 1) 
        store_scene(2, 1)
    elseif morph_amount == 100 then 
        store_scene(1, 2) 
        store_scene(2, 2)
    end
end

local function initialize_scenes_with_current_params()
    for track = 1, 2 do
        for scene = 1, 2 do
            store_scene(track, scene)
        end
    end
end

local function setup_key1_monitor()
    key1_monitor_metro = metro.init()
    key1_monitor_metro.time = 0.2
    key1_monitor_metro.event = function()
        if key1_press_time and not key1_long_press_triggered and not key1_has_other_interaction then
            local press_duration = util.time() - key1_press_time
            if press_duration >= KEY1_LONG_PRESS_THRESHOLD then
                key1_long_press_triggered = true
                key1_has_other_interaction = true
                local current_mode = params:get("scene_mode")
                local new_mode = (current_mode == 1) and 2 or 1
                params:set("scene_mode", new_mode)
                redraw()
            end
        end
    end
    key1_monitor_metro:start()
end

local function disable_lfos_for_param(param_name, only_self)
    local base_param = param_name:sub(2)
    if only_self then
        local is_active, lfo_index = is_lfo_active_for_param(param_name)
        if is_active then params:set(lfo_index .. "lfo", 1) end
    else
        for track = 1, 2 do
            local full_param = track .. base_param
            local is_active, lfo_index = is_lfo_active_for_param(full_param)
            if is_active then params:set(lfo_index .. "lfo", 1) end
        end
    end
end

local function get_audio_duration(filepath)
    if not filepath or filepath == "" or filepath == "none" or filepath == "-" then return nil end
    if not util.file_exists(filepath) then return nil end
    local ch, samples, rate = audio.file_info(filepath)
    if samples and rate and rate > 0 then return samples / rate end
    return nil
end

local function handle_lfo(param_name, force_disable)
    if force_disable then disable_lfos_for_param(param_name)
    else
        local active, idx = is_lfo_active_for_param(param_name)
        if active then params:set(idx.."lfo", 1) end
    end
end

local last_selected = {[1] = nil, [2] = nil}
local function scan_audio_files(dir)
    local files = {}
    for _, entry in ipairs(util.scandir(dir)) do
        local path = dir .. entry
        if entry:sub(-1) == "/" then
            for _, f in ipairs(scan_audio_files(path)) do files[#files+1] = f end
        elseif valid_audio_exts[path:lower():match("^.+(%..+)$") or ""] then files[#files+1] = path end
    end
    return files
end

local function set_track_sample(track_num, file)
    if params:get(track_num .. "live_input") == 1 then return false end
    if params:get(track_num .. "sample") ~= file then
        params:set(track_num .. "sample", file)
    end
    last_selected[track_num] = file
    return true
end

local function load_random_tape_file(track_num)
    local audio_files = scan_audio_files(_path.tape)
    if #audio_files == 0 then return false end
    if track_num then
        local file = audio_files[math.random(#audio_files)]
        return set_track_sample(track_num, file)
    end
    local file1 = audio_files[math.random(#audio_files)]
    local file2 = (math.random() < 0.5) and file1 or audio_files[math.random(#audio_files)]
    set_track_sample(1, file1)
    set_track_sample(2, file2)
    return true
end

local function register_tap()
    local now = util.time()
    if #tap_times > 0 and (now - tap_times[#tap_times]) > TAP_TIMEOUT then tap_times = {} end
    table.insert(tap_times, now)
    while #tap_times > 3 do table.remove(tap_times, 1) end
    if #tap_times >= 2 then
        local sum, count = 0, 0
        for i = math.max(2, #tap_times - 2), #tap_times do
            sum = sum + (tap_times[i] - tap_times[i - 1])
            count = count + 1
        end
        local avg_interval = sum / count
        params:set("delay_time", util.clamp(avg_interval, 0.02, 2))
    end
end

local function setup_params()
    params:add_separator("Input")
    for i = 1, 2 do
      params:add_file(i.."sample","Sample "..i)params:set_action(i.."sample",function(file)if file~=nil and file~=""and file~="none"and file~="-"then lfo.clearLFOs(tostring(i),"jitter")engine.read(i,file)audio_active[i]=true update_pan_positioning()local d=get_audio_duration(file)if d then local ms=d*1000 local max_jit=math.min(ms,99999)params:set(i.."max_jitter",max_jit)params:set(i.."min_jitter",0)if not is_param_locked(i,"jitter")then local jp=i.."jitter"handle_lfo(jp,true)params:set(jp,util.clamp(d*math.random()*1000,0,99999))end if math.random()<0.3 and not lfo.is_param_locked(tostring(i),"jitter")then clock.run(function()clock.sleep(0.1)for s=1,16 do if params.lookup[s.."lfo"]and params:get(s.."lfo")==1 then randomize_lfo(s,i.."jitter")break end end end)end end else lfo.clearLFOs(tostring(i),"jitter")audio_active[i]=false osc_positions[i]=0 update_pan_positioning()end end)
    end
    params:add_binary("randomtapes", "Random Tapes", "trigger", 0) params:set_action("randomtapes", function() load_random_tape_file() end)
    
    params:add_group("Live!", 10)
    for i = 1, 2 do
      params:add_binary(i.."live_input", "Live Buffer "..i.." ● ►", "toggle", 0) params:set_action(i.."live_input", function(value) if value == 1 then if params:get(i.."live_direct") == 1 then params:set(i.."live_direct", 0) end engine.set_live_input(i, 1) engine.live_mono(i, params:get("isMono") - 1) audio_active[i] = true update_pan_positioning() else engine.set_live_input(i, 0) if not audio_active[i] and params:get(i.."live_direct") == 0 then osc_positions[i] = 0 else update_pan_positioning() end end end)
    end
    params:add_control("live_buffer_mix", "Overdub", controlspec.new(0, 100, "lin", 1, 100, "%")) params:set_action("live_buffer_mix", function(value) engine.live_buffer_mix(value * 0.01) end)
    params:add_control("live_buffer_length", "Buffer Length", controlspec.new(0.1, 60, "lin", 0.1, 2, "s")) params:set_action("live_buffer_length", function(value) engine.live_buffer_length(value) end)
    params:add{type = "trigger", id = "save_live_buffer1", name = "Buffer1 to Tape", action = function() local timestamp = os.date("%Y%m%d_%H%M%S") local filename = "live1_"..timestamp..".wav" engine.save_live_buffer(1, filename) end}
    params:add{type = "trigger", id = "save_live_buffer2", name = "Buffer2 to Tape", action = function() local timestamp = os.date("%Y%m%d_%H%M%S") local filename = "live2_"..timestamp..".wav" engine.save_live_buffer(2, filename) end}
    for i = 1, 2 do
      params:add_binary(i.."live_direct", "Direct "..i.." ►", "toggle", 0) params:set_action(i.."live_direct", function(value) if value == 1 then local was_live = params:get(i.."live_input") _G["prev_live_state_"..i] = was_live if was_live == 1 then params:set(i.."live_input", 0) end engine.live_direct(i, 1) audio_active[i] = true update_pan_positioning() else engine.live_direct(i, 0) if not audio_active[i] and params:get(i.."live_input") == 0 then osc_positions[i] = 0 else update_pan_positioning() end end end)
    end
    params:add_option("isMono", "Input Mode", {"stereo", "mono"}, 1) params:set_action("isMono", function(value) local monoValue = value - 1 for i = 1, 2 do if params:get(i.."live_direct") == 1 then engine.isMono(i, monoValue) end if params:get(i.."live_input") == 1 then engine.live_mono(i, monoValue) end end end)
    params:add_binary("dry_mode2", "Dry Mode", "toggle", 0) params:set_action("dry_mode2", function(x) drymode.toggle_dry_mode2() end)
    
    params:add{type = "trigger", id = "save_preset", name = "Save Preset", action = function() presets.save_complete_preset(nil, scene_data, current_scene_mode, initialize_scenes_with_current_params) end}
    params:add{type = "trigger", id = "load_preset_menu", name = "Preset Browser", action = function() presets.open_menu() end}

    params:add_separator("Settings")
    params:add_group("Granular", 43)
    for i = 1, 2 do
      params:add_separator("Sample "..i)
      params:add_control(i.. "granular_gain", i.. " Mix", controlspec.new(0, 100, "lin", 1, 100, "%")) params:set_action(i.. "granular_gain", function(value) engine.granular_gain(i, value * 0.01) if value < 100 then lfo.clearLFOs(i, "seek") end end)
      params:add_control(i.. "subharmonics_3", i.. " Subharmonics -3oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0)) params:set_action(i.. "subharmonics_3", function(value) engine.subharmonics_3(i, value) end)
      params:add_control(i.. "subharmonics_2", i.. " Subharmonics -2oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0)) params:set_action(i.. "subharmonics_2", function(value) engine.subharmonics_2(i, value) end)
      params:add_control(i.. "subharmonics_1", i.. " Subharmonics -1oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0)) params:set_action(i.. "subharmonics_1", function(value) engine.subharmonics_1(i, value) end)
      params:add_control(i.. "overtones_1", i.. " Overtones +1oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0)) params:set_action(i.. "overtones_1", function(value) engine.overtones_1(i, value) end)
      params:add_control(i.. "overtones_2", i.. " Overtones +2oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0)) params:set_action(i.. "overtones_2", function(value) engine.overtones_2(i, value) end)
      params:add_option(i.. "smoothbass", i.." Smooth Sub", {"off", "on"}, 1) params:set_action(i.. "smoothbass", function(x) local engine_value = (x == 2) and 2.5 or 1 engine.smoothbass(i, engine_value) end)
      params:add_taper(i.."pitch_walk_rate", i.." Pitch Walk", 0, 30, 0, 3, "Hz") params:set_action(i.."pitch_walk_rate", function(value) engine.pitch_walk_rate(i, value) end)
      params:add_control(i.."pitch_walk_step", i.." Walk Range", controlspec.new(1, 24, "lin", 1, 2, "steps")) params:set_action(i.."pitch_walk_step", function(value) engine.pitch_walk_step(i, value) end)
      params:add_control(i.."pitch_random_prob", i.." Pitch Randomize", controlspec.new(-100, 100, "lin", 1, 0, "%")) params:set_action(i.."pitch_random_prob", function(value) engine.pitch_random_prob(i, value) end)
      params:add_option(i.."pitch_random_scale_type", i.." Pitch Quantize", {"5th+oct", "5th+oct 2", "1 oct", "2 oct", "chrom", "maj", "min", "penta", "whole"}, 1) params:set_action(i.."pitch_random_scale_type", function(value) engine.pitch_random_scale_type(i, value - 1) end)
      params:add_control(i.."ratcheting_prob", i.." Ratcheting", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.."ratcheting_prob", function(value) engine.ratcheting_prob(i, value) end)
      params:add_option(i.."env_select", i.." Grain Envelope", {"Sine", "Tukey", "Triangle", "Square", "Perc.", "Rev. Perc.", "ADSR", "Ramp", "Rev. Ramp"}, 1) params:set_action(i.."env_select", function(value) engine.env_select(i, value - 1) end)
      params:add_control(i.. "size_variation", i.. " Size Variation", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.. "size_variation", function(value) engine.size_variation(i, value * 0.01) end)
      params:add_control(i.. "direction_mod", i.. " Reverse", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.. "direction_mod", function(value) engine.direction_mod(i, value * 0.01) end)
      params:add_control(i.. "density_mod_amt", i.. " Density Mod", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.. "density_mod_amt", function(value) engine.density_mod_amt(i, value * 0.01) end)      
      params:add_option(i.. "trig_mode", i.. " Trigger Mode", {"impulse", "dust"}, 1) params:set_action(i.."trig_mode", function(value) engine.trig_mode(i, value-1) end)
      params:add_control(i.."probability", i.." Trigger Probability", controlspec.new(0, 100, "lin", 1, 100, "%")) params:set_action(i.."probability", function(value) engine.probability(i, value * 0.01) end)
      params:add_option(i.. "pitch_mode", i.. " Pitch Mode", {"match speed", "independent"}, 2) params:set_action(i.. "pitch_mode", function(value) engine.pitch_mode(i, value - 1) end)
    end
    params:add_separator(" ")
    params:add_binary("randomize_granular", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_granular", function() for i=1, 2 do randpara.randomize_granular_params(i) end end)
    params:add_option("lock_granular", "Lock Parameters", {"off", "on"}, 1)

    params:add_group("Delay", 12)
    params:add_control("delay_mix", "Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("delay_mix", function(x) engine.mix(x * 0.01) end)
    params:add_taper("delay_time", "Time", 0.02, 2, 0.5, 0.1, "s") params:set_action("delay_time", function(value) engine.delay(value) end)
    params:add_binary("tap", "↳ TAP!", "trigger", 0) params:set_action("tap", function() register_tap() end)
    params:add_taper("delay_feedback", "Feedback", 0, 120, 30, 1, "%") params:set_action("delay_feedback", function(value) engine.fb_amt(value * 0.01) end)
    params:add_control("delay_lowpass", "LPF", controlspec.new(20, 20000, 'exp', 1, 20000, "Hz")) params:set_action('delay_lowpass', function(value) engine.lpf(value) end)
    params:add_control("delay_highpass", "HPF", controlspec.new(20, 20000, 'exp', 1, 20, "Hz")) params:set_action('delay_highpass', function(value) engine.dhpf(value) end)
    params:add_taper("wiggle_depth", "Mod Depth", 0, 100, 1, 0, "%") params:set_action("wiggle_depth", function(value) engine.w_depth(value * 0.01) end)
    params:add_taper("wiggle_rate", "Mod Freq", 0, 20, 2, 1, "Hz") params:set_action("wiggle_rate", function(value) engine.w_rate(value) end)
    params:add_control("stereo", "Ping-Pong", controlspec.new(0, 100, "lin", 1, 30, "%")) params:set_action("stereo", function(x) engine.stereo(x * 0.01) end)
    params:add_separator("   ")
    params:add_binary("randomize_delay_params", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_delay_params", function() randpara.randomize_delay_params(steps) end)
    params:add_option("lock_delay", "Lock Parameters", {"off", "on"}, 1)

    params:add_group("Reverb", 15)
    params:add_taper("reverb_mix", "Mix", 0, 100, 0.0, 0, "%") params:set_action("reverb_mix", function(value) engine.reverb_mix(value * 0.01) end)
    params:add_taper("t60", "Decay", 0.1, 60, 4, 5, "s") params:set_action("t60", function(value) engine.t60(value) end)
    params:add_taper("damp", "Damping", 0, 100, 0, 0, "%") params:set_action("damp", function(value) engine.damp(value * 0.01) end)
    params:add_taper("rsize", "Size", 0.5, 5, 1.25, 0, "") params:set_action("rsize", function(value) engine.rsize(value) end)
    params:add_taper("earlyDiff", "Early Diffusion", 0, 100, 70.7, 0, "%") params:set_action("earlyDiff", function(value) engine.earlyDiff(value * 0.01) end)
    params:add_taper("modDepth", "Mod Depth", 0, 100, 10, 0, "%") params:set_action("modDepth", function(value) engine.modDepth(value * 0.01) end)
    params:add_taper("modFreq", "Mod Frequency", 0, 10, 0.2, 0, "Hz") params:set_action("modFreq", function(value) engine.modFreq(value) end)
    params:add_control("low", "Low Decay", controlspec.new(0, 1, "lin", 0.01, 1, "x")) params:set_action("low", function(value) engine.low(value) end)
    params:add_control("mid", "Mid Decay", controlspec.new(0, 1, "lin", 0.01, 1, "x")) params:set_action("mid", function(value) engine.mid(value) end)
    params:add_control("high", "High Decay", controlspec.new(0, 1, "lin", 0.01, 1, "x")) params:set_action("high", function(value) engine.high(value) end)
    params:add_taper("lowcut", "Low-Mid X", 100, 6000, 500, 2, "Hz") params:set_action("lowcut", function(value) engine.lowcut(value) end)
    params:add_taper("highcut", "Mid-High X", 1000, 10000, 2000, 2, "Hz") params:set_action("highcut", function(value) engine.highcut(value) end)
    params:add_separator("  ")
    params:add_binary("randomize_jpverb", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_jpverb", function() randpara.randomize_jpverb_params(steps) end)
    params:add_option("lock_reverb", "Lock Parameters", {"off", "on"}, 1)
    
    params:add_group("Shimmer", 9)
    params:add_control("shimmer_mix", "Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("shimmer_mix", function(x) engine.shimmer_mix(x * 0.01) end)
    params:add_option("o2", "2nd Octave", {"off", "on"}, 1) params:set_action("o2", function(x) engine.o2(x-1) end)
    params:add_control("pitchv", "Variance", controlspec.new(0, 100, "lin", 1, 2, "%")) params:set_action("pitchv", function(x) engine.pitchv(x * 0.01) end)
    params:add_control("lowpass", "LPF", controlspec.new(20, 20000, "lin", 1, 13000, "Hz")) params:set_action("lowpass", function(x) engine.lowpass(x) end)
    params:add_control("hipass", "HPF", controlspec.new(20, 20000, "exp", 1, 1400, "Hz")) params:set_action("hipass", function(x) engine.hipass(x) end)
    params:add_control("fbDelay", "Delay", controlspec.new(0.01, 0.5, "lin", 0.01, 0.2, "s")) params:set_action("fbDelay", function(x) engine.fbDelay(x) end)
    params:add_control("fb", "Feedback", controlspec.new(0, 100, "lin", 1, 15, "%")) params:set_action("fb", function(x) engine.fb(x * 0.01) end)
    params:add_separator("        ")
    params:add_option("lock_shimmer", "Lock Parameters", {"off", "on"}, 1)
    
    params:add_group("Tape", 16)
    params:add_option("tape_mix", "Analog Tape", {"off", "on"}, 1) params:set_action("tape_mix", function(x) engine.tape_mix(x-1) end)
    params:add_control("sine_drive", "Shaper Drive", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("sine_drive", function(value) engine.sine_drive((10+value)/20) end)
    params:add_control("drive", "Saturation", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("drive", function(x) engine.drive(x * 0.01) end)
    params:add{type = "control", id = "wobble_mix", name = "Wobble", controlspec = controlspec.new(0, 100, "lin", 1, 0, "%"), action = function(value) engine.wobble_mix(value * 0.01) end}
    params:add{type = "control", id = "wobble_amp", name = "Wow Depth", controlspec = controlspec.new(0, 100, "lin", 1, 20, "%"), action = function(value) engine.wobble_amp(value * 0.01) end}
    params:add{type = "control", id = "wobble_rpm", name = "Wow Speed", controlspec = controlspec.new(30, 90, "lin", 1, 33, "RPM"), action = function(value) engine.wobble_rpm(value) end}
    params:add{type = "control", id = "flutter_amp", name = "Flutter Depth", controlspec = controlspec.new(0, 100, "lin", 1, 35, "%"), action = function(value) engine.flutter_amp(value * 0.01) end}
    params:add{type = "control", id = "flutter_freq", name = "Flutter Speed", controlspec = controlspec.new(3, 30, "lin", 0.01, 6, "Hz"), action = function(value) engine.flutter_freq(value) end}
    params:add{type = "control", id = "flutter_var", name = "Flutter Var.", controlspec = controlspec.new(0.1, 10, "lin", 0.01, 2, "Hz"), action = function(value) engine.flutter_var(value) end}
    params:add{type = "control", id = "chew_depth", name = "Chew", controlspec = controlspec.new(0, 50, "lin", 1, 0, "%"), action = function(value) engine.chew_depth(value * 0.01) end}
    params:add{type = "control", id = "chew_freq", name = "Chew Freq.", controlspec = controlspec.new(0, 60, "lin", 1, 60, "%"), action = function(value) engine.chew_freq(value * 0.01) end}
    params:add{type = "control", id = "chew_variance", name = "Chew Var.", controlspec = controlspec.new(0, 70, "lin", 1, 60, "%"), action = function(value) engine.chew_variance(value * 0.01) end}
    params:add_control("lossdegrade_mix", "Loss / Degrade", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("lossdegrade_mix", function(value) engine.lossdegrade_mix(value * 0.01) end)
    params:add_separator("    ")
    params:add_binary("randomize_tape", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_tape", function() randpara.randomize_tape_params(steps) end)
    params:add_option("lock_tape", "Lock Parameters", {"off", "on"}, 1)    
    
    params:add_group("EQ", 9)
    for i = 1, 2 do 
    params:add_control(i.."eq_low_gain", i.." Bass", controlspec.new(-1, 1, "lin", 0.01, 0, "")) params:set_action(i.."eq_low_gain", function(value) engine.eq_low_gain(i, value*55) end)
    params:add_control(i.."eq_mid_gain", i.." Mid", controlspec.new(-1, 1, "lin", 0.01, 0, "")) params:set_action(i.."eq_mid_gain", function(value) engine.eq_mid_gain(i, value*20) end)
    params:add_control(i.."eq_high_gain", i.." Treble", controlspec.new(-1, 1, "lin", 0.01, 0, "")) params:set_action(i.."eq_high_gain", function(value) engine.eq_high_gain(i, value*45) end)
    end
    params:add_separator("     ")
    params:add_binary("randomize_eq", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_eq", function() for i=1, 2 do randpara.randomize_eq_params(i) end end)
    params:add_option("lock_eq", "Lock Parameters", {"off", "on"}, 1)
    
    params:add_group("LFOs", 118)
    params:add_binary("randomize_lfos", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_lfos", function() lfo.clearLFOs() local allow_vol = params:get("allow_volume_lfos") == 2 for i = 1, 2 do lfo.randomize_lfos(i, allow_vol) end end)
    params:add_binary("lfo.assign_to_current_row", "Assign to Selection", "trigger", 0) params:set_action("lfo.assign_to_current_row", function() lfo.assign_to_current_row(current_mode, current_filter_mode) end)
    params:add_control("global_lfo_freq_scale", "Freq Scale", controlspec.new(0.1, 10, "exp", 0.01, 1, "x")) params:set_action("global_lfo_freq_scale", function(value) local base_freq for i = 1, 16 do local phase = lfo[i].phase base_freq = params:get(i.."lfo_freq") or 0.05 lfo[i].base_freq = base_freq lfo[i].freq = base_freq * value lfo[i].phase = phase end end)
    params:add_binary("lfo_pause", "Pause ⏸︎", "toggle", 0) params:set_action("lfo_pause", function(value) lfo.set_pause(value == 1) end)
    params:add_binary("ClearLFOs", "Clear All", "trigger", 0) params:set_action("ClearLFOs", function() lfo.clearLFOs() update_pan_positioning() end)
    params:add_option("allow_volume_lfos", "Allow Volume LFOs", {"no", "yes"}, 1) params:set_action("allow_volume_lfos", function(value) if value == 2 then lfo.clearLFOs("1", "volume") lfo.clearLFOs("2", "volume") lfo.assign_volume_lfos() else lfo.clearLFOs("1", "volume") lfo.clearLFOs("2", "volume") end end)
    lfo.init()
    
    params:add_group("Stereo", 5)
    params:add_control("Width", "Stereo Width", controlspec.new(0, 200, "lin", 2, 100, "%")) params:set_action("Width", function(value) engine.width(value * 0.01) end)
    params:add_control("dimension_mix", "Dimension", controlspec.new(0, 100, "lin", 2, 0, "%")) params:set_action("dimension_mix", function(value) engine.dimension_mix(value * 0.01) end)
    params:add_option("haas", "Haas Effect", {"off", "on"}, 1) params:set_action("haas", function(x) engine.haas(x-1) end)
    params:add_taper("rspeed", "Rotation", 0, 1, 0, 1, "Hz") params:set_action("rspeed", function(value) engine.rspeed(value) end)
    params:add_option("monobass_mix", "Mono Bass", {"off", "on"}, 1) params:set_action("monobass_mix", function(x) engine.monobass_mix(x-1) end)

    params:add_group("BitCrush", 3)
    params:add_taper("bitcrush_mix", "Mix", 0, 100, 0.0, 0, "%") params:set_action("bitcrush_mix", function(value) engine.bitcrush_mix(value * 0.01) end)
    params:add_taper("bitcrush_rate", "Rate", 0, 44100, 4500, 100, "Hz") params:set_action("bitcrush_rate", function(value) engine.bitcrush_rate(value) end)
    params:add_taper("bitcrush_bits", "Bits", 1, 24, 14, 1) params:set_action("bitcrush_bits", function(value) engine.bitcrush_bits(value) end)

    params:add_group("Evolve", 3)
    params:add_binary("evolution", "Evolve!", "toggle", 0) params:set_action("evolution", function(value) if value == 1 then randpara.reset_evolution_centers() randpara.start_evolution() else randpara.stop_evolution() end end)
    params:add_control("evolution_range", "Evolution Range", controlspec.new(0, 100, "lin", 1, 10, "%")) params:set_action("evolution_range", function(value) randpara.set_evolution_range(value) end)
    params:add_option("evolution_rate", "Evolution Rate", {"slowest", "slow", "moderate", "medium", "fast", "crazy"}, 2) params:set_action("evolution_rate", function(value) local rates = {1/0.5, 1/1.5, 1/4, 1/8, 1/15, 1/30} randpara.set_evolution_rate(rates[value]) end)

    params:add_group("Symmetry", 3)
    params:add_binary("symmetry", "Symmetry", "toggle", 0)
    params:add_binary("copy_1_to_2", "Copy 1 → 2", "trigger", 0) params:set_action("copy_1_to_2", function() Mirror.copy_voice_params("1", "2", true) end)
    params:add_binary("copy_2_to_1", "Copy 1 ← 2", "trigger", 0) params:set_action("copy_2_to_1", function() Mirror.copy_voice_params("2", "1", true) end)

    params:add_group("Filters", 10)
    for i = 1, 2 do
      params:add_control(i.."cutoff",i.." LPF",controlspec.new(20,20000,"exp",0,20000,"Hz")) params:set_action(i.."cutoff", function(value) engine.cutoff(i, value) if filter_lock_ratio then local new_hpf = value - filter_differences[i] new_hpf = util.clamp(new_hpf, 20, 20000) params:set(i.."hpf", new_hpf) end end)
      params:add_control(i.."hpf",i.." HPF",controlspec.new(20,20000,"exp",0,20,"Hz")) params:set_action(i.."hpf", function(value) engine.hpf(i, value) if filter_lock_ratio then local new_cutoff = value + filter_differences[i] new_cutoff = util.clamp(new_cutoff, 20, 20000) params:set(i.."cutoff", new_cutoff) end end)
      params:add_taper(i.."lpfgain", i.." Q", 0, 1, 0.0, 1, "") params:set_action(i.."lpfgain", function(value) engine.lpfgain(i, value * 4) end)
    end
    params:add_separator("                   ")
    params:add_binary("filter_lock_ratio", "Lock Filter Spread", "toggle", 0) params:set_action("filter_lock_ratio", function(value) filter_lock_ratio = value == 1 if filter_lock_ratio then for i = 1, 2 do local cutoff = params:get(i.."cutoff") local hpf = params:get(i.."hpf") filter_differences[i] = cutoff - hpf end end end)
    params:add_binary("randomizefilters", "RaNd0m1ze!", "trigger", 0) params:set_action("randomizefilters", function(value) for i = 1, 2 do local cutoff = math.random(20, 20000) params:set(i.."cutoff", cutoff) params:set(i.."lpfgain", math.random()) params:set(i.."hpf", math.random(20, math.floor(cutoff))) end end)
    params:add_binary("resetfilters", "Reset", "trigger", 0) params:set_action("resetfilters", function(value) params:set("filter_lock_ratio", 0) for i=1, 2 do params:set(i.."cutoff", 20000) params:set(i.."hpf", 20) params:set(i.."lpfgain", 0.0) end end)

    params:add_group("Locking", 19)
    for i = 1, 2 do
      params:add_binary(i.."size_density_lock", i.." Size-Density Lock", "toggle", 0) params:set_action(i.."size_density_lock", function(value) if value == 1 then local size = params:get(i.."size") local density = params:get(i.."density") if size > 0 and density > 0 then _G["size_density_ratio_"..i] = size / (1000 / density) end end end)
    end
    params:add_separator("                  ")
    for i = 1, 2 do
      params:add_option(i.. "lock_jitter", i.. " Lock Jitter", {"off", "on"}, 1)
      params:add_option(i.. "lock_size", i.. " Lock Size", {"off", "on"}, 1)
      params:add_option(i.. "lock_density", i.. " Lock Density", {"off", "on"}, 1)
      params:add_option(i.. "lock_spread", i.. " Lock Spread", {"off", "on"}, 1)
      params:add_option(i.. "lock_pitch", i.. " Lock Pitch", {"off", "on"}, 1)
      params:add_option(i.. "lock_speed", i.. " Lock Speed", {"off", "on"}, 1)
      params:add_option(i.. "lock_seek", i.. " Lock Seek", {"off", "on"}, 1)
      params:add_option(i.. "lock_pan", i.. " Lock Pan", {"off", "on"}, 1)
    end

    params:add_group("Limits", 30) 
    for i = 1, 2 do
        params:add_separator("Voice "..i)
        params:add_taper(i.."min_jitter", i.." jitter (min)", 0, 999999, 0, 5, "ms")
        params:add_taper(i.."max_jitter", i.." jitter (max)", 0, 999999, 4999, 5, "ms")
        params:add_taper(i.."min_size", i.." size (min)", 20, 999, 50, 5, "ms")
        params:add_taper(i.."max_size", i.." size (max)", 20, 999, 599, 5, "ms")
        params:add_taper(i.."min_density", i.." density (min)", 0.1, 50, 0.5, 5, "Hz")
        params:add_taper(i.."max_density", i.." density (max)", 0.1, 50, 30, 5, "Hz")
        params:add_taper(i.."min_spread", i.." spread (min)", 0, 100, 0, 0, "%")
        params:add_taper(i.."max_spread", i.." spread (max)", 0, 100, 90, 0, "%")
        params:add_control(i.."min_pitch", i.." pitch (min)", controlspec.new(-48, 48, "lin", 1, -31, "st"))
        params:add_control(i.."max_pitch", i.." pitch (max)", controlspec.new(-48, 48, "lin", 1, 31, "st"))
        params:add_taper(i.."min_speed", i.." speed (min)", -2, 2, -0.15, 0, "x")
        params:add_taper(i.."max_speed", i.." speed (max)", -2, 2, 0.5, 0, "x")
        params:add_taper(i.."min_seek", i.." seek (min)", 0, 100, 0, 0, "%")
        params:add_taper(i.."max_seek", i.." seek (max)", 0, 100, 100, 0, "%")
    end
    
    params:add_group("Actions", 2)
    params:add_binary("macro_more", "More+", "trigger", 0) params:set_action("macro_more", function() macro.macro_more() end)
    params:add_binary("macro_less", "Less-", "trigger", 0) params:set_action("macro_less", function() macro.macro_less() end)
    
    params:add_group("Loop", 3)
    params:add{type = "trigger", id = "save_output_buffer_only", name = "Save", action = function() local filename = "twins_output.wav" if engine.save_output_buffer_only then showing_save_message = true engine.save_output_buffer_only(filename) end end}
    params:add{type = "trigger", id = "save_output_buffer", name = "Bounce", action = function() local filename = "twins_output.wav" if engine.save_output_buffer then showing_save_message = true engine.save_output_buffer(filename) end end}
    params:add_control("output_buffer_length", "Loop Length", controlspec.new(1, 60, "lin", 1, 8, "s")) params:set_action("output_buffer_length", function(value) engine.set_output_buffer_length(value + 1) end)    
    
    params:add_group("Other", 8)
    params:add_binary("dry_mode", "Dry Mode", "toggle", 0) params:set_action("dry_mode", function(x) drymode.toggle_dry_mode() end)
    params:add_binary("randomtape1", "Random Tape 1", "trigger", 0) params:set_action("randomtape1", function() load_random_tape_file(1) end)
    params:add_binary("randomtape2", "Random Tape 2", "trigger", 0) params:set_action("randomtape2", function() load_random_tape_file(2) end)
    params:add_binary("unload_all", "Unload All Audio", "trigger", 0) params:set_action("unload_all", function() for i=1, 2 do params:set(i.."seek", 0) params:set(i.."sample", "-") params:set(i.."live_input", 0) params:set(i.."live_direct", 0) audio_active[i] = false osc_positions[i] = 0 end engine.unload_all() update_pan_positioning() end)
    params:add_control("morph_amount", "Morph", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("morph_amount", function(value) morph_amount = value apply_morph() end)
    params:add{type = "trigger", id = "save_to_scene1", name = "Morph Target A", action = function() store_scene(1, 1) store_scene(2, 1) end}
    params:add{type = "trigger", id = "save_to_scene2", name = "Morph Target B", action = function() store_scene(1, 2) store_scene(2, 2) end}
    params:add_option("steps", "Transition Time", {"short", "medium", "long"}, 1) params:set_action("steps", function(value) steps = ({20, 300, 800})[value] end)
    params:add_option("scene_mode", "Morph Mode", {"off", "on"}, 1) params:set_action("scene_mode", function(value) current_scene_mode = (value == 2) and "on" or "off" end) params:hide("scene_mode")
    
    for i = 1, 2 do
      params:add_taper(i.. "volume", i.. " volume", -70, 10, -15, 0, "dB") params:set_action(i.. "volume", function(value) if value == -70 then engine.volume(i, 0) else engine.volume(i, math.pow(10, value / 20)) end end) params:hide(i.. "volume")
      params:add_taper(i.. "pan", i.. " pan", -100, 100, 0, 0, "%") params:set_action(i.. "pan", function(value) engine.pan(i, value * 0.01)  end) params:hide(i.. "pan")
      params:add_taper(i.. "speed", i.. " speed", -2, 2, 0.10, 0) params:set_action(i.. "speed", function(value) if math.abs(value) < 0.01 then engine.speed(i, 0) else engine.speed(i, value) end end) params:hide(i.. "speed")
      params:add_taper(i.. "density", i.. " density", 0.1, 300, 10, 5) params:set_action(i.. "density", function(value) engine.density(i, value) end) params:hide(i.. "density")
      params:add_control(i.. "pitch", i.. " pitch", controlspec.new(-48, 48, "lin", 1, 0, "st")) params:set_action(i.. "pitch", function(value) engine.pitch_offset(i, math.pow(0.5, -value / 12)) end) params:hide(i.. "pitch")
      params:add_taper(i.. "jitter", i.. " jitter", 0, 999900, 2500, 10, "ms") params:set_action(i.. "jitter", function(value) engine.jitter(i, value * 0.001) end) params:hide(i.. "jitter")
      params:add_taper(i.. "size", i.. " size", 20, 5999, 200, 1, "ms") params:set_action(i.. "size", function(value) engine.size(i, value * 0.001) end) params:hide(i.. "size")
      params:add_taper(i.. "spread", i.. " spread", 0, 100, 30, 0, "%") params:set_action(i.. "spread", function(value) engine.spread(i, value * 0.01) end) params:hide(i.. "spread")
      params:add_control(i.. "seek", i.. " seek", controlspec.new(0, 100, "lin", 0.01, 0, "%")) params:set_action(i.. "seek", function(value) engine.seek(i, value * 0.01) end) params:hide(i.. "seek")
    end
    params:bang()
    initialize_scenes_with_current_params()
end

local function randomize_pitch(track, other_track, symmetry)
    local function set_pitch(track, other_track, new_pitch, symmetry)
		  if params:get(track.."pitch") ~= new_pitch then
			  params:set(track.."pitch", new_pitch)
			  if symmetry then params:set(other_track.."pitch", new_pitch) end
		  end
    end
		local current_pitch = params:get(track .. "pitch")
		local min_pitch = math.max(params:get(track.."min_pitch"), current_pitch - 48)
		local max_pitch = math.min(params:get(track.."max_pitch"), current_pitch + 48)
		if min_pitch >= max_pitch then return end
		local base_pitch = params:get(other_track .. "pitch")
		local weighted_intervals = {[-12] = 3, [-7] = 2, [-5] = 2, [-3] = 1, [0] = 2, [3] = 1, [5] = 2, [7] = 2, [12] = 3}
		local larger_intervals = {-24, -19, -17, -15, 15, 17, 19, 24}
		local valid_intervals = {}
		local total_weight = 0
		for interval, weight in pairs(weighted_intervals) do
			local candidate_pitch = base_pitch + interval
			if candidate_pitch >= min_pitch and candidate_pitch <= max_pitch then
				table.insert(valid_intervals, {interval = interval, weight = weight})
				total_weight = total_weight + weight
			end
		end
		if #valid_intervals > 0 then
			local random_weight = math.random(total_weight)
			local cumulative_weight = 0
			for _, v in ipairs(valid_intervals) do
				cumulative_weight = cumulative_weight + v.weight
				if random_weight <= cumulative_weight then set_pitch(track, other_track, base_pitch + v.interval, symmetry)	return end
			end
		end
		for _, interval in ipairs(larger_intervals) do
			local candidate_pitch = base_pitch + interval
			if candidate_pitch >= min_pitch and candidate_pitch <= max_pitch then	set_pitch(track, other_track, candidate_pitch, symmetry) return end
		end
end

local function randomize(n)
		randomize_metro[n] = randomize_metro[n] or metro.init()
		local m_rand = randomize_metro[n]
		local active_controlled_params = {}
		local symmetry = params:get("symmetry") == 1
		local other_track = 3 - n
		local locked_params = {}
		local param_names = {"speed", "jitter", "size", "density", "spread", "pitch", "seek"}
		for _, name in ipairs(param_names) do
			locked_params[name] = params:get(n .. "lock_" .. name) == 1
		end
		if locked_params.pitch and not active_controlled_params[n .. "pitch"] then
			randomize_pitch(n, other_track, symmetry)
		end
		local targets = {}
		for _, key in ipairs(param_names) do
			if key == "pitch" then goto continue end
			local cfg_name = n .. key
			if not locked_params[key] or active_controlled_params[cfg_name] then goto continue end
			if key == "seek" then
				local min_val = params:get(n .. "min_seek")
				local max_val = params:get(n .. "max_seek")
				local val = random_float(min_val, max_val)
				local val_norm = val * 0.01
				if symmetry then
					for _, track in ipairs({n, other_track}) do
						params:set(track .. "seek", val)
						engine.seek(track, val_norm)
						osc_positions[track] = val_norm
					end
				else
					engine.seek(n, val_norm)
					osc_positions[n] = val_norm
				end
			else
				local min_val = params:get(n .. "min_" .. key)
				local max_val = params:get(n .. "max_" .. key)
				if min_val and max_val and min_val < max_val and not is_lfo_active_for_param(cfg_name) then
					local val = random_float(min_val, max_val)
					targets[cfg_name] = val
					if symmetry then
						local other_name = other_track .. key
						targets[other_name] = (key == "pan") and -val or val
					end
				end
			end
			::continue::
		end
		if next(targets) then
			m_rand.time = 1 / 30
			m_rand.event = function(count)
				local tolerance = 0.01
				local factor = count / steps
				local all_done = true
				for param, target in pairs(targets) do
					if not active_controlled_params[param] then
						local current = params:get(param)
						local new_val = current + (target - current) * factor
						params:set(param, new_val)
						all_done = all_done and (math.abs(new_val - target) < tolerance)
					end
				end
				if all_done then stop_metro_safe(m_rand) end
			end
			m_rand:start()
		end
end

local function handle_volume_lfo(track, delta, crossfade_mode)
		local p = track .. "volume"
		local other_track = 3 - track
		local op = other_track .. "volume"
		local a1, i1 = is_lfo_active_for_param(p)
		local a2, i2 = is_lfo_active_for_param(op)
		local lfo_delta = delta * 1.5
		local vol_delta = delta * 3
		if a1 then
			params:delta(i1.."offset", lfo_delta)
			if a2 then
				params:delta(i2.."offset", crossfade_mode and -lfo_delta or lfo_delta)
			else
				params:delta(op, crossfade_mode and -vol_delta or vol_delta)
			end
		elseif a2 then
			params:delta(i2.."offset", crossfade_mode and -lfo_delta or lfo_delta)
			params:delta(p, vol_delta)
		else
			params:delta(p, vol_delta)
			params:delta(op, crossfade_mode and -vol_delta or vol_delta)
		end
end

local function handle_size_density_lock(track, config, delta)
    local size_density_locked = params:get(track.."size_density_lock") == 1
    local is_size = config.param == "size"
    local is_density = config.param == "density"
    if not (size_density_locked and (is_size or is_density)) then
        return false
    end
    local sym = params:get("symmetry") == 1
    local p = track .. config.param
    handle_lfo(p, not sym)
    handle_lfo(track .. (is_size and "density" or "size"), not sym)
    local function update_track_ratio(tr, delta_mult, density_mult)
        local ratio = _G["size_density_ratio_"..tr] or 1
        if is_size then
            local new_size = params:get(tr.."size") + delta_mult * delta
            params:set(tr.."size", new_size)
            params:set(tr.."density", (1000 / new_size) * ratio)
        else
            local new_density = params:get(tr.."density") + density_mult * delta
            params:set(tr.."density", new_density)
            params:set(tr.."size", (1000 / new_density) * ratio)
        end
    end
    update_track_ratio(track, is_size and 3 or 0, is_density and 0.05 or 0)
    if sym then update_track_ratio(3 - track, is_size and 3 or 0, is_density and 0.05 or 0) end
    return true
end

local function handle_seek_param(track, config, delta)
    if config.param ~= "seek" then return false end
    local sym = params:get("symmetry") == 1
    local p = track .. config.param
    handle_lfo(p, not sym)
    local current_pos = osc_positions[track] * 100
    local new_pos = (current_pos + delta) % 100
    if new_pos < 0 then new_pos = new_pos + 100 end
    local norm_pos = new_pos * 0.01
    local function update_seek_pos(tr)
        osc_positions[tr] = norm_pos
        params:set(tr.."seek", new_pos)
        engine.seek(tr, norm_pos)
    end
    if sym then
        update_seek_pos(1)
        update_seek_pos(2)
    else
        update_seek_pos(track)
    end
    return true
end

local function handle_standard_param(track, config, delta)
    local sym = params:get("symmetry") == 1
    local p = track .. config.param
    local other_track = 3 - track
    local op = other_track .. config.param
    if sym then
        handle_lfo(p, true)
        params:delta(p, delta)
        params:delta(op, delta)
    else
        handle_lfo(p, false)
        params:delta(p, delta)
    end
end

local function handle_param_change(track, config, delta)
    if handle_size_density_lock(track, config, delta) then return end
    if handle_seek_param(track, config, delta) then return end
    handle_standard_param(track, config, delta)
end

local function handle_randomize_track(n)
    if not key_state[1] then return false end
    local track = n - 1
    if track >= 1 and track <= 2 then
        stop_metro_safe(randomize_metro[track])
        lfo.clearLFOs(track)
        lfo.randomize_lfos(tostring(track), params:get("allow_volume_lfos") == 2)
        randomize(track)
        randpara.randomize_params(steps, track)
        randpara.reset_evolution_centers()
        update_pan_positioning()
        return true
    end
    return false
end

local function handle_mode_navigation(n)
    if key_state[1] then return end
    if n == 2 then
        local idx = mode_indices[current_mode] or 1
        current_mode = mode_list[(idx % #mode_list) + 1]
    elseif n == 3 then
        local idx = mode_indices2[current_mode] or 1
        current_mode = mode_list2[(idx % #mode_list2) + 1]
    end
end

local function handle_parameter_lock()
    local lockable_params = {"jitter", "size", "density", "spread", "pitch", "pan", "seek", "speed"}
    if current_mode == "lpf" or current_mode == "hpf" then
        current_filter_mode = current_filter_mode == "lpf" and "hpf" or "lpf"
        return
    end
    local param_name = string.match(current_mode, "%a+")
    if param_name and table_find(lockable_params, param_name) then
        local is_locked1 = params:get("1lock_" .. param_name) == 2
        local is_locked2 = params:get("2lock_" .. param_name) == 2
        if is_locked1 ~= is_locked2 then
            params:set("1lock_" .. param_name, 1)
            params:set("2lock_" .. param_name, 1)
        else
            local new_state = is_locked1 and 1 or 2
            params:set("1lock_" .. param_name, new_state)
            params:set("2lock_" .. param_name, new_state)
        end
    end
end

function enc(n, d)
    if not installer:ready() then return end
    if presets.is_menu_open() then presets.menu_enc(n, d) redraw() return end
    if key1_press_time then key1_has_other_interaction = true end
    local k1 = key_state[1]
    local should_auto_save = current_scene_mode == "on" and (morph_amount == 0 or morph_amount == 100)
    if n == 1 then
        if should_auto_save then auto_save_to_scene() end
        if k1 and current_scene_mode == "on" then params:set("morph_amount", util.clamp(morph_amount + (d * 3), 0, 100))
        else handle_volume_lfo(1, d, k1) end
    elseif n == 2 or n == 3 then
        local track = n - 1
        stop_metro_safe(randomize_metro[track])
        if k1 then
            local sym = params:get("symmetry") == 1
            local p = track .. "volume"
            handle_lfo(p, sym)
            params:delta(p, 3 * d)
        else
            local mode = (current_mode == "lpf" or current_mode == "hpf") and current_filter_mode or current_mode
            local config = param_modes[mode]
            handle_param_change(track, config, config.delta * d)
        end
        if should_auto_save then auto_save_to_scene() end
    end
end

function key(n, z)
    if not installer:ready() then installer:key(n, z) return end
    if presets.is_menu_open() then if n == 1 and z == 1 then presets.close_menu() redraw() return end
        local handled = presets.menu_key(n, z, scene_data, update_pan_positioning, audio_active)
        if handled then redraw() return end
    end
    if n == 1 then
        if z == 1 then
            key_state[1] = true
            key1_press_time = util.time()
            key1_long_press_triggered = false
            key1_has_other_interaction = false
        else
            local press_duration = key1_press_time and (util.time() - key1_press_time) or 0
            if press_duration < KEY1_LONG_PRESS_THRESHOLD and not key1_has_other_interaction then
                if handle_randomize_track(1) then 
                    key1_press_time = nil
                    key_state[1] = false
                    return 
                end
                handle_mode_navigation(1)
            end
            key_state[1] = false
            key1_press_time = nil
            key1_long_press_triggered = false
            key1_has_other_interaction = false
        end
    else
        key_state[n] = z == 1
        if key1_press_time then key1_has_other_interaction = true end
        if z == 1 then
            if handle_randomize_track(n) then return end
            handle_mode_navigation(n)
        end
    end
    if key_state[2] and key_state[3] then handle_parameter_lock() end
end

local function format_density(value) return string.format("%.1f Hz", value) end
local function format_pitch(value, track) if track then local pitch_walk_rate = params:get(track.."pitch_walk_rate") or 0 local pitch_walk_enabled = pitch_walk_rate > 0 if value > 0 then return string.format("+%.0f%s", value, pitch_walk_enabled and ".." or "") else return string.format("%.0f%s", value, pitch_walk_enabled and ".." or "") end else if value > 0 then return string.format("+%.0f", value) else return string.format("%.0f", value) end end end
local function format_seek(value) return string.format("%.0f%%", value) end
local function format_speed(speed) if math.abs(speed) < 0.01 then return ".00x" elseif math.abs(speed) < 1 then if speed < -0.01 then return string.format("-.%02dx", math.floor(math.abs(speed) * 100)) else return string.format(".%02dx", math.floor(math.abs(speed) * 100)) end else return string.format("%.2fx", speed) end end
local function format_jitter(value) if value > 999 then return string.format("%.1f s", value / 1000) else return string.format("%.0f ms", value) end end
local function format_size(value) if value > 999 then return string.format("%.2f s", value / 1000) else return string.format("%.0f ms", value) end end

local function get_lfo_modulation(param_name)
    for i = 1, 16 do
        local target_index = params:get(i.. "lfo_target")
        if lfo.lfo_targets[target_index] == param_name and params:get(i.. "lfo") == 2 then
            local min_val, max_val = lfo.get_parameter_range(param_name)
            return min_val + (lfo[i].slope + 1) * 0.5 * (max_val - min_val)
        end
    end
    return nil
end

local LEVELS = {highlight = 15, dim = 9, value = 2}
local UPPER_MODES = {jitter=true, size=true, density=true, spread=true, pitch=true}
local format_lookup = {
    hz = function(val, track) return format_density(val) end,
    st = function(val, track) return format_pitch(val, track) end,
    spread = function(val, track) return string.format("%.0f%%", val) end,
    jitter = function(val, track) return format_jitter(val) end,
    size = function(val, track) return format_size(val) end}

local TRACK_X = {51, 92}
local BOTTOM_ROW_Y = 61
local SEEK_BAR_Y = 63
local VOLUME_METER_X = {0, 127}
local PAN_CENTER_START = {52, 93}

-- Draw lock shape
local function add_l_shape(draw_ops, x, y)
    local pulse_level = math.floor(util.linlin(-1, 1, 1, 8, math.sin(util.time() * 4)))
    draw_ops.pixels[#draw_ops.pixels + 1] = {pulse_level, x - 2, y-1}
    draw_ops.pixels[#draw_ops.pixels + 1] = {pulse_level, x - 3, y-1}
    draw_ops.pixels[#draw_ops.pixels + 1] = {pulse_level, x - 3, y - 2}
    draw_ops.pixels[#draw_ops.pixels + 1] = {pulse_level, x - 3, y - 3}
end

-- Draw size-density lock
local function add_lock_shape(draw_ops, x, y)
    draw_ops.pixels[#draw_ops.pixels + 1] = {4, x - 3, y + 1}
    draw_ops.pixels[#draw_ops.pixels + 1] = {4, x - 3, y + 3}
    draw_ops.pixels[#draw_ops.pixels + 1] = {4, x - 3, y + 5}
end

local function add_recording_head(draw_ops, x, y, position)
    draw_ops.rects[#draw_ops.rects + 1] = {15, x + math.floor(position * 30), y - 1, 1, 2}
end

function redraw()
    if not installer:ready() then installer:redraw() return end
    if presets.draw_menu() then return end
    screen.clear()
    screen.save()
    screen.translate(animation_x, animation_y)
    local cached = {
        volume = {params:get("1volume"), params:get("2volume")},
        pan = {params:get("1pan"), params:get("2pan")},
        seek = {params:get("1seek"), params:get("2seek")},
        speed = {params:get("1speed"), params:get("2speed")},
        cutoff = {params:get("1cutoff"), params:get("2cutoff")},
        hpf = {params:get("1hpf"), params:get("2hpf")},
        live_input = {params:get("1live_input"), params:get("2live_input")},
        live_direct = {params:get("1live_direct"), params:get("2live_direct")},
        size_density_lock = {params:get("1size_density_lock"), params:get("2size_density_lock")},
        size = {params:get("1size"), params:get("2size")},
        dry_mode = params:get("dry_mode"),
        symmetry = params:get("symmetry"),
        evolution = params:get("evolution")    }
    local draw_ops = {rects = {}, pixels = {}, text = {}}
    local function add_rect(lvl, x, y, w, h) draw_ops.rects[#draw_ops.rects + 1] = {lvl, x, y, w, h} end
    local function add_pixel(lvl, x, y) draw_ops.pixels[#draw_ops.pixels + 1] = {lvl, x, y} end
    local function add_text(lvl, x, y, text, align) draw_ops.text[#draw_ops.text + 1] = {lvl, x, y, text, align} end
    -- Process upper parameter rows
    local is_upper_highlighted = UPPER_MODES[current_mode]
    for _, row in ipairs(param_rows) do
        local param_name = string.match(row.label, "%a+")
        local is_highlighted = current_mode == row.mode
        local label_text = is_highlighted and string.upper(row.label) or row.label
        local label_brightness = is_highlighted and 15 or 7
        add_text(label_brightness, 5, row.y, label_text, nil)
    
        for track = 1, 2 do
            local param = track == 1 and row.param1 or row.param2
            local x = TRACK_X[track]
            if param_name == "size" and cached.size_density_lock[track] == 1 then add_lock_shape(draw_ops, x, row.y) end
            if is_param_locked(track, param_name) then add_l_shape(draw_ops, x, row.y) end
            -- Text values
            local value_level = is_highlighted and LEVELS.highlight or LEVELS.value
            local lfo_mod = get_lfo_modulation(param)
            local val = lfo_mod or params:get(param)
            local format_key = row.hz and "hz" or (row.st and "st" or param_name)
            local format_func = format_lookup[format_key]
            local display_text = format_func and format_func(val, track) or params:string(param)
            add_text(value_level, x, row.y, display_text, nil)
            -- LFO modulation bars
            if param_name ~= "pitch" and lfo_mod then
                local min_val, max_val = lfo.get_parameter_range(param)
                local bar_value = util.linlin(min_val, max_val, 0, 30, lfo_mod)
                add_rect(LEVELS.dim, x, row.y + 1, bar_value, 1)
            end
        end
    end
    -- Bottom row setup
    local is_upper_row_active = UPPER_MODES[current_mode]
    local bottom_row_mode = is_upper_row_active and "seek" or current_mode
    local is_bottom_active = not is_upper_row_active
    -- Bottom row label
    local bottom_label
    if bottom_row_mode == "lpf" or bottom_row_mode == "hpf" then bottom_label = current_filter_mode == "lpf" and "lpf:      " or "hpf:      " 
    else bottom_label = bottom_row_mode .. ":     " end
    if is_bottom_active then bottom_label = string.upper(bottom_label) end
    local bottom_label_brightness = is_bottom_active and 15 or 7
    add_text(bottom_label_brightness, 5, BOTTOM_ROW_Y, bottom_label, nil)
    -- Bottom row values
    local current_time = util.time()
    for track = 1, 2 do
        local x = TRACK_X[track]
        local value_level = is_bottom_active and LEVELS.highlight or LEVELS.value
        if bottom_row_mode == "seek" then
            if is_param_locked(track, "seek") then add_l_shape(draw_ops, x, BOTTOM_ROW_Y) end
            local is_loaded = audio_active[track] or cached.live_input[track] == 1 or cached.live_direct[track] == 1
            local display_text
            if cached.live_input[track] == 1 then display_text = "live"
            elseif cached.live_direct[track] == 1 then display_text = "direct"
            else display_text = string.format("%.0f%%", osc_positions[track] * 100) end
            add_text(value_level, x, BOTTOM_ROW_Y, display_text, nil)
            if is_loaded and cached.live_direct[track] ~= 1 then
                local current_speed = cached.speed[track]
                local symbol = math.abs(current_speed) < 0.01 and "⏸" or (current_speed > 0 and "▶" or "◀")
                add_text(value_level, track == 1 and 75 or 116, BOTTOM_ROW_Y, symbol, nil)
            end
            if cached.live_direct[track] ~= 1 then 
                local pos = osc_positions[track]
                add_rect(1, x, SEEK_BAR_Y, 30, 1)
                add_rect(LEVELS.dim, x, SEEK_BAR_Y, 30 * pos, 1)
                if is_loaded then add_pixel(15, x + math.floor(pos * 30), SEEK_BAR_Y) end
            end
        elseif bottom_row_mode == "speed" then
            if is_param_locked(track, "speed") then add_l_shape(draw_ops, x, BOTTOM_ROW_Y) end
            add_text(LEVELS.highlight, x, BOTTOM_ROW_Y, format_speed(cached.speed[track]), nil)
            local is_loaded = audio_active[track] or cached.live_input[track] == 1 or cached.live_direct[track] == 1
            if is_loaded and cached.live_direct[track] ~= 1 then
                local current_speed = cached.speed[track]
                local symbol = math.abs(current_speed) < 0.01 and "⏸" or (current_speed > 0 and "▶" or "◀")
                add_text(value_level, track == 1 and 75 or 116, BOTTOM_ROW_Y, symbol, nil)
            end
        elseif bottom_row_mode == "pan" then
            if is_param_locked(track, "pan") then add_l_shape(draw_ops, x, BOTTOM_ROW_Y) end
            local pan_val = cached.pan[track]
            local pan_text = math.abs(pan_val) < 0.5 and "0%" or string.format("%.0f%%", pan_val)
            add_text(LEVELS.highlight, x, BOTTOM_ROW_Y, pan_text, nil)
        elseif bottom_row_mode == "lpf" or bottom_row_mode == "hpf" then
            local filter_param = current_filter_mode == "lpf" and cached.cutoff[track] or cached.hpf[track]
            if filter_lock_ratio then add_l_shape(draw_ops, x, BOTTOM_ROW_Y) end
            local bar_width = util.linlin(math.log(20), math.log(20000), 0, 30, math.log(filter_param))
            add_rect(1, x, SEEK_BAR_Y, bar_width, 1)
            add_text(LEVELS.highlight, x, BOTTOM_ROW_Y, string.format("%.0f", filter_param), nil)
        end
    end
    -- Volume meters and pan indicators
    for track = 1, 2 do
        local height = util.linlin(-70, 10, 0, 64, cached.volume[track])
        add_rect(LEVELS.dim, VOLUME_METER_X[track], 64 - height, 1, height)
        local pos = util.linlin(-100, 100, PAN_CENTER_START[track], PAN_CENTER_START[track] + 25, cached.pan[track])
        add_rect(LEVELS.dim, pos - 1, 0, 4, 1)
    end
    -- Status indicators
    if cached.dry_mode == 1 then add_pixel(LEVELS.highlight, 6, 0) add_pixel(LEVELS.highlight, 10, 0) add_pixel(LEVELS.highlight, 14, 0) add_pixel(LEVELS.highlight, 18, 0) end
    if cached.symmetry == 1 then add_pixel(LEVELS.highlight, 18, 0) add_pixel(LEVELS.highlight, 20, 0) add_pixel(LEVELS.highlight, 22, 0) end
    if cached.evolution == 1 then local pattern = patterns[evolution_animation_phase] or patterns[0] for _, pixel in ipairs(pattern) do add_pixel(LEVELS.highlight, pixel[1], pixel[2]) end end 
    -- Grains (only if in seek mode)
    if bottom_row_mode == "seek" then
        for track = 1, 2 do
            local granular_gain = params:get(track.."granular_gain")
            if granular_gain > 0 then
                local base_x = TRACK_X[track]
                local kept = {}
                local size_ms = cached.size[track]
                local lifetime = size_ms > 0 and (size_ms * 0.001) or 0.01
                for _, g in ipairs(grain_positions[track]) do
                    local age = current_time - (g.t or 0)
                    if age <= lifetime then
                        local x = base_x + math.floor((g.pos or 0) * 30)
                        local bright = math.floor(lifetime > 0 and util.linlin(0, lifetime, LEVELS.highlight-2, LEVELS.dim, age) or LEVELS.highlight)
                        add_pixel(bright, x, SEEK_BAR_Y)
                        kept[#kept + 1] = g
                    end
                end
                grain_positions[track] = kept
            else
                grain_positions[track] = {}
            end
        end
    end
    -- Draw recording head
    if bottom_row_mode == "seek" then
        for track = 1, 2 do
            if cached.live_input[track] == 1 then
                add_recording_head(draw_ops, TRACK_X[track], SEEK_BAR_Y, rec_positions[track])
            end
        end
    end
    -- Draw morph bar
    if current_scene_mode == "on" then
        local bar_width = 22
        local morph_pos = util.linlin(0, 100, 0, bar_width, morph_amount)
        add_rect(1, 6, 0, bar_width, 1)
        add_rect(LEVELS.dim, 6, 0, morph_pos, 1)
    end 
    -- Draw save message
    if showing_save_message then add_rect(15, 40, 25, 48, 10) add_text(0, 64, 32, "SAVING...", "center") end
    local levels_used = {}
    -- Collect all levels used
    for _, op in ipairs(draw_ops.rects) do levels_used[op[1]] = true end
    for _, op in ipairs(draw_ops.pixels) do levels_used[op[1]] = true end
    for _, op in ipairs(draw_ops.text) do levels_used[op[1]] = true end
    local sorted_levels = {}
    for lvl in pairs(levels_used) do sorted_levels[#sorted_levels + 1] = lvl end
    table.sort(sorted_levels)
    -- Batch rendering by level
    for _, lvl in ipairs(sorted_levels) do
        screen.level(lvl)
        -- Render rectangles
        local rect_count = 0
        for _, op in ipairs(draw_ops.rects) do
            if op[1] == lvl then
                screen.rect(op[2], op[3], op[4], op[5])
                rect_count = rect_count + 1
            end
        end
        if rect_count > 0 then screen.fill() end
        -- Render pixels
        local pixel_count = 0
        for _, op in ipairs(draw_ops.pixels) do
            if op[1] == lvl then
                screen.pixel(op[2], op[3])
                pixel_count = pixel_count + 1
            end
        end
        if pixel_count > 0 then screen.fill() end
        -- Render text
        for _, op in ipairs(draw_ops.text) do
            if op[1] == lvl then
                screen.move(op[2], op[3])
                local text_value = tostring(op[4])
                if op[5] == "center" then 
                    screen.text_center(text_value)
                else screen.text(text_value) end
            end
        end
    end
    screen.restore()
    screen.update()
end

local osc_handlers = {
    ["/twins/buf_pos"] = function(args)
        local vid, pos = args[1] + 1, args[2]
        if audio_active[vid] or params:get(vid.."live_input") == 1 or params:get(vid.."live_direct") == 1 then
            osc_positions[vid] = pos
            params:set(vid.."seek", pos * 100, true)
        end
    end,
    ["/twins/rec_pos"] = function(args)
        local vid, pos = args[1] + 1, args[2]
        if params:get(vid.."live_input") == 1 then rec_positions[vid] = pos end
    end,
    ["/twins/grain_pos"] = function(args)
        local vid, pos = args[1] + 1, args[2]
        if audio_active[vid] then
            table.insert(grain_positions[vid], {pos = pos, t = util.time()})
        end
    end,
    ["/twins/output_saved"] = function(args)
        local filepath = args[1]
        params:set("unload_all", 1)
        clock.run(function()
            clock.sleep(0.1)
            params:set("1granular_gain", 0) disable_lfos_for_param("1speed") disable_lfos_for_param("1pan") params:set("1speed", 1) params:set("1sample", filepath) params:set("1pan", 0) params:set("2pan", 0) params:set("reverb_mix", 0) params:set("delay_mix", 0) params:set("shimmer_mix", 0) params:set("tape_mix", 1) params:set("dimension_mix", 0) params:set("sine_drive", 0) params:set("drive", 0) params:set("wobble_mix", 0) params:set("chew_depth", 0) params:set("lossdegrade_mix", 0) params:set("Width", 100)  params:set("rspeed", 0) params:set("haas", 1) params:set("monobass_mix", 1) params:set("bitcrush_mix", 0) params:set("1lock_speed", 2)
            for i = 1, 2 do 
                params:set(i.."eq_low_gain", 0) params:set(i.."eq_mid_gain", 0) params:set(i.."eq_high_gain", 0) params:set(i.."cutoff", 20000) params:set(i.."hpf", 20)
            end
        end)
    end, 
    ["/twins/save_complete"] = function(args)
        showing_save_message = false
        output_save_start_time = nil
    end}
local function osc_event(path, args) if osc_handlers[path] then osc_handlers[path](args) end end
local function setup_osc() osc.event = osc_event end

function init()
    initial_reverb_onoff = params:get('reverb')
    params:set('reverb', 1)
    initial_monitor_level = params:get('monitor_level')
    params:set('monitor_level', -math.huge)
    if not installer:ready() then clock.run(function() while true do redraw() clock.sleep(1 / 10) end end) do return end end
    setup_ui_metro()
    setup_params()
    setup_osc()
    setup_key1_monitor()
end

function cleanup()
    stop_metro_safe(ui_metro)
    stop_metro_safe(m_rand)
    stop_metro_safe(key1_monitor_metro)
    for i = 1, 2 do stop_metro_safe(randomize_metro[i]) end
    randpara.cleanup()
    params:set('monitor_level', initial_monitor_level)
    params:set('reverb', initial_reverb_onoff)
    osc.event = nil
end