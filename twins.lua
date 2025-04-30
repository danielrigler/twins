--
--
--  __ __|         _)          
--     | \ \  \  / |  \ |  (_< 
--     |  \_/\_/ _| _| _| __/ 
--           by: @dddstudio                       
--
--                          
--                           v0.27
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
engine.name = 'twins'

local ui_metro
local randomize_metro = { [1] = nil, [2] = nil }
local key1_pressed, key2_pressed, key3_pressed = false
local current_mode = "speed"
local current_filter_mode = "lpf"
local manual_adjustments = {}
local MANUAL_ADJUSTMENT_DURATION = 0.5

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

local last_random_sample = nil  
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
    if #audio_files == 0 then return false end
    local selected_file
    if not last_random_sample then
        selected_file = audio_files[math.random(1, #audio_files)]
        last_random_sample = selected_file
    else
        if math.random() < 0.5 then
            selected_file = last_random_sample
        else
            selected_file = audio_files[math.random(1, #audio_files)]
            while selected_file == last_random_sample and #audio_files > 1 do
                selected_file = audio_files[math.random(1, #audio_files)]
            end
        end
        last_random_sample = nil
    end
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
    params:set_action("randomize_params", function() load_random_tape_file(1) load_random_tape_file(2) end)
    
    params:add_separator("Settings")

    params:add_group("Granular", 30)
    params:add_control("shimmer_mix", "Shimmer", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("shimmer_mix", function(x) engine.shimmer_mix(x/100) end)
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
    params:add_taper("modDepth", "Modulation Depth", 0, 100, 10, 0, "%") params:set_action("modDepth", function(value) engine.modDepth(value/100) end)
    params:add_taper("modFreq", "Modulation Freq.", 0, 10, 2, 0, "Hz") params:set_action("modFreq", function(value) engine.modFreq(value) end)
    params:add_taper("low", "Low", 0, 100, 100, 0, "%") params:set_action("low", function(value) engine.low(value/100) end)
    params:add_taper("mid", "Mid", 0, 100, 100, 0, "%") params:set_action("mid", function(value) engine.mid(value/100) end)
    params:add_taper("high", "High", 0, 100, 100, 0, "%") params:set_action("high", function(value) engine.high(value/100) end)
    params:add_taper("lowcut", "Low Cut", 100, 6000, 500, 2, "Hz") params:set_action("lowcut", function(value) engine.lowcut(value) end)
    params:add_taper("highcut", "High Cut", 1000, 10000, 2000, 2, "Hz") params:set_action("highcut", function(value) engine.highcut(value) end)
    params:add_separator("  ")
    params:add_binary("randomize_jpverb", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_jpverb", function() randpara.randomize_jpverb_params(steps) end)
    params:add_option("lock_reverb", "Lock Parameters", {"off", "on"}, 1)
    
    params:add_group("Tape", 11)
    params:add_control("sine_wet", "Drive Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("sine_wet", function(value) engine.sine_wet(1, value / 100) engine.sine_wet(2, value / 100) end)
    params:add_control("sine_drive", "Drive", controlspec.new(0, 5, "lin", 0.01, 1, "")) params:set_action("sine_drive", function(value) engine.sine_drive(1, value) engine.sine_drive(2, value) end)
    params:add{type = "control", id = "wobble_wet", name = "Wobble Mix", controlspec = controlspec.new(0, 100, "lin", 1, 0, "%"), action = function(value) engine.wobble_wet(1, value/100) engine.wobble_wet(2, value/100) end}
    params:add{type = "control", id = "wobble_amp", name = "Wow Amount", controlspec = controlspec.new(0, 100, "lin", 1, 25, "%"), action = function(value) engine.wobble_amp(1, value/100) engine.wobble_amp(2, value/100) end}
    params:add{type = "control", id = "wobble_rpm", name = "Wow Speed", controlspec = controlspec.new(30, 90, "lin", 1, 33, "RPM"), action = function(value) engine.wobble_rpm(1, value) engine.wobble_rpm(2, value) end}
    params:add{type = "control", id = "flutter_amp", name = "Flutter Amt", controlspec = controlspec.new(0, 100, "lin", 1, 25, "%"), action = function(value) engine.flutter_amp(1, value/100) engine.flutter_amp(2, value/100) end}
    params:add{type = "control", id = "flutter_freq", name = "Flutter Freq", controlspec = controlspec.new(3, 30, "lin", 0.01, 6, "Hz"), action = function(value) engine.flutter_freq(1, value) engine.flutter_freq(2, value) end}
    params:add{type = "control", id = "flutter_var", name = "Flutter Var", controlspec = controlspec.new(0.1, 10, "lin", 0.01, 2, "Hz"), action = function(value) engine.flutter_var(1, value) engine.flutter_var(2, value) end}
    params:add_separator("    ")
    params:add_binary("randomize_tape", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_tape", function() randpara.randomize_tape_params(steps) end)
    params:add_option("lock_tape", "Lock Parameters", {"off", "on"}, 1)
    
    params:add_group("EQ", 6)
    params:add_control("eq_low_gain_1", "1 Bass", controlspec.new(-1, 1, "lin", 0.01, 0, ""))
    params:set_action("eq_low_gain_1", function(value) engine.eq_low_gain(1, value*45) end)
    params:add_control("eq_high_gain_1", "1 Treble", controlspec.new(-1, 1, "lin", 0.01, 0, ""))
    params:set_action("eq_high_gain_1", function(value) engine.eq_high_gain(1, value*45) end)
    params:add_control("eq_low_gain_2", "2 Bass", controlspec.new(-1, 1, "lin", 0.01, 0, ""))
    params:set_action("eq_low_gain_2", function(value) engine.eq_low_gain(2, value*45) end)
    params:add_control("eq_high_gain_2", "2 Treble", controlspec.new(-1, 1, "lin", 0.01, 0, ""))
    params:set_action("eq_high_gain_2", function(value) engine.eq_high_gain(2, value*45) end)
    params:add_separator("     ")
    params:add_option("lock_eq", "Lock Parameters", {"off", "on"}, 1)

    params:add_group("Stereo Width", 2)
    for i = 1, 2 do
      params:add_control(i .. "Width", i .. " Width", controlspec.new(0, 200, "lin", 0.01, 100, "%"))
      params:set_action(i .. "Width", function(value) engine.width(i, value / 100) end)
    end  

    params:add_group("LFOs", 117)
    params:add_binary("randomize_lfos", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_lfos", function() lfo.clearLFOs("1") lfo.clearLFOs("2") lfo.randomize_lfos("1", params:get("allow_volume_lfos") == 2)  lfo.randomize_lfos("2", params:get("allow_volume_lfos") == 2) if randomize_metro[1] then randomize_metro[1]:stop() end if randomize_metro[2] then randomize_metro[2]:stop() end end)
    params:add_binary("lfo.assign_to_current_row", "Assign to Selection", "trigger", 0) params:set_action("lfo.assign_to_current_row", function() lfo.assign_to_current_row(current_mode, current_filter_mode) end)
    params:add_binary("ClearLFOs", "Clear All LFOs", "trigger", 0) params:set_action("ClearLFOs", function() lfo.clearLFOs() end)
    params:add_option("allow_volume_lfos", "Allow Volume LFOs", {"no", "yes"}, 2)
    params:add_control("global_lfo_freq_scale", "Freq Scale", controlspec.new(0.1, 10, "exp", 0.01, 1.0, "x")) params:set_action("global_lfo_freq_scale", function(value) 
    for i = 1, 16 do 
      lfo[i].base_freq = params:get(i .. "lfo_freq")
      lfo[i].freq = lfo[i].base_freq * value
    end 
    end)
    lfo.init()

    for i = 1, 2 do
      params:add_taper(i .. "volume", i .. " volume", -70, 20, 0, 0, "dB") params:set_action(i .. "volume", function(value) if value == -70 then engine.volume(i, 0) else engine.volume(i, math.pow(10, value / 20)) end end)
      params:add_taper(i .. "pan", i .. " pan", -100, 100, 0, 0, "%") params:set_action(i .. "pan", function(value) engine.pan(i, value / 100)  end)
      params:add_taper(i .. "speed", i .. " speed", -2, 2, 0.10, 0) params:set_action(i .. "speed", function(value) engine.speed(i, value) end)
      params:add_taper(i .. "density", i .. " density", 0.1, 300, 10, 5) params:set_action(i .. "density", function(value) engine.density(i, value) end)
      params:add_control(i .. "pitch", i .. " pitch", controlspec.new(-48, 48, "lin", 1, 0, "st")) params:set_action(i .. "pitch", function(value) engine.pitch_offset(i, math.pow(0.5, -value / 12)) end)
      params:add_taper(i .. "jitter", i .. " jitter", 0, 4999, 250, 3, "ms") params:set_action(i .. "jitter", function(value) engine.jitter(i, value / 1000) end)
      params:add_taper(i .. "size", i .. " size", 1, 999, 100, 1, "ms") params:set_action(i .. "size", function(value) engine.size(i, value / 1000) end)
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

    params:add_group("Limits", 14)
    params:add_taper("min_jitter", "jitter (min)", 0, 4999, 100, 5, "ms")
    params:add_taper("max_jitter", "jitter (max)", 0, 4999, 1999, 5, "ms")
    params:add_taper("min_size", "size (min)", 1, 999, 100, 5, "ms")
    params:add_taper("max_size", "size (max)", 1, 999, 599, 5, "ms")
    params:add_taper("min_density", "density (min)", 0.1, 50, 1, 5, "Hz")
    params:add_taper("max_density", "density (max)", 0.1, 50, 16, 5, "Hz")
    params:add_taper("min_spread", "spread (min)", 0, 100, 0, 0, "%")
    params:add_taper("max_spread", "spread (max)", 0, 100, 90, 0, "%")
    params:add_control("min_pitch", "pitch (min)", controlspec.new(-48, 48, "lin", 1, -31, "st"))
    params:add_control("max_pitch", "pitch (max)", controlspec.new(-48, 48, "lin", 1, 31, "st"))
    params:add_taper("min_speed", "speed (min)", -2, 2, 0, 0, "x")
    params:add_taper("max_speed", "speed (max)", -2, 2, 1, 0, "x")
    params:add_taper("min_seek", "seek (min)", 0, 100, 0, 0, "%")
    params:add_taper("max_seek", "seek (max)", 0, 100, 100, 0, "%")

    params:add_group("Locking", 16)
    for i = 1, 2 do
      params:add_option(i .. "lock_jitter", i .. " lock jitter", {"off", "on"}, 1)
      params:add_option(i .. "lock_size", i .. " lock size", {"off", "on"}, 1)
      params:add_option(i .. "lock_density", i .. " lock density", {"off", "on"}, 1)
      params:add_option(i .. "lock_spread", i .. " lock spread", {"off", "on"}, 1)
      params:add_option(i .. "lock_pitch", i .. " lock pitch", {"off", "on"}, 1)
      params:add_option(i .. "lock_pan", i .. " lock pan", {"off", "on"}, 1)
      params:add_option(i .. "lock_seek", i .. " lock seek", {"off", "on"}, 1)
      params:add_option(i .. "lock_speed", i .. " lock speed", {"off", "on"}, 1)
    end

    params:add_group("Other", 2)
    params:add_separator("Transition Steps")
    params:add_control("steps","Steps",controlspec.new(10,20000,"lin",1,400)) params:set_action("steps", function(value) steps = value end)
    
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
      pitch = {lock = params:get(n.."lock_pitch")==1, param_name = n.."pitch"}}
    local current_pitch = params:get(n .. "pitch")
    local min_pitch = math.max(params:get("min_pitch"), current_pitch - 48)
    local max_pitch = math.min(params:get("max_pitch"), current_pitch + 48)
    local base_pitch = params:get(n == 1 and "2pitch" or "1pitch")
    if param_config.pitch.lock and not active_controlled_params[param_config.pitch.param_name] then
        if min_pitch < max_pitch and not is_lfo_active_for_param(param_config.pitch.param_name) then
            local weighted_intervals = {
                [-12] = 3, [-7] = 2, [-5] = 2, [-3] = 1,
                [0] = 2, [3] = 1, [5] = 2, [7] = 2, [12] = 3}
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
                        break
                    end
                end
            else
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

    local targets = {}
    for param, config in pairs(param_config) do
        if param ~= "pitch" then
            if config.lock and not active_controlled_params[config.param_name] then
                local min_val = config.min and params:get(config.min) or config.min
                local max_val = config.max and params:get(config.max) or config.max
                    if min_val < max_val and not is_lfo_active_for_param(config.param_name) then
                    targets[config.param_name] = random_float(min_val, max_val)
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

function init()
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
    local param_modes = {
      speed = {param = "speed", delta = 0.5, has_lock = true},
      seek = {param = "seek", delta = 1, wrap = {0, 100}, engine = true, has_lock = true},
      pan = {param = "pan", delta = 5, has_lock = true},
      lpf = {param = "cutoff", delta = 1, has_lock = false},
      hpf = {param = "hpf", delta = 1, has_lock = false},
      jitter = {param = "jitter", delta = 2, has_lock = true},
      size = {param = "size", delta = 2, has_lock = true},
      density = {param = "density", delta = 2, has_lock = true},
      spread = {param = "spread", delta = 2, has_lock = true},
      pitch = {param = "pitch", delta = 1, has_lock = true}
    }
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
                local mode = (current_mode == "lpf" or current_mode == "hpf") and current_filter_mode or current_mode
                local config = param_modes[mode]
                local param_name = track .. config.param
                if not config.has_lock or params:get(track .. "lock_" .. config.param) ~= 2 then
                    active_controlled_params[param_name] = true
                    local is_active, lfo_index = is_lfo_active_for_param(param_name)
                    if is_active then params:set(lfo_index .. "lfo", 1) end
                    manual_adjustments[param_name] = manual_adjustments[param_name] or {}
                    manual_adjustments[param_name].active = true
                    manual_adjustments[param_name].value = params:get(param_name)
                    manual_adjustments[param_name].time = util.time()
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
        end,
        [3] = function()
            local track = 2
            if key1_pressed then 
                local is_active, lfo_index = is_lfo_active_for_param("2volume")
                if is_active then params:set(lfo_index .. "lfo", 1) end
                params:delta("2volume", 3*d)
            else
                local mode = (current_mode == "lpf" or current_mode == "hpf") and current_filter_mode or current_mode
                local config = param_modes[mode]
                local param_name = track .. config.param
                if not config.has_lock or params:get(track .. "lock_" .. config.param) ~= 2 then
                    active_controlled_params[param_name] = true
                    local is_active, lfo_index = is_lfo_active_for_param(param_name)
                    if is_active then params:set(lfo_index .. "lfo", 1) end
                    manual_adjustments[param_name] = manual_adjustments[param_name] or {}
                    manual_adjustments[param_name].active = true
                    manual_adjustments[param_name].value = params:get(param_name)
                    manual_adjustments[param_name].time = util.time()
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
        end
    }
    if enc_actions[n] then enc_actions[n]() end
end

function key(n, z)
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
                redraw()
            elseif n == 3 then
                local modes = {"speed", "seek", "pan", "lpf", "jitter", "size", "density", "spread", "pitch"}
                local current_index = table.find(modes, current_mode) or 1
                current_mode = modes[(current_index % #modes) + 1]
                redraw()
            end
        end
    end
    if key2_pressed and key3_pressed then
        if current_mode == "lpf" or current_mode == "hpf" then
            current_filter_mode = current_filter_mode == "lpf" and "hpf" or "lpf"
            redraw()
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

local function format_speed(speed)
    if math.abs(speed) < 1 then
        if speed < -0.008 then return string.format("-.%02dx", math.floor(math.abs(speed) * 100))
        else return string.format(".%02dx", math.floor(math.abs(speed) * 100)) end
    else return string.format("%.2fx", speed) end
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
            if manual_adjustments[param] and manual_adjustments[param].active then
                local bar_value = util.linlin(min_val, max_val, 0, bar_width, manual_adjustments[param].value)
                screen.level(6)
                screen.rect(x, y + 1, bar_value, bar_height)
                screen.fill()
            else
                local lfo_mod = get_lfo_modulation(param)
                if lfo_mod then
                    local bar_value = util.linlin(min_val, max_val, 0, bar_width, lfo_mod)
                    screen.level(6)
                    screen.rect(x, y + 1, bar_value, bar_height)
                    screen.fill()
                end
            end
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
    screen.fill()
end

function redraw()
    local current_time = util.time()
    for param, adjustment in pairs(manual_adjustments) do
        if adjustment and adjustment.time and (current_time - adjustment.time > MANUAL_ADJUSTMENT_DURATION) then
            adjustment.active = false
        end
    end
    screen.clear()
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
            screen.fill()
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
            screen.fill()
        end
    end
    screen.update()
end

function cleanup()
  if ui_metro then ui_metro:stop() end
  for i = 1, 2 do
    if randomize_metro[i] then randomize_metro[i]:stop() end
  end
  lfo.cleanup()
end