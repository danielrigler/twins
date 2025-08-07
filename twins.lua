--
--
--  __ __|         _)          
--     | \ \  \  / |  \ |  (_< 
--     |  \_/\_/ _| _| _| __/ 
--           by: @dddstudio                       
--
--                          
--                           v0.35
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
--
-- Thanks to:
-- @infinitedigits @cfdrake 
-- @justmat @artfwo @nzimas
-- @sonoCircuit @graymazes
-- @Higaru @NiklasKramer
--
-- If you like this,
-- buy them a beer :)
--
--                    Daniel Rigler

local randpara = include("lib/randpara")
local lfo = include("lib/lfo")
local Mirror = include("lib/mirror")
local macro = include("lib/macro") macro.set_lfo_reference(lfo)
local drymode = include("lib/drymode") drymode.set_lfo_reference(lfo)
installer_ = include("lib/scinstaller/scinstaller") installer = installer_:new{requirements = {"AnalogTape", "AnalogChew", "AnalogLoss", "AnalogDegrade"}, 
  zip = "https://github.com/schollz/portedplugins/releases/download/v0.4.6/PortedPlugins-RaspberryPi.zip"}
engine.name = installer:ready() and 'twins' or nil
local ui_metro
local randomize_metro = { [1] = nil, [2] = nil }
local key_state = {} for n = 1, 3 do key_state[n] = false end
local current_mode = "speed"
local current_filter_mode = "lpf"
local manual_adjustments = {}
local manual_adjustment_duration = 0.5
local manual_cleanup_metro = nil
local last_cleanup_time = 0
local CLEANUP_INTERVAL = 0.5
local animation_y = -64
local animation_speed = 150
local animation_complete = false
local animation_start_time = nil
local initital_monitor_level
local initital_reverb_onoff
local initital_compressor_onoff

local valid_audio_exts = {[".wav"]=true,[".aif"]=true,[".aiff"]=true,[".flac"]=true}
local mode_list = {"pitch","spread","density","size","jitter","lpf","pan","seek","speed"}
local mode_indices = {}; for i,v in ipairs(mode_list) do mode_indices[v]=i end
local mode_list2 = {"speed","seek","pan","lpf","jitter","size","density","spread","pitch"}
local mode_indices2 = {}; for i,v in ipairs(mode_list2) do mode_indices2[v]=i end

local param_modes = {
    speed = {param = "speed", delta = 0.5, wrap = nil, engine = false, has_lock = true},
    seek = {param = "seek", delta = 1, wrap = {0, 100}, engine = true, has_lock = true},
    pan = {param = "pan", delta = 5, wrap = nil, engine = false, has_lock = true, invert = true},
    lpf = {param = "cutoff", delta = 1, wrap = nil, engine = false, has_lock = false},
    hpf = {param = "hpf", delta = 1, wrap = nil, engine = false, has_lock = false},
    jitter = {param = "jitter", delta = 2, wrap = nil, engine = false, has_lock = true},
    size = {param = "size", delta = 2, wrap = nil, engine = false, has_lock = true},
    density = {param = "density", delta = 2, wrap = nil, engine = false, has_lock = true},
    spread = {param = "spread", delta = 2, wrap = nil, engine = false, has_lock = true},
    pitch = {param = "pitch", delta = 1, wrap = nil, engine = false, has_lock = true}}

local param_rows = {
    {y = 11, label = "jitter:    ", mode = "jitter", param1 = "1jitter", param2 = "2jitter"},
    {y = 21, label = "size:     ", mode = "size", param1 = "1size", param2 = "2size"},
    {y = 31, label = "density:  ", mode = "density", param1 = "1density", param2 = "2density", hz = true},
    {y = 41, label = "spread:   ", mode = "spread", param1 = "1spread", param2 = "2spread"},
    {y = 51, label = "pitch:    ", mode = "pitch", param1 = "1pitch", param2 = "2pitch", st = true}}

local function setup_manual_cleanup()
    manual_cleanup_metro = metro.init()
    manual_cleanup_metro.time = CLEANUP_INTERVAL
    manual_cleanup_metro.event = function()
        local current_time = util.time()
        if next(manual_adjustments) ~= nil and (current_time - last_cleanup_time) >= CLEANUP_INTERVAL then
            for param, adjustment in pairs(manual_adjustments) do
                if adjustment and adjustment.time and (current_time - adjustment.time > manual_adjustment_duration) then
                    adjustment.active = false
                end
            end
            last_cleanup_time = current_time
        end
    end
    manual_cleanup_metro:start()
end

local function is_audio_loaded(track_num)
    local file_path = params:get(track_num .. "sample")
    return (file_path and file_path ~= "" and file_path ~= "none" and file_path ~= "-")
end

local function random_float(l, h)
    return l + math.random() * (h - l)
end

local function setup_ui_metro()
    ui_metro = metro.init()
    ui_metro.time = 1/30
    ui_metro.event = function()
        if animation_complete then
            redraw()
            return
        end
        animation_start_time = animation_start_time or util.time()
        local elapsed = util.time() - animation_start_time
        animation_y = util.clamp(elapsed * animation_speed - 64, -64, 0)
        if animation_y >= 0 then
            animation_complete = true
            animation_y = 0
        end
        redraw()
    end
    ui_metro:start()
end

local function is_direct_live(track_num)
    return params:get(track_num.."live_direct") == 1
end

local function is_lfo_active_for_param(param_name)
    for i = 1, 16 do
        local target_index = params:get(i.. "lfo_target")
        if lfo.lfo_targets[target_index] == param_name and params:get(i.. "lfo") == 2 then
            return true, i
        end
    end
    return false, nil
end

local function disable_lfos_for_param(param_name)
    local base_param = param_name:sub(2)
    for track = 1, 2 do
        local full_param = track .. base_param
        local is_active, lfo_index = is_lfo_active_for_param(full_param)
        if is_active then
            params:set(lfo_index .. "lfo", 1)
        end
    end
end

local function stop_interpolations()
    for i = 1, 2 do
        if randomize_metro[i] then
            randomize_metro[i]:stop()
        end
    end
    active_controlled_params = {}
end

local last_random_sample = nil
local function scan_audio_files(dir)
    local files = {}
    for _, entry in ipairs(util.scandir(dir)) do
        local path = dir .. entry
        if entry:sub(-1) == "/" then
            local subdir_files = scan_audio_files(path)
            for _, f in ipairs(subdir_files) do
                table.insert(files, f)
            end
        else
            local ext = path:lower():match("^.+(%..+)$") or ""
            if valid_audio_exts[ext] then
                table.insert(files, path)
            end
        end
    end
    return files
end

local function load_random_tape_file(track_num)
    if params:get(track_num .. "live_input") == 1 then return false end
    local audio_files = scan_audio_files(_path.tape)
    if #audio_files == 0 then return false end
    if last_random_sample and math.random() < 0.5 and tab.contains(audio_files, last_random_sample) then
        if params:get(track_num .. "sample") ~= last_random_sample then
            params:set(track_num .. "sample", last_random_sample)
        end
        return true
    end
    local selected_file = audio_files[math.random(#audio_files)]
    while selected_file == last_random_sample and #audio_files > 1 do
        selected_file = audio_files[math.random(#audio_files)]
    end
    last_random_sample = selected_file
    if params:get(track_num .. "sample") ~= selected_file then
        params:set(track_num .. "sample", selected_file)
    end
    return true
end

local function setup_params()
    local all_params = {
        "jitter", "size", "density", "spread", "pitch", 
        "pan", "seek", "speed", "cutoff", "hpf"}
    for _, param in ipairs(all_params) do
        manual_adjustments["1"..param] = {active = false, value = 0}
        manual_adjustments["2"..param] = {active = false, value = 0}
    end

    params:add_separator("Input")
    for i = 1, 2 do
        params:add_file(i.. "sample", "Sample " ..i)
        params:set_action(i.. "sample", function(file)
            if file ~= nil and file ~= "" and file ~= "none" and file ~= "-" then
                engine.read(i, file)
                if is_audio_loaded(1) and is_audio_loaded(2) then
                    params:set("1pan", -15)
                    params:set("2pan", 15)
                end
            end
        end)
    end
    params:add_binary("randomtapes", "Random Tapes", "trigger", 0) params:set_action("randomtapes", function() load_random_tape_file(1) load_random_tape_file(2) end)

    params:add_group("Live!", 10)
    for i = 1, 2 do
        params:add_binary(i.."live_input", "Live Buffer "..i.." ● ►", "toggle", 0)
        params:set_action(i.."live_input", function(value)
            if value == 1 then
                if params:get(i.."live_direct") == 1 then
                    params:set(i.."live_direct", 0)
                end
                engine.set_live_input(i, 1)
                engine.live_mono(i, params:get("isMono") - 1)
            else
                engine.set_live_input(i, 0)
            end
        end)
    end

    params:add_control("live_buffer_mix", "Overdub", controlspec.new(0, 100, "lin", 1, 100, "%")) params:set_action("live_buffer_mix", function(value) engine.live_buffer_mix(value / 100) end)
    params:add_control("live_buffer_length", "Buffer Length", controlspec.new(0.1, 60, "lin", 0.1, 8, "s")) params:set_action("live_buffer_length", function(value) engine.live_buffer_length(value) end)
    params:add{type = "trigger", id = "save_live_buffer1", name = "Buffer1 to Tape", action = function() local timestamp = os.date("%Y%m%d_%H%M%S") local filename = "live1_"..timestamp..".wav" engine.save_live_buffer(1, filename) end}
    params:add{type = "trigger", id = "save_live_buffer2", name = "Buffer2 to Tape", action = function() local timestamp = os.date("%Y%m%d_%H%M%S") local filename = "live2_"..timestamp..".wav" engine.save_live_buffer(2, filename) end}

    for i = 1, 2 do
        params:add_binary(i.."live_direct", "Direct "..i.." ►", "toggle", 0)
        params:set_action(i.."live_direct", function(value)
            if value == 1 then
                local was_live = params:get(i.."live_input")
                _G["prev_live_state_"..i] = was_live
                if was_live == 1 then
                    params:set(i.."live_input", 0)
                end
                engine.live_direct(i, 1)
                engine.isMono(i, params:get("isMono") - 1)
            else
                engine.live_direct(i, 0)
                if _G["prev_live_state_"..i] == 1 then
                    params:set(i.."live_input", 1)
                    engine.isMono(i, params:get("isMono") - 1)
                else
                    local current_sample = params:get(i.."sample")
                    if current_sample ~= "none" and current_sample ~= "" then
                        engine.read(i, current_sample)
                    end
                end
            end
        end)
    end

    params:add_option("isMono", "Input Mode", {"stereo", "mono"}, 1) params:set_action("isMono", function(value) local monoValue = value - 1
        for i = 1, 2 do
            if params:get(i.."live_direct") == 1 then
                engine.isMono(i, monoValue)
            end
            if params:get(i.."live_input") == 1 then
                engine.live_mono(i, monoValue)
            end
        end
    end)
    params:add_binary("dry_mode2", "Dry Mode", "toggle", 0) params:set_action("dry_mode2", function(x) drymode.toggle_dry_mode2() end)

    params:add_separator("Settings")
    params:add_group("Granular", 35)
    for i = 1, 2 do
      params:add_separator("Sample "..i)
      params:add_control(i.. "granular_gain", i.. " Mix", controlspec.new(0, 100, "lin", 1, 100, "%")) params:set_action(i.. "granular_gain", function(value) engine.granular_gain(i, value / 100) if value < 100 then lfo.clearLFOs(i, "seek") end end)
      params:add_control(i.. "subharmonics_3", i.. " Subharmonics -3oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0)) params:set_action(i.. "subharmonics_3", function(value) engine.subharmonics_3(i, value) end)
      params:add_control(i.. "subharmonics_2", i.. " Subharmonics -2oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0)) params:set_action(i.. "subharmonics_2", function(value) engine.subharmonics_2(i, value) end)
      params:add_control(i.. "subharmonics_1", i.. " Subharmonics -1oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0)) params:set_action(i.. "subharmonics_1", function(value) engine.subharmonics_1(i, value) end)
      params:add_control(i.. "overtones_1", i.. " Overtones +1oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0)) params:set_action(i.. "overtones_1", function(value) engine.overtones_1(i, value) end)
      params:add_control(i.. "overtones_2", i.. " Overtones +2oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0)) params:set_action(i.. "overtones_2", function(value) engine.overtones_2(i, value) end)
      params:add_option(i.. "smoothbass", i.." Smooth Sub", {"off", "on"}, 1) params:set_action(i.. "smoothbass", function(x) local engine_value = (x == 2) and 2.5 or 1 engine.smoothbass(i, engine_value) end)
      params:add_control(i.. "pitch_random_plus", i.. " Octave Variation +", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.. "pitch_random_plus", function(value) engine.pitch_random_plus(i, value / 100) end)
      params:add_control(i.. "pitch_random_minus", i.. " Octave Variation -", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.. "pitch_random_minus", function(value) engine.pitch_random_minus(i, value / 100) end)
      params:add_control(i.. "size_variation", i.. " Size Variation", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.. "size_variation", function(value) engine.size_variation(i, value / 100) end)
      params:add_control(i.. "direction_mod", i.. " Reverse", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.. "direction_mod", function(value) engine.direction_mod(i, value / 100) end)
      params:add_control(i.. "density_mod_amt", i.. " Density Mod", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.. "density_mod_amt", function(value) engine.density_mod_amt(i, value / 100) end)      
      params:add_option(i.. "trig_mode", i.. " Trigger Mode", {"impulse", "dust"}, 1) params:set_action(i.."trig_mode", function(value) engine.trig_mode(i, value-1) end)
      params:add_control(i.."probability", i.." Trigger Probability", controlspec.new(0, 100, "lin", 1, 100, "%")) params:set_action(i.."probability", function(value) engine.probability(i, value / 100) end)
      params:add_option(i.. "pitch_mode", i.. " Pitch Mode", {"match speed", "independent"}, 2) params:set_action(i.. "pitch_mode", function(value) engine.pitch_mode(i, value - 1) end)
    end
    params:add_separator(" ")
    params:add_binary("randomize_granular", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_granular", function() randpara.randomize_granular_params(1) randpara.randomize_granular_params(2) end)
    params:add_option("lock_granular", "Lock Parameters", {"off", "on"}, 1)

    params:add_group("Delay", 11)
    params:add_taper("delay_mix", "Mix", 0, 100, 0, 1, "%") params:set_action("delay_mix", function(value) engine.mix(value/100) end)
    params:add_taper("delay_time", "Time", 0.02, 2, 0.5, 0.1, "s") params:set_action("delay_time", function(value) engine.delay(value) end)
    params:add_taper("delay_feedback", "Feedback", 0, 100, 30, 1, "%") params:set_action("delay_feedback", function(value) engine.time(value/5) end)
    params:add_control("delay_lowpass", "LPF", controlspec.new(20, 20000, 'exp', 1, 20000, "Hz")) params:set_action('delay_lowpass', function(value) engine.lpf(value) end)
    params:add_control("delay_highpass", "HPF", controlspec.new(20, 20000, 'exp', 1, 20, "Hz")) params:set_action("delay_highpass", function(value) engine.dhpf(value) end)
    params:add_taper("wiggle_rate", "Mod Freq", 0, 20, 2, 1, "Hz") params:set_action("wiggle_rate", function(value) engine.w_rate(value) end)
    params:add_taper("wiggle_depth", "Mod Depth", 0, 100, 0, 0, "%") params:set_action("wiggle_depth", function(value) engine.w_depth(value/100) end)
    params:add_taper("stereo", "Ping-Pong", 0, 100, 30, 1, "%") params:set_action("stereo", function(value) engine.stereo(value/100) end)
    params:add_separator("   ")
    params:add_binary("randomize_delay_params", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_delay_params", function() randpara.randomize_delay_params(steps) end)
    params:add_option("lock_delay", "Lock Parameters", {"off", "on"}, 1)

    params:add_group("Reverb", 15)
    params:add_taper("reverb_mix", "Mix", 0, 100, 0.0, 0, "%") params:set_action("reverb_mix", function(value) engine.reverb_mix(value / 100) end)
    params:add_taper("t60", "Decay", 0.1, 60, 3, 5, "s") params:set_action("t60", function(value) engine.t60(value) end)
    params:add_taper("damp", "Damping", 0, 100, 0, 0, "%") params:set_action("damp", function(value) engine.damp(value/100) end)
    params:add_taper("rsize", "Size", 0.5, 5, 1, 0, "") params:set_action("rsize", function(value) engine.rsize(value) end)
    params:add_taper("earlyDiff", "Early Diffusion", 0, 100, 70.7, 0, "%") params:set_action("earlyDiff", function(value) engine.earlyDiff(value/100) end)
    params:add_taper("modDepth", "Mod Depth", 0, 100, 10, 0, "%") params:set_action("modDepth", function(value) engine.modDepth(value/100) end)
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
    params:add_control("shimmer_mix", "Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("shimmer_mix", function(x) engine.shimmer_mix(x/100) end)
    params:add_option("o2", "2nd Octave", {"off", "on"}, 1) params:set_action("o2", function(x) engine.o2(x-1) end)
    params:add_control("pitchv", "Variance", controlspec.new(0, 100, "lin", 1, 2, "%")) params:set_action("pitchv", function(x) engine.pitchv(x/100) end)
    params:add_control("lowpass", "LPF", controlspec.new(20, 20000, "lin", 1, 13000, "Hz")) params:set_action("lowpass", function(x) engine.lowpass(x) end)
    params:add_control("hipass", "HPF", controlspec.new(20, 20000, "exp", 1, 1400, "Hz")) params:set_action("hipass", function(x) engine.hipass(x) end)
    params:add_control("fbDelay", "Delay", controlspec.new(0.01, 0.5, "lin", 0.01, 0.2, "s")) params:set_action("fbDelay", function(x) engine.fbDelay(x) end)
    params:add_control("fb", "Feedback", controlspec.new(0, 100, "lin", 1, 15, "%")) params:set_action("fb", function(x) engine.fb(x/100) end)
    params:add_separator("        ")
    params:add_option("lock_shimmer", "Lock Parameters", {"off", "on"}, 1)
    
    params:add_group("Tape", 16)
    params:add_option("tape_mix", "Analog Tape", {"off", "on"}, 1) params:set_action("tape_mix", function(x) engine.tape_mix(x-1) end)
    params:add_control("sine_drive", "Shaper Drive", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("sine_drive", function(value) engine.sine_drive((10+value)/20) end)
    params:add_control("drive", "Saturation", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("drive", function(x) engine.drive(x/100) end)
    params:add{type = "control", id = "wobble_mix", name = "Wobble", controlspec = controlspec.new(0, 100, "lin", 1, 0, "%"), action = function(value) engine.wobble_mix(value/100) end}
    params:add{type = "control", id = "wobble_amp", name = "Wow Depth", controlspec = controlspec.new(0, 100, "lin", 1, 20, "%"), action = function(value) engine.wobble_amp(value/100) end}
    params:add{type = "control", id = "wobble_rpm", name = "Wow Speed", controlspec = controlspec.new(30, 90, "lin", 1, 33, "RPM"), action = function(value) engine.wobble_rpm(value) end}
    params:add{type = "control", id = "flutter_amp", name = "Flutter Depth", controlspec = controlspec.new(0, 100, "lin", 1, 35, "%"), action = function(value) engine.flutter_amp(value/100) end}
    params:add{type = "control", id = "flutter_freq", name = "Flutter Speed", controlspec = controlspec.new(3, 30, "lin", 0.01, 6, "Hz"), action = function(value) engine.flutter_freq(value) end}
    params:add{type = "control", id = "flutter_var", name = "Flutter Var.", controlspec = controlspec.new(0.1, 10, "lin", 0.01, 2, "Hz"), action = function(value) engine.flutter_var(value) end}
    params:add{type = "control", id = "chew_depth", name = "Chew Depth", controlspec = controlspec.new(0, 50, "lin", 1, 0, "%"), action = function(value) engine.chew_depth(value/100) end}
    params:add{type = "control", id = "chew_freq", name = "Chew Freq.", controlspec = controlspec.new(0, 60, "lin", 1, 50, "%"), action = function(value) engine.chew_freq(value/100) end}
    params:add{type = "control", id = "chew_variance", name = "Chew Var.", controlspec = controlspec.new(0, 60, "lin", 1, 50, "%"), action = function(value) engine.chew_variance(value/100) end}
    params:add_control("lossdegrade_mix", "Loss / Degrade", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("lossdegrade_mix", function(value) engine.lossdegrade_mix(value / 100) end)
    params:add_separator("    ")
    params:add_binary("randomize_tape", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_tape", function() randpara.randomize_tape_params(steps) end)
    params:add_option("lock_tape", "Lock Parameters", {"off", "on"}, 1)    
    
    params:add_group("EQ", 6)
    for i = 1, 2 do 
    params:add_control(i.."eq_low_gain", i.." Bass", controlspec.new(-1, 1, "lin", 0.01, 0, "")) params:set_action(i.."eq_low_gain", function(value) engine.eq_low_gain(i, value*55) end)
    params:add_control(i.."eq_high_gain", i.." Treble", controlspec.new(-1, 1, "lin", 0.01, 0, "")) params:set_action(i.."eq_high_gain", function(value) engine.eq_high_gain(i, value*45) end)
    end
    params:add_separator("     ")
    params:add_option("lock_eq", "Lock Parameters", {"off", "on"}, 1)
    
    params:add_group("Filters", 6)
    for i = 1, 2 do
      params:add_control(i.."cutoff",i.." LPF Cutoff",controlspec.new(20,20000,"exp",0,20000,"Hz")) params:set_action(i.."cutoff",function(value) engine.cutoff(i,value) end)
      params:add_taper(i.."lpfgain", i.." LPF Resonance", 0, 4, 0.1, 3, "") params:set_action(i.."lpfgain", function(value) engine.lpfgain(i, value) end)
      params:add_control(i.."hpf",i.." HPF Cutoff",controlspec.new(20,20000,"exp",0,20,"Hz")) params:set_action(i.."hpf",function(value) engine.hpf(i,value) end)
    end
    
    params:add_group("Stereo", 2)
    params:add_control("Width", "Stereo Width", controlspec.new(0, 200, "lin", 0.01, 100, "%")) params:set_action("Width", function(value) engine.width(value / 100) end)
    params:add_option("monobass_mix", "Mono Bass", {"off", "on"}, 1) params:set_action("monobass_mix", function(x) engine.monobass_mix(x-1) end)

    params:add_group("BitCrush", 3)
    params:add_taper("bitcrush_mix", "Mix", 0, 100, 0.0, 0, "%") params:set_action("bitcrush_mix", function(value) engine.bitcrush_mix(value / 100) end)
    params:add_taper("bitcrush_rate", "Rate", 0, 44100, 4500, 100, "Hz") params:set_action("bitcrush_rate", function(value) engine.bitcrush_rate(value) end)
    params:add_taper("bitcrush_bits", "Bits", 1, 24, 10, 1) params:set_action("bitcrush_bits", function(value) engine.bitcrush_bits(value) end)

    params:add_group("LFOs", 118)
    params:add_binary("randomize_lfos", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_lfos", function() lfo.clearLFOs() if randomize_metro[1] then randomize_metro[1]:stop() end if randomize_metro[2] then randomize_metro[2]:stop() end lfo.randomize_lfos("1", params:get("allow_volume_lfos") == 2)  lfo.randomize_lfos("2", params:get("allow_volume_lfos") == 2) end)
    params:add_control("global_lfo_freq_scale", "Freq Scale", controlspec.new(0.1, 10, "exp", 0.01, 1.0, "x"))
    params:set_action("global_lfo_freq_scale", function(value)
      local phase_ref = {} for i = 1, 16 do phase_ref[i] = lfo[i].phase end
      for i = 1, 16 do
          local base_freq = params:get(i.."lfo_freq") or 0.05
          lfo[i].base_freq = base_freq
          lfo[i].freq = base_freq * value
          lfo[i].phase = phase_ref[i]
      end end)
    params:add_binary("lfo.assign_to_current_row", "Assign to Selection", "trigger", 0) params:set_action("lfo.assign_to_current_row", function() lfo.assign_to_current_row(current_mode, current_filter_mode) end)
    params:add_binary("lfo_pause", "Pause ⏸︎", "toggle", 0) params:set_action("lfo_pause", function(value) lfo.set_pause(value == 1) end)
    params:add_binary("ClearLFOs", "Clear All", "trigger", 0) params:set_action("ClearLFOs", function() lfo.clearLFOs() end)
    params:add_option("allow_volume_lfos", "Allow Volume LFOs", {"no", "yes"}, 2)
    lfo.init()

    params:add_group("Limits", 14)
    params:add_taper("min_jitter", "jitter (min)", 0, 4999, 100, 5, "ms")
    params:add_taper("max_jitter", "jitter (max)", 0, 4999, 999, 5, "ms")
    params:add_taper("min_size", "size (min)", 1, 999, 100, 5, "ms")
    params:add_taper("max_size", "size (max)", 1, 999, 500, 5, "ms")
    params:add_taper("min_density", "density (min)", 0.1, 50, 1, 5, "Hz")
    params:add_taper("max_density", "density (max)", 0.1, 50, 16, 5, "Hz")
    params:add_taper("min_spread", "spread (min)", 0, 100, 0, 0, "%")
    params:add_taper("max_spread", "spread (max)", 0, 100, 65, 0, "%")
    params:add_control("min_pitch", "pitch (min)", controlspec.new(-48, 48, "lin", 1, -31, "st"))
    params:add_control("max_pitch", "pitch (max)", controlspec.new(-48, 48, "lin", 1, 31, "st"))
    params:add_taper("min_speed", "speed (min)", -2, 2, 0, 0, "x")
    params:add_taper("max_speed", "speed (max)", -2, 2, 0.2, 0, "x")
    params:add_taper("min_seek", "seek (min)", 0, 100, 0, 0, "%")
    params:add_taper("max_seek", "seek (max)", 0, 100, 100, 0, "%")

    params:add_group("Locking", 16)
    for i = 1, 2 do
      params:add_option(i.. "lock_jitter", i.. " lock jitter", {"off", "on"}, 1)
      params:add_option(i.. "lock_size", i.. " lock size", {"off", "on"}, 1)
      params:add_option(i.. "lock_density", i.. " lock density", {"off", "on"}, 1)
      params:add_option(i.. "lock_spread", i.. " lock spread", {"off", "on"}, 1)
      params:add_option(i.. "lock_pitch", i.. " lock pitch", {"off", "on"}, 1)
      params:add_option(i.. "lock_speed", i.. " lock speed", {"off", "on"}, 1)
      params:add_option(i.. "lock_seek", i.. " lock seek", {"off", "on"}, 1)
      params:add_option(i.. "lock_pan", i.. " lock pan", {"off", "on"}, 1)
    end

    params:add_group("Symmetry", 3)
    params:add_binary("copy_1_to_2", "Copy 1 → 2", "trigger", 0) params:set_action("copy_1_to_2", function() Mirror.copy_voice_params("1", "2", true) Mirror.copy_voice_params("2", "1", true) end)
    params:add_binary("copy_2_to_1", "Copy 1 ← 2", "trigger", 0) params:set_action("copy_2_to_1", function() Mirror.copy_voice_params("2", "1", true) Mirror.copy_voice_params("1", "2", true) end)
    params:add_binary("symmetry", "Symmetry", "toggle", 0)
    
    params:add_group("Actions", 2)
    params:add_binary("macro_more", "More+", "trigger", 0) params:set_action("macro_more", function() macro.macro_more() end)
    params:add_binary("macro_less", "Less-", "trigger", 0) params:set_action("macro_less", function() macro.macro_less() end)
    
    params:add_group("Other", 3)
    params:add_binary("dry_mode", "Dry Mode", "toggle", 0) params:set_action("dry_mode", function(x) drymode.toggle_dry_mode() end)
    params:add_binary("unload_all", "Unload All Audio", "trigger", 0) params:set_action("unload_all", function() engine.unload_all() params:set("1sample", "-") params:set("2sample", "-") params:set("1live_input", 0) params:set("2live_input", 0) params:set("1live_direct", 0) params:set("2live_direct", 0) end)
    params:add_option("steps", "Transition Time", {"short", "medium", "long"}, 2) params:set_action("steps", function(value) lfo.cleanup() steps = ({20, 400, 800})[value] end)

    for i = 1, 2 do
      params:add_taper(i.. "volume", i.. " volume", -70, 20, -5, 0, "dB") params:set_action(i.. "volume", function(value) if value == -70 then engine.volume(i, 0) else engine.volume(i, math.pow(10, value / 20)) end end) params:hide(i.. "volume")
      params:add_taper(i.. "pan", i.. " pan", -100, 100, 0, 0, "%") params:set_action(i.. "pan", function(value) engine.pan(i, value / 100)  end) params:hide(i.. "pan")
      params:add_taper(i.. "speed", i.. " speed", -2, 2, 0.10, 0) params:set_action(i.. "speed", function(value) if math.abs(value) < 0.01 then engine.speed(i, 0) else engine.speed(i, value) end end) params:hide(i.. "speed")
      params:add_taper(i.. "density", i.. " density", 0.1, 300, 10, 5) params:set_action(i.. "density", function(value) engine.density(i, value) end) params:hide(i.. "density")
      params:add_control(i.. "pitch", i.. " pitch", controlspec.new(-48, 48, "lin", 1, 0, "st")) params:set_action(i.. "pitch", function(value) engine.pitch_offset(i, math.pow(0.5, -value / 12)) end) params:hide(i.. "pitch")
      params:add_taper(i.. "jitter", i.. " jitter", 0, 4999, 250, 3, "ms") params:set_action(i.. "jitter", function(value) engine.jitter(i, value / 1000) end) params:hide(i.. "jitter")
      params:add_taper(i.. "size", i.. " size", 1, 5999, 100, 1, "ms") params:set_action(i.. "size", function(value) engine.size(i, value / 1000) end) params:hide(i.. "size")
      params:add_taper(i.. "spread", i.. " spread", 0, 100, 0, 0, "%") params:set_action(i.. "spread", function(value) engine.spread(i, value / 100) end) params:hide(i.. "spread")
      params:add_control(i.. "seek", i.. " seek", controlspec.new(0, 100, "lin", 0.01, 0, "%")) params:set_action(i.. "seek", function(value) engine.seek(i, value) end) params:hide(i.. "seek")
    end
    params:bang()
end

local function interpolate(start_val, end_val, factor)
    return start_val + (end_val - start_val) * factor
end

local function randomize_pitch(track, other_track, symmetry)
    local current_pitch = params:get(track .. "pitch")
    local min_pitch = math.max(params:get("min_pitch"), current_pitch - 48)
    local max_pitch = math.min(params:get("max_pitch"), current_pitch + 48)
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
    if not randomize_metro[n] then 
        randomize_metro[n] = metro.init() 
    end
    active_controlled_params = {}
    local param_config = {
      speed = {min = "min_speed", max = "max_speed", lock = params:get(n.."lock_speed")==1, param_name = n.."speed"},
      jitter = {min = "min_jitter", max = "max_jitter", lock = params:get(n.."lock_jitter")==1, param_name = n.."jitter"},
      size = {min = "min_size", max = "max_size", lock = params:get(n.."lock_size")==1, param_name = n.."size"},
      density = {min = "min_density", max = "max_density", lock = params:get(n.."lock_density")==1, param_name = n.."density"},
      spread = {min = "min_spread", max = "max_spread", lock = params:get(n.."lock_spread")==1, param_name = n.."spread"},
      pitch = {lock = params:get(n.."lock_pitch")==1, param_name = n.."pitch"}}
    local targets = {}
    local symmetry = params:get("symmetry") == 1
    local other_track = n == 1 and 2 or 1
    if param_config.pitch.lock and not active_controlled_params[param_config.pitch.param_name] then
       randomize_pitch(n, other_track, symmetry)
    end
    for param, config in pairs(param_config) do
        if param ~= "pitch" then
            if config.lock and not active_controlled_params[config.param_name] then
                local min_val = config.min and params:get(config.min) or config.min
                local max_val = config.max and params:get(config.max) or config.max
                if min_val < max_val and not is_lfo_active_for_param(config.param_name) then
                    local target_value = random_float(min_val, max_val)
                    targets[config.param_name] = target_value
                    if symmetry then
                        if param == "pan" then
                            targets[other_track.."pan"] = -target_value
                        else
                            targets[other_track..param] = target_value
                        end
                    end
                end
            end
        end
    end
    randomize_metro[n].time = 1/30
    randomize_metro[n].event = function(count)
        local tolerance = 0.01
        local factor = count / steps
        local all_done = true
        for param, target in pairs(targets) do
            if not active_controlled_params[param] then
                local current_value = params:get(param)
                local new_value = interpolate(current_value, target, factor)
                params:set(param, new_value)
                all_done = all_done and (math.abs(new_value - target) < tolerance)
            end
        end
        if all_done then 
            randomize_metro[n]:stop() 
        end
    end
    randomize_metro[n]:start()
end

local function setup_engine()
    randomize(1)
    randomize(2)
end

function init()
    if not installer:ready() then
        clock.run(function() while true do redraw() clock.sleep(1 / 10) end end)
        do return end
    end
    initital_monitor_level = params:get('monitor_level')
    params:set('monitor_level', -math.huge)
    initital_reverb_onoff = params:get('reverb')
    params:set('reverb', 1)
    initital_compressor_onoff = params:get('compressor')
    params:set('compressor', 1)
    setup_ui_metro()
    setup_params()
    setup_engine()
    setup_manual_cleanup()
end

function enc(n, d)
    if not installer:ready() then return end
    local function handle_param_adjustment(track, config, delta_multiplier)
        stop_interpolations()
        local param_name = track .. config.param
        manual_adjustments[param_name] = {
            active = true,
            value = params:get(param_name),
            time = util.time()}
        if params:get("symmetry") == 1 then
            disable_lfos_for_param(param_name)
            local other_track = 3 - track
            local other_param_name = other_track .. config.param
            local delta = config.invert and -d or d
            if config.wrap then
            local current_val = params:get(other_param_name)
            local range = config.wrap[2] - config.wrap[1] + 1
            local new_val = (current_val + delta - config.wrap[1]) % range + config.wrap[1]
            params:set(other_param_name, new_val)
            if config.engine then engine.seek(other_track, new_val / 100) end
        else
            params:delta(other_param_name, config.delta * (config.invert and -delta_multiplier or delta_multiplier) * d)
        end
        else
            local is_active, lfo_index = is_lfo_active_for_param(param_name)
            if is_active then params:set(lfo_index .. "lfo", 1) end
        end
        if config.wrap then
            local current_val = params:get(param_name)
            local range = config.wrap[2] - config.wrap[1] + 1
            local new_val = (current_val + d - config.wrap[1]) % range + config.wrap[1]
            params:set(param_name, new_val)
            if config.engine then engine.seek(track, new_val / 100) end
        else
            params:delta(param_name, config.delta * delta_multiplier * d)
        end
    end
    if n == 1 then
        local is_active1, lfo_index1 = is_lfo_active_for_param("1volume")
        local is_active2, lfo_index2 = is_lfo_active_for_param("2volume")
        local lfo_delta = 0.75 * d
        local key1 = key_state[1]
        if is_active1 or is_active2 then
            if is_active1 and is_active2 then
                local delta = key1 and lfo_delta or lfo_delta
                params:delta(lfo_index1 .. "offset", delta)
                params:delta(lfo_index2 .. "offset", key1 and -delta or delta)
            elseif is_active1 then
                params:delta(lfo_index1 .. "offset", lfo_delta)
                params:delta("2volume", key1 and -3 * d or 3 * d)
            else
                params:delta(lfo_index2 .. "offset", key1 and -lfo_delta or lfo_delta)
                params:delta("1volume", key1 and 3 * d or 3 * d)
            end
        else
            params:delta("1volume", 3 * d)
            params:delta("2volume", key1 and -3 * d or 3 * d)
        end
    elseif n == 2 then
        if key_state[1] then
            if params:get("symmetry") == 1 then
                disable_lfos_for_param("1volume")
            else
                local is_active, lfo_index = is_lfo_active_for_param("1volume")
                if is_active then params:set(lfo_index .. "lfo", 1) end
            end
            params:delta("1volume", 3 * d)
        else
            local mode = current_mode
            if mode == "lpf" or mode == "hpf" then mode = current_filter_mode end
            handle_param_adjustment(1, param_modes[mode], 1)
        end
    elseif n == 3 then
        if key_state[1] then
            if params:get("symmetry") == 1 then
                disable_lfos_for_param("2volume")
            else
                local is_active, lfo_index = is_lfo_active_for_param("2volume")
                if is_active then params:set(lfo_index .. "lfo", 1) end
            end
            params:delta("2volume", 3 * d)
        else
            local mode = current_mode
            if mode == "lpf" or mode == "hpf" then mode = current_filter_mode end
            handle_param_adjustment(2, param_modes[mode], 1)
        end
    end
end

function key(n, z)
    if not installer:ready() then installer:key(n, z) return end
    key_state[n] = z == 1 and true or false
    if z == 1 then
        if key_state[1] then
            if n == 2 then
                lfo.clearLFOs(1)
                lfo.randomize_lfos("1", params:get("allow_volume_lfos") == 2)
                randomize(1)
                randpara.randomize_params(steps, 1)
                return
            elseif n == 3 then
                lfo.clearLFOs(2)
                lfo.randomize_lfos("2", params:get("allow_volume_lfos") == 2)
                randomize(2)
                randpara.randomize_params(steps, 2)
                return
            end
        end
        if not key_state[1] then
            if n == 2 then
                local idx = mode_indices[current_mode] or 1
                current_mode = mode_list[(idx % #mode_list) + 1]
            elseif n == 3 then
                local idx = mode_indices2[current_mode] or 1
                current_mode = mode_list2[(idx % #mode_list2) + 1]
            end
        end
    end
    if key_state[2] and key_state[3] then
        if current_mode == "lpf" or current_mode == "hpf" then
            current_filter_mode = current_filter_mode == "lpf" and "hpf" or "lpf"
        else
            local lockable_params = {"jitter", "size", "density", "spread", "pitch", "pan", "seek", "speed"}
            local param_name = string.match(current_mode, "%a+")
            if param_name and table.find(lockable_params, param_name) then
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
    end
end

local function format_density(value)
    return string.format("%.1f Hz", value)
end

local function format_pitch(value)
    if value > 0 then
        return string.format("+%.0f", value)
    else
        return string.format("%.0f", value)
    end
end

local function format_seek(value)
    return string.format("%.0f%%", value)
end

local function format_speed(speed)
    if math.abs(speed) < 0.01 then
        return ".00x"
    elseif math.abs(speed) < 1 then
        if speed < -0.01 then 
            return string.format("-.%02dx", math.floor(math.abs(speed) * 100))
        else 
            return string.format(".%02dx", math.floor(math.abs(speed) * 100))
        end
    else 
        return string.format("%.2fx", speed)
    end
end

local function is_param_locked(track_num, param)
    return params:get(track_num .. "lock_" .. param) == 2
end

local function draw_l_shape(x, y, is_locked)
    if is_locked then
        local pulse_level = math.floor(util.linlin(-1, 1, 1, 8, math.sin(util.time() * 4)))
        screen.level(pulse_level)
        screen.move(x - 4, y) screen.line_rel(2, 0)
        screen.move(x - 3, y) screen.line_rel(0, -3)
        screen.stroke()
    end
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

local function draw_progress_bar(x, y, width, value, min, max, is_log)
    value = math.min(math.max(value, min), max)
    local value_pos
    if is_log then
        value_pos = util.linlin(math.log(min), math.log(max), x, x + width, math.log(value))
    else
        value_pos = util.linlin(min, max, x, x + width, value)
    end
    screen.level(6)
    screen.rect(x, y, value_pos - x, 1)
end

function redraw()
    if not installer:ready() then installer:redraw() do return end end
    screen.clear()
    screen.save()
    screen.translate(0, animation_y)
    local highlight_level = 15
    local normal_level = 15
    local dim_level = 6
    local value_level = 1

    local cached_params = {}
    for _, row in ipairs(param_rows) do
        cached_params[row.param1] = params:get(row.param1)
        cached_params[row.param2] = params:get(row.param2)
    end
    cached_params["1volume"] = params:get("1volume")
    cached_params["2volume"] = params:get("2volume")
    cached_params["1pan"] = params:get("1pan")
    cached_params["2pan"] = params:get("2pan")
    cached_params["1seek"] = params:get("1seek")
    cached_params["2seek"] = params:get("2seek")
    cached_params["1speed"] = params:get("1speed")
    cached_params["2speed"] = params:get("2speed")
    cached_params["1cutoff"] = params:get("1cutoff")
    cached_params["2cutoff"] = params:get("2cutoff")
    cached_params["1hpf"] = params:get("1hpf")
    cached_params["2hpf"] = params:get("2hpf")

    for _, row in ipairs(param_rows) do
        local param_name = string.match(row.label, "%a+")
        local is_highlighted_row = current_mode == row.mode
        screen.level(normal_level)
        screen.move(5, row.y)
        screen.text(row.label)
        for i, param in ipairs({row.param1, row.param2}) do
            local x = i == 1 and 51 or 92
            local track = i == 1 and 1 or 2
            local is_locked = is_param_locked(track, param_name)
            if is_locked then
                draw_l_shape(x, row.y, true)
            end
            screen.move(x, row.y)
            screen.level(is_highlighted_row and highlight_level or value_level)
            if row.hz then
                screen.text(format_density(cached_params[param]))
            elseif row.st then
                screen.text(format_pitch(cached_params[param]))
            elseif param_name == "spread" then
                screen.text(string.format("%.0f%%", cached_params[param]))
            else
                screen.text(params:string(param))
            end
            if not row.st and param_name ~= "seek" then
                local min_val, max_val = lfo.get_parameter_range(param)
                screen.level(dim_level)
                if manual_adjustments[param] and manual_adjustments[param].active then
                    local bar_value = util.linlin(min_val, max_val, 0, 30, manual_adjustments[param].value)
                    screen.rect(x, row.y + 1, bar_value, 1)
                else
                    local lfo_mod = get_lfo_modulation(param)
                    if lfo_mod then
                        local bar_value = util.linlin(min_val, max_val, 0, 30, lfo_mod)
                        screen.rect(x, row.y + 1, bar_value, 1)
                    end
                end
                screen.fill()
            end
        end
    end

    local bottom_label = (current_mode == "lpf" or current_mode == "hpf") and (current_filter_mode == "lpf" and "lpf:      " or "hpf:      ") 
                       or (current_mode == "seek" and "seek:     ") 
                       or (current_mode == "pan" and "pan:      ") 
                       or "speed:    "
    local is_bottom_row_active = current_mode == "speed" or current_mode == "seek" or current_mode == "pan" or current_mode == "lpf" or current_mode == "hpf"
    local show_direct = not (current_mode == "pan" or current_mode == "lpf" or current_mode == "hpf")
    screen.move(5, 61)
    screen.level(normal_level)
    screen.text(bottom_label)
    for i, track in ipairs({1, 2}) do
        local x = i == 1 and 51 or 92
        local text_level = is_bottom_row_active and highlight_level or value_level
        if is_direct_live(track) and show_direct then
            screen.move(x, 61)
            screen.level(text_level)
            screen.text("direct")
        else
            if current_mode == "seek" then
                local value = params:get(track.."seek")
                screen.level(dim_level)
                screen.rect(x, 63, util.linlin(0, 100, 0, 30, value), 1)
                screen.fill()
                screen.move(x, 61)
                screen.level(text_level)
                screen.text(format_seek(value))
            elseif current_mode == "pan" then
                local pan = params:get(track.."pan")
                screen.move(x, 61)
                screen.level(text_level)
                screen.text(math.abs(pan) < 0.5 and "0%" or string.format("%.0f%%", pan))
            elseif current_mode == "lpf" or current_mode == "hpf" then
                local param = current_filter_mode == "lpf" and track.."cutoff" or track.."hpf"
                draw_progress_bar(x, 63, 30, params:get(param), 20, 20000, true)
                screen.move(x, 61)
                screen.level(text_level)
                screen.text(string.format("%.0f", params:get(param)))
            else
                screen.move(x, 61)
                screen.level(text_level)
                screen.text(format_speed(params:get(track.."speed")))
            end
        end
    end
    if (current_mode ~= "lpf" and current_mode ~= "hpf") then
        local param_type = (current_mode == "pan" or current_mode == "seek") and current_mode or "speed"
        for i, track in ipairs({1, 2}) do
            if not is_direct_live(track) then
                local x = i == 1 and 51 or 92
                if is_param_locked(track, param_type) then
                    draw_l_shape(x, 61, true)
                end
            end
        end
    end
    screen.level(dim_level)
    for i, track in ipairs({1, 2}) do
        local x = i == 1 and 0 or 127
        local volume = params:get(track.."volume")
        local height = util.linlin(-60, 20, 0, 64, volume)
        screen.rect(x, 64 - height, 1, height)
    end
    for i, track in ipairs({1, 2}) do
        local center_start = i == 1 and 52 or 93
        local center_end = center_start + 25
        local pan = params:get(track.."pan")
        local pos = util.linlin(-100, 100, center_start, center_end, pan)
        screen.rect(pos - 1, 0, 4, 1)
    end
    screen.fill()
    screen.level(normal_level)
    if params:get("dry_mode") == 1 then screen.pixel(6, 0) screen.pixel(10, 0) screen.pixel(14, 0) end 
    if params:get("symmetry") == 1 then screen.pixel(6, 0) screen.pixel(8, 0) screen.pixel(10, 0) end
    screen.fill()
    screen.restore()
    screen.update()
end

function cleanup()
  if ui_metro then ui_metro:stop() ui_metro = nil end
  if manual_cleanup_metro then manual_cleanup_metro:stop() manual_cleanup_metro = nil end
  for i = 1, 2 do
    if randomize_metro[i] then randomize_metro[i]:stop() randomize_metro[i] = nil end
  end
  lfo.cleanup()
  params:set('monitor_level', initital_monitor_level)
  params:set('reverb', initital_reverb_onoff)
  params:set('compressor', initital_compressor_onoff)
end