--  __ __|         _)             
--     | \ \  \  / |  \ |  (_< 
--     |  \_/\_/ _| _| _| __/ 
--           by: @dddstudio                       
--

halfsecond = include("lib/halfsecond")
installer_ = include("lib/scinstaller/scinstaller")
local lfo = include("lib/hnds")
installer = installer_:new{requirements = {"Fverb"}}

engine.name = installer:ready() and 'twins' or nil

local ALI_X = 46
local ALI2_X = 93
local ui_metro
local randomize_metro = { [1] = nil, [2] = nil }
local key1_pressed,key2_pressed,key3_pressed  = false
local enc1_position = 0
local current_mode = "speed"

-- New variables for double press detection
local last_key2_press_time = 0
local last_key3_press_time = 0
local double_press_threshold = 0.3 -- seconds

-- Blinking effect variables
local blink_state = false
local blink_metro = metro.init()
blink_metro.time = 0.5
blink_metro.event = function()
    blink_state = not blink_state
    redraw()
end
blink_metro:start()

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

local function clearLFOs()
    for i = 1, 8 do
        if params:get(i .. "lfo") == 2 then
            params:set(i .. "lfo", 1) -- Turn off the LFO
        end
        params:set(i .. "lfo_target", 1) -- Reset LFO target to "none"
    end
end

local lfo_targets = {"none","1pan","2pan","1speed","2speed","1seek","2seek","1jitter","2jitter","1spread","2spread","1size","2size","1density","2density","1volume","2volume","1pitch","2pitch","time","size","damp","diff","feedback","mod_depth","mod_freq"}

function lfo.process()
  for i = 1, 8 do
    local target = params:get(i .. "lfo_target")
    if params:get(i .. "lfo") == 2 then
      -- 1pan
      if target == 2 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, -100.00, 100.00))
      -- 2pan
      elseif target == 3 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, -100.00, 100.00))
      -- 1speed
      elseif target == 4 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, -2.00, 2.00))
      -- 2speed
      elseif target == 5 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, -2.00, 2.00))
      -- 1seek
      elseif target == 6 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 0, 100))
      -- 2seek
      elseif target == 7 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 0, 100))
      -- 1jitter
      elseif target == 8 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 0, 500))
      -- 2jitter
      elseif target == 9 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 0, 500))
      -- 1spread
      elseif target == 10 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 0, 100))
      -- 2spread
      elseif target == 11 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 0, 100)) 
      -- 1size
      elseif target == 12 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 1, 500))
      -- 2size
      elseif target == 13 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 1, 500)) 
      -- 1density
      elseif target == 14 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 0, 40))
      -- 2density
      elseif target == 15 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 0, 40)) 
      -- 1volume
      elseif target == 16 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, -100.00, 100.00))
      -- 2volume
      elseif target == 17 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, -100.00, 100.00))
      -- 1pitch
      elseif target == 18 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, -12.00, 12.00))
      -- 2pitch
      elseif target == 19 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, -12.00, 12.00))        
      -- Greyhole delay time
      elseif target == 20 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 2.0, 0.00, 6.00))
      -- Greyhole size
      elseif target == 21 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 2.0, 0.50, 5.00))
      -- Greyhole dampening
      elseif target == 22 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 2.0, 0.00, 1.00))
      -- Greyhole diffusion
      elseif target == 23 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 2.0, 0.00, 1.00))
      -- Greyhole feedback
      elseif target == 24 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 2.0, 0.00, 1.00))
      -- Greyhole delay line modulation depth
      elseif target == 25 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 2.0, 0.00, 1.00))
      -- Greyhole delay line modulation frequency
      elseif target == 26 then
        params:set(lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 2.0, 0.00, 10.00))
      end
    end
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
                    params:set("1pan", -25)
                    params:set("2pan", 25)
                end
            end
        end)
    end 
    
    params:add_separator("Settings")
    params:add_group("Delay", 3)
    halfsecond.init()
    
    params:add_group("Greyhole", 8)
    -- mix
    params:add_control("greyhole_mix", "Mix", controlspec.new(0.0, 1.0, "lin", 0.01, 0.5, ""))
    params:set_action("greyhole_mix", function(value) engine.greyhole_mix(value) end)
    -- delay size
    params:add_control("time", "Time", controlspec.new(0.00, 10.00, "lin", 0.01, 1.7, ""))
    params:set_action("time", function(value) engine.greyhole_delay_time(value) end)
    -- delay size
    params:add_control("size", "Size", controlspec.new(0.5, 5.0, "lin", 0.01, 4.00, ""))
    params:set_action("size", function(value) engine.greyhole_size(value) end)
    -- dampening 
    params:add_control("damp", "Damping", controlspec.new(0.0, 1.0, "lin", 0.01, 0.13, ""))
    params:set_action("damp", function(value) engine.greyhole_damp(value) end)
    -- diffusion
    params:add_control("diff", "Diffusion", controlspec.new(0.0, 1.0, "lin", 0.01, 0.5, ""))
    params:set_action("diff", function(value) engine.greyhole_diff(value) end)
    -- feedback
    params:add_control("feedback", "Feedback", controlspec.new(0.00, 1.0, "lin", 0.01, 0.20, ""))
    params:set_action("feedback", function(value) engine.greyhole_feedback(value) end)
    -- mod depth
    params:add_control("mod_depth", "Mod depth", controlspec.new(0.0, 1.0, "lin", 0.01, 0.75, ""))
    params:set_action("mod_depth", function(value) engine.greyhole_mod_depth(value) end)
    -- mod rate
    params:add_control("mod_freq", "Mod freq", controlspec.new(0.0, 10.0, "lin", 0.01, 1, "hz"))
    params:set_action("mod_freq", function(value) engine.greyhole_mod_freq(value) end)

    params:add_group("Fverb", 12)
    params:add_taper("reverb_mix", "Mix", 0, 100, 17.5, 0, "%")
    params:set_action("reverb_mix", function(value) engine.reverb_mix(value / 100) end)

    params:add_taper("reverb_predelay", "Predelay", 0, 100, 60, 0, "ms")
    params:set_action("reverb_predelay", function(value) engine.reverb_predelay(value) end)

    params:add_taper("reverb_input_amount", "Input amount", 0, 100, 100, 0, "%")
    params:set_action("reverb_input_amount", function(value) engine.reverb_input_amount(value) end)

    params:add_taper("reverb_lowpass_cutoff", "Lowpass cutoff", 0, 20000, 10500, 0, "Hz")
    params:set_action("reverb_lowpass_cutoff", function(value) engine.reverb_lowpass_cutoff(value) end)

    params:add_taper("reverb_highpass_cutoff", "Highpass cutoff", 0, 20000, 150, 0, "Hz")
    params:set_action("reverb_highpass_cutoff", function(value) engine.reverb_highpass_cutoff(value) end)

    params:add_taper("reverb_diffusion_1", "Diffusion 1", 0, 100, 75, 0, "%")
    params:set_action("reverb_diffusion_1", function(value) engine.reverb_diffusion_1(value) end)

    params:add_taper("reverb_diffusion_2", "Diffusion 2", 0, 100, 62.5, 0, "%")
    params:set_action("reverb_diffusion_2", function(value) engine.reverb_diffusion_2(value) end)

    params:add_taper("reverb_tail_density", "Tail density", 0, 100, 70, 0, "%")
    params:set_action("reverb_tail_density", function(value) engine.reverb_tail_density(value) end)

    params:add_taper("reverb_decay", "Decay", 0, 100, 80, 0, "%")
    params:set_action("reverb_decay", function(value) engine.reverb_decay(value) end)

    params:add_taper("reverb_damping", "Damping", 0, 20000, 6500, 0, "Hz")
    params:set_action("reverb_damping", function(value) engine.reverb_damping(value) end)

    params:add_taper("reverb_modulator_frequency", "Modulator frequency", 0, 10, 1, 0, "Hz")
    params:set_action("reverb_modulator_frequency", function(value) engine.reverb_modulator_frequency(value) end)

    params:add_taper("reverb_modulator_depth", "Modulator depth", 0, 100, 90, 0, "%")
    params:set_action("reverb_modulator_depth", function(value) engine.reverb_modulator_depth(value / 100) end)

    params:add_group("Filters", 4)
      params:add_control("1cutoff","1 LPF cutoff",controlspec.new(20,20000,"exp",0,20000,"Hz"))
      params:set_action("1cutoff",function(value) engine.cutoff(1,value) end)
      params:add_control("1q","1 LPF rq",controlspec.new(0.1,1.00,"lin",0.01,1))
      params:set_action("1q",function(value) engine.q(1,value) end)
      params:add_control("2cutoff","2 LPF cutoff",controlspec.new(20,20000,"exp",0,20000,"Hz"))
      params:set_action("2cutoff",function(value) engine.cutoff(2,value) end)
      params:add_control("2q","2 LPF rq",controlspec.new(0.1,1.00,"lin",0.01,1))
      params:set_action("2q",function(value) engine.q(2,value) end)

    params:add_group("LFOs", 57)
      params:add_binary("ClearLFOs", "Clear LFOs", "trigger", 0)
      params:set_action("ClearLFOs", function() clearLFOs() end)
    for i = 1, 8 do
      lfo[i].lfo_targets = lfo_targets
    end
    lfo.init()

    params:add_group("Randomizer", 10)
    params:add_taper("min_jitter", "jitter (min)", 0, 500, 0, 5, "ms")
    params:add_taper("max_jitter", "jitter (max)", 0, 500, 500, 5, "ms")
    params:add_taper("min_size", "size (min)", 1, 500, 100, 5, "ms")
    params:add_taper("max_size", "size (max)", 1, 500, 500, 5, "ms")
    params:add_taper("min_density", "density (min)", 1, 50, 1, 5, "Hz")
    params:add_taper("max_density", "density (max)", 1, 50, 40, 5, "Hz")
    params:add_taper("min_spread", "spread (min)", 0, 100, 0, 0, "%")
    params:add_taper("max_spread", "spread (max)", 0, 100, 100, 0, "%")
    params:add_control("min_pitch", "pitch (min)", controlspec.new(-48, 48, "lin", 1, -12, "st"))
    params:add_control("max_pitch", "pitch (max)", controlspec.new(-48, 48, "lin", 1, 12, "st"))

    params:add_group("Locking", 10)
    for i = 1, 2 do
        params:add_option(i .. "lock_jitter", i .. " lock jitter", {"off", "on"}, 1)
        params:add_option(i .. "lock_size", i .. " lock size", {"off", "on"}, 1)
        params:add_option(i .. "lock_density", i .. " lock density", {"off", "on"}, 1)
        params:add_option(i .. "lock_spread", i .. " lock spread", {"off", "on"}, 1)
        params:add_option(i .. "lock_pitch", i .. " lock pitch", {"off", "on"}, 1)
    end

    params:add_group("Parameters", 20)
    for i = 1, 2 do
        params:add_taper(i .. "volume", i .. " volume", -60, 20, 0, 0, "dB")
        params:set_action(i .. "volume", function(value) engine.volume(i, math.pow(10, value / 20)) end)
        params:add_taper(i .. "pan", i .. " pan", -100, 100, 0, 0, "%")
        params:set_action(i .. "pan", function(value) engine.pan(i, value / 100)  end)
        params:add_control(i .. "speed", i .. " speed", controlspec.new(-2, 2, "lin", 0.01, 0, "")) 
        params:set_action(i .. "speed", function(value) engine.speed(i, value) end)
        params:add_taper(i .. "density", i .. " density", 1, 50, 20, 6)
        params:set_action(i .. "density", function(value) engine.density(i, value) end)
        params:add_taper(i .. "pitch", i .. " pitch", -48, 48, 0, 0)
        params:set_action(i .. "pitch", function(value) engine.pitch_offset(i, math.pow(0.5, -value / 12)) end)
        params:add_taper(i .. "jitter", i .. " jitter", 0, 500, 250, 5, "ms")
        params:set_action(i .. "jitter", function(value) engine.jitter(i, value / 1000) end)
        params:add_taper(i .. "size", i .. " size", 1, 500, 100, 5, "ms")
        params:set_action(i .. "size", function(value) engine.size(i, value / 1000) end)
        params:add_taper(i .. "spread", i .. " spread", 0, 100, 0, 0, "%")
        params:set_action(i .. "spread", function(value) engine.spread(i, value / 100) end)
        params:add_control(i .. "seek", i .. " seek", controlspec.new(0, 100, "lin", 0.01, 0, "%"))
        params:set_action(i .. "seek", function(value) engine.seek(i, value) end)
        params:add_taper(i .."fade", i .." att / dec", 1, 9000, 1000, 3, "ms")
        params:set_action(i .."fade", function(value) engine.envscale(i, value / 1000) end)
    end
    
    params:add_taper("granular_gain", "Granular Mix", 0, 100, 100, 0, "%")
    params:set_action("granular_gain", function(value) engine.granular_gain(value / 100) end) 
    params:add_taper("density_mod_amt", "Density Mod", 0, 100, 0, 0, "%")
    params:set_action("density_mod_amt", function(value) engine.density_mod_amt(1, value / 100) end)
    params:add_option("pitch_mode", "Pitch Mode", {"match speed", "independent"}, 2)
    params:set_action("pitch_mode", function(value) engine.pitch_mode(1, value - 1) engine.pitch_mode(2, value - 1) end)
    
    params:add_control("subharmonics","Subharmonics",controlspec.new(0.00,1.00,"lin",0.01,0))
    params:set_action("subharmonics",function(value) engine.subharmonics(1,value) engine.subharmonics(2,value) end)

    params:add_control("overtones","Overtones",controlspec.new(0.00,1.00,"lin",0.01,0))
    params:set_action("overtones",function(value) engine.overtones(1,value) engine.overtones(2,value) end)

    params:add_separator("Transition")
    params:add_control("steps", "Steps", controlspec.new(5, 200000, "lin", 5, 5, ""))
    params:set_action("steps", function(value) steps = value end)
    
    params:bang()
end

local function interpolate(start_val, end_val, factor)
    return start_val + (end_val - start_val) * factor
end

local function randomize(n)
    if not randomize_metro[n] then
        randomize_metro[n] = metro.init()
    end

    local targets = {}
    local locks = {
        jitter = params:get(n .. "lock_jitter") == 1,
        size = params:get(n .. "lock_size") == 1,
        density = params:get(n .. "lock_density") == 1,
        spread = params:get(n .. "lock_spread") == 1,
        pitch = params:get(n .. "lock_pitch") == 1
    }

    if locks.jitter then targets[n .. "jitter"] = random_float(params:get("min_jitter"), params:get("max_jitter")) end
    if locks.size then targets[n .. "size"] = random_float(params:get("min_size"), params:get("max_size")) end
    if locks.density then targets[n .. "density"] = random_float(params:get("min_density"), params:get("max_density")) end
    if locks.spread then targets[n .. "spread"] = random_float(params:get("min_spread"), params:get("max_spread")) end
    if locks.pitch then targets[n .. "pitch"] = math.floor(random_float(params:get("min_pitch"), params:get("max_pitch")) + 0.5) end

    local tolerance = 0.001

    randomize_metro[n].time = 1/30
    randomize_metro[n].event = function(count)
    local factor = count / steps
      
        for param, target in pairs(targets) do
            local current_value = params:get(param)
            local new_value = interpolate(current_value, target, factor)
            if math.abs(new_value - target) < tolerance then
            randomize_metro[n]:stop()
            end
            params:set(param, new_value)
        end
    end
    randomize_metro[n]:start()
end

local function setup_engine()
    engine.seek(1, 0)
    engine.gate(1, 1)
    engine.seek(2, 0)
    engine.gate(2, 1)
    randomize(1)
    randomize(2)
    audio.level_adc(0)
end

function init()
    setup_ui_metro()
    setup_params()
    setup_engine()
end

local function adjust_volume(sample_num, delta)
    params:delta(sample_num .. "volume", 5 * delta)
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
    local enc_actions = {
        [1] = function()
            if key1_pressed then
                -- Adjust volumes in opposite directions
                adjust_volume("1", d)  -- Increase volume for track 1
                adjust_volume("2", -d) -- Decrease volume for track 2
            else
                -- Normal behavior: adjust both volumes in the same direction
                adjust_volume("1", d)
                adjust_volume("2", d)
            end
        end,
        [2] = function()
            if key1_pressed then
                adjust_volume("1", d)
            else
                if current_mode == "speed" then
                    params:delta("1speed", d * 1) -- Adjust speed with delta
                elseif current_mode == "seek" then
                    local current_seek = params:get("1seek")
                    local new_seek = wrap_value(current_seek + d, 0, 100)
                    params:set("1seek", new_seek)
                    engine.seek(1, new_seek / 100)
                elseif current_mode == "pan" then
                    params:delta("1pan", d * 5) -- Adjust pan with delta
                elseif current_mode == "lpf" then
                    params:delta("1cutoff", d) -- Adjust LPF cutoff with delta
                elseif current_mode == "jitter" then
                    params:delta("1jitter", d * 2) -- Adjust jitter with delta
                elseif current_mode == "size" then
                    params:delta("1size", d * 2) -- Adjust size with delta
                elseif current_mode == "density" then
                    params:delta("1density", d * 2) -- Adjust density with delta
                elseif current_mode == "spread" then
                    params:delta("1spread", d * 2) -- Adjust spread with delta
                elseif current_mode == "pitch" then
                    params:delta("1pitch", d) -- Adjust pitch with delta
                end
            end
        end,
        [3] = function()
            if key1_pressed then
                adjust_volume("2", d)
            else
                if current_mode == "speed" then
                    params:delta("2speed", d * 1) -- Adjust speed with delta
                elseif current_mode == "seek" then
                    local current_seek = params:get("2seek")
                    local new_seek = wrap_value(current_seek + d, 0, 100)
                    params:set("2seek", new_seek)
                    engine.seek(2, new_seek / 100)
                elseif current_mode == "pan" then
                    params:delta("2pan", d * 5) -- Adjust pan with delta
                elseif current_mode == "lpf" then
                    params:delta("2cutoff", d) -- Adjust LPF cutoff with delta
                elseif current_mode == "jitter" then
                    params:delta("2jitter", d * 2) -- Adjust jitter with delta
                elseif current_mode == "size" then
                    params:delta("2size", d * 2) -- Adjust size with delta
                elseif current_mode == "density" then
                    params:delta("2density", d * 2) -- Adjust density with delta
                elseif current_mode == "spread" then
                    params:delta("2spread", d * 2) -- Adjust spread with delta
                elseif current_mode == "pitch" then
                    params:delta("2pitch", d) -- Adjust pitch with delta
                end
            end
        end
    }

    if enc_actions[n] then enc_actions[n]() end
end

function key(n, z)
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
            -- Randomize parameters for track 1
            randomize(1)
            return
        elseif key1_pressed and key3_pressed then
            -- Randomize parameters for track 2
            randomize(2)
            return
        end
    end

    -- Handle single key presses for switching active row
    if not key1_pressed and z == 1 then
        if n == 2 then
            -- Cycle through modes in reverse order: pitch -> spread -> density -> size -> jitter -> lpf -> seek -> speed -> pitch
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
            -- Cycle through modes in forward order: speed -> seek -> lpf -> jitter -> size -> density -> spread -> pitch -> speed
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

-- Helper function to check if a parameter is locked
local function is_param_locked(track_num, param)
    return params:get(track_num .. "lock_" .. param) == 2
end

local function draw_param_row(y, label, param1, param2, is_density, is_pitch, is_highlighted)
    -- Determine if the parameter is locked for either track
    local param_name = string.match(label, "%a+") -- Extract the parameter name (e.g., "jitter" from "jitter:")
    local is_locked1 = is_param_locked(1, param_name)
    local is_locked2 = is_param_locked(2, param_name)

    -- Draw the label
    screen.move(5, y)
    if is_highlighted then
        screen.level(15) -- Bright text for highlighted row
    else
        screen.level(5) -- Dim text for non-highlighted rows
    end
    screen.text(label)

    -- Draw the parameter values with blinking effect if locked
    screen.move(ALI_X, y)
    if is_locked1 and blink_state then
        screen.level(0) -- Hide the value when blinking
    else
        screen.level(is_highlighted and 15 or 5) -- Bright text for highlighted row
    end
    if is_density then
        screen.text(format_density(params:get(param1)))
    elseif is_pitch then
        screen.text(format_pitch(params:get(param1)))
    else
        screen.text(params:string(param1))
    end

    screen.move(77, y)
    screen.level(1)
    screen.text(" / ")

    screen.move(ALI2_X, y)
    if is_locked2 and blink_state then
        screen.level(0) -- Hide the value when blinking
    else
        screen.level(is_highlighted and 15 or 5) -- Bright text for highlighted row
    end
    if is_density then
        screen.text(format_density(params:get(param2)))
    elseif is_pitch then
        screen.text(format_pitch(params:get(param2)))
    else
        screen.text(params:string(param2))
    end
end

function redraw()
    screen.clear()

    -- Draw vertical volume bars for channel 1 (left) and channel 2 (right)
    local volume1 = params:get("1volume") -- Get volume for channel 1
    local volume2 = params:get("2volume") -- Get volume for channel 2

    -- Convert volume from dB to a scale of 0 to 64 (screen height)
    local function volume_to_height(volume)
        -- Volume range is -60 dB to 20 dB, map to 0 to 64 pixels
        return util.linlin(-60, 20, 0, 64, volume)
    end

    local bar_width = 1 -- Width of the volume bars
    local bar1_height = volume_to_height(volume1) -- Height of channel 1 volume bar
    local bar2_height = volume_to_height(volume2) -- Height of channel 2 volume bar

    -- Draw parameter rows with highlighting
    draw_param_row(10, "jitter:    ", "1jitter", "2jitter", false, false, current_mode == "jitter")
    draw_param_row(20, "size:     ", "1size", "2size", false, false, current_mode == "size")
    draw_param_row(30, "density:  ", "1density", "2density", true, false, current_mode == "density")
    draw_param_row(40, "spread:   ", "1spread", "2spread", false, false, current_mode == "spread")
    draw_param_row(50, "pitch:    ", "1pitch", "2pitch", false, true, current_mode == "pitch")

    -- Display "seek:", "speed:", "pan:", or "filter:" based on the current mode
    screen.move(5, 60)
    if current_mode == "seek" or current_mode == "lpf" or current_mode == "speed" or current_mode == "pan" then
        screen.level(15) -- Bright text for highlighted row
    else
        screen.level(5) -- Dim text for non-highlighted rows
    end
    if current_mode == "seek" then
        screen.text("seek:     ")
    elseif current_mode == "pan" then
        screen.text("pan:      ")
    elseif current_mode == "lpf" then
        screen.text("filter:      ")
    else
        screen.text("speed:    ")
    end

    -- Display track 1 value (always bright if it's the active mode)
    screen.move(ALI_X, 60)
    if current_mode == "seek" or current_mode == "lpf" or current_mode == "speed" or current_mode == "pan" then
        screen.level(15) -- Bright text for highlighted row
    else
        screen.level(5) -- Dim text for non-highlighted rows
    end
    if current_mode == "seek" then
        screen.text(format_seek(params:get("1seek"))) -- Display seek for track 1
    elseif current_mode == "pan" then
        screen.text(string.format("%.0f%%", params:get("1pan"))) -- Display pan for track 1
    elseif current_mode == "lpf" then
        screen.text(string.format("%.0f", params:get("1cutoff"))) -- Display lpf for track 1 
    else
        local speed1 = params:get("1speed")
        screen.text(string.format("%.2fx", speed1))  -- Display speed for track 1
    end

    -- Display track 2 value (always bright if it's the active mode)
    screen.move(ALI2_X, 60)
    if current_mode == "seek" or current_mode == "lpf" or current_mode == "speed" or current_mode == "pan" then
        screen.level(15) -- Bright text for highlighted row
    else
        screen.level(5) -- Dim text for non-highlighted rows
    end
    if current_mode == "seek" then
        screen.text(format_seek(params:get("2seek"))) -- Display seek for track 2
    elseif current_mode == "pan" then
        screen.text(string.format("%.0f%%", params:get("2pan"))) -- Display pan for track 2
    elseif current_mode == "lpf" then
        screen.text(string.format("%.0f", params:get("2cutoff"))) -- Display lpf for track 2
    else
        local speed2 = params:get("2speed")
        screen.text(string.format("%.2fx", speed2))  -- Display speed for track 2
    end

    screen.level(5)

    -- Draw volume bars if files are loaded (always visible)
    if is_audio_loaded(1) then
        screen.rect(0, 64 - bar1_height, bar_width, bar1_height) -- Draw the volume bar
        screen.fill()
    end

    if is_audio_loaded(2) then
        screen.rect(128 - bar_width, 64 - bar2_height, bar_width, bar2_height) -- Draw the volume bar
        screen.fill()
    end

    -- Check if an LFO is assigned to the panning parameters
    local lfo_assigned_to_pan1 = false
    local lfo_assigned_to_pan2 = false

    for i = 1, 8 do
        if params:get(i .. "lfo_target") == 2 then -- 2 corresponds to "1pan"
            lfo_assigned_to_pan1 = true
        end
        if params:get(i .. "lfo_target") == 3 then -- 3 corresponds to "2pan"
            lfo_assigned_to_pan2 = true
        end
    end

    -- Draw panning bars only if an LFO is assigned to the panning parameters
    if is_audio_loaded(1) and lfo_assigned_to_pan1 then
        local center_start = 47
        local center_end = 74
        local pan1 = params:get("1pan")
        local pan1_pos = util.linlin(-100, 100, center_start, center_end, pan1)
        screen.rect(pan1_pos - 1, 0, 2, 1) -- Draw the pan bar (2 pixels wide, 1 pixel height)
        screen.fill()
    end

    if is_audio_loaded(2) and lfo_assigned_to_pan2 then
        local center_start = 94
        local center_end = 121
        local pan2 = params:get("2pan")
        local pan2_pos = util.linlin(-100, 100, center_start, center_end, pan2)
        screen.rect(pan2_pos - 1, 0, 2, 1) -- Draw the pan bar (2 pixels wide, 1 pixel height)
        screen.fill()
    end

    screen.update()
end

function cleanup()
    if ui_metro then ui_metro:stop() end
    if blink_metro then blink_metro:stop() end
    for i = 1, 2 do
        if randomize_metro[i] then randomize_metro[i]:stop() end
    end
end