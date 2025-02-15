--  __ __|         _)             
--     | \ \  \  / |  \ |  (_< 
--     |  \_/\_/ _| _| _| __/ 
--           by: @dddstudio                       
--

halfsecond = include("lib/halfsecond")

installer_ = include("lib/scinstaller/scinstaller")
installer = installer_:new{requirements = {"Fverb"}}

engine.name = installer:ready() and 'twins' or nil

local ui_metro
local ALI_X = 42
local ALI2_X = 89
local ALIDASH_X = 73
local randomize_metro = { [1] = nil, [2] = nil }
local key1_pressed = false
local key2_pressed = false
local key3_pressed = false
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

local function setup_params()
    params:add_separator("Samples")
    for i = 1, 2 do
        params:add_file(i .. "sample", i .. " sample")
        params:set_action(i .. "sample", function(file)
            if file ~= nil and file ~= "" and file ~= "none" and file ~= "-" then
                engine.read(i, file)
                if is_audio_loaded(1) and is_audio_loaded(2) then
                    params:set("1pan", -40)
                    params:set("2pan", 40)
                end
            end
        end)

        params:add_taper(i .. "pan", i .. " pan", -100, 100, 0, 0, "%")
        params:set_action(i .. "pan", function(value) engine.pan(i, value / 100)  end)
        
        params:add_control(i .. "speed", i .. " speed", controlspec.new(-4, 4, "lin", 0.01, 0, "")) 
        params:set_action(i .. "speed", function(value) engine.speed(i, value) end)
    end 
    
    params:add_separator("Transition")
    params:add_control("steps", "steps", controlspec.new(5, 200000, "lin", 5, 5, ""))
    params:set_action("steps", function(value) steps = value end)

    params:add_separator("Settings")

    params:add_option("pitch_mode", "Pitch Mode", {"match speed", "independent"}, 2)
    params:set_action("pitch_mode", function(value)
        engine.pitch_mode(1, value - 1)
        engine.pitch_mode(2, value - 1)
    end)

    params:add_taper("granular_gain", "Granular Mix", 0, 100, 100, 0, "%")
    params:set_action("granular_gain", function(value) engine.granular_gain(value / 100) end) 

    params:add_taper("density_mod_amt", "Density Mod", 0, 100, 20, 0, "%")
    params:set_action("density_mod_amt", function(value) engine.density_mod_amt(1, value / 100) end)

    params:add_group("Delay", 3)
    halfsecond.init()

    params:add_group("Fverb", 12)
    params:add_taper("reverb_mix", "Mix", 0, 100, 25, 0, "%")
    params:set_action("reverb_mix", function(value) engine.reverb_mix(value / 100) end)

    params:add_taper("reverb_predelay", "Predelay", 0, 100, 25, 0, "ms")
    params:set_action("reverb_predelay", function(value) engine.reverb_predelay(value) end)

    params:add_taper("reverb_input_amount", "Input amount", 0, 100, 75, 0, "%")
    params:set_action("reverb_input_amount", function(value) engine.reverb_input_amount(value) end)

    params:add_taper("reverb_lowpass_cutoff", "Lowpass cutoff", 0, 20000, 10500, 0, "Hz")
    params:set_action("reverb_lowpass_cutoff", function(value) engine.reverb_lowpass_cutoff(value) end)

    params:add_taper("reverb_highpass_cutoff", "Highpass cutoff", 0, 20000, 200, 0, "Hz")
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

    params:add_group("Randomizer", 10)
    params:add_taper("min_jitter", "jitter (min)", 0, 500, 0, 5, "ms")
    params:add_taper("max_jitter", "jitter (max)", 0, 500, 500, 5, "ms")
    params:add_taper("min_size", "size (min)", 1, 500, 50, 5, "ms")
    params:add_taper("max_size", "size (max)", 1, 500, 500, 5, "ms")
    params:add_taper("min_density", "density (min)", 0, 50, 1, 5, "Hz")
    params:add_taper("max_density", "density (max)", 0, 50, 40, 5, "Hz")
    params:add_taper("min_spread", "spread (min)", 0, 100, 25, 0, "%")
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

    params:add_group("Parameters", 16)
    for i = 1, 2 do
        params:add_taper(i .. "volume", i .. " volume", -60, 20, 0, 0, "dB")
        params:set_action(i .. "volume", function(value) engine.volume(i, math.pow(10, value / 20)) end)
        params:add_taper(i .. "density", i .. " density", 0, 50, 20, 6)
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

local pan_direction = 1  -- 1 for increasing, -1 for decreasing
local function crossfade_pan(delta)
    enc1_position = enc1_position + 2 * delta * pan_direction
    local pan1, pan2
    if enc1_position <= 50 then
        pan1 = -100 + (enc1_position / 50) * 100  -- pan1: -100 to 0
        pan2 = 100 - (enc1_position / 50) * 100   -- pan2: 100 to 0
    else
        pan1 = (enc1_position - 50) / 50 * 100    -- pan1: 0 to 100
        pan2 = -((enc1_position - 50) / 50 * 100) -- pan2: 0 to -100
    end
    if pan1 <= -100 or pan1 >= 100 or pan2 <= -100 or pan2 >= 100 then
        pan_direction = -pan_direction
        enc1_position = enc1_position + 2 * delta * pan_direction  
    end
    params:set("1pan", math.max(-100, math.min(100, pan1)))
    params:set("2pan", math.max(-100, math.min(100, pan2)))
end

function enc(n, d)
    local enc_actions = {
        [1] = function()
            if key1_pressed then
                crossfade_pan(d)
            else
                adjust_volume("1", d)
                adjust_volume("2", d)
            end
        end,
        [2] = function()
            if key1_pressed then
                adjust_volume("1", d)
            else
                if current_mode == "speed" then
                    local current_speed = params:get("1speed")
                    local new_speed = wrap_value(current_speed + (d * 0.01), -4, 4)
                    params:set("1speed", new_speed)
                elseif current_mode == "seek" then
                    local current_seek = params:get("1seek")
                    local new_seek = wrap_value(current_seek + d, 0, 100)
                    params:set("1seek", new_seek)
                    engine.seek(1, new_seek / 100)
                elseif current_mode == "pan" then
                    local current_pan = params:get("1pan")
                    local new_pan = math.max(-100, math.min(100, current_pan + d))
                    params:set("1pan", new_pan)
                elseif current_mode == "jitter" then
                    local current_jitter = params:get("1jitter")
                    local new_jitter = math.max(0, math.min(500, current_jitter + 2*d))
                    params:set("1jitter", new_jitter)
                elseif current_mode == "size" then
                    local current_size = params:get("1size")
                    local new_size = math.max(1, math.min(500, current_size + 2*d))
                    params:set("1size", new_size)
                elseif current_mode == "density" then
                    local current_density = params:get("1density")
                    local new_density = math.max(0, math.min(50, current_density + d))
                    params:set("1density", new_density)
                elseif current_mode == "spread" then
                    local current_spread = params:get("1spread")
                    local new_spread = math.max(0, math.min(100, current_spread + 2*d))
                    params:set("1spread", new_spread)
                elseif current_mode == "pitch" then
                    local current_pitch = params:get("1pitch")
                    local new_pitch = math.max(-48, math.min(48, current_pitch + d))
                    params:set("1pitch", new_pitch)
                end
            end
        end,
        [3] = function()
            if key1_pressed then
                adjust_volume("2", d)
            else
                if current_mode == "speed" then
                    local current_speed = params:get("2speed")
                    local new_speed = wrap_value(current_speed + (d * 0.01), -4, 4)
                    params:set("2speed", new_speed)
                elseif current_mode == "seek" then
                    local current_seek = params:get("2seek")
                    local new_seek = wrap_value(current_seek + d, 0, 100)
                    params:set("2seek", new_seek)
                    engine.seek(2, new_seek / 100)
                elseif current_mode == "pan" then
                    local current_pan = params:get("2pan")
                    local new_pan = math.max(-100, math.min(100, current_pan + d))
                    params:set("2pan", new_pan)
                elseif current_mode == "jitter" then
                    local current_jitter = params:get("2jitter")
                    local new_jitter = math.max(0, math.min(500, current_jitter + 2*d))
                    params:set("2jitter", new_jitter)
                elseif current_mode == "size" then
                    local current_size = params:get("2size")
                    local new_size = math.max(1, math.min(500, current_size + 2*d))
                    params:set("2size", new_size)
                elseif current_mode == "density" then
                    local current_density = params:get("2density")
                    local new_density = math.max(0, math.min(50, current_density + d))
                    params:set("2density", new_density)
                elseif current_mode == "spread" then
                    local current_spread = params:get("2spread")
                    local new_spread = math.max(0, math.min(100, current_spread + 2*d))
                    params:set("2spread", new_spread)
                elseif current_mode == "pitch" then
                    local current_pitch = params:get("2pitch")
                    local new_pitch = math.max(-48, math.min(48, current_pitch + d))
                    params:set("2pitch", new_pitch)
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
            -- Cycle through modes in reverse order: pitch -> spread -> density -> size -> jitter -> pan -> seek -> speed -> pitch
            local modes = {"pitch", "spread", "density", "size", "jitter", "pan", "seek", "speed"}
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
            -- Cycle through modes in forward order: speed -> seek -> pan -> jitter -> size -> density -> spread -> pitch -> speed
            local modes = {"speed", "seek", "pan", "jitter", "size", "density", "spread", "pitch"}
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

    -- Draw the label (shifted 3 pixels to the right)
    screen.move(5, y) -- Shifted 3 pixels to the right
    if is_highlighted then
        screen.level(15) -- Bright text for highlighted row
    else
        screen.level(5) -- Dim text for non-highlighted rows
    end
    screen.text(label)

    -- Draw the parameter values with blinking effect if locked (shifted 3 pixels to the right)
    screen.move(ALI_X + 4, y) -- Shifted 3 pixels to the right
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

    screen.move(ALIDASH_X + 4, y) -- Shifted 3 pixels to the right
    screen.level(1)
    screen.text(" / ")

    screen.move(ALI2_X + 4, y) -- Shifted 3 pixels to the right
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

    local bar_width = 1 -- Width of the volume bars (now 2 pixels)
    local bar1_height = volume_to_height(volume1) -- Height of channel 1 volume bar
    local bar2_height = volume_to_height(volume2) -- Height of channel 2 volume bar

    -- Draw channel 1 volume bar (left side)
    screen.level(5) -- Dim level for the bar background
    screen.rect(0, 64 - bar1_height, bar_width, bar1_height) -- Draw the bar
    screen.fill()

    -- Draw channel 2 volume bar (right side)
    screen.level(5) -- Dim level for the bar background
    screen.rect(128 - bar_width, 64 - bar2_height, bar_width, bar2_height) -- Draw the bar
    screen.fill()

    -- Draw parameter rows with highlighting (shifted 3 pixels to the right)
    draw_param_row(10, "jitter:    ", "1jitter", "2jitter", false, false, current_mode == "jitter")
    draw_param_row(20, "size:     ", "1size", "2size", false, false, current_mode == "size")
    draw_param_row(30, "density:  ", "1density", "2density", true, false, current_mode == "density")
    draw_param_row(40, "spread:   ", "1spread", "2spread", false, false, current_mode == "spread")
    draw_param_row(50, "pitch:    ", "1pitch", "2pitch", false, true, current_mode == "pitch")

    -- Display "seek:", "speed:", or "pan:" based on the current mode (shifted 3 pixels to the right)
    screen.move(5, 60) -- Shifted 3 pixels to the right
    if current_mode == "seek" or current_mode == "pan" or current_mode == "speed" then
        screen.level(15) -- Bright text for highlighted row
    else
        screen.level(5) -- Dim text for non-highlighted rows
    end
    if current_mode == "seek" then
        screen.text("seek:     ")
    elseif current_mode == "pan" then
        screen.text("pan:      ")
    else
        screen.text("speed:    ")
    end

    -- Display track 1 value (always bright if it's the active mode, shifted 3 pixels to the right)
    screen.move(ALI_X + 4, 60) -- Shifted 3 pixels to the right
    if current_mode == "seek" or current_mode == "pan" or current_mode == "speed" then
        screen.level(15) -- Bright text for highlighted row
    else
        screen.level(5) -- Dim text for non-highlighted rows
    end
    if current_mode == "seek" then
        screen.text(format_seek(params:get("1seek"))) -- Display seek for track 1
    elseif current_mode == "pan" then
        screen.text(string.format("%.0f%%", params:get("1pan"))) -- Display pan for track 1 with sign
    else
        local speed1 = params:get("1speed")
        screen.text(string.format("%.2fx", speed1))  -- Display speed for track 1
    end

    -- Display track 2 value (always bright if it's the active mode, shifted 3 pixels to the right)
    screen.move(ALI2_X + 4, 60) -- Shifted 3 pixels to the right
    if current_mode == "seek" or current_mode == "pan" or current_mode == "speed" then
        screen.level(15) -- Bright text for highlighted row
    else
        screen.level(5) -- Dim text for non-highlighted rows
    end
    if current_mode == "seek" then
        screen.text(format_seek(params:get("2seek"))) -- Display seek for track 2
    elseif current_mode == "pan" then
        screen.text(string.format("%.0f%%", params:get("2pan"))) -- Display pan for track 2 with sign
    else
        local speed2 = params:get("2speed")
        screen.text(string.format("%.2fx", speed2))  -- Display speed for track 2
    end

    -- Draw pan indicator bar at the bottom of the screen
    local pan1 = params:get("1pan") -- Get pan value for channel 1 (-100 to 100)
    local pan2 = params:get("2pan") -- Get pan value for channel 2 (-100 to 100)

    -- Convert pan values to screen positions (0 to 128)
    local pan1_pos = util.linlin(-100, 100, 0, 128, pan1)
    local pan2_pos = util.linlin(-100, 100, 0, 128, pan2)

    screen.level(5) 
    screen.rect(pan1_pos - 1, 63, 2, 1) 
    screen.fill()

    screen.level(5) 
    screen.rect(pan2_pos - 1, 63, 2, 1) 
    screen.fill()

    screen.update()
end

function cleanup()
    if ui_metro then ui_metro:stop() end
    if blink_metro then blink_metro:stop() end
    for i = 1, 2 do
        if randomize_metro[i] then randomize_metro[i]:stop() end
    end
end