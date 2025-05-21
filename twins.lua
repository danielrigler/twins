--
--
--  __ __|         _)          
--     | \ \  \  / |  \ |  (_< 
--     |  \_/\_/ _| _| _| __/ 
--           by: @dddstudio                       
--
--                          
--                           v0.30
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
-- @Higaru
--
-- If you like this,
-- buy them a beer :)
--
--                    Daniel Rigler

delay = include("lib/delay")
local randpara = include("lib/randpara")
local lfo = include("lib/lfo")
local Mirror = include("lib/mirror")
local macro = include("lib/macro")
macro.set_lfo_reference(lfo)
local drymode = include("lib/drymode")
drymode.set_lfo_reference(lfo)
installer_ = include("lib/scinstaller/scinstaller")
installer = installer_:new{requirements = {"AnalogTape", "AnalogChew", "AnalogLoss", "AnalogDegrade"}, 
  zip = "https://github.com/schollz/portedplugins/releases/download/v0.4.6/PortedPlugins-RaspberryPi.zip"}
engine.name = installer:ready() and 'twins' or nil
local ui_metro
local randomize_metro = { [1] = nil, [2] = nil }
local key1_pressed, key2_pressed, key3_pressed = false
local current_mode = "speed"
local current_filter_mode = "lpf"
local manual_adjustments = {}
local manual_adjustment_duration = 0.5
local animation_y = -64
local animation_speed = 200
local animation_complete = false
local animation_start_time = nil

local function is_audio_loaded(track_num)
    local file_path = params:get(track_num .. "sample")
    return file_path and file_path ~= "" and file_path ~= "none" and file_path ~= "-"
end

local function random_float(l, h)
    return l + math.random() * (h - l)
end

local function setup_ui_metro()
    ui_metro = metro.init()
    ui_metro.time = 1/30
    ui_metro.event = function()
        if not animation_complete then
            local current_time = util.time()
            if not animation_start_time then
                animation_start_time = current_time
            end
            local elapsed = current_time - animation_start_time
            animation_y = util.clamp(elapsed * animation_speed - 64, -64, 0)
            if animation_y >= 0 then
                animation_complete = true
                animation_y = 0
            end
        end
        redraw()
    end
    ui_metro:start()
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

local function stop_interpolations()
    for i = 1, 2 do
        if randomize_metro[i] then 
            randomize_metro[i]:stop() 
            active_controlled_params = {} -- Clear any active controlled params
        end
    end
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
            if ext == ".wav" or ext == ".aif" or ext == ".aiff" or ext == ".flac" then
                table.insert(files, path)
            end
        end
    end
    return files
end

local function load_random_tape_file(track_num)
    local audio_files = scan_audio_files(_path.tape)
    if #audio_files == 0 then return false end
    if last_random_sample and math.random() < 0.5 and tab.contains(audio_files, last_random_sample) then
        params:set(track_num .. "sample", last_random_sample)
        return true
    end
    local selected_file = audio_files[math.random(#audio_files)]
    while selected_file == last_random_sample and #audio_files > 1 do
        selected_file = audio_files[math.random(#audio_files)]
    end
    last_random_sample = selected_file
    params:set(track_num .. "sample", selected_file)
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
    params:add_separator("Samples")
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
    params:add_binary("randomize_params", "Random Tapes", "trigger", 0) 
    params:set_action("randomize_params", function() load_random_tape_file(1) load_random_tape_file(2) end)
    
    params:add_separator("Settings")
    params:add_group("Granular", 31)
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
      params:add_control(i.. "density_mod_amt", i.. " Density Mod", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.. "density_mod_amt", function(value) engine.density_mod_amt(i, value / 100) end)
      params:add_control(i.. "direction_mod", i.. " Reverse", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.. "direction_mod", function(value) engine.direction_mod(i, value / 100) end)
      params:add_option(i.. "pitch_mode", i.. " Pitch Mode", {"match speed", "independent"}, 2) params:set_action(i.. "pitch_mode", function(value) engine.pitch_mode(i, value - 1) end)
    end
    params:add_separator(" ")
    params:add_binary("randomize_granular", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_granular", function() randpara.randomize_granular_params(1) randpara.randomize_granular_params(2) end)
    params:add_option("lock_granular", "Lock Parameters", {"off", "on"}, 1)

    params:add_group("Delay", 6)
    delay.init()

    params:add_group("Reverb", 15)
    params:add_taper("reverb_mix", "Mix", 0, 100, 0.0, 0, "%") params:set_action("reverb_mix", function(value) engine.reverb_mix(value / 100) end)
    params:add_taper("t60", "Decay", 0.1, 60, 3, 5, "s") params:set_action("t60", function(value) engine.t60(value) end)
    params:add_taper("damp", "Damping", 0, 100, 0, 0, "%") params:set_action("damp", function(value) engine.damp(value/100) end)
    params:add_taper("rsize", "Size", 0.5, 5, 1, 0, "") params:set_action("rsize", function(value) engine.rsize(value) end)
    params:add_taper("earlyDiff", "Early Diffusion", 0, 100, 70.7, 0, "%") params:set_action("earlyDiff", function(value) engine.earlyDiff(value/100) end)
    params:add_taper("modDepth", "Mod Depth", 0, 100, 10, 0, "%") params:set_action("modDepth", function(value) engine.modDepth(value/100) end)
    params:add_taper("modFreq", "Mod Frequency", 0, 10, 2, 0, "Hz") params:set_action("modFreq", function(value) engine.modFreq(value) end)
    params:add_control("low", "Low Decay", controlspec.new(0, 1, "lin", 0.01, 1, "x")) params:set_action("low", function(value) engine.low(value) end)
    params:add_control("mid", "Mid Decay", controlspec.new(0, 1, "lin", 0.01, 1, "x")) params:set_action("mid", function(value) engine.mid(value) end)
    params:add_control("high", "High Decay", controlspec.new(0, 1, "lin", 0.01, 1, "x")) params:set_action("high", function(value) engine.high(value) end)
    params:add_taper("lowcut", "Low-Mid X", 100, 6000, 500, 2, "Hz") params:set_action("lowcut", function(value) engine.lowcut(value) end)
    params:add_taper("highcut", "Mid-High X", 1000, 10000, 2000, 2, "Hz") params:set_action("highcut", function(value) engine.highcut(value) end)
    params:add_separator("  ")
    params:add_binary("randomize_jpverb", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_jpverb", function() randpara.randomize_jpverb_params(steps) end)
    params:add_option("lock_reverb", "Lock Parameters", {"off", "on"}, 1)
    
    params:add_group("Shimmer", 8)
    params:add_control("shimmer_mix", "Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("shimmer_mix", function(x) engine.shimmer_mix(x/100) end)
    params:add_control("pitchv", "Variance", controlspec.new(0, 100, "lin", 1, 2, "%")) params:set_action("pitchv", function(x) engine.pitchv(x/100) end)
    params:add_control("lowpass", "LPF", controlspec.new(20, 20000, "lin", 1, 13000, "Hz")) params:set_action("lowpass", function(x) engine.lowpass(x) end)
    params:add_control("hipass", "HPF", controlspec.new(20, 20000, "exp", 1, 1400, "Hz")) params:set_action("hipass", function(x) engine.hipass(x) end)
    params:add_control("fbDelay", "Delay", controlspec.new(0.01, 0.5, "lin", 0.01, 0.2, "s")) params:set_action("fbDelay", function(x) engine.fbDelay(x) end)
    params:add_control("fb", "Feedback", controlspec.new(0, 100, "lin", 1, 15, "%")) params:set_action("fb", function(x) engine.fb(x/100) end)
    params:add_separator("        ")
    params:add_option("lock_shimmer", "Lock Parameters", {"off", "on"}, 1)
    
    params:add_group("Tape", 17)
    params:add_option("tape_mix", "Analog Tape", {"off", "on"}, 1) params:set_action("tape_mix", function(x) engine.tape_mix(x-1) end)
    params:add_control("sine_mix", "Sine Shaper", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("sine_mix", function(value) engine.sine_mix(value / 100) end)
    params:add_control("sine_drive", "Sine Drive", controlspec.new(0, 100, "lin", 1, 17, "%")) params:set_action("sine_drive", function(value) engine.sine_drive(value/20) end)
    params:add{type = "control", id = "wobble_mix", name = "Wobble", controlspec = controlspec.new(0, 100, "lin", 1, 0, "%"), action = function(value) engine.wobble_mix(value/100) end}
    params:add{type = "control", id = "wobble_amp", name = "Wow Depth", controlspec = controlspec.new(0, 100, "lin", 1, 20, "%"), action = function(value) engine.wobble_amp(value/100) end}
    params:add{type = "control", id = "wobble_rpm", name = "Wow Speed", controlspec = controlspec.new(30, 90, "lin", 1, 33, "RPM"), action = function(value) engine.wobble_rpm(value) end}
    params:add{type = "control", id = "flutter_amp", name = "Flutter Depth", controlspec = controlspec.new(0, 100, "lin", 1, 35, "%"), action = function(value) engine.flutter_amp(value/100) end}
    params:add{type = "control", id = "flutter_freq", name = "Flutter Speed", controlspec = controlspec.new(3, 30, "lin", 0.01, 6, "Hz"), action = function(value) engine.flutter_freq(value) end}
    params:add{type = "control", id = "flutter_var", name = "Flutter Var.", controlspec = controlspec.new(0.1, 10, "lin", 0.01, 2, "Hz"), action = function(value) engine.flutter_var(value) end}
    params:add{type = "control", id = "chew_mix", name = "Chew", controlspec = controlspec.new(0, 100, "lin", 1, 0, "%"), action = function(value) engine.chew_mix(value/100) end}
    params:add{type = "control", id = "chew_depth", name = "Chew Depth", controlspec = controlspec.new(0, 100, "lin", 1, 50, "%"), action = function(value) engine.chew_depth(value/100) end}
    params:add{type = "control", id = "chew_freq", name = "Chew Freq.", controlspec = controlspec.new(0, 75, "lin", 1, 50, "%"), action = function(value) engine.chew_freq(value/100) end}
    params:add{type = "control", id = "chew_variance", name = "Chew Var.", controlspec = controlspec.new(0, 100, "lin", 1, 50, "%"), action = function(value) engine.chew_variance(value/100) end}
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
    
    params:add_group("Stereo", 2)
    params:add_control("Width", "Stereo Width", controlspec.new(0, 200, "lin", 0.01, 100, "%")) params:set_action("Width", function(value) engine.width(value / 100) end)
    params:add_option("monobass_mix", "Mono Bass", {"off", "on"}, 1) params:set_action("monobass_mix", function(x) engine.monobass_mix(x-1) end)

    params:add_group("LFOs", 118)
    params:add_binary("randomize_lfos", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_lfos", function() lfo.clearLFOs() lfo.randomize_lfos("1", params:get("allow_volume_lfos") == 2)  lfo.randomize_lfos("2", params:get("allow_volume_lfos") == 2) if randomize_metro[1] then randomize_metro[1]:stop() end if randomize_metro[2] then randomize_metro[2]:stop() end end)
    params:add_control("global_lfo_freq_scale", "Freq Scale", controlspec.new(0.1, 10, "exp", 0.01, 1.0, "x"))
    params:set_action("global_lfo_freq_scale", function(value)
    -- Store current phase relationships
    local phase_ref = {}
    for i = 1, 16 do
        phase_ref[i] = lfo[i].phase
    end
    
    -- Apply new frequency scale
    for i = 1, 16 do
        local base_freq = params:get(i.."lfo_freq") or 0.05
        lfo[i].base_freq = base_freq
        lfo[i].freq = base_freq * value
        -- Restore phase relationship
        lfo[i].phase = phase_ref[i]
    end
    end)
    params:add_binary("lfo.assign_to_current_row", "Assign to Selection", "trigger", 0) params:set_action("lfo.assign_to_current_row", function() lfo.assign_to_current_row(current_mode, current_filter_mode) end)
    params:add_binary("lfo_pause", "Pause LFOs", "toggle", 0) params:set_action("lfo_pause", function(value) lfo.set_pause(value == 1) end)
    params:add_binary("ClearLFOs", "Clear All LFOs", "trigger", 0) params:set_action("ClearLFOs", function() lfo.clearLFOs() end)
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
    params:add_taper("max_spread", "spread (max)", 0, 100, 70, 0, "%")
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
      params:add_option(i.. "lock_pan", i.. " lock pan", {"off", "on"}, 1)
      params:add_option(i.. "lock_seek", i.. " lock seek", {"off", "on"}, 1)
      params:add_option(i.. "lock_speed", i.. " lock speed", {"off", "on"}, 1)
    end

    params:add_group("Symmetry", 3)
    params:add_binary("copy_1_to_2", "Copy 1 → 2", "trigger", 0) params:set_action("copy_1_to_2", function() Mirror.copy_voice_params("1", "2", true) Mirror.copy_voice_params("2", "1", true) end)
    params:add_binary("copy_2_to_1", "Copy 1 ← 2", "trigger", 0) params:set_action("copy_2_to_1", function() Mirror.copy_voice_params("2", "1", true) Mirror.copy_voice_params("1", "2", true) end)
    params:add_binary("symmetry", "Symmetry", "toggle", 0)
    
    params:add_group("Actions", 2)
    params:add_binary("macro_more", "More+", "trigger", 0) params:set_action("macro_more", function() macro.macro_more() end)
    params:add_binary("macro_less", "Less-", "trigger", 0) params:set_action("macro_less", function() macro.macro_less() end)
    
    params:add_group("Other", 2)
    params:add_binary("dry_mode", "Dry Mode", "toggle", 0) params:set_action("dry_mode", function(x) drymode.toggle_dry_mode() end)
    params:add_option("steps", "Transition Time", {"short", "medium", "long"}, 2) params:set_action("steps", function(value) for i = 1, 2 do if randomize_metro[i] then randomize_metro[i]:stop() end end lfo.cleanup() steps = ({20, 400, 5000})[value] end)
    
    for i = 1, 2 do
      params:add_taper(i.. "volume", i.. " volume", -70, 20, 0, 0, "dB") params:set_action(i.. "volume", function(value) if value == -70 then engine.volume(i, 0) else engine.volume(i, math.pow(10, value / 20)) end end)
      params:add_taper(i.. "pan", i.. " pan", -100, 100, 0, 0, "%") params:set_action(i.. "pan", function(value) engine.pan(i, value / 100)  end)
      params:add_taper(i.. "speed", i.. " speed", -2, 2, 0.10, 0) params:set_action(i.. "speed", function(value) if math.abs(value) < 0.01 then engine.speed(i, 0) else engine.speed(i, value) end end)
      params:add_taper(i.. "density", i.. " density", 0.1, 300, 10, 5) params:set_action(i.. "density", function(value) engine.density(i, value) end)
      params:add_control(i.. "pitch", i.. " pitch", controlspec.new(-48, 48, "lin", 1, 0, "st")) params:set_action(i.. "pitch", function(value) engine.pitch_offset(i, math.pow(0.5, -value / 12)) end)
      params:add_taper(i.. "jitter", i.. " jitter", 0, 4999, 250, 3, "ms") params:set_action(i.. "jitter", function(value) engine.jitter(i, value / 1000) end)
      params:add_taper(i.. "size", i.. " size", 1, 5999, 100, 1, "ms") params:set_action(i.. "size", function(value) engine.size(i, value / 1000) end)
      params:add_taper(i.. "spread", i.. " spread", 0, 100, 0, 0, "%") params:set_action(i.. "spread", function(value) engine.spread(i, value / 100) end)
      params:add_control(i.. "seek", i.. " seek", controlspec.new(0, 100, "lin", 0.01, 0, "%")) params:set_action(i.. "seek", function(value) engine.seek(i, value) end)
      params:hide(i.. "speed")
      params:hide(i.. "jitter")
      params:hide(i.. "size")
      params:hide(i.. "density")
      params:hide(i.. "pitch")
      params:hide(i.. "spread")
      params:hide(i.. "seek")
      params:hide(i.. "pan")
      params:hide(i.. "volume")
    end
    
    params:add_control("1cutoff","1 Cutoff",controlspec.new(20,20000,"exp",0,20000,"Hz")) params:set_action("1cutoff",function(value) engine.cutoff(1,value) end)
    params:add_control("2cutoff","2 Cutoff",controlspec.new(20,20000,"exp",0,20000,"Hz")) params:set_action("2cutoff",function(value) engine.cutoff(2,value) end)
    params:add_control("1hpf", "1 Cutoff", controlspec.new(20, 20000, "exp", 0, 20, "Hz")) params:set_action("1hpf", function(value) engine.hpf(1, value) end)
    params:add_control("2hpf", "2 Cutoff", controlspec.new(20, 20000, "exp", 0, 20, "Hz")) params:set_action("2hpf", function(value) engine.hpf(2, value) end)
    params:hide("1cutoff")
    params:hide("2cutoff")
    params:hide("1hpf")
    params:hide("2hpf")
    
    params:bang()
end

local function interpolate(start_val, end_val, factor)
    return start_val + (end_val - start_val) * factor
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
      pitch = {lock = params:get(n.."lock_pitch")==1, param_name = n.."pitch"}
    }

    local targets = {}
    local symmetry = params:get("symmetry") == 1
    local other_track = n == 1 and 2 or 1

    -- Handle pitch instantly (no interpolation)
    if param_config.pitch.lock and not active_controlled_params[param_config.pitch.param_name] then
        local current_pitch = params:get(n .. "pitch")
        local min_pitch = math.max(params:get("min_pitch"), current_pitch - 48)
        local max_pitch = math.min(params:get("max_pitch"), current_pitch + 48)
        local base_pitch = params:get(n == 1 and "2pitch" or "1pitch")
        
        if min_pitch < max_pitch and not is_lfo_active_for_param(param_config.pitch.param_name) then
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
                        params:set(param_config.pitch.param_name, base_pitch + v.interval)
                        if symmetry then
                            params:set(other_track.."pitch", base_pitch + v.interval)
                        end
                        break
                    end
                end
            else
                for _, interval in ipairs(larger_intervals) do
                    local candidate_pitch = base_pitch + interval
                    if candidate_pitch >= min_pitch and candidate_pitch <= max_pitch then
                        params:set(param_config.pitch.param_name, candidate_pitch)
                        if symmetry then
                            params:set(other_track.."pitch", candidate_pitch)
                        end
                        break
                    end
                end
            end
        end
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
                        -- Special handling for pan (invert value)
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
    audio.level_adc(0)
end

function init() if not installer:ready() then clock.run(function() while true do redraw() clock.sleep(1 / 10) end end) do return end end
    setup_ui_metro()
    setup_params()
    setup_engine()
    Mirror.init(lfo)
end

local function wrap_value(value, min, max)
    if value < min then
        return max + (value - min)
    elseif value > max then
        return min + (value - max)
    else
        return value
    end
end

function enc(n, d)
    if not installer:ready() then return end
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
    local function handle_param_adjustment(track, config, delta_multiplier)
        stop_interpolations()
        local param_name = track .. config.param
        if config.has_lock and params:get(track .. "lock_" .. config.param) == 2 then
            return
        end
        if params:get("symmetry") == 1 then
            disable_lfos_for_param(param_name)
        else
            local is_active, lfo_index = is_lfo_active_for_param(param_name)
            if is_active then params:set(lfo_index .. "lfo", 1) end
        end
        manual_adjustments[param_name] = {active = true, value = params:get(param_name), time = util.time()}
        if params:get("symmetry") == 1 then
            local other_track = track == 1 and 2 or 1
            local other_param_name = other_track .. config.param
            
            if not config.has_lock or params:get(other_track .. "lock_" .. config.param) ~= 2 then
                local delta = config.invert and -d or d
                if config.wrap then
                    local current_val = params:get(other_param_name)
                    local new_val = wrap_value(current_val + delta, config.wrap[1], config.wrap[2])
                    params:set(other_param_name, new_val)
                    if config.engine then engine.seek(other_track, new_val / 100) end
                else
                    params:delta(other_param_name, config.delta * (config.invert and -delta_multiplier or delta_multiplier) * d)
                end
            end
        end
        if config.wrap then
            local current_val = params:get(param_name)
            local new_val = wrap_value(current_val + d, config.wrap[1], config.wrap[2])
            params:set(param_name, new_val)
            if config.engine then engine.seek(track, new_val / 100) end
        else
            params:delta(param_name, config.delta * delta_multiplier * d)
        end
    end
    local param_modes = {
        speed = {param = "speed", delta = 0.5, has_lock = true, action = function(track, value) engine.speed(track, math.abs(value) < 0.01 and 0 or value) end},
        seek = {param = "seek", delta = 1, wrap = {0, 100}, engine = true, has_lock = true},
        pan = {param = "pan", delta = 5, has_lock = true, invert = true},
        lpf = {param = "cutoff", delta = 1, has_lock = false},
        hpf = {param = "hpf", delta = 1, has_lock = false},
        jitter = {param = "jitter", delta = 2, has_lock = true},
        size = {param = "size", delta = 2, has_lock = true},
        density = {param = "density", delta = 2, has_lock = true},
        spread = {param = "spread", delta = 2, has_lock = true},
        pitch = {param = "pitch", delta = 1, has_lock = true} }
    local enc_actions = {
        [1] = function()
            local is_active1, lfo_index1 = is_lfo_active_for_param("1volume")
            local is_active2, lfo_index2 = is_lfo_active_for_param("2volume")
            local lfo_delta = 0.75 * d
            if is_active1 or is_active2 then
                if is_active1 and is_active2 then
                    params:delta(lfo_index1 .. "offset", key1_pressed and lfo_delta or lfo_delta)
                    params:delta(lfo_index2 .. "offset", key1_pressed and -lfo_delta or lfo_delta)
                elseif is_active1 then
                    params:delta(lfo_index1 .. "offset", lfo_delta)
                    params:delta("2volume", key1_pressed and -3 * d or 3 * d)
                else
                    params:delta(lfo_index2 .. "offset", key1_pressed and -lfo_delta or lfo_delta)
                    params:delta("1volume", key1_pressed and 3 * d or 3 * d)
                end
            else
                params:delta("1volume", 3 * d)
                params:delta("2volume", key1_pressed and -3 * d or 3 * d)
            end
        end,
        [2] = function()
            if key1_pressed then
                if params:get("symmetry") == 1 then
                    disable_lfos_for_param("1volume")
                else
                    local is_active, lfo_index = is_lfo_active_for_param("1volume")
                    if is_active then params:set(lfo_index .. "lfo", 1) end
                end
                params:delta("1volume", 3 * d)
            else
                local mode = (current_mode == "lpf" or current_mode == "hpf") and current_filter_mode or current_mode
                handle_param_adjustment(1, param_modes[mode], 1)
            end
        end,
        [3] = function()
            if key1_pressed then
                if params:get("symmetry") == 1 then
                    disable_lfos_for_param("2volume")
                else
                    local is_active, lfo_index = is_lfo_active_for_param("2volume")
                    if is_active then params:set(lfo_index .. "lfo", 1) end
                end
                params:delta("2volume", 3 * d)
            else
                local mode = (current_mode == "lpf" or current_mode == "hpf") and current_filter_mode or current_mode
                handle_param_adjustment(2, param_modes[mode], 1)
            end
        end
    }
    if enc_actions[n] then enc_actions[n]() end
end

function key(n, z)
    if not installer:ready() then installer:key(n, z) return end
    if n == 1 then key1_pressed = z == 1
      elseif n == 2 then key2_pressed = z == 1
      elseif n == 3 then key3_pressed = z == 1
    end
    if z == 1 then
        if key1_pressed then
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
        if not key1_pressed then
            if n == 2 then
                local modes = {"pitch", "spread", "density", "size", "jitter", "lpf", "pan", "seek", "speed"}
                local current_index = table.find(modes, current_mode) or 1
                current_mode = modes[(current_index % #modes) + 1]
            elseif n == 3 then
                local modes = {"speed", "seek", "pan", "lpf", "jitter", "size", "density", "spread", "pitch"}
                local current_index = table.find(modes, current_mode) or 1
                current_mode = modes[(current_index % #modes) + 1]
            end
        end
    end
    if key2_pressed and key3_pressed then
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

local function draw_param_row(y, label, param1, param2, is_density, is_pitch, is_highlighted)
    local param_name = string.match(label, "%a+")
    local is_locked1 = is_param_locked(1, param_name)
    local is_locked2 = is_param_locked(2, param_name)
    local text_level = is_highlighted and 15 or 1
    screen.level(15)
    screen.move(5, y)
    screen.text(label)
    local function draw_param_value(x, param, is_locked)
        if is_locked then
            draw_l_shape(x, y, true)  
        end
        screen.move(x, y)
        screen.level(text_level)
        if is_density then
            screen.text(format_density(params:get(param)))
        elseif is_pitch then
            screen.text(format_pitch(params:get(param)))
        elseif param_name == "spread" then
            screen.text(string.format("%.0f%%", params:get(param)))
        else
            screen.text(params:string(param))
        end
    end
    draw_param_value(51, param1, is_locked1)
    draw_param_value(92, param2, is_locked2)
    if not is_pitch then
        local function draw_value_bar(x, param)
            local bar_width = 30
            local bar_height = 1
            local min_val, max_val = lfo.get_parameter_range(param)
            screen.level(6)
            if manual_adjustments[param] and manual_adjustments[param].active then
                local bar_value = util.linlin(min_val, max_val, 0, bar_width, manual_adjustments[param].value)
                screen.rect(x, y + 1, bar_value, bar_height)
            else
                local lfo_mod = get_lfo_modulation(param)
                if lfo_mod then
                    local bar_value = util.linlin(min_val, max_val, 0, bar_width, lfo_mod)
                    screen.rect(x, y + 1, bar_value, bar_height)
                end
            end
            screen.fill()
        end
        draw_value_bar(51, param1)
        draw_value_bar(92, param2)
    end
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
    local current_time = util.time()
    for param, adjustment in pairs(manual_adjustments) do
        if adjustment and adjustment.time and (current_time - adjustment.time > manual_adjustment_duration) then
            adjustment.active = false
        end
    end
    screen.clear()
    screen.save()
    screen.translate(0, animation_y)
    local current_mode = current_mode
    local current_filter_mode = current_filter_mode
    local param_rows = {
        {y = 11, label = "jitter:    ", mode = "jitter", param1 = "1jitter", param2 = "2jitter", hz = false, st = false},
        {y = 21, label = "size:     ", mode = "size", param1 = "1size", param2 = "2size", hz = false, st = false},
        {y = 31, label = "density:  ", mode = "density", param1 = "1density", param2 = "2density", hz = true, st = false},
        {y = 41, label = "spread:   ", mode = "spread", param1 = "1spread", param2 = "2spread", hz = false, st = false},
        {y = 51, label = "pitch:    ", mode = "pitch", param1 = "1pitch", param2 = "2pitch", hz = false, st = true}}
    local bottom_labels = {seek = "seek:     ",pan = "pan:      ",lpf = current_filter_mode == "lpf" and "lpf:      " or "hpf:      ",speed = "speed:    "}
    for _, row in ipairs(param_rows) do
        draw_param_row(row.y, row.label, row.param1, row.param2, row.hz, row.st, current_mode == row.mode)
    end
    screen.move(5, 61)
    screen.level(15)
    screen.text(bottom_labels[current_mode] or "speed:    ")
    if current_mode == "seek" then
        draw_progress_bar(51, 63, 30, params:get("1seek"), 0, 100, false)
        draw_progress_bar(92, 63, 30, params:get("2seek"), 0, 100, false)
    elseif current_mode == "lpf" or current_mode == "hpf" then
        local param1 = current_filter_mode == "lpf" and "1cutoff" or "1hpf"
        local param2 = current_filter_mode == "lpf" and "2cutoff" or "2hpf"
        draw_progress_bar(51, 63, 30, params:get(param1), 20, 20000, true)
        draw_progress_bar(92, 63, 30, params:get(param2), 20, 20000, true)
    end
    local is_highlighted = current_mode == "seek" or current_mode == "lpf" or current_mode == "hpf" or current_mode == "speed" or current_mode == "pan"
    local function draw_bottom_value(x, track)
        screen.move(x, 61)
        screen.level(is_highlighted and 15 or 1)
        if current_mode == "seek" then
            screen.text(format_seek(params:get(track.."seek")))
        elseif current_mode == "pan" then
            local pan = params:get(track.."pan")
            screen.text(math.abs(pan) < 0.5 and "0%" or string.format("%.0f%%", pan))
        elseif current_mode == "lpf" or current_mode == "hpf" then
            local param = current_filter_mode == "lpf" and track.."cutoff" or track.."hpf"
            screen.text(string.format("%.0f", params:get(param)))
        else
            screen.text(format_speed(params:get(track.."speed")))
        end
    end
    draw_bottom_value(51, "1")
    draw_bottom_value(92, "2")
    local show_speed_lock = current_mode == "speed" or current_mode == "jitter" or current_mode == "size" or current_mode == "density" or current_mode == "spread" or current_mode == "pitch"
    if current_mode == "pan" or current_mode == "seek" or show_speed_lock then
        local param_type = show_speed_lock and "speed" or current_mode
        local function draw_if_locked(x, track)
            if is_param_locked(track, param_type) then
                draw_l_shape(x, 61, true)
            end
        end
        draw_if_locked(51, 1)
        draw_if_locked(92, 2)
    end
    screen.level(6)
    -- Draw volume bars
    for i, x in ipairs({0, 127}) do
        local track = tostring(i)
        if is_audio_loaded(track) then
            local volume = params:get(track.."volume")
            local height = util.linlin(-60, 20, 0, 64, volume)
            screen.rect(x, 64 - height, 1, height)
        end
    end
    -- Draw pan indicators
    for i, center_start in ipairs({52, 93}) do
        local track = tostring(i)
        if is_audio_loaded(track) then
            local pan = params:get(track.."pan")
            local center_end = center_start + 25
            local pos = util.linlin(-100, 100, center_start, center_end, pan)
            screen.rect(pos - 1, 0, 4, 1)
        end
    end
    screen.fill()
    screen.level(1)
    if params:get("dry_mode") == 1 then screen.pixel(6, 0) screen.pixel(10, 0) screen.pixel(14, 0) end 
    if params:get("symmetry") == 1 then screen.pixel(6, 0) screen.pixel(8, 0) screen.pixel(10, 0) end
    screen.fill()
    screen.restore()
    screen.update()
end

function cleanup()
  if ui_metro then ui_metro:stop() end
  for i = 1, 2 do
    if randomize_metro[i] then randomize_metro[i]:stop() end
  end
  lfo.cleanup()
end