--
--
--  __ __|         _)          
--     | \ \  \  / |  \ |  (_< 
--     |  \_/\_/ _| _| _| __/ 
--           by: @dddstudio                       
--
--                          
--                           v0.22
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
--
-- If you like this,
-- buy them a beer :)
--
--                    Daniel Rigler

local lfo = include("lib/lfo")
local randpara = include("lib/randpara")
delay = include("lib/delay")
installer_ = include("lib/scinstaller/scinstaller")
installer = installer_:new{requirements = {"Fverb2","AnalogChew"}, 
  zip = "https://github.com/schollz/portedplugins/releases/download/v0.4.6/PortedPlugins-RaspberryPi.zip"}
engine.name = installer:ready() and 'twins' or nil

local ui_metro
local randomize_metro = { [1] = nil, [2] = nil }
local key1_pressed, key2_pressed, key3_pressed = false
local current_mode = "speed"
local current_filter_mode = "lpf"

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
        redraw()
    end
    ui_metro:start()
end

local function is_lfo_active_for_param(param_name)
    for i = 1, 16 do
        local target_index = params:get(i .. "lfo_target")
        if lfo.lfo_targets[target_index] == param_name and params:get(i .. "lfo") == 2 then
            return true, i
        end
    end
    return false, nil
end

local function load_random_tape_file(track_num)
    local tape_dir = _path.tape
    local files = util.scandir(tape_dir)
    local audio_files = {}
    for _, file in ipairs(files) do
        local ext = string.lower(string.match(file, "%.(.+)$")) or ""
        if (ext == "wav") or (ext == "aif") or (ext == "aiff") or (ext == "flac") then
            table.insert(audio_files, tape_dir .. file)
        end
    end
    if #audio_files > 0 then
        local random_index = math.random(1, #audio_files)
        params:set(track_num .. "sample", audio_files[random_index])
        return true
    else
        print("No audio files found in tape directory")
        return false
    end
end

local function setup_params()
    params:add_separator("Samples")
    for i = 1, 2 do
        params:add_file(i .. "sample", "Sample " ..i)
        params:set_action(i .. "sample", function(file)
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
    params:set_action("randomize_params", function() load_random_tape_file(1) load_random_tape_file(2) randpara.randomize_params(steps) lfo.clearLFOs("1") lfo.clearLFOs("2") lfo.randomize_lfos("1", params:get("allow_volume_lfos") == 2)  lfo.randomize_lfos("2", params:get("allow_volume_lfos") == 2) if randomize_metro[1] then randomize_metro[1]:stop() end if randomize_metro[2] then randomize_metro[2]:stop() end end)
    
    params:add_separator("Settings")

    params:add_group("Delay", 4)
    delay.init()

    params:add_group("Reverbs", 24)
    params:add_separator("Fverb2")
    params:add_binary("randomize_fverb", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_fverb", function() randpara.randomize_fverb_params(steps) end)
    params:add_taper("reverb_mix", "Mix", 0, 100, 0.0, 0, "%") params:set_action("reverb_mix", function(value) engine.reverb_mix(value / 100) end)
    params:add_taper("reverb_predelay", "Predelay", 0, 250, 20, 0, "ms") params:set_action("reverb_predelay", function(value) engine.reverb_predelay(value) end)
    params:add_taper("reverb_input_amount", "Input Amount", 0, 100, 100, 0, "%") params:set_action("reverb_input_amount", function(value) engine.reverb_input_amount(value) end)
    params:add_taper("reverb_lowpass_cutoff", "Lowpass", 0, 20000, 8000, 0, "Hz") params:set_action("reverb_lowpass_cutoff", function(value) engine.reverb_lowpass_cutoff(value) end)
    params:add_taper("reverb_highpass_cutoff", "Highpass", 0, 20000, 75, 0, "Hz") params:set_action("reverb_highpass_cutoff", function(value) engine.reverb_highpass_cutoff(value) end)
    params:add_taper("reverb_diffusion_1", "Diffusion 1", 0, 100, 85, 0, "%") params:set_action("reverb_diffusion_1", function(value) engine.reverb_diffusion_1(value) end)
    params:add_taper("reverb_diffusion_2", "Diffusion 2", 0, 100, 85, 0, "%") params:set_action("reverb_diffusion_2", function(value) engine.reverb_diffusion_2(value) end)
    params:add_taper("reverb_tail_density", "Tail Density", 0, 100, 75, 0, "%") params:set_action("reverb_tail_density", function(value) engine.reverb_tail_density(value) end)
    params:add_taper("reverb_decay", "Decay", 0, 100, 80, 0, "%") params:set_action("reverb_decay", function(value) engine.reverb_decay(value) end)
    params:add_taper("reverb_damping", "Damping", 0, 20000, 6000, 0, "Hz") params:set_action("reverb_damping", function(value) engine.reverb_damping(value) end)
    params:add_taper("reverb_modulator_depth", "Mod Depth", 0, 100, 40, 0, "%") params:set_action("reverb_modulator_depth", function(value) engine.reverb_modulator_depth(value / 100) end)
    params:add_taper("reverb_modulator_frequency", "Mod Freq", 0, 10, 1, 0, "Hz") params:set_action("reverb_modulator_frequency", function(value) engine.reverb_modulator_frequency(value) end)
    params:add_separator("Greyhole")
    params:add_binary("randomize_greyhole", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_greyhole", function() randpara.randomize_greyhole_params(steps) end)
    params:add_taper("greyhole_mix", "Mix", 0, 100, 0.0, 0, "%") params:set_action("greyhole_mix", function(value) engine.greyhole_mix(value / 100) end)
    params:add_control("time", "Time", controlspec.new(0.00, 10.00, "lin", 0.01, 3, "")) params:set_action("time", function(value) engine.greyhole_delay_time(value) end)
    params:add_control("size", "Size", controlspec.new(0.5, 5.0, "lin", 0.01, 4.00, "")) params:set_action("size", function(value) engine.greyhole_size(value) end)
    params:add_control("damp", "Damping", controlspec.new(0.0, 1.0, "lin", 0.01, 0.1, "")) params:set_action("damp", function(value) engine.greyhole_damp(value) end)
    params:add_control("diff", "Diffusion", controlspec.new(0.0, 1.0, "lin", 0.01, 0.5, "")) params:set_action("diff", function(value) engine.greyhole_diff(value) end)
    params:add_control("feedback", "Feedback", controlspec.new(0.00, 1.0, "lin", 0.01, 0.22, "")) params:set_action("feedback", function(value) engine.greyhole_feedback(value) end)
    params:add_control("mod_depth", "Mod Depth", controlspec.new(0.0, 1.0, "lin", 0.01, 0.85, "")) params:set_action("mod_depth", function(value) engine.greyhole_mod_depth(value) end)
    params:add_control("mod_freq", "Mod Freq", controlspec.new(0.0, 10.0, "lin", 0.01, 0.7, "Hz")) params:set_action("mod_freq", function(value) engine.greyhole_mod_freq(value) end)   

    params:add_group("Grains", 27)
    params:add_binary("randomize_voices", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_voices", function() randpara.randomize_voice_params(1) randpara.randomize_voice_params(2) end)
    for i = 1, 2 do
      params:add_separator("Sample " ..i)
      params:add_control(i .. "granular_gain", i .. " Mix", controlspec.new(0, 100, "lin", 1, 100, "%")) 
      params:set_action(i .. "granular_gain", function(value) engine.granular_gain(i, value / 100) if value < 100 then lfo.clearLFOs(i, "seek") end end)
      params:add_control(i .. "pitch_random_plus", i .. " Octave Variation +", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i .. "pitch_random_plus", function(value) engine.pitch_random_plus(i, value / 100) end)
      params:add_control(i .. "pitch_random_minus", i .. " Octave Variation -", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i .. "pitch_random_minus", function(value) engine.pitch_random_minus(i, value / 100) end)
      params:add_control(i .. "subharmonics_3", i .. " Subharmonics -3oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0))
      params:set_action(i .. "subharmonics_3", function(value) engine.subharmonics_3(i, value) end)
      params:add_control(i .. "subharmonics_2", i .. " Subharmonics -2oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0))
      params:set_action(i .. "subharmonics_2", function(value) engine.subharmonics_2(i, value) end)
      params:add_control(i .. "subharmonics_1", i .. " Subharmonics -1oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0))
      params:set_action(i .. "subharmonics_1", function(value) engine.subharmonics_1(i, value) end)
      params:add_control(i .. "overtones_1", i .. " Overtones +1oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0))
      params:set_action(i .. "overtones_1", function(value) engine.overtones_1(i, value) end)
      params:add_control(i .. "overtones_2", i .. " Overtones +2oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0))
      params:set_action(i .. "overtones_2", function(value) engine.overtones_2(i, value) end)
      params:add_control(i .. "size_variation", i .. " Size Variation", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i .. "size_variation", function(value) engine.size_variation(i, value / 100) end)
      params:add_control(i .. "density_mod_amt", i .. " Density Mod", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i .. "density_mod_amt", function(value) engine.density_mod_amt(i, value / 100) end)
      params:add_control(i .. "direction_mod", i .. " Reverse", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i .. "direction_mod", function(value) engine.direction_mod(i, value / 100) end)
      params:add_option(i .. "pitch_mode", i .. " Pitch Mode", {"match speed", "independent"}, 2) params:set_action(i .. "pitch_mode", function(value) engine.pitch_mode(i, value - 1) end)
    end

    params:add_group("Filters", 10)
    params:add_separator("LPF")
    params:add_control("1cutoff","1 Cutoff",controlspec.new(20,20000,"exp",0,20000,"Hz")) params:set_action("1cutoff",function(value) engine.cutoff(1,value) end)
    params:add_control("1q","1 Resonance",controlspec.new(0,4,"lin",0.01,0)) params:set_action("1q",function(value) engine.q(1,value) end)
    params:add_control("2cutoff","2 Cutoff",controlspec.new(20,20000,"exp",0,20000,"Hz")) params:set_action("2cutoff",function(value) engine.cutoff(2,value) end)
    params:add_control("2q","2 Resonance",controlspec.new(0,4,"lin",0.01,0)) params:set_action("2q",function(value) engine.q(2,value) end)
    params:add_separator("HPF")
    params:add_control("1hpf", "1 Cutoff", controlspec.new(20, 20000, "exp", 0, 20, "Hz")) params:set_action("1hpf", function(value) engine.hpf(1, value) end)
    params:add_control("1hpfrq","1 Resonance",controlspec.new(0,1,"lin",0.01,1)) params:set_action("1hpfrq",function(value) engine.hpfrq(1,value) end)
    params:add_control("2hpf", "2 Cutoff", controlspec.new(20, 20000, "exp", 0, 20, "Hz")) params:set_action("2hpf", function(value) engine.hpf(2, value) end)
    params:add_control("2hpfrq","2 Resonance",controlspec.new(0,1,"lin",0.01,1)) params:set_action("2hpfrq",function(value) engine.hpfrq(2,value) end)
    
    params:add_group("Tape", 7)
    params:add_control("sine_wet", "Drive Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("sine_wet", function(value) engine.sine_wet(1, value / 100) engine.sine_wet(2, value / 100) end)
    params:add_control("sine_drive", "Drive", controlspec.new(0, 5, "lin", 0.01, 1, "")) params:set_action("sine_drive", function(value) engine.sine_drive(1, value) engine.sine_drive(2, value) end)
    params:add{type = "control", id = "1chew_wet", name = "1 Chew Mix", controlspec = controlspec.new(0, 100, "lin", 1, 0, "%"), action = function(value) engine.chew_wet(1, value / 100) end}
    params:add{type = "control", id = "2chew_wet", name = "2 Chew Mix", controlspec = controlspec.new(0, 100, "lin", 1, 0, "%"), action = function(value) engine.chew_wet(2, value / 100) end}
    params:add{type = "control", id = "chew_depth", name = "Chew Depth", controlspec = controlspec.new(0, 1, "lin", 0.01, 0.5, ""), action = function(value) engine.chew_depth(1, value) engine.chew_depth(2, value) end}
    params:add{type = "control", id = "chew_freq", name = "Chew Freq", controlspec = controlspec.new(0, 1, "lin", 0.01, 0.5, ""), action = function(value) engine.chew_freq(1, value) engine.chew_freq(2, value) end}
    params:add{type = "control", id = "chew_variance", name = "Chew Variance", controlspec = controlspec.new(0, 1, "lin", 0.01, 0.5, ""), action = function(value) engine.chew_variance(1, value) engine.chew_variance(2, value) end}

    params:add_group("EQ", 4)
    params:add_control("eq_low_gain_1", "1 Bass", controlspec.new(-1, 1, "lin", 0.01, 0, ""))
    params:set_action("eq_low_gain_1", function(value) engine.eq_low_gain(1, value*35) end)
    params:add_control("eq_high_gain_1", "1 Treble", controlspec.new(-1, 1, "lin", 0.01, 0, ""))
    params:set_action("eq_high_gain_1", function(value) engine.eq_high_gain(1, value*35) end)
    params:add_control("eq_low_gain_2", "2 Bass", controlspec.new(-1, 1, "lin", 0.01, 0, ""))
    params:set_action("eq_low_gain_2", function(value) engine.eq_low_gain(2, value*35) end)
    params:add_control("eq_high_gain_2", "2 Treble", controlspec.new(-1, 1, "lin", 0.01, 0, ""))
    params:set_action("eq_high_gain_2", function(value) engine.eq_high_gain(2, value*35) end)

    params:add_group("LFOs", 116)
    params:add_binary("randomize_lfos", "RaNd0m1ze LFOs", "trigger", 0) 
    params:set_action("randomize_lfos", function() lfo.clearLFOs("1") lfo.clearLFOs("2") lfo.randomize_lfos("1", params:get("allow_volume_lfos") == 2)  lfo.randomize_lfos("2", params:get("allow_volume_lfos") == 2) if randomize_metro[1] then randomize_metro[1]:stop() end if randomize_metro[2] then randomize_metro[2]:stop() end end)
    params:add_binary("ClearLFOs", "Clear All LFOs", "trigger", 0) 
    params:set_action("ClearLFOs", function() lfo.clearLFOs() end)
    params:add_option("allow_volume_lfos", "Allow Volume LFOs", {"no", "yes"}, 2)
    params:add_control("global_lfo_freq_scale", "Freq Scale", controlspec.new(0.1, 10, "exp", 0.01, 1.0, "x")) 
    params:set_action("global_lfo_freq_scale", function(value) 
    for i = 1, 16 do 
      lfo[i].base_freq = params:get(i .. "lfo_freq")  -- Store the base frequency
      lfo[i].freq = lfo[i].base_freq * value  -- Apply scaling
    end 
    end)
    lfo.init()

    for i = 1, 2 do
      params:add_taper(i .. "volume", i .. " volume", -70, 20, 0, 0, "dB") params:set_action(i .. "volume", function(value) if value == -70 then engine.volume(i, 0) else engine.volume(i, math.pow(10, value / 20)) end end)
      params:add_taper(i .. "pan", i .. " pan", -100, 100, 0, 0, "%") params:set_action(i .. "pan", function(value) engine.pan(i, value / 100)  end)
      params:add_control(i .. "speed", i .. " speed", controlspec.new(-2, 2, "lin", 0.01, 0.1, "")) params:set_action(i .. "speed", function(value) engine.speed(i, value) end)
      params:add_taper(i .. "density", i .. " density", 0.1, 20, 10, 1) params:set_action(i .. "density", function(value) engine.density(i, value) end)
      params:add_control(i .. "pitch", i .. " pitch", controlspec.new(-48, 48, "lin", 1, 0, "st")) params:set_action(i .. "pitch", function(value) engine.pitch_offset(i, math.pow(0.5, -value / 12)) end)
      params:add_taper(i .. "jitter", i .. " jitter", 0, 1999, 250, 5, "ms") params:set_action(i .. "jitter", function(value) engine.jitter(i, value / 1000) end)
      params:add_taper(i .. "size", i .. " size", 1, 999, 100, 5, "ms") params:set_action(i .. "size", function(value) engine.size(i, value / 1000) end)
      params:add_taper(i .. "spread", i .. " spread", 0, 100, 0, 0, "%") params:set_action(i .. "spread", function(value) engine.spread(i, value / 100) end)
      params:add_control(i .. "seek", i .. " seek", controlspec.new(0, 100, "lin", 0.01, 0, "%")) params:set_action(i .. "seek", function(value) engine.seek(i, value) end)
      params:hide(i .. "speed")
      params:hide(i .. "jitter")
      params:hide(i .. "size")
      params:hide(i .. "density")
      params:hide(i .. "pitch")
      params:hide(i .. "spread")
      params:hide(i .. "seek")
      params:hide(i .. "pan")
      params:hide(i .. "volume")
    end

    params:add_group("Limits", 10)
    params:add_taper("min_jitter", "jitter (min)", 0, 1999, 100, 5, "ms")
    params:add_taper("max_jitter", "jitter (max)", 0, 1999, 1999, 5, "ms")
    params:add_taper("min_size", "size (min)", 1, 999, 100, 5, "ms")
    params:add_taper("max_size", "size (max)", 1, 999, 599, 5, "ms")
    params:add_taper("min_density", "density (min)", 0.1, 30, 1, 5, "Hz")
    params:add_taper("max_density", "density (max)", 0.1, 30, 16, 5, "Hz")
    params:add_taper("min_spread", "spread (min)", 0, 100, 0, 0, "%")
    params:add_taper("max_spread", "spread (max)", 0, 100, 90, 0, "%")
    params:add_control("min_pitch", "pitch (min)", controlspec.new(-48, 48, "lin", 1, -31, "st"))
    params:add_control("max_pitch", "pitch (max)", controlspec.new(-48, 48, "lin", 1, 31, "st"))

    params:add_group("Locking", 14)
    for i = 1, 2 do
      params:add_option(i .. "lock_jitter", i .. " lock jitter", {"off", "on"}, 1)
      params:add_option(i .. "lock_size", i .. " lock size", {"off", "on"}, 1)
      params:add_option(i .. "lock_density", i .. " lock density", {"off", "on"}, 1)
      params:add_option(i .. "lock_spread", i .. " lock spread", {"off", "on"}, 1)
      params:add_option(i .. "lock_pitch", i .. " lock pitch", {"off", "on"}, 1)
      params:add_option(i .. "lock_pan", i .. " lock pan", {"off", "on"}, 1)
      params:add_option(i .. "lock_seek", i .. " lock seek", {"off", "on"}, 1) -- Add this line
    end

    params:add_group("Other", 5)
    params:add_separator("Stereo Width")
    for i = 1, 2 do
    params:add_control(i .. "Width", i .. " Width", controlspec.new(0, 200, "lin", 0.01, 100, "%"))
    params:set_action(i .. "Width", function(value) engine.width(i, value / 100) end)
    end  
    params:add_separator("Transition Steps")
    params:add_control("steps","Steps",controlspec.new(10,2000,"lin",1,400)) params:set_action("steps", function(value) steps = value end)
    
    params:bang()
end

local function interpolate(start_val, end_val, factor)
    return start_val + (end_val - start_val) * factor
end

local active_controlled_params = {} -- Track which parameters are being controlled by encoders

local function randomize(n)
    if not randomize_metro[n] then 
        randomize_metro[n] = metro.init() 
    end

    -- Clear active_controlled_params more efficiently
    active_controlled_params = {}

    -- Consolidated parameter configuration with all properties
    local param_config = {
    jitter = { min = "min_jitter", max = "max_jitter", lock = params:get(n.."lock_jitter")==1, param_name = n.."jitter" },
    size = { min = "min_size", max = "max_size", lock = params:get(n.."lock_size")==1, param_name = n.."size" },
    density = { min = "min_density", max = "max_density", lock = params:get(n.."lock_density")==1, param_name = n.."density" },
    spread = { min = "min_spread", max = "max_spread", lock = params:get(n.."lock_spread")==1, param_name = n.."spread" },
    pitch = { lock = params:get(n.."lock_pitch")==1, param_name = n.."pitch" },
    seek = { lock = params:get(n.."lock_seek")==1, param_name = n.."seek" }
    }
    
    local targets = {}

    -- Pre-calculate values to avoid repeated calls
    local current_pitch = params:get(n .. "pitch")
    local min_pitch = math.max(params:get("min_pitch"), current_pitch - 48)
    local max_pitch = math.min(params:get("max_pitch"), current_pitch + 48)
    local base_pitch = params:get(n == 1 and "2pitch" or "1pitch")

    -- Randomize parameters using the config table
    for param, config in pairs(param_config) do
        if param ~= "pitch" and param ~= "seek" then
            if config.lock and not active_controlled_params[config.param_name] then
                local min_val = params:get(config.min)
                local max_val = params:get(config.max)
                
                if min_val < max_val and not is_lfo_active_for_param(config.param_name) then
                    targets[config.param_name] = random_float(min_val, max_val)
                end
            end
        end
    end

    -- Randomize pitch parameter with optimized logic
    if param_config.pitch.lock and not active_controlled_params[param_config.pitch.param_name] then
        if min_pitch < max_pitch and not is_lfo_active_for_param(param_config.pitch.param_name) then
            local weighted_intervals = {
                {interval = -12, weight = 3}, {interval = -7, weight = 2},
                {interval = -5, weight = 2},  {interval = -3, weight = 1},
                {interval = 0, weight = 2},   {interval = 3, weight = 1},
                {interval = 5, weight = 2},   {interval = 7, weight = 2},
                {interval = 12, weight = 3}
            }

            -- Filter valid intervals first
            local valid_intervals = {}
            for _, v in ipairs(weighted_intervals) do
                local candidate_pitch = base_pitch + v.interval
                if candidate_pitch >= min_pitch and candidate_pitch <= max_pitch then
                    table.insert(valid_intervals, v)
                end
            end

            if #valid_intervals > 0 then
                -- Calculate total weight once
                local total_weight = 0
                for _, v in ipairs(valid_intervals) do
                    total_weight = total_weight + v.weight
                end

                -- Select weighted random interval
                local random_weight = math.random(total_weight)
                local cumulative_weight = 0

                for _, v in ipairs(valid_intervals) do
                    cumulative_weight = cumulative_weight + v.weight
                    if random_weight <= cumulative_weight then
                        params:set(param_config.pitch.param_name, base_pitch + v.interval)
                        break
                    end
                end
            else
                -- Fallback to larger intervals if no valid ones found
                local larger_intervals = {-24, -19, -17, -15, 15, 17, 19, 24}
                for _, interval in ipairs(larger_intervals) do
                    local candidate_pitch = base_pitch + interval
                    if candidate_pitch >= min_pitch and candidate_pitch <= max_pitch then
                        params:set(param_config.pitch.param_name, candidate_pitch)
                        break
                    end
                end
            end
        end
    end

    -- Start the interpolation metro with optimized logic
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

    local enc_actions = {
        [1] = function()
            local is_active1, lfo_index1 = is_lfo_active_for_param("1volume")
            local is_active2, lfo_index2 = is_lfo_active_for_param("2volume")
            local track1_delta = key1_pressed and 3 or 3
            local track2_delta = key1_pressed and -3 or 3
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
                params:delta("1volume", track1_delta * d)
                params:delta("2volume", track2_delta * d)
            end
        end,
        
        [2] = function()
            local track = 1
            if key1_pressed then 
                local is_active, lfo_index = is_lfo_active_for_param("1volume")
                if is_active then params:set(lfo_index .. "lfo", 1) end
                params:delta("1volume", 3*d)
            else
                local param_modes = {
                    speed = {param = "speed", delta = 0.5},
                    seek = {param = "seek", delta = 1, wrap = {0, 100}, engine = true},
                    pan = {param = "pan", delta = 5},
                    lpf = {param = "cutoff", delta = 1},
                    hpf = {param = "hpf", delta = 1},
                    jitter = {param = "jitter", delta = 2},
                    size = {param = "size", delta = 2},
                    density = {param = "density", delta = 2},
                    spread = {param = "spread", delta = 2},
                    pitch = {param = "pitch", delta = 1}
                }
                
                local mode = (current_mode == "lpf" or current_mode == "hpf") and current_filter_mode or current_mode
                local config = param_modes[mode]
                local param_name = track .. config.param
                
                active_controlled_params[param_name] = true
                
                local is_active, lfo_index = is_lfo_active_for_param(param_name)
                if is_active then params:set(lfo_index .. "lfo", 1) end
                
                if config.wrap then
                    local current_val = params:get(param_name)
                    local new_val = wrap_value(current_val + d, config.wrap[1], config.wrap[2])
                    params:set(param_name, new_val)
                    if config.engine then engine.seek(track, new_val / 100) end
                else
                    params:delta(param_name, config.delta * d)
                end
            end
        end,
        
        [3] = function()
            local track = 2
            if key1_pressed then 
                local is_active, lfo_index = is_lfo_active_for_param("2volume")
                if is_active then params:set(lfo_index .. "lfo", 1) end
                params:delta("2volume", 3*d)
            else
                local param_modes = {
                    speed = {param = "speed", delta = 0.5},
                    seek = {param = "seek", delta = 1, wrap = {0, 100}, engine = true},
                    pan = {param = "pan", delta = 5},
                    lpf = {param = "cutoff", delta = 1},
                    hpf = {param = "hpf", delta = 1},
                    jitter = {param = "jitter", delta = 2},
                    size = {param = "size", delta = 2},
                    density = {param = "density", delta = 2},
                    spread = {param = "spread", delta = 2},
                    pitch = {param = "pitch", delta = 1}
                }
                
                local mode = (current_mode == "lpf" or current_mode == "hpf") and current_filter_mode or current_mode
                local config = param_modes[mode]
                local param_name = track .. config.param
                
                active_controlled_params[param_name] = true
                
                local is_active, lfo_index = is_lfo_active_for_param(param_name)
                if is_active then params:set(lfo_index .. "lfo", 1) end
                
                if config.wrap then
                    local current_val = params:get(param_name)
                    local new_val = wrap_value(current_val + d, config.wrap[1], config.wrap[2])
                    params:set(param_name, new_val)
                    if config.engine then engine.seek(track, new_val / 100) end
                else
                    params:delta(param_name, config.delta * d)
                end
            end
        end
    }
    
    if enc_actions[n] then enc_actions[n]() end
end

function key(n, z)
    if not installer:ready() then 
        installer:key(n, z) 
        return 
    end

    -- Update key states
    if n == 1 then key1_pressed = z == 1
      elseif n == 2 then key2_pressed = z == 1
      elseif n == 3 then key3_pressed = z == 1
    end

    -- Key press handlers (z == 1 only)
    if z == 1 then
        -- Handle key combinations for randomization
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

        -- Handle single key presses for mode switching
        if not key1_pressed then
            if n == 2 then
                local modes = {"pitch", "spread", "density", "size", "jitter", "lpf", "pan", "seek", "speed"}
                local current_index = table.find(modes, current_mode) or 1
                current_mode = modes[(current_index % #modes) + 1]
                redraw()
            elseif n == 3 then
                local modes = {"speed", "seek", "pan", "lpf", "jitter", "size", "density", "spread", "pitch"}
                local current_index = table.find(modes, current_mode) or 1
                current_mode = modes[(current_index % #modes) + 1]
                redraw()
            end
        end
    end

    -- Handle key2 + key3 combination (works on both press and release)
    if key2_pressed and key3_pressed then
        if current_mode == "lpf" or current_mode == "hpf" then
            -- Toggle between LPF and HPF modes
            current_filter_mode = current_filter_mode == "lpf" and "hpf" or "lpf"
            redraw()
        else
            -- Handle parameter locking
            local lockable_params = {"jitter", "size", "density", "spread", "pitch", "pan", "seek"}
            local param_name = string.match(current_mode, "%a+")
            
            if param_name and table.find(lockable_params, param_name) then
                local is_locked1 = params:get("1lock_" .. param_name) == 2
                local is_locked2 = params:get("2lock_" .. param_name) == 2
                
                if is_locked1 ~= is_locked2 then
                    -- If only one is locked, unlock both
                    params:set("1lock_" .. param_name, 1)
                    params:set("2lock_" .. param_name, 1)
                else
                    -- Toggle both
                    local new_state = is_locked1 and 1 or 2
                    params:set("1lock_" .. param_name, new_state)
                    params:set("2lock_" .. param_name, new_state)
                end
                redraw()
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

local function is_param_locked(track_num, param)
    return params:get(track_num .. "lock_" .. param) == 2
end

local function draw_l_shape(x, y, is_locked)
    if is_locked then
        local pulse_level = math.floor(util.linlin(-1, 1, 1, 8, math.sin(util.time() * 4)))
        screen.level(pulse_level)
        screen.move(x - 4, y)
        screen.line_rel(2, 0)
        screen.move(x - 3, y)
        screen.line_rel(0, -3)
        screen.stroke()
    end
end

local function get_lfo_modulation(param_name)
    for i = 1, 16 do
        local target_index = params:get(i .. "lfo_target")
        if lfo.lfo_targets[target_index] == param_name and params:get(i .. "lfo") == 2 then
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

    -- Draw the label (always level 15)
    screen.level(15)
    screen.move(5, y)
    screen.text(label)

    -- Helper function to draw parameter value with common logic
    local function draw_param_value(x, param, is_locked)
        if is_locked then
            draw_l_shape(x, y, true)  -- Draw pulsing "L" shape for locked parameter
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

    -- Draw both parameter values
    draw_param_value(51, param1, is_locked1)
    draw_param_value(92, param2, is_locked2)

    -- Helper function to draw LFO visualization bars
    local function draw_lfo_bar(x, param)
        local lfo_mod = get_lfo_modulation(param)
        if lfo_mod then
            local bar_width = 30
            local bar_height = 1
            local min_val, max_val = lfo.get_parameter_range(param)
            local bar_value = util.linlin(min_val, max_val, 0, bar_width, lfo_mod)
            
            screen.level(key1_pressed and 6 or 1)
            screen.rect(x, y + 1, bar_value, bar_height)
            screen.fill()
        end
    end

    -- Draw both LFO bars
    draw_lfo_bar(51, param1)
    draw_lfo_bar(92, param2)
end

local function draw_progress_bar(x, y, width, value, min, max, center, is_log)
    -- Clamp the value to ensure it's within bounds
    value = math.min(math.max(value, min), max)
    
    -- Calculate position
    local value_pos
    if is_log then
        value_pos = util.linlin(math.log(min), math.log(max), x, x + width, math.log(value))
    else
        value_pos = util.linlin(min, max, x, x + width, value)
    end
    
    -- Draw the bar
    screen.level(3)
    if center then
        local center_pos = x + (width * 0.5)
        local bar_start = math.min(center_pos, value_pos)
        local bar_width = math.abs(value_pos - center_pos)
        screen.rect(bar_start, y, bar_width, 1)
    else
        screen.rect(x, y, value_pos - x, 1)
    end
    screen.fill()
end

local function format_speed(speed)
    if math.abs(speed) < 1 then
        -- Remove leading zero for speeds between 0 and 1
        if speed < 0 then
            -- Include negative sign for negative speeds
            return string.format("-.%02dx", math.floor(math.abs(speed) * 100))
        else
            -- No negative sign for positive speeds
            return string.format(".%02dx", math.floor(math.abs(speed) * 100))
        end
    else
        -- Display full value for speeds >= 1
        return string.format("%.2fx", speed)
    end
end

function redraw()
    if not installer:ready() then installer:redraw() do return end end
    screen.clear()

    -- Draw parameter rows with highlighting
    local param_rows = {
        {y = 10, label = "jitter:    ", mode = "jitter", param1 = "1jitter", param2 = "2jitter", hz = false, st = false},
        {y = 20, label = "size:     ", mode = "size", param1 = "1size", param2 = "2size", hz = false, st = false},
        {y = 30, label = "density:  ", mode = "density", param1 = "1density", param2 = "2density", hz = true, st = false},
        {y = 40, label = "spread:   ", mode = "spread", param1 = "1spread", param2 = "2spread", hz = false, st = false},
        {y = 50, label = "pitch:    ", mode = "pitch", param1 = "1pitch", param2 = "2pitch", hz = false, st = true}
    }
    
    for _, row in ipairs(param_rows) do
        draw_param_row(row.y, row.label, row.param1, row.param2, row.hz, row.st, current_mode == row.mode)
    end

    -- Handle bottom row display
    local bottom_row = {
        x = 5, y = 60,
        labels = {
            seek = "seek:     ",
            pan = "pan:      ",
            lpf = current_filter_mode == "lpf" and "lpf:      " or "hpf:      ",
            default = "speed:    "
        }
    }
    
    screen.move(bottom_row.x, bottom_row.y)
    screen.level(15)
    screen.text(bottom_row.labels[current_mode] or bottom_row.labels.default)

    -- Draw progress bars for seek or filter modes
    if current_mode == "seek" then
        draw_progress_bar(51, 62, 30, params:get("1seek"), 0, 100, false, false)
        draw_progress_bar(92, 62, 30, params:get("2seek"), 0, 100, false, false)
    elseif current_mode == "lpf" or current_mode == "hpf" then
        local param1 = current_filter_mode == "lpf" and "1cutoff" or "1hpf"
        local param2 = current_filter_mode == "lpf" and "2cutoff" or "2hpf"
        draw_progress_bar(51, 62, 30, params:get(param1), 20, 20000, false, true)
        draw_progress_bar(92, 62, 30, params:get(param2), 20, 20000, false, true)
    end

    -- Draw parameter values for bottom row
    local function draw_bottom_value(x, track)
        local is_highlighted = current_mode == "seek" or current_mode == "lpf" or current_mode == "hpf" or 
                             current_mode == "speed" or current_mode == "pan"
        screen.move(x, 60)
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

    -- Draw L-shapes for locked parameters
    if current_mode == "pan" or current_mode == "seek" then
        local param_type = current_mode
        local function draw_if_locked(x, track)
            if is_param_locked(track, param_type) then
                draw_l_shape(x, 60, true)
            end
        end
        draw_if_locked(51, 1)
        draw_if_locked(92, 2)
    end

    -- Draw volume bars
    local function draw_volume_bar(x, track)
        if is_audio_loaded(track) then
            local volume = params:get(track.."volume")
            local height = util.linlin(-60, 20, 0, 64, volume)
            local bar_width = 1
            screen.rect(x, 64 - height, bar_width, height)
            screen.fill()
        end
    end

    screen.level(key1_pressed and 6 or 3)
    draw_volume_bar(0, 1)
    draw_volume_bar(127, 2)

    -- Draw pan indicators
    local function draw_pan_indicator(track, center_start)
        if is_audio_loaded(track) then
            local pan = params:get(track.."pan")
            local center_end = center_start + 25
            local pos = util.linlin(-100, 100, center_start, center_end, pan)
            screen.rect(pos - 1, 0, 4, 1)
            screen.fill()
        end
    end
    screen.level(key1_pressed and 6 or 1)
    draw_pan_indicator(1, 52)
    draw_pan_indicator(2, 93)

    screen.update()
end

function cleanup()
  if ui_metro then ui_metro:stop() end
  for i = 1, 2 do
    if randomize_metro[i] then randomize_metro[i]:stop() end
  end
  lfo.cleanup()
end