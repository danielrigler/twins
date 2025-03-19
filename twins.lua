--
--
--  __ __|         _)          
--     | \ \  \  / |  \ |  (_< 
--     |  \_/\_/ _| _| _| __/ 
--           by: @dddstudio                       
--
--                          
--                            v0.17
-- E1: Master Volume
-- K1+E2/E3: Volume 1/2
-- K1+E1: Crossfade Volumes
-- K2/K3: Navigate
-- E2/E3: Adjust Parameters
-- K2+K3: Lock Parameters
-- K2+K3: HP/LP Filter 
-- K1+K2/K3: Randomize 1/2
-- K1+K2/K3 x2: Stop Randomize
--
--
--
--              
--
--
--
--
-- If you like this,
-- buy them a beer :)
-- @infinitedigits @cfdrake 
-- @justmat @artfwo @nzimas
-- @sonoCircuit

local lfo = include("lib/lfo")
local randpara = include("lib/randpara")
delay = include("lib/delay")
installer_ = include("lib/scinstaller/scinstaller")
installer = installer_:new{requirements = {"Fverb","AnalogChew"}, 
  zip = "https://github.com/schollz/portedplugins/releases/download/v0.4.6/PortedPlugins-RaspberryPi.zip"}
engine.name = installer:ready() and 'twins' or nil

local ui_metro
local randomize_metro = { [1] = nil, [2] = nil }
local key1_pressed, key2_pressed, key3_pressed = false
local current_mode = "speed"
local current_filter_mode = "lpf"

-- New variables for double press detection
local last_key2_press_time = 0
local last_key3_press_time = 0
local double_press_threshold = 0.3 -- seconds

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
        -- Get the target parameter name for the LFO
        local target_index = params:get(i .. "lfo_target")
        local target_param = lfo.lfo_targets[target_index]
        if target_param == param_name and params:get(i .. "lfo") == 2 then
            return true, i
        end
    end
    return false, nil
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

    params:add_separator("Actions")
    
    params:add_binary("randomize_params", "R a N d 0 m 1 z e", "trigger", 0) params:set_action("randomize_params", function() randpara.randomize_params(steps) end)
    params:add_binary("randomize_lfos", "RaNd0m1ze LFOs", "trigger", 0) params:set_action("randomize_lfos", function() lfo.randomize_lfos() if randomize_metro[1] then randomize_metro[1]:stop() end if randomize_metro[2] then randomize_metro[2]:stop() end end)
    params:add_binary("ClearLFOs", "Clear All LFOs", "trigger", 0) params:set_action("ClearLFOs", function() lfo.clearLFOs() end)
    
    params:add_separator("Settings")

    params:add_group("Delay", 3)
    delay.init()
    
    params:add_group("Greyhole", 8)
    params:add_control("greyhole_mix", "Mix", controlspec.new(0.0, 1.0, "lin", 0.01, 0.5, "")) params:set_action("greyhole_mix", function(value) engine.greyhole_mix(value) end)
    params:add_control("time", "Time", controlspec.new(0.00, 10.00, "lin", 0.01, 3, "")) params:set_action("time", function(value) engine.greyhole_delay_time(value) end)
    params:add_control("size", "Size", controlspec.new(0.5, 5.0, "lin", 0.01, 4.00, "")) params:set_action("size", function(value) engine.greyhole_size(value) end)
    params:add_control("damp", "Damping", controlspec.new(0.0, 1.0, "lin", 0.01, 0.1, "")) params:set_action("damp", function(value) engine.greyhole_damp(value) end)
    params:add_control("diff", "Diffusion", controlspec.new(0.0, 1.0, "lin", 0.01, 0.5, "")) params:set_action("diff", function(value) engine.greyhole_diff(value) end)
    params:add_control("feedback", "Feedback", controlspec.new(0.00, 1.0, "lin", 0.01, 0.22, "")) params:set_action("feedback", function(value) engine.greyhole_feedback(value) end)
    params:add_control("mod_depth", "Mod depth", controlspec.new(0.0, 1.0, "lin", 0.01, 0.85, "")) params:set_action("mod_depth", function(value) engine.greyhole_mod_depth(value) end)
    params:add_control("mod_freq", "Mod freq", controlspec.new(0.0, 10.0, "lin", 0.01, 0.7, "Hz")) params:set_action("mod_freq", function(value) engine.greyhole_mod_freq(value) end)
    
    params:add_group("Fverb", 12)
    params:add_taper("reverb_mix", "Mix", 0, 100, 17.5, 0, "%") params:set_action("reverb_mix", function(value) engine.reverb_mix(value / 100) end)
    params:add_taper("reverb_predelay", "Predelay", 0, 250, 20, 0, "ms") params:set_action("reverb_predelay", function(value) engine.reverb_predelay(value) end)
    params:add_taper("reverb_input_amount", "Input amount", 0, 100, 100, 0, "%") params:set_action("reverb_input_amount", function(value) engine.reverb_input_amount(value) end)
    params:add_taper("reverb_lowpass_cutoff", "Lowpass cutoff", 0, 20000, 8000, 0, "Hz") params:set_action("reverb_lowpass_cutoff", function(value) engine.reverb_lowpass_cutoff(value) end)
    params:add_taper("reverb_highpass_cutoff", "Highpass cutoff", 0, 20000, 75, 0, "Hz") params:set_action("reverb_highpass_cutoff", function(value) engine.reverb_highpass_cutoff(value) end)
    params:add_taper("reverb_diffusion_1", "Diffusion 1", 0, 100, 85, 0, "%") params:set_action("reverb_diffusion_1", function(value) engine.reverb_diffusion_1(value) end)
    params:add_taper("reverb_diffusion_2", "Diffusion 2", 0, 100, 85, 0, "%") params:set_action("reverb_diffusion_2", function(value) engine.reverb_diffusion_2(value) end)
    params:add_taper("reverb_tail_density", "Tail density", 0, 100, 75, 0, "%") params:set_action("reverb_tail_density", function(value) engine.reverb_tail_density(value) end)
    params:add_taper("reverb_decay", "Decay", 0, 100, 80, 0, "%") params:set_action("reverb_decay", function(value) engine.reverb_decay(value) end)
    params:add_taper("reverb_damping", "Damping", 0, 20000, 6000, 0, "Hz") params:set_action("reverb_damping", function(value) engine.reverb_damping(value) end)
    params:add_taper("reverb_modulator_frequency", "Modulator frequency", 0, 10, 1, 0, "Hz") params:set_action("reverb_modulator_frequency", function(value) engine.reverb_modulator_frequency(value) end)
    params:add_taper("reverb_modulator_depth", "Modulator depth", 0, 100, 40, 0, "%") params:set_action("reverb_modulator_depth", function(value) engine.reverb_modulator_depth(value / 100) end)
    
    params:add_group("Shimmer+", 10)
    for i = 1, 2 do
      params:add_control(i .. "shimmer", i .. " Shimmer", controlspec.new(0, 100, "lin", 1, 0, "%"))
      params:set_action(i.. "shimmer", function(value) engine.shimmer(i, value/50) end)
      params:add_control(i .. "subharmonics_2", i .. " Subharmonics -2oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0))
      params:set_action(i .. "subharmonics_2", function(value) engine.subharmonics_2(i, value) end)
      params:add_control(i .. "subharmonics_1", i .. " Subharmonics -1oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0))
      params:set_action(i .. "subharmonics_1", function(value) engine.subharmonics_1(i, value) end)
      params:add_control(i .. "overtones_1", i .. " Overtones +1oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0))
      params:set_action(i .. "overtones_1", function(value) engine.overtones_1(i, value) end)
      params:add_control(i .. "overtones_2", i .. " Overtones +2oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0))
      params:set_action(i .. "overtones_2", function(value) engine.overtones_2(i, value) end)
    end

    params:add_group("Filters", 8)
    params:add_control("1cutoff","1 LPF cutoff",controlspec.new(20,20000,"exp",0,20000,"Hz")) params:set_action("1cutoff",function(value) engine.cutoff(1,value) end)
    params:add_control("1q","1 LPF resonance",controlspec.new(0,4,"lin",0.01,0)) params:set_action("1q",function(value) engine.q(1,value) end)
    params:add_control("2cutoff","2 LPF cutoff",controlspec.new(20,20000,"exp",0,20000,"Hz")) params:set_action("2cutoff",function(value) engine.cutoff(2,value) end)
    params:add_control("2q","2 LPF resonance",controlspec.new(0,4,"lin",0.01,0)) params:set_action("2q",function(value) engine.q(2,value) end)
    params:add_control("1hpf", "1 HPF cutoff", controlspec.new(20, 20000, "exp", 0, 20, "Hz")) params:set_action("1hpf", function(value) engine.hpf(1, value) end)
    params:add_control("1hpfrq","1 HPF resonance",controlspec.new(0,1,"lin",0.01,1)) params:set_action("1hpfrq",function(value) engine.hpfrq(1,value) end)
    params:add_control("2hpf", "2 HPF cutoff", controlspec.new(20, 20000, "exp", 0, 20, "Hz")) params:set_action("2hpf", function(value) engine.hpf(2, value) end)
    params:add_control("2hpfrq","2 HPF resonance",controlspec.new(0,1,"lin",0.01,1)) params:set_action("2hpfrq",function(value) engine.hpfrq(2,value) end)
    
    params:add_group("Tape", 6)
    params:add_control("sine_wet", "Shaper Drive Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("sine_wet", function(value) engine.sine_wet(1, value / 100) engine.sine_wet(2, value / 100) end)
    params:add_control("sine_drive", "Shaper Drive", controlspec.new(0, 5, "lin", 0.01, 1, "")) params:set_action("sine_drive", function(value) engine.sine_drive(1, value) engine.sine_drive(2, value) end)
    params:add{type = "control", id = "chew_wet", name = "Chew Mix", controlspec = controlspec.new(0, 100, "lin", 1, 0, "%"), action = function(value) engine.chew_wet(1, value /100) engine.chew_wet(2, value / 100) end}
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

    params:add_group("LFOs", 113)
    params:add_control("global_lfo_freq_scale", "Freq Scale", controlspec.new(0.1, 10, "exp", 0.01, 1.0, "x")) 
    params:set_action("global_lfo_freq_scale", function(value) for i = 1, 16 do lfo[i].freq = lfo[i].base_freq * value end end)
    lfo.init()

    params:add_group("Extras", 11)
    for i = 1, 2 do
      params:add_taper(i .. "granular_gain", i .. " Granular Mix", 0, 100, 100, 0, "%")
      params:set_action(i .. "granular_gain", function(value) engine.granular_gain(i, value / 100) end)
      params:add_option(i .. "pitch_mode", i .. " Pitch Mode", {"match speed", "independent"}, 2)
      params:set_action(i .. "pitch_mode", function(value) engine.pitch_mode(i, value - 1) end)
      params:add_control(i .. "direction_mod", i .. " Reverse", controlspec.new(0, 100, "lin", 1, 0, "%"))
      params:set_action(i .. "direction_mod", function(value) engine.direction_mod(i, value / 100) end)
      params:add_control(i .. "size_variation", i .. " Size Variation", controlspec.new(0, 100, "lin", 1, 0, "%"))
      params:set_action(i .. "size_variation", function(value) engine.size_variation(i, value / 100) end)
      params:add_taper(i .. "density_mod_amt", i .. " Density Mod", 0, 100, 0, 0, "%")
      params:set_action(i .. "density_mod_amt", function(value) engine.density_mod_amt(i, value / 100) end)
    end
  
    params:add_control("volume_compensation", "Volume compensation", controlspec.new(0,1,"lin",0.01,0.1)) params:set_action("volume_compensation", function(value) engine.compensation_factor(1,value) engine.compensation_factor(2,value) end)
    
    for i = 1, 2 do
      params:add_taper(i .. "volume", i .. " volume", -70, 20, 0, 0, "dB") params:set_action(i .. "volume", function(value) if value == -70 then engine.volume(i, 0) else engine.volume(i, math.pow(10, value / 20)) end end)
      params:add_taper(i .. "pan", i .. " pan", -100, 100, 0, 0, "%") params:set_action(i .. "pan", function(value) engine.pan(i, value / 100)  end)
      params:add_control(i .. "speed", i .. " speed", controlspec.new(-2, 2, "lin", 0.01, 0.1, "")) params:set_action(i .. "speed", function(value) engine.speed(i, value) end)
      params:add_taper(i .. "density", i .. " density", 1, 30, 20, 1) params:set_action(i .. "density", function(value) engine.density(i, value) end)
      params:add_control(i .. "pitch", i .. " pitch", controlspec.new(-48, 48, "lin", 1, 0, "st")) params:set_action(i .. "pitch", function(value) engine.pitch_offset(i, math.pow(0.5, -value / 12)) end)
      params:add_taper(i .. "jitter", i .. " jitter", 0, 1999, 250, 5, "ms") params:set_action(i .. "jitter", function(value) engine.jitter(i, value / 1000) end)
      params:add_taper(i .. "size", i .. " size", 1, 999, 100, 5, "ms") params:set_action(i .. "size", function(value) engine.size(i, value / 1000) end)
      params:add_taper(i .. "spread", i .. " spread", 0, 100, 0, 0, "%") params:set_action(i .. "spread", function(value) engine.spread(i, value / 100) end)
      params:add_control(i .. "seek", i .. " seek", controlspec.new(0, 100, "lin", 0.01, 0, "%")) params:set_action(i .. "seek", function(value) engine.seek(i, value) end)
      params:add_taper(i .."fade", i .." att / dec", 1, 9000, 1000, 3, "ms") params:set_action(i .."fade", function(value) engine.envscale(i, value / 1000) end)

      params:hide(i .. "speed")
      params:hide(i .. "jitter")
      params:hide(i .. "size")
      params:hide(i .. "density")
      params:hide(i .. "pitch")
      params:hide(i .. "spread")
      params:hide(i .. "fade")
      params:hide(i .. "seek")
      params:hide(i .. "pan")
      params:hide(i .. "volume")
    end

    params:add_group("Limits", 10)
    params:add_taper("min_jitter", "jitter (min)", 0, 1999, 100, 5, "ms")
    params:add_taper("max_jitter", "jitter (max)", 0, 1999, 1999, 5, "ms")
    params:add_taper("min_size", "size (min)", 1, 999, 100, 5, "ms")
    params:add_taper("max_size", "size (max)", 1, 999, 599, 5, "ms")
    params:add_taper("min_density", "density (min)", 1, 30, 1, 5, "Hz")
    params:add_taper("max_density", "density (max)", 1, 30, 16, 5, "Hz")
    params:add_taper("min_spread", "spread (min)", 0, 100, 0, 0, "%")
    params:add_taper("max_spread", "spread (max)", 0, 100, 90, 0, "%")
    params:add_control("min_pitch", "pitch (min)", controlspec.new(-48, 48, "lin", 1, -48, "st"))
    params:add_control("max_pitch", "pitch (max)", controlspec.new(-48, 48, "lin", 1, 48, "st"))

    params:add_group("Locking", 12)
    for i = 1, 2 do
      params:add_option(i .. "lock_jitter", i .. " lock jitter", {"off", "on"}, 1)
      params:add_option(i .. "lock_size", i .. " lock size", {"off", "on"}, 1)
      params:add_option(i .. "lock_density", i .. " lock density", {"off", "on"}, 1)
      params:add_option(i .. "lock_spread", i .. " lock spread", {"off", "on"}, 1)
      params:add_option(i .. "lock_pitch", i .. " lock pitch", {"off", "on"}, 1)
      params:add_option(i .. "lock_pan", i .. " lock pan", {"off", "on"}, 1)
    end
    
    params:add_control("steps","Transition steps",controlspec.new(10,2000,"lin",1,400)) params:set_action("steps", function(value) steps = value end)
    
    params:bang()
end

local function interpolate(start_val, end_val, factor)
    return start_val + (end_val - start_val) * factor
end

local active_controlled_params = {} -- Track which parameters are being controlled by encoders

local function randomize(n)
    if not randomize_metro[n] then randomize_metro[n] = metro.init() end

    -- Clear the active_controlled_params table at the start of each randomization
    active_controlled_params = {}

    local targets = {}
    local locks = {
        jitter = params:get(n .. "lock_jitter") == 1,
        size = params:get(n .. "lock_size") == 1,
        density = params:get(n .. "lock_density") == 1,
        spread = params:get(n .. "lock_spread") == 1,
        pitch = params:get(n .. "lock_pitch") == 1
    }

    -- Randomize non-pitch parameters
    if locks.jitter and not active_controlled_params[n .. "jitter"] then 
        local min_jitter = params:get("min_jitter")
        local max_jitter = params:get("max_jitter")
        if min_jitter < max_jitter then
            local is_lfo_active, _ = is_lfo_active_for_param(n .. "jitter")
            if not is_lfo_active then
                targets[n .. "jitter"] = random_float(min_jitter, max_jitter)
            end
        end
    end
    if locks.size and not active_controlled_params[n .. "size"] then 
        local min_size = params:get("min_size")
        local max_size = params:get("max_size")
        if min_size < max_size then
            local is_lfo_active, _ = is_lfo_active_for_param(n .. "size")
            if not is_lfo_active then
                targets[n .. "size"] = random_float(min_size, max_size)
            end
        end
    end
    if locks.density and not active_controlled_params[n .. "density"] then 
        local min_density = params:get("min_density")
        local max_density = params:get("max_density")
        if min_density < max_density then
            local is_lfo_active, _ = is_lfo_active_for_param(n .. "density")
            if not is_lfo_active then
                targets[n .. "density"] = random_float(min_density, max_density)
            end
        end
    end
    if locks.spread and not active_controlled_params[n .. "spread"] then 
        local min_spread = params:get("min_spread")
        local max_spread = params:get("max_spread")
        if min_spread < max_spread then
            local is_lfo_active, _ = is_lfo_active_for_param(n .. "spread")
            if not is_lfo_active then
                targets[n .. "spread"] = random_float(min_spread, max_spread)
            end
        end
    end

-- Randomize pitch parameter
if locks.pitch and not active_controlled_params[n .. "pitch"] then
    local weighted_intervals = {
        {interval = -12, weight = 3},
        {interval = -7, weight = 2},
        {interval = -5, weight = 2},
        {interval = -3, weight = 1},
        {interval = 0, weight = 2},
        {interval = 3, weight = 1},
        {interval = 5, weight = 2},
        {interval = 7, weight = 2},
        {interval = 12, weight = 3}
    }

    local current_pitch = params:get(n .. "pitch")
    local min_pitch = math.max(params:get("min_pitch"), current_pitch - 48)
    local max_pitch = math.min(params:get("max_pitch"), current_pitch + 48)

    if min_pitch < max_pitch and not is_lfo_active_for_param(n .. "pitch") then
        local base_pitch = params:get(n == 1 and "2pitch" or "1pitch")

        -- Function to check if a pitch is within bounds
        local function is_pitch_valid(pitch)
            return pitch >= min_pitch and pitch <= max_pitch
        end

        -- Try to find a valid interval from the weighted_intervals table
        local valid_intervals = {}
        for _, v in ipairs(weighted_intervals) do
            local candidate_pitch = base_pitch + v.interval
            if is_pitch_valid(candidate_pitch) then
                table.insert(valid_intervals, v)
            end
        end

        -- If no valid intervals are found, allow larger steps
        if #valid_intervals == 0 then
            -- Allow larger steps, but still prioritize musical intervals
            local larger_intervals = {-24, -19, -17, -15, 15, 17, 19, 24}
            for _, interval in ipairs(larger_intervals) do
                local candidate_pitch = base_pitch + interval
                if is_pitch_valid(candidate_pitch) then
                    params:set(n .. "pitch", candidate_pitch)
                    return -- Exit after setting the pitch
                end
            end
        else
            -- Choose a random interval from the valid_intervals table
            local total_weight = 0
            for _, v in ipairs(valid_intervals) do
                total_weight = total_weight + v.weight
            end

            local random_weight = math.random(total_weight)
            local cumulative_weight = 0
            local chosen_interval = 0

            for _, v in ipairs(valid_intervals) do
                cumulative_weight = cumulative_weight + v.weight
                if random_weight <= cumulative_weight then
                    chosen_interval = v.interval
                    break
                end
            end

            local random_pitch = base_pitch + chosen_interval
            params:set(n .. "pitch", random_pitch)
        end
    end
end

    -- Start the interpolation metro
    randomize_metro[n].time = 1/30
    randomize_metro[n].event = function(count)
        local tolerance = 0.01
        local factor = count / steps
        local all_done = true  -- Flag to track if all parameters have reached their targets

        for param, target in pairs(targets) do
            if not active_controlled_params[param] then -- Skip if the parameter is being controlled by an encoder
                local current_value = params:get(param)
                local new_value = interpolate(current_value, target, factor)
                params:set(param, new_value)
                if math.abs(new_value - target) >= tolerance then all_done = false end
            end
        end
        if all_done then randomize_metro[n]:stop() end
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
    if not installer:ready() then do return end end

    local enc_actions = {
        [1] = function()
            if key1_pressed then
                -- Adjust volumes in opposite directions
                params:delta("1volume", 3*d)    
                params:delta("2volume", -3*d)    
            else
                -- Normal behavior: adjust both volumes in the same direction
                params:delta("1volume", 3*d)    
                params:delta("2volume", 3*d)    
            end
        end,
        [2] = function()
            if key1_pressed then 
                params:delta("1volume", 3*d) 
            else
                local param_name
                if current_mode == "speed" then param_name = "1speed"
                elseif current_mode == "seek" then param_name = "1seek"
                elseif current_mode == "pan" then param_name = "1pan"
                elseif current_mode == "lpf" or current_mode == "hpf" then
                    -- Use current_filter_mode to decide whether to adjust LPF or HPF
                    if current_filter_mode == "lpf" then
                        param_name = "1cutoff"  -- Adjust LPF cutoff
                    else
                        param_name = "1hpf"     -- Adjust HPF cutoff
                    end
                elseif current_mode == "jitter" then param_name = "1jitter"
                elseif current_mode == "size" then param_name = "1size"
                elseif current_mode == "density" then param_name = "1density"
                elseif current_mode == "spread" then param_name = "1spread"
                elseif current_mode == "pitch" then param_name = "1pitch"
                end

                -- Mark the parameter as being controlled by the encoder
                active_controlled_params[param_name] = true

                -- Check if an LFO is active for the parameter
                local is_active, lfo_index = is_lfo_active_for_param(param_name)
                if is_active then params:set(lfo_index .. "lfo", 1) -- Deactivate the LFO
                end

                -- Adjust the parameter
                if current_mode == "speed" then params:delta("1speed", 0.5 * d)
                elseif current_mode == "seek" then local current_seek = params:get("1seek")
                    local new_seek = wrap_value(current_seek + d, 0, 100)
                    params:set("1seek", new_seek)
                    engine.seek(1, new_seek / 100)
                elseif current_mode == "pan" then params:delta("1pan", d * 5)
                elseif current_mode == "lpf" or current_mode == "hpf" then
                    if current_filter_mode == "lpf" then
                        params:delta("1cutoff", d)
                    else
                        params:delta("1hpf", d)
                    end
                elseif current_mode == "jitter" then params:delta("1jitter", d * 2)
                elseif current_mode == "size" then params:delta("1size", d * 2)
                elseif current_mode == "density" then params:delta("1density", d * 2)
                elseif current_mode == "spread" then params:delta("1spread", d * 2)
                elseif current_mode == "pitch" then params:delta("1pitch", d)
                end
            end
        end,
        [3] = function()
            if key1_pressed then 
                params:delta("2volume", 3*d) 
            else
                local param_name
                if current_mode == "speed" then param_name = "2speed"
                elseif current_mode == "seek" then param_name = "2seek"
                elseif current_mode == "pan" then param_name = "2pan"
                elseif current_mode == "lpf" or current_mode == "hpf" then
                    if current_filter_mode == "lpf" then
                        param_name = "2cutoff"
                    else
                        param_name = "2hpf"
                    end
                elseif current_mode == "jitter" then param_name = "2jitter"
                elseif current_mode == "size" then param_name = "2size"
                elseif current_mode == "density" then param_name = "2density"
                elseif current_mode == "spread" then param_name = "2spread"
                elseif current_mode == "pitch" then param_name = "2pitch"
                end

                -- Mark the parameter as being controlled by the encoder
                active_controlled_params[param_name] = true

                -- Check if an LFO is active for the parameter
                local is_active, lfo_index = is_lfo_active_for_param(param_name)
                if is_active then
                    params:set(lfo_index .. "lfo", 1) -- Deactivate the LFO
                end

                -- Adjust the parameter
                if current_mode == "speed" then params:delta("2speed", 0.5 * d) 
                elseif current_mode == "seek" then local current_seek = params:get("2seek")
                    local new_seek = wrap_value(current_seek + d, 0, 100)
                    params:set("2seek", new_seek)
                    engine.seek(2, new_seek / 100)
                elseif current_mode == "pan" then params:delta("2pan", d * 5)
                elseif current_mode == "lpf" or current_mode == "hpf" then
                    if current_filter_mode == "lpf" then
                        params:delta("2cutoff", d)
                    else
                        params:delta("2hpf", d)
                    end
                elseif current_mode == "jitter" then params:delta("2jitter", d * 2) 
                elseif current_mode == "size" then params:delta("2size", d * 2)
                elseif current_mode == "density" then params:delta("2density", d * 2)
                elseif current_mode == "spread" then params:delta("2spread", d * 2)
                elseif current_mode == "pitch" then params:delta("2pitch", d)
                end
            end
        end
    }
    if enc_actions[n] then enc_actions[n]() end
end

function key(n, z)
    if not installer:ready() then installer:key(n, z) return end

    -- Update key states
    if n == 1 then
        key1_pressed = z == 1
    elseif n == 2 then
        key2_pressed = z == 1
    elseif n == 3 then
        key3_pressed = z == 1
    end

    -- Handle key combinations for randomization
    if z == 1 then
        if key1_pressed and key2_pressed then
            randomize(1)
            randpara.randomize_params(steps, 1)
            return
        elseif key1_pressed and key3_pressed then
            randomize(2)
            randpara.randomize_params(steps, 2)
            return
        end
    end

    -- Handle single key presses for switching active row
    if not key1_pressed and z == 1 then
        if n == 2 then
            local modes = {"pitch", "spread", "density", "size", "jitter", "lpf", "pan", "seek", "speed"}
            local current_index = 1
            for i, mode in ipairs(modes) do
                if mode == current_mode then
                    current_index = i
                    break
                end
            end
            current_mode = modes[(current_index % #modes) + 1]
            redraw()
        elseif n == 3 then
            local modes = {"speed", "seek", "pan", "lpf", "jitter", "size", "density", "spread", "pitch"}
            local current_index = 1
            for i, mode in ipairs(modes) do
                if mode == current_mode then
                    current_index = i
                    break
                end
            end
            current_mode = modes[(current_index % #modes) + 1]
            redraw()
        end
    end

    -- Handle single press of key2 + key3 to toggle lock state of the active row
    if key2_pressed and key3_pressed then
        if current_mode == "lpf" or current_mode == "hpf" then
            -- Toggle between LPF and HPF modes
            if current_filter_mode == "lpf" then
                current_filter_mode = "hpf"
            else
                current_filter_mode = "lpf"
            end
            redraw()
        else
            -- Only toggle lock state for parameters that have lock parameters
            local lockable_params = {"jitter", "size", "density", "spread", "pitch", "pan"}
            local param_name = string.match(current_mode, "%a+") -- Extract the parameter name (e.g., "jitter" from "jitter:")

            if param_name and table.find(lockable_params, param_name) then
                -- Check if only one parameter is locked
                local is_locked1 = params:get("1lock_" .. param_name) == 2
                local is_locked2 = params:get("2lock_" .. param_name) == 2

                if is_locked1 ~= is_locked2 then
                    -- If only one parameter is locked, unlock both
                    params:set("1lock_" .. param_name, 1)
                    params:set("2lock_" .. param_name, 1)
                else
                    -- If both are locked or both are unlocked, toggle both
                    local new_state = is_locked1 and 1 or 2
                    params:set("1lock_" .. param_name, new_state)
                    params:set("2lock_" .. param_name, new_state)
                end
                redraw()
            end
        end
    end

    -- Handle double press of key2 or key3 while holding key1 to stop randomization
    if key1_pressed then
        local current_time = util.time()
        if n == 2 then
            if current_time - last_key2_press_time < double_press_threshold then
                -- Double press detected for key2
                if randomize_metro[1] then
                    randomize_metro[1]:stop()
                end
            end
            last_key2_press_time = current_time
        elseif n == 3 then
            if current_time - last_key3_press_time < double_press_threshold then
                -- Double press detected for key3
                if randomize_metro[2] then
                    randomize_metro[2]:stop()
                end
            end
            last_key3_press_time = current_time
        end
    end
end

local function format_density(value)
    return string.format("%.0f Hz", value)
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
        local target_param = lfo.lfo_targets[target_index]
        if target_param == param_name and params:get(i .. "lfo") == 2 then
            -- Return the actual modulated value from the LFO
            local min_param_value, max_param_value = lfo.get_parameter_range(param_name)
            local modulated_value = lfo.scale(lfo[i].slope, -1.0, 1.0, min_param_value, max_param_value)
            return modulated_value
        end
    end
    return nil
end

local function draw_param_row(y, label, param1, param2, is_density, is_pitch, is_highlighted)
    local param_name = string.match(label, "%a+")
    local is_locked1 = is_param_locked(1, param_name)
    local is_locked2 = is_param_locked(2, param_name)

    -- Draw the label
    screen.move(5, y)
    screen.level(15)  -- Always use level 15 for the label
    screen.text(label)

    -- Track 1 value
    if is_locked1 then
        draw_l_shape(51, y, is_locked1)  -- Draw pulsing "L" shape for locked parameter
    end
    screen.move(51, y)
    if is_highlighted then
        screen.level(15)  -- Highlighted row is always level 15
    else
        screen.level(1)  -- Non-highlighted rows are level 1
    end
    if is_density then
        screen.text(format_density(params:get(param1)))
    elseif is_pitch then
        screen.text(format_pitch(params:get(param1)))
    elseif param_name == "spread" then
        screen.text(string.format("%.0f%%", params:get(param1)))
    else
        screen.text(params:string(param1))
    end

    -- Track 2 value
    if is_locked2 then
        draw_l_shape(92, y, is_locked2)  -- Draw pulsing "L" shape for locked parameter
    end
    screen.move(92, y)
    if is_highlighted then
        screen.level(15)  -- Highlighted row is always level 15
    else
        screen.level(1)  -- Non-highlighted rows are level 1
    end
    if is_density then
        screen.text(format_density(params:get(param2)))
    elseif is_pitch then
        screen.text(format_pitch(params:get(param2)))
    elseif param_name == "spread" then
        screen.text(string.format("%.0f%%", params:get(param2)))
    else
        screen.text(params:string(param2))
    end

    -- Draw LFO visualization bars
    local lfo_mod1 = get_lfo_modulation(param1)
    local lfo_mod2 = get_lfo_modulation(param2)

    if lfo_mod1 then
        local bar_width = 30
        local bar_x = 51
        local bar_y = y + 1  -- Position the bar 1 pixel below the parameter value
        local bar_height = 1
        local min_param_value, max_param_value = lfo.get_parameter_range(param1)
        -- Map the modulated value to the bar width
        local bar_value = util.linlin(min_param_value, max_param_value, 0, bar_width, lfo_mod1)
        screen.level(1)
        screen.rect(bar_x, bar_y, bar_value, bar_height)
        screen.fill()
    end

    if lfo_mod2 then
        local bar_width = 30
        local bar_x = 92
        local bar_y = y + 1  -- Position the bar 1 pixel below the parameter value
        local bar_height = 1
        local min_param_value, max_param_value = lfo.get_parameter_range(param2)
        -- Map the modulated value to the bar width
        local bar_value = util.linlin(min_param_value, max_param_value, 0, bar_width, lfo_mod2)
        screen.level(1)
        screen.rect(bar_x, bar_y, bar_value, bar_height)
        screen.fill()
    end
end

local function draw_progress_bar(x, y, width, value, min, max, center, is_log)
    local bar_width = width
    local center_pos = x + (width / 2)
    local value_pos
    if is_log then
      -- Logarithmic scaling for LPF and HPF
        value_pos = util.linlin(math.log(min), math.log(max), x, x + width, math.log(value))
    else
        if center then
            -- For centered progress bars (e.g., speed, pan)
            value_pos = util.linlin(min, max, x, x + width, value)
        else
            -- For non-centered progress bars (e.g., seek)
            value_pos = util.linlin(min, max, x, x + width, value)
        end
    end

    screen.level(3)
    if center then
        -- Draw from the center to the value position
        if value_pos > center_pos then
            screen.rect(center_pos, y, value_pos - center_pos, 1)
        else
            screen.rect(value_pos, y, center_pos - value_pos, 1)
        end
    else
        -- Draw from the start to the value position
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
    
    if current_mode == "seek" then
        draw_progress_bar(51, 62, 30, params:get("1seek"), 0, 100, false, false)
        draw_progress_bar(92, 62, 30, params:get("2seek"), 0, 100, false, false)
    elseif current_mode == "lpf" or current_mode == "hpf" then
        if current_filter_mode == "lpf" then
            draw_progress_bar(51, 62, 30, params:get("1cutoff"), 20, 20000, false, true)
            draw_progress_bar(92, 62, 30, params:get("2cutoff"), 20, 20000, false, true)
        else
            draw_progress_bar(51, 62, 30, params:get("1hpf"), 20, 20000, false, true)
            draw_progress_bar(92, 62, 30, params:get("2hpf"), 20, 20000, false, true)
        end
    end

    -- Draw vertical volume bars for channel 1 (left) and channel 2 (right)
    local volume1 = params:get("1volume") 
    local volume2 = params:get("2volume") 

    local function volume_to_height(volume)
        return util.linlin(-60, 20, 0, 64, volume)
    end

    local bar_width = 1 -- Width of the volume bars
    local bar1_height = volume_to_height(volume1)
    local bar2_height = volume_to_height(volume2)

    -- Draw parameter rows with highlighting
    draw_param_row(10, "jitter:    ", "1jitter", "2jitter", false, false, current_mode == "jitter")
    draw_param_row(20, "size:     ", "1size", "2size", false, false, current_mode == "size")
    draw_param_row(30, "density:  ", "1density", "2density", true, false, current_mode == "density")
    draw_param_row(40, "spread:   ", "1spread", "2spread", false, false, current_mode == "spread")
    draw_param_row(50, "pitch:    ", "1pitch", "2pitch", false, true, current_mode == "pitch")

    -- Display "seek:", "speed:", "pan:", "filter:", or "hpf:" based on the current mode
    screen.move(5, 60)
    screen.level(15)
    
    if current_mode == "seek" then
        screen.text("seek:     ")
    elseif current_mode == "pan" then
        screen.text("pan:      ")
    elseif current_mode == "lpf" or current_mode == "hpf" then
        -- Display "filter:" or "hpf:" based on the current_filter_mode
        if current_filter_mode == "lpf" then
            screen.text("lpf:      ")
        else
            screen.text("hpf:      ")
        end
    else
        screen.text("speed:    ")
    end

    -- Display track 1 value (always bright if it's the active mode)
    screen.move(51, 60)
    if current_mode == "seek" or current_mode == "lpf" or current_mode == "hpf" or current_mode == "speed" or current_mode == "pan" then
        screen.level(15) -- Highlighted row is always level 15
    else
        screen.level(1) -- Non-highlighted rows are level 1
    end
    if current_mode == "seek" then
        screen.text(format_seek(params:get("1seek"))) -- Display seek for track 1
    elseif current_mode == "pan" then
       local pan1 = params:get("1pan")
       if pan1 == 0 then
            screen.text(string.format("0%%"))
       else
        screen.text(string.format("%.0f%%", params:get("1pan"))) -- Display pan for track 1
        end
    elseif current_mode == "lpf" or current_mode == "hpf" then
        -- Display LPF or HPF cutoff based on current_filter_mode
        if current_filter_mode == "lpf" then
            screen.text(string.format("%.0f", params:get("1cutoff"))) -- Display LPF for track 1
        else
            screen.text(string.format("%.0f", params:get("1hpf"))) -- Display HPF for track 1
        end
    else
        local speed1 = params:get("1speed")
        screen.text(format_speed(speed1))
    end

    -- Display track 2 value (always bright if it's the active mode)
    screen.move(92, 60)
    if current_mode == "seek" or current_mode == "lpf" or current_mode == "hpf" or current_mode == "speed" or current_mode == "pan" then
        screen.level(15) -- Highlighted row is always level 15
    else
        screen.level(1) -- Non-highlighted rows are level 1
    end
    if current_mode == "seek" then
        screen.text(format_seek(params:get("2seek"))) -- Display seek for track 2
    elseif current_mode == "pan" then
      local pan2 = params:get("2pan")
      if pan2 == 0 then
            screen.text(string.format("0%%"))
      else
        screen.text(string.format("%.0f%%", params:get("2pan"))) -- Display pan for track 2
      end
    elseif current_mode == "lpf" or current_mode == "hpf" then
        if current_filter_mode == "lpf" then
            screen.text(string.format("%.0f", params:get("2cutoff"))) -- Display LPF for track 2
        else
            screen.text(string.format("%.0f", params:get("2hpf"))) -- Display HPF for track 2
        end
    else
        local speed2 = params:get("2speed")
        screen.text(format_speed(speed2))
    end

    -- Draw L-shape for locked pan parameters in the bottom row
    if current_mode == "pan" then
        local is_locked1 = is_param_locked(1, "pan")
        local is_locked2 = is_param_locked(2, "pan")

        if is_locked1 then
            draw_l_shape(51, 60, is_locked1)  -- Draw L-shape for track 1 pan
        end
        if is_locked2 then
            draw_l_shape(92, 60, is_locked2)  -- Draw L-shape for track 2 pan
        end
    end

    screen.level(3)

    if is_audio_loaded(1) then
        screen.rect(0, 64 - bar1_height, bar_width, bar1_height)
        screen.fill()
    end

    if is_audio_loaded(2) then
        screen.rect(128 - bar_width, 64 - bar2_height, bar_width, bar2_height)
        screen.fill()
    end

    if is_audio_loaded(1) then
        local center_start = 52
        local center_end = 77
        local pan1 = params:get("1pan")
        local pan1_pos = util.linlin(-100, 100, center_start, center_end, pan1)
        screen.rect(pan1_pos - 1, 0, 4, 1)
        screen.fill()
    end

    if is_audio_loaded(2) then
        local center_start = 93
        local center_end = 118
        local pan2 = params:get("2pan")
        local pan2_pos = util.linlin(-100, 100, center_start, center_end, pan2)
        screen.rect(pan2_pos - 1, 0, 4, 1)
        screen.fill()
    end
    screen.update()
end

function cleanup()
    if ui_metro then ui_metro:stop() end
    for i = 1, 2 do
        if randomize_metro[i] then randomize_metro[i]:stop() end
    end
end