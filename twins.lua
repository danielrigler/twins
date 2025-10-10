--
--
--   __ __|         _)          
--      | \ \  \  / |  \ |  (_< 
--      |  \_/\_/ _| _| _| __/ 
--            by: @dddstudio                       
-- 
--                          
--                           v0.43
-- E1: Master Volume
-- K1+E2/E3: Volume 1/2
-- K1+E1: Crossfade Volumes
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
local osc_positions = {[1] = 0, [2] = 0}
local rec_positions = {[1] = 0, [2] = 0}
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
local animation_y = -64
local animation_speed = 100
local animation_complete = false
local animation_start_time = nil
local initital_monitor_level
local initital_reverb_onoff
local filter_lock_ratio = false
local filter_differences = {[1] = 0, [2] = 0}
local oscgo = 0
local audio_active = {[1] = false, [2] = false}
local valid_audio_exts = {[".wav"]=true,[".aif"]=true,[".aiff"]=true,[".flac"]=true}
local mode_list = {"pitch","spread","density","size","jitter","lpf","pan","speed","seek"}
local mode_indices = {}; for i,v in ipairs(mode_list) do mode_indices[v]=i end
local mode_list2 = {"seek","speed","pan","lpf","jitter","size","density","spread","pitch"}
local mode_indices2 = {}; for i,v in ipairs(mode_list2) do mode_indices2[v]=i end
local current_scene_mode = "off"
local current_scenes = {[1] = 1, [2] = 1}
local scene_data = {[1] = {[1] = {}, [2] = {}}, [2] = {[1] = {}, [2] = {}}}
local evolution_animation_phase = 0
local evolution_animation_time = 0
local patterns = {[0] = {}, [1] = {{6,0}}, [2] = {{6,0}, {8,0}}, [3] = {{6,0}, {8,0}, {10,0}}, [4] = {{6,0}, {8,0}}, [5] = {{6,0}}}
local grain_positions = {[1] = {}, [2] = {}}
local param_modes = {
    speed = {param = "speed", delta = 0.5, engine = false, has_lock = true},
    seek = {param = "seek", delta = 1, engine = true, has_lock = true},
    pan = {param = "pan", delta = 5, engine = false, has_lock = true, invert = true},
    lpf = {param = "cutoff", delta = 1, engine = false, has_lock = false},
    hpf = {param = "hpf", delta = 1, engine = false, has_lock = false},
    jitter = {param = "jitter", delta = 2, engine = false, has_lock = true},
    size = {param = "size", delta = 2, engine = false, has_lock = true},
    density = {param = "density", delta = 2, engine = false, has_lock = true},
    spread = {param = "spread", delta = 2, engine = false, has_lock = true},
    pitch = {param = "pitch", delta = 1, engine = false, has_lock = true}}
local param_rows = {
    {y = 11, label = "jitter:    ", mode = "jitter", param1 = "1jitter", param2 = "2jitter"},
    {y = 21, label = "size:     ", mode = "size", param1 = "1size", param2 = "2size"},
    {y = 31, label = "density:  ", mode = "density", param1 = "1density", param2 = "2density", hz = true},
    {y = 41, label = "spread:   ", mode = "spread", param1 = "1spread", param2 = "2spread"},
    {y = 51, label = "pitch:    ", mode = "pitch", param1 = "1pitch", param2 = "2pitch", st = true}}

local function table_find(tbl, value) for i = 1, #tbl do if tbl[i] == value then return i end end return nil end
local function is_audio_loaded(track_num) local file_path = params:get(track_num .. "sample") return (file_path and file_path ~= "-") or audio_active[track_num] end
local function random_float(l, h) return l + math.random() * (h - l) end
local function stop_metro_safe(m) if m then local ok, err = pcall(function() m:stop() end) if m then m.event = nil end end end

local function update_evolution_animation()
    if params:get("evolution") == 1 then
        evolution_animation_time = evolution_animation_time + (1/60)
        local cycle_duration = 0.3
        evolution_animation_phase = math.floor((evolution_animation_time / cycle_duration) % 6)
    else
        evolution_animation_time = 0
        evolution_animation_phase = 0
    end
end

local function setup_ui_metro()
    ui_metro = metro.init()
    ui_metro.time = 1/60
    ui_metro.event = function()
        update_evolution_animation()
        if animation_complete then redraw() return end
        animation_start_time = animation_start_time or util.time()
        local elapsed = util.time() - animation_start_time
        local progress = util.clamp(elapsed * animation_speed / 64, 0, 1)
        local eased = 1 - (1 - progress) * (1 - progress) * (1 - progress)
        animation_y = -64 + (eased * 64)
        if progress >= 1 then
            animation_complete = true
            animation_y = 0
        end
        redraw()
    end
    ui_metro:start()
end

local function store_scene(track, scene)
    scene_data[track][scene] = {}
    local params_to_store = {"speed", "pitch", "jitter", "size", "density", "spread", "pan", "seek",
                             "cutoff", "hpf", "lpfgain", "granular_gain", "subharmonics_3", "subharmonics_2",
                             "subharmonics_1", "overtones_1", "overtones_2", "smoothbass", "pitch_random_plus",
                             "pitch_random_minus", "size_variation", "direction_mod", "density_mod_amt",
                             "pitch_mode", "trig_mode", "probability", "eq_low_gain", "eq_mid_gain", "eq_high_gain"}
    for _, param in ipairs(params_to_store) do
        local full_param = track .. param
        if params.lookup[full_param] then
            scene_data[track][scene][full_param] = params:get(full_param)
        end
    end
    scene_data[track][scene].lfo_data = {}
    for i = 1, 16 do
        if params:get(i.."lfo") == 2 then
            local target_index = params:get(i.."lfo_target")
            local target_param = lfo.lfo_targets[target_index]
            if target_param and target_param:sub(1, 1) == tostring(track) then
                scene_data[track][scene].lfo_data[i] = {
                    target = target_index,
                    shape = params:get(i.."lfo_shape"),
                    freq = params:get(i.."lfo_freq"),
                    depth = params:get(i.."lfo_depth"),
                    offset = params:get(i.."offset")}
            end
        end
    end
end

local function recall_scene(track, scene)
    if not scene_data[track][scene] then return end
    for param, value in pairs(scene_data[track][scene]) do
        if param ~= "lfo_data" and params.lookup[param] then
            params:set(param, value)
        end
    end
    if scene_data[track][scene].lfo_data then
        lfo.clearLFOs(tostring(track))
        for lfo_index, lfo_settings in pairs(scene_data[track][scene].lfo_data) do
            params:set(lfo_index.."lfo_target", lfo_settings.target)
            params:set(lfo_index.."lfo_shape", lfo_settings.shape)
            params:set(lfo_index.."lfo_freq", lfo_settings.freq)
            params:set(lfo_index.."lfo_depth", lfo_settings.depth)
            params:set(lfo_index.."offset", lfo_settings.offset)
            params:set(lfo_index.."lfo", 2)
        end
    end
    current_scenes[track] = scene
end

local function initialize_scenes_with_current_params() for track = 1, 2 do for scene = 1, 2 do store_scene(track, scene) end end end

local function is_lfo_active_for_param(param_name)
    for i = 1, 16 do
        local target_index = params:get(i.. "lfo_target")
        if lfo.lfo_targets[target_index] == param_name and params:get(i.. "lfo") == 2 then
            return true, i
        end
    end
    return false, nil
end

local function disable_lfos_for_param(param_name, only_self)
    local base_param = param_name:sub(2)
    if only_self then
        local is_active, lfo_index = is_lfo_active_for_param(param_name)
        if is_active then
            params:set(lfo_index .. "lfo", 1)
        end
    else
        for track = 1, 2 do
            local full_param = track .. base_param
            local is_active, lfo_index = is_lfo_active_for_param(full_param)
            if is_active then
                params:set(lfo_index .. "lfo", 1)
            end
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
    if force_disable then
        disable_lfos_for_param(param_name)
    else
        local active, idx = is_lfo_active_for_param(param_name)
        if active then 
            params:set(idx.."lfo", 1) 
        end
    end
end

local last_selected = nil
local function load_random_tape_file(track_num)
    if params:get(track_num .. "live_input") == 1 then return false end
    local function scan(dir)
      local files = {}
      for _, entry in ipairs(util.scandir(dir)) do
        local path = dir .. entry
        if entry:sub(-1) == "/" then for _, f in ipairs(scan(path)) do files[#files+1] = f end
        elseif valid_audio_exts[path:lower():match("^.+(%..+)$") or ""] then files[#files+1] = path end
      end
      return files
    end
    local audio_files = scan(_path.tape)
    if #audio_files == 0 then return false end
    local selected
    if track_num == 2 and last_selected and math.random() < 0.5 then selected = last_selected
    else selected = audio_files[math.random(#audio_files)] end
    last_selected = selected
    if params:get(track_num .. "sample") ~= selected then params:set(track_num .. "sample", selected) end
    oscgo = 1
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

local function is_param_locked(track_num, param)
    return params:get(track_num .. "lock_" .. param) == 2
end

local function update_pan_positioning()
  local loaded1 = is_audio_loaded(1)
  local loaded2 = is_audio_loaded(2)
  if not is_param_locked(1, "pan") and not is_lfo_active_for_param("1pan") then params:set("1pan", loaded2 and -15 or 0) end
  if not is_param_locked(2, "pan") and not is_lfo_active_for_param("2pan") then params:set("2pan", loaded1 and 15 or 0) end
end

local function setup_params()
    params:add_separator("Input")
    for i = 1, 2 do
        params:add_file(i.. "sample", "Sample " ..i) params:set_action(i.."sample", function(file) if file ~= nil and file ~= "" and file ~= "none" and file ~= "-" then engine.read(i, file) audio_active[i] = true oscgo = 1 update_pan_positioning() local duration = get_audio_duration(file) if duration then local duration_ms = duration * 1000 params:set(i.."max_jitter", math.min(duration_ms, 99999)) params:set(i.."min_jitter", 0) if not is_param_locked(i, "jitter") then local jitter_param = i.."jitter" handle_lfo(jitter_param, true) local jitter_value = (duration * 0.2) * 1000 jitter_value = util.clamp(jitter_value, 0, 99999) params:set(i.."jitter", jitter_value) end end else audio_active[i] = false osc_positions[i] = 0 update_pan_positioning() end end) end
    params:add_binary("randomtapes", "Random Tapes", "trigger", 0) params:set_action("randomtapes", function() load_random_tape_file(1) load_random_tape_file(2) end)
    
    params:add_group("Live!", 10)
    for i = 1, 2 do
      params:add_binary(i.."live_input", "Live Buffer "..i.." ● ►", "toggle", 0) params:set_action(i.."live_input", function(value) if value == 1 then if params:get(i.."live_direct") == 1 then params:set(i.."live_direct", 0) end engine.set_live_input(i, 1) engine.live_mono(i, params:get("isMono") - 1) audio_active[i] = true oscgo = 1 update_pan_positioning() else engine.set_live_input(i, 0) if not audio_active[i] and params:get(i.."live_direct") == 0 then osc_positions[i] = 0 else oscgo = 1 update_pan_positioning() end end end)
    end
    params:add_control("live_buffer_mix", "Overdub", controlspec.new(0, 100, "lin", 1, 100, "%")) params:set_action("live_buffer_mix", function(value) engine.live_buffer_mix(value * 0.01) end)
    params:add_control("live_buffer_length", "Buffer Length", controlspec.new(0.1, 60, "lin", 0.1, 2, "s")) params:set_action("live_buffer_length", function(value) engine.live_buffer_length(value) end)
    params:add{type = "trigger", id = "save_live_buffer1", name = "Buffer1 to Tape", action = function() local timestamp = os.date("%Y%m%d_%H%M%S") local filename = "live1_"..timestamp..".wav" engine.save_live_buffer(1, filename) end}
    params:add{type = "trigger", id = "save_live_buffer2", name = "Buffer2 to Tape", action = function() local timestamp = os.date("%Y%m%d_%H%M%S") local filename = "live2_"..timestamp..".wav" engine.save_live_buffer(2, filename) end}
    for i = 1, 2 do
      params:add_binary(i.."live_direct", "Direct "..i.." ►", "toggle", 0) params:set_action(i.."live_direct", function(value) if value == 1 then local was_live = params:get(i.."live_input") _G["prev_live_state_"..i] = was_live if was_live == 1 then params:set(i.."live_input", 0) end engine.live_direct(i, 1) audio_active[i] = true oscgo = 1 update_pan_positioning() else engine.live_direct(i, 0) if not audio_active[i] and params:get(i.."live_input") == 0 then osc_positions[i] = 0 else oscgo = 1 update_pan_positioning() end end end)
    end
    params:add_option("isMono", "Input Mode", {"stereo", "mono"}, 1) params:set_action("isMono", function(value) local monoValue = value - 1 for i = 1, 2 do if params:get(i.."live_direct") == 1 then engine.isMono(i, monoValue) end if params:get(i.."live_input") == 1 then engine.live_mono(i, monoValue) end end end)
    params:add_binary("dry_mode2", "Dry Mode", "toggle", 0) params:set_action("dry_mode2", function(x) drymode.toggle_dry_mode2() end)

    params:add_separator("Settings")
    params:add_group("Granular", 41)
    for i = 1, 2 do
      params:add_separator("Sample "..i)
      params:add_control(i.. "granular_gain", i.. " Mix", controlspec.new(0, 100, "lin", 1, 100, "%")) params:set_action(i.. "granular_gain", function(value) engine.granular_gain(i, value * 0.01) if value < 100 then lfo.clearLFOs(i, "seek") end end)
      params:add_control(i.. "subharmonics_3", i.. " Subharmonics -3oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0)) params:set_action(i.. "subharmonics_3", function(value) engine.subharmonics_3(i, value) end)
      params:add_control(i.. "subharmonics_2", i.. " Subharmonics -2oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0)) params:set_action(i.. "subharmonics_2", function(value) engine.subharmonics_2(i, value) end)
      params:add_control(i.. "subharmonics_1", i.. " Subharmonics -1oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0)) params:set_action(i.. "subharmonics_1", function(value) engine.subharmonics_1(i, value) end)
      params:add_control(i.. "overtones_1", i.. " Overtones +1oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0)) params:set_action(i.. "overtones_1", function(value) engine.overtones_1(i, value) end)
      params:add_control(i.. "overtones_2", i.. " Overtones +2oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0)) params:set_action(i.. "overtones_2", function(value) engine.overtones_2(i, value) end)
      params:add_option(i.. "smoothbass", i.." Smooth Sub", {"off", "on"}, 1) params:set_action(i.. "smoothbass", function(x) local engine_value = (x == 2) and 2.5 or 1 engine.smoothbass(i, engine_value) end)
      params:add_control(i.. "pitch_random_plus", i.. " Octave Variation +", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.. "pitch_random_plus", function(value) engine.pitch_random_plus(i, value * 0.01) end)
      params:add_control(i.. "pitch_random_minus", i.. " Octave Variation -", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.. "pitch_random_minus", function(value) engine.pitch_random_minus(i, value * 0.01) end)
      params:add_option(i.."pitch_walk_mode", i.." Pitch Walk", {"off", "on"}, 1) params:set_action(i.."pitch_walk_mode", function(value) engine.pitch_walk_mode(i, value - 1) end)
      params:add_control(i.."pitch_walk_rate", i.." Walk Rate", controlspec.new(0.1, 30, "exp", 0.1, 1, "Hz")) params:set_action(i.."pitch_walk_rate", function(value) engine.pitch_walk_rate(i, value) end)
      params:add_control(i.."pitch_walk_step", i.." Walk Range", controlspec.new(1, 24, "lin", 1, 2, "steps")) params:set_action(i.."pitch_walk_step", function(value) engine.pitch_walk_step(i, value) end)
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
    params:add_taper("delay_mix", "Mix", 0, 100, 0, 1, "%") params:set_action("delay_mix", function(value) engine.mix(value * 0.01) end)
    params:add_taper("delay_time", "Time", 0.02, 2, 0.5, 0.1, "s") params:set_action("delay_time", function(value) engine.delay(value) end)
    params:add_binary("tap", "↳ TAP!", "trigger", 0) params:set_action("tap", function() register_tap() end)
    params:add_taper("delay_feedback", "Feedback", 0, 120, 30, 1, "%") params:set_action("delay_feedback", function(value) engine.fb_amt(value * 0.01) end)
    params:add_control("delay_lowpass", "LPF", controlspec.new(20, 20000, 'exp', 1, 20000, "Hz")) params:set_action('delay_lowpass', function(value) engine.lpf(value) end)
    params:add_control("delay_highpass", "HPF", controlspec.new(20, 20000, 'exp', 1, 20, "Hz")) params:set_action('delay_highpass', function(value) engine.dhpf(value) end)
    params:add_taper("wiggle_depth", "Mod Depth", 0, 100, 1, 0, "%") params:set_action("wiggle_depth", function(value) engine.w_depth(value * 0.01) end)
    params:add_taper("wiggle_rate", "Mod Freq", 0, 20, 2, 1, "Hz") params:set_action("wiggle_rate", function(value) engine.w_rate(value) end)
    params:add_taper("stereo", "Ping-Pong", 0, 100, 30, 1, "%") params:set_action("stereo", function(value) engine.stereo(value * 0.01) end)
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
    
    params:add_group("Tape", 17)
    params:add_option("tape_mix", "Analog Tape", {"off", "on"}, 1) params:set_action("tape_mix", function(x) engine.tape_mix(x-1) end)
    params:add_option("tascam", "Tascam Filter", {"off", "on"}, 1) params:set_action("tascam", function(x) engine.tascam(x-1) end)
    params:add_control("sine_drive", "Shaper Drive", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("sine_drive", function(value) engine.sine_drive((10+value)/20) end)
    params:add_control("drive", "Saturation", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("drive", function(x) engine.drive(x * 0.01) end)
    params:add{type = "control", id = "wobble_mix", name = "Wobble", controlspec = controlspec.new(0, 100, "lin", 1, 0, "%"), action = function(value) engine.wobble_mix(value * 0.01) end}
    params:add{type = "control", id = "wobble_amp", name = "Wow Depth", controlspec = controlspec.new(0, 100, "lin", 1, 20, "%"), action = function(value) engine.wobble_amp(value * 0.01) end}
    params:add{type = "control", id = "wobble_rpm", name = "Wow Speed", controlspec = controlspec.new(30, 90, "lin", 1, 33, "RPM"), action = function(value) engine.wobble_rpm(value) end}
    params:add{type = "control", id = "flutter_amp", name = "Flutter Depth", controlspec = controlspec.new(0, 100, "lin", 1, 35, "%"), action = function(value) engine.flutter_amp(value * 0.01) end}
    params:add{type = "control", id = "flutter_freq", name = "Flutter Speed", controlspec = controlspec.new(3, 30, "lin", 0.01, 6, "Hz"), action = function(value) engine.flutter_freq(value) end}
    params:add{type = "control", id = "flutter_var", name = "Flutter Var.", controlspec = controlspec.new(0.1, 10, "lin", 0.01, 2, "Hz"), action = function(value) engine.flutter_var(value) end}
    params:add{type = "control", id = "chew_depth", name = "Chew", controlspec = controlspec.new(0, 50, "lin", 1, 0, "%"), action = function(value) engine.chew_depth(value * 0.01) end}
    params:add{type = "control", id = "chew_freq", name = "Chew Freq.", controlspec = controlspec.new(0, 60, "lin", 1, 25, "%"), action = function(value) engine.chew_freq(value * 0.01) end}
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
    
    params:add_group("Stereo", 4)
    params:add_control("Width", "Stereo Width", controlspec.new(0, 200, "lin", 0.01, 100, "%")) params:set_action("Width", function(value) engine.width(value * 0.01) end)
    params:add_taper("rspeed", "Rotation Speed", 0, 1, 0, 1) params:set_action("rspeed", function(value) engine.rspeed(value) end)
    params:add_option("haas", "Haas Effect", {"off", "on"}, 1) params:set_action("haas", function(x) engine.haas(x-1) end)
    params:add_option("monobass_mix", "Mono Bass", {"off", "on"}, 1) params:set_action("monobass_mix", function(x) engine.monobass_mix(x-1) end)

    params:add_group("BitCrush", 3)
    params:add_taper("bitcrush_mix", "Mix", 0, 100, 0.0, 0, "%") params:set_action("bitcrush_mix", function(value) engine.bitcrush_mix(value * 0.01) end)
    params:add_taper("bitcrush_rate", "Rate", 0, 44100, 4500, 100, "Hz") params:set_action("bitcrush_rate", function(value) engine.bitcrush_rate(value) end)
    params:add_taper("bitcrush_bits", "Bits", 1, 24, 14, 1) params:set_action("bitcrush_bits", function(value) engine.bitcrush_bits(value) end)

    params:add_group("LFOs", 118)
    params:add_binary("randomize_lfos", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_lfos", function() lfo.clearLFOs() local allow_vol = params:get("allow_volume_lfos") == 2 for i = 1, 2 do lfo.randomize_lfos(i, allow_vol) end end)
    params:add_binary("lfo.assign_to_current_row", "Assign to Selection", "trigger", 0) params:set_action("lfo.assign_to_current_row", function() lfo.assign_to_current_row(current_mode, current_filter_mode) end)
    params:add_control("global_lfo_freq_scale", "Freq Scale", controlspec.new(0.1, 10, "exp", 0.01, 1.0, "x")) params:set_action("global_lfo_freq_scale", function(value) local base_freq for i = 1, 16 do local phase = lfo[i].phase base_freq = params:get(i.."lfo_freq") or 0.05 lfo[i].base_freq = base_freq lfo[i].freq = base_freq * value lfo[i].phase = phase end end)
    params:add_binary("lfo_pause", "Pause ⏸︎", "toggle", 0) params:set_action("lfo_pause", function(value) lfo.set_pause(value == 1) end)
    params:add_binary("ClearLFOs", "Clear All", "trigger", 0) params:set_action("ClearLFOs", function() lfo.clearLFOs() update_pan_positioning() end)
    params:add_option("allow_volume_lfos", "Allow Volume LFOs", {"no", "yes"}, 1) params:set_action("allow_volume_lfos", function(value) if value == 2 then lfo.clearLFOs("1", "volume") lfo.clearLFOs("2", "volume") lfo.assign_volume_lfos() else lfo.clearLFOs("1", "volume") lfo.clearLFOs("2", "volume") end end)
    lfo.init()

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

    params:add_group("Symmetry", 3)
    params:add_binary("symmetry", "Symmetry", "toggle", 0)
    params:add_binary("copy_1_to_2", "Copy 1 → 2", "trigger", 0) params:set_action("copy_1_to_2", function() Mirror.copy_voice_params("1", "2", true) end)
    params:add_binary("copy_2_to_1", "Copy 1 ← 2", "trigger", 0) params:set_action("copy_2_to_1", function() Mirror.copy_voice_params("2", "1", true) end)
    
    params:add_group("Limits", 30) 
    for i = 1, 2 do
        params:add_separator("Voice "..i)
        params:add_taper(i.."min_jitter", i.." jitter (min)", 0, 999999, 0, 5, "ms")
        params:add_taper(i.."max_jitter", i.." jitter (max)", 0, 999999, 4999, 5, "ms")
        params:add_taper(i.."min_size", i.." size (min)", 1, 999, 100, 5, "ms")
        params:add_taper(i.."max_size", i.." size (max)", 1, 999, 499, 5, "ms")
        params:add_taper(i.."min_density", i.." density (min)", 0.1, 50, 1, 5, "Hz")
        params:add_taper(i.."max_density", i.." density (max)", 0.1, 50, 16, 5, "Hz")
        params:add_taper(i.."min_spread", i.." spread (min)", 0, 100, 0, 0, "%")
        params:add_taper(i.."max_spread", i.." spread (max)", 0, 100, 75, 0, "%")
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
    
    params:add_group("Other", 7)
    params:add_binary("dry_mode", "Dry Mode", "toggle", 0) params:set_action("dry_mode", function(x) drymode.toggle_dry_mode() end)
    params:add_option("scene_mode", "Scene Mode", {"off", "on"}, 1) params:set_action("scene_mode", function(value) current_scene_mode = (value == 2) and "on" or "off" if current_scene_mode == "on" then initialize_scenes_with_current_params() end end)
    params:add_binary("unload_all", "Unload All Audio", "trigger", 0) params:set_action("unload_all", function() for i=1, 2 do params:set(i.."seek", 0) params:set(i.."sample", "-") params:set(i.."live_input", 0) params:set(i.."live_direct", 0) audio_active[i] = false osc_positions[i] = 0 end engine.unload_all() oscgo = 0 update_pan_positioning() end)
    params:add_option("steps", "Transition Time", {"short", "medium", "long"}, 2) params:set_action("steps", function(value) steps = ({20, 300, 800})[value] end)
    params:add_binary("evolution", "Evolve!", "toggle", 0) params:set_action("evolution", function(value) if value == 1 then randpara.reset_evolution_centers() randpara.start_evolution() else randpara.stop_evolution() end end)
    params:add_control("evolution_range", "Evolution Range", controlspec.new(0, 100, "lin", 1, 25, "%")) params:set_action("evolution_range", function(value) randpara.set_evolution_range(value) end)
    params:add_option("evolution_rate", "Evolution Rate", {"slowest", "slow", "moderate", "medium", "fast", "crazy"}, 3) params:set_action("evolution_rate", function(value) local rates = {1/0.5, 1/1.5, 1/4, 1/8, 1/15, 1/30} randpara.set_evolution_rate(rates[value]) end)

    for i = 1, 2 do
      params:add_taper(i.. "volume", i.. " volume", -70, 10, -15, 0, "dB") params:set_action(i.. "volume", function(value) if value == -70 then engine.volume(i, 0) else engine.volume(i, math.pow(10, value / 20)) end end) params:hide(i.. "volume")
      params:add_taper(i.. "pan", i.. " pan", -100, 100, 0, 0, "%") params:set_action(i.. "pan", function(value) engine.pan(i, value * 0.01)  end) params:hide(i.. "pan")
      params:add_taper(i.. "speed", i.. " speed", -2, 2, 0.10, 0) params:set_action(i.. "speed", function(value) if math.abs(value) < 0.01 then engine.speed(i, 0) else engine.speed(i, value) end end) params:hide(i.. "speed")
      params:add_taper(i.. "density", i.. " density", 0.1, 300, 10, 5) params:set_action(i.. "density", function(value) engine.density(i, value) end) params:hide(i.. "density")
      params:add_control(i.. "pitch", i.. " pitch", controlspec.new(-48, 48, "lin", 1, 0, "st")) params:set_action(i.. "pitch", function(value) engine.pitch_offset(i, math.pow(0.5, -value / 12)) end) params:hide(i.. "pitch")
      params:add_taper(i.. "jitter", i.. " jitter", 0, 999900, 2500, 10, "ms") params:set_action(i.. "jitter", function(value) engine.jitter(i, value * 0.001) end) params:hide(i.. "jitter")
      params:add_taper(i.. "size", i.. " size", 1, 5999, 200, 1, "ms") params:set_action(i.. "size", function(value) engine.size(i, value * 0.001) end) params:hide(i.. "size")
      params:add_taper(i.. "spread", i.. " spread", 0, 100, 30, 0, "%") params:set_action(i.. "spread", function(value) engine.spread(i, value * 0.01) end) params:hide(i.. "spread")
      params:add_control(i.. "seek", i.. " seek", controlspec.new(0, 100, "lin", 0.01, 0, "%")) params:set_action(i.. "seek", function(value) engine.seek(i, value * 0.01) end) params:hide(i.. "seek")
    end
    params:bang()
end

local function randomize_pitch(track, other_track, symmetry)
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
            if random_weight <= cumulative_weight then
                local new_pitch = base_pitch + v.interval
                if params:get(track.."pitch") ~= new_pitch then
                    params:set(track.."pitch", new_pitch)
                    if symmetry then
                        params:set(other_track.."pitch", new_pitch)
                    end
                end
                return
            end
        end
    end
    for _, interval in ipairs(larger_intervals) do
        local candidate_pitch = base_pitch + interval
        if candidate_pitch >= min_pitch and candidate_pitch <= max_pitch then
            if params:get(track.."pitch") ~= candidate_pitch then
                params:set(track.."pitch", candidate_pitch)
                if symmetry then
                    params:set(other_track.."pitch", candidate_pitch)
                end
            end
            return
        end
    end
end

local function randomize(n)
    randomize_metro[n] = randomize_metro[n] or metro.init()
    local m_rand = randomize_metro[n]
    active_controlled_params = {}
    local symmetry = params:get("symmetry") == 1
    local other_track = (n == 1) and 2 or 1
    local locked_params = {
        speed   = params:get(n .. "lock_speed") == 1,
        jitter  = params:get(n .. "lock_jitter") == 1,
        size    = params:get(n .. "lock_size") == 1,
        density = params:get(n .. "lock_density") == 1,
        spread  = params:get(n .. "lock_spread") == 1,
        pitch   = params:get(n .. "lock_pitch") == 1,
        seek    = params:get(n .. "lock_seek") == 1}
    local param_config = {
        speed   = {min = n.."min_speed",   max = n.."max_speed",   name = n .. "speed"},
        jitter  = {min = n.."min_jitter",  max = n.."max_jitter",  name = n .. "jitter"},
        size    = {min = n.."min_size",    max = n.."max_size",    name = n .. "size"},
        density = {min = n.."min_density", max = n.."max_density", name = n .. "density"},
        spread  = {min = n.."min_spread",  max = n.."max_spread",  name = n .. "spread"},
        pitch   = {name = n .. "pitch"},
        seek    = {min = n.."min_seek",    max = n.."max_seek",    name = n .. "seek"}}
    local targets = {}
    if locked_params.pitch and not active_controlled_params[param_config.pitch.name] then
        randomize_pitch(n, other_track, symmetry)
    end
    for key, cfg in pairs(param_config) do
        local min_val = cfg.min and params:get(cfg.min)
        local max_val = cfg.max and params:get(cfg.max)
        if key ~= "pitch" and key ~= "seek" and locked_params[key] and not active_controlled_params[cfg.name] then
            if min_val and max_val and min_val < max_val and not is_lfo_active_for_param(cfg.name) then
                local val = random_float(min_val, max_val)
                targets[cfg.name] = val
                if symmetry then
                  local other_name = (key == "pan") and (other_track .. "pan") or (other_track .. key)
                  targets[other_name] = (key == "pan") and -val or val
                end
            end
        elseif key == "seek" and locked_params[key] and not active_controlled_params[cfg.name] then
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
        end
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
    local lfo_delta = 1.5 * delta
    local vol_delta = 3 * delta
    if a1 and a2 then
        params:delta(i1.."offset", lfo_delta)
        params:delta(i2.."offset", crossfade_mode and -lfo_delta or lfo_delta)
    elseif a1 then
        params:delta(i1.."offset", lfo_delta)
        params:delta(op, crossfade_mode and -vol_delta or vol_delta)
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
    if sym then
        update_track_ratio(3 - track, is_size and 3 or 0, is_density and 0.05 or 0)
    end
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
        if config.param == "pan" then
            params:delta(p, delta)
            params:delta(op, -delta)
            engine.pan(track, params:get(p) * 0.01)
            engine.pan(other_track, params:get(op) * 0.01)
        else
            params:delta(p, delta)
            params:delta(op, delta)
        end
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

local function handle_scene_mode(n)
    if current_scene_mode ~= "on" or not key_state[1] then
        return false
    end
    local track = n - 1
    if track >= 1 and track <= 2 then
        store_scene(track, current_scenes[track])
        local new_scene = (current_scenes[track] % 2) + 1
        recall_scene(track, new_scene)
        return true
    end
    return false
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
    local k1 = key_state[1]
    if n == 1 then
        handle_volume_lfo(1, d, k1)
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
            local delta = config.delta * d
            handle_param_change(track, config, delta)
        end
    end
end

function key(n, z)
    if not installer:ready() then 
        installer:key(n, z) 
        return 
    end
    key_state[n] = z == 1
    if z == 1 then
        if handle_scene_mode(n) then return end
        if handle_randomize_track(n) then return end
        handle_mode_navigation(n)
    end
    if key_state[2] and key_state[3] then
        handle_parameter_lock()
    end
end

local function format_density(value) return string.format("%.1f Hz", value) end
local function format_pitch(value, track) local pitch_walk_enabled = track and params:get(track.."pitch_walk_mode") == 2 if value > 0 then return string.format("+%.0f%s", value, pitch_walk_enabled and ".." or "") else return string.format("%.0f%s", value, pitch_walk_enabled and ".." or "") end end
local function format_seek(value) return string.format("%.0f%%", value) end
local function format_speed(speed) if math.abs(speed) < 0.01 then return ".00x" elseif math.abs(speed) < 1 then if speed < -0.01 then return string.format("-.%02dx", math.floor(math.abs(speed) * 100)) else return string.format(".%02dx", math.floor(math.abs(speed) * 100)) end else return string.format("%.2fx", speed) end end
local function format_jitter(value) if value > 999 then return string.format("%.1f s", value / 1000) else return string.format("%.0f ms", value) end end
local function format_size(value) if value > 999 then return string.format("%.2f s", value / 1000) else return string.format("%.0f ms", value) end end

local function draw_l_shape(x, y)
    local pulse_level = math.floor(util.linlin(-1, 1, 1, 8, math.sin(util.time() * 4)))
    screen.level(pulse_level)
    screen.move(x - 4, y) screen.line_rel(2, 0) screen.move(x - 3, y) screen.line_rel(0, -3)
    screen.stroke()
end

local function draw_lock_shape(x, y)
    screen.level(4)
    screen.move(x - 3, y + 1) screen.line_rel(0, 1) screen.move(x - 3, y + 3) screen.line_rel(0, 1) screen.move(x - 3, y + 5) screen.line_rel(0, 1)
    screen.stroke()
end

local function draw_recording_head(x, y, position)
    screen.level(15)
    screen.rect(x + math.floor(position * 30), y - 1, 1, 2)
    screen.fill()
end

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

function redraw()
    if not installer:ready() then installer:redraw() return end
    screen.clear()
    screen.save()
    screen.translate(0, animation_y)
    local levels = {highlight = 15, dim = 6, value = 4}
    local cached_volume = {params:get("1volume"), params:get("2volume")}
    local cached_pan    = {params:get("1pan"), params:get("2pan")}
    local cached_seek   = {params:get("1seek"), params:get("2seek")}
    local cached_speed  = {params:get("1speed"), params:get("2speed")}
    local cached_cutoff = {params:get("1cutoff"), params:get("2cutoff")}
    local cached_hpf    = {params:get("1hpf"), params:get("2hpf")}
    local dry_mode      = params:get("dry_mode")
    local symmetry      = params:get("symmetry")
    local rects = {[1] = {}, [levels.highlight] = {}, [levels.dim] = {}, [levels.value] = {} }
    local pixels_by_level = {}

    local function add_pixel(x, y, lvl)
        lvl = math.max(0, math.min(15, math.floor(lvl or levels.highlight)))
        pixels_by_level[lvl] = pixels_by_level[lvl] or {}
        table.insert(pixels_by_level[lvl], {x, y})
    end
    -- Draw upper 5 parameter rows
    for _, row in ipairs(param_rows) do
        local param_name = string.match(row.label, "%a+")
        local is_highlighted = (current_mode == row.mode)
        screen.level(levels.highlight)
        screen.move(5, row.y)
        screen.text(row.label)
        for track = 1, 2 do
            local param = (track == 1) and row.param1 or row.param2
            local x = (track == 1) and 51 or 92
            -- Locks
            if (param_name == "size") and params:get(track.."size_density_lock") == 1 then draw_lock_shape(x, row.y) end
            if is_param_locked(track, param_name) then draw_l_shape(x, row.y) end
            -- Text values
            screen.move(x, row.y)
            screen.level(is_highlighted and levels.highlight or levels.value)
            local lfo_mod = get_lfo_modulation(param)
            local val = lfo_mod or params:get(param)
            if row.hz then screen.text(format_density(val))
            elseif row.st then screen.text(format_pitch(val, track))
            elseif param_name == "spread" then screen.text(string.format("%.0f%%", val))
            elseif param_name == "jitter" then screen.text(format_jitter(val))
            elseif param_name == "size" then screen.text(format_size(val)) 
            else screen.text(params:string(param)) end
            -- LFO modulation bars
            if param_name ~= "pitch" then
                local min_val, max_val = lfo.get_parameter_range(param)
                local lfo_mod = get_lfo_modulation(param)
                if lfo_mod then
                    local bar_value = util.linlin(min_val, max_val, 0, 30, lfo_mod)
                    table.insert(rects[levels.dim], {x, row.y + 1, bar_value, 1})
                end
            end
        end
    end
    -- Determine bottom row mode
    local upper_modes = {jitter=true, size=true, density=true, spread=true, pitch=true}
    local is_upper_row_active = upper_modes[current_mode]
    local bottom_row_mode = is_upper_row_active and "seek" or current_mode
    local is_bottom_active = not is_upper_row_active
    -- Bottom row label
    screen.move(5, 61)
    screen.level(levels.highlight)
    if bottom_row_mode == "lpf" or bottom_row_mode == "hpf" then screen.text(current_filter_mode == "lpf" and "lpf:      " or "hpf:      ")
    else screen.text(bottom_row_mode .. ":     ") end
    -- Bottom row values
    for track = 1, 2 do
        local x = (track == 1) and 51 or 92
        if bottom_row_mode == "seek" then
            if is_param_locked(track, "seek") then draw_l_shape(x, 61) end
            local current_speed = cached_speed[track]
            local is_loaded = audio_active[track] or params:get(track.."live_input") == 1 or params:get(track.."live_direct") == 1
            screen.level(is_bottom_active and levels.highlight or levels.value)
            screen.move(x, 61)
            if params:get(track.."live_input") == 1 then 
                screen.text("live")
            elseif params:get(track.."live_direct") == 1 then 
                screen.text("direct")
            else 
                screen.text(string.format("%.0f%%", osc_positions[track] * 100))
            end
            if is_loaded and params:get(track.."live_direct") ~= 1 then
                local symbol
                if math.abs(current_speed) < 0.01 then symbol = "⏸"
                elseif current_speed > 0 then symbol = "▶"
                else symbol = "◀"
                end
                local symbol_x = (track == 1) and 75 or 116
                screen.move(symbol_x, 61)
                screen.text(symbol)
            end
            if params:get(track.."live_direct") ~= 1 then 
                table.insert(rects[1], {x, 63, 30, 1})
                table.insert(rects[levels.dim], {x, 63, 30 * osc_positions[track], 1})
                add_pixel(x + math.floor(osc_positions[track] * 30), 63, 15)
            end
        elseif bottom_row_mode == "speed" then
            if is_param_locked(track, "speed") then draw_l_shape(x, 61) end
            screen.move(x, 61)
            screen.level(levels.highlight)
            screen.text(format_speed(cached_speed[track]))
        elseif bottom_row_mode == "pan" then
            if is_param_locked(track, "pan") then draw_l_shape(x, 61) end
            screen.move(x, 61)
            screen.level(levels.highlight)
            screen.text(math.abs(cached_pan[track]) < 0.5 and "0%" or string.format("%.0f%%", cached_pan[track]))
        elseif bottom_row_mode == "lpf" or bottom_row_mode == "hpf" then
            local filter_param = (current_filter_mode == "lpf") and cached_cutoff[track] or cached_hpf[track]
            if filter_lock_ratio then draw_l_shape(x, 61) end
            local bar_width = util.linlin(math.log(20), math.log(20000), 0, 30, math.log(filter_param))
            table.insert(rects[levels.dim], {x, 63, bar_width, 1})
            screen.move(x, 61)
            screen.level(levels.highlight)
            screen.text(string.format("%.0f", filter_param))
        end
    end
    -- Volume meters
    for track = 1, 2 do
        local x = (track == 1) and 0 or 127
        local height = util.linlin(-70, 10, 0, 64, cached_volume[track])
        table.insert(rects[levels.dim], {x, 64 - height, 1, height})
    end
    -- Pan indicators
    for track = 1, 2 do
        local center_start = (track == 1) and 52 or 93
        local pos = util.linlin(-100, 100, center_start, center_start + 25, cached_pan[track])
        table.insert(rects[levels.dim], {pos - 1, 0, 4, 1})
    end
    -- Status indicators
    if dry_mode == 1 then add_pixel(6,0, levels.highlight) add_pixel(10,0, levels.highlight) add_pixel(14,0, levels.highlight) add_pixel(18,0, levels.highlight) end
    if symmetry == 1 then add_pixel(18,0, levels.highlight) add_pixel(20,0, levels.highlight) add_pixel(22,0, levels.highlight) end
    if params:get("evolution") == 1 then 
      local pattern = patterns[evolution_animation_phase] or patterns[0]
      for _, pixel in ipairs(pattern) do
        add_pixel(pixel[1], pixel[2], levels.highlight)
      end
    end 
    -- grains
    if bottom_row_mode == "seek" then
        for track = 1, 2 do
            local base_x = (track == 1) and 51 or 92
            local kept = {}
            local size_ms = params:get(track .. "size") or 0
            local lifetime = (size_ms > 0) and (size_ms * 0.001) or 0.01
            for _, g in ipairs(grain_positions[track]) do
                local age = util.time() - (g.t or 0)
                if age <= lifetime then
                    local x = base_x + math.floor(util.clamp(g.pos or 0, 0, 1) * 30)
                    local y = 63
                    local bright
                    if lifetime > 0 then
                        bright = util.linlin(0, lifetime, levels.highlight-2, levels.dim, age)
                    else
                        bright = levels.highlight
                    end
                    add_pixel(x, y, bright)
                    table.insert(kept, g)
                end
            end
            grain_positions[track] = kept
        end
    end
    local level_keys_map = {[1] = true}
    for _, v in ipairs({levels.dim, levels.value, levels.highlight}) do level_keys_map[v] = true end
    for lvl, _ in pairs(pixels_by_level) do level_keys_map[lvl] = true end
    local level_keys = {}
    for k, _ in pairs(level_keys_map) do table.insert(level_keys, k) end
    table.sort(level_keys)
    for _, lvl in ipairs(level_keys) do
        screen.level(lvl)
        if rects[lvl] then
            for _, r in ipairs(rects[lvl]) do
                screen.rect(table.unpack(r))
            end
        end
        if pixels_by_level[lvl] then
            for _, p in ipairs(pixels_by_level[lvl]) do
                screen.pixel(p[1], p[2])
            end
        end
        screen.fill()
    end
    -- draw recording head
    for track = 1, 2 do
        if params:get(track.."live_input") == 1 and bottom_row_mode == "seek" then
            local x = (track == 1) and 51 or 92
            draw_recording_head(x, 63, rec_positions[track])
        end
    end
    if current_scene_mode == "on" then
        screen.move(45, 5) screen.text(current_scenes[1])
        screen.move(86, 5) screen.text(current_scenes[2])
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
    end}
local function osc_event(path, args) if osc_handlers[path] then osc_handlers[path](args) end end
local function setup_osc() osc.event = osc_event end

function init()
    initital_reverb_onoff = params:get('reverb')
    params:set('reverb', 1)
    initital_monitor_level = params:get('monitor_level')
    params:set('monitor_level', -math.huge)
    if not installer:ready() then clock.run(function() while true do redraw() clock.sleep(1 / 10) end end) do return end end
    setup_ui_metro()
    setup_params()
    setup_osc()
end

function cleanup()
    stop_metro_safe(ui_metro)
    stop_metro_safe(m_rand)
    for i = 1, 2 do stop_metro_safe(randomize_metro[i]) end
    randpara.cleanup()
    params:set('monitor_level', initital_monitor_level)
    params:set('reverb', initital_reverb_onoff)
    osc.event = nil
end