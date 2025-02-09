--  __ __|       _)             
--     | \ \  \ / |    \  (_-< 
--    _|  \_/\_/ _| _| _| ___/ 
--    by: @cfd90 & @dddstudio                       
--
-- E1: Master Volume
-- E2: Seek1 / Varispeed |>
-- E3: Seek2 / Varispeed |>
-- K1: Shift
-- K2: Randomize1
-- K3: Randomize2
-- K2/K3 double tap: Stop Rand.
-- k1+K2: Play1 / Stop
-- K1+K3: Play2 / Stop
-- K1+E1: Seek1 >< Seek2
-- K1+E2: Volume1
-- K1+E3: Volume2


halfsecond = include("lib/halfsecond")

installer_ = include("lib/scinstaller/scinstaller")
installer = installer_:new{
    requirements = {"Fverb2", "Fverb", "AnalogTape", "AnalogChew", "AnalogLoss", "AnalogDegrade"},
    zip = "https://github.com/schollz/portedplugins/releases/download/v0.4.6/PortedPlugins-RaspberryPi.zip"
}

engine.name = installer:ready() and 'twins' or nil

local ui_metro
local steps = 600
local ALI_X = 42
local ALI2_X = 89
local ALIDASH_X = 73
local randomize_metro = { [1] = nil, [2] = nil } -- Track randomization metronomes for both tracks
local key1_pressed = false
local key2_pressed = false
local key3_pressed = false
local enc1_position = 0
local initial_seek1, initial_seek2 = 0, 0
local automation_metro1 = nil
local automation_metro2 = nil
local automation_speed1 = 0
local automation_speed2 = 0
local automation_active1 = false
local automation_active2 = false
local speed_scale = 0.25
local speed_increment = 0.1
local smoothing_factor = 0.1
local min_speed = -10
local max_speed = 10

-- New variables for double press detection
local last_key2_press_time = 0
local last_key3_press_time = 0
local double_press_threshold = 0.3 -- seconds

-- Blinking effect variables
local blink_state = false
local blink_metro = metro.init()
blink_metro.time = 0.5 -- Blink every 0.5 seconds
blink_metro.event = function()
    blink_state = not blink_state
    redraw()
end
blink_metro:start()

-- Custom menu variables
local menu_page = 1 -- Current menu page (1 for track 1, 2 for track 2)
local menu_param_index = 1 -- Current parameter index in the menu
local menu_params = {
    "jitter", "size", "density", "spread", "pitch"
}

local function setup_ui_metro()
  ui_metro = metro.init()
  ui_metro.time = 1/15
  ui_metro.event = function()
    redraw()
  end
  ui_metro:start()
end

local function setup_params()
  params:add_separator("Samples")
  
  for i=1,2 do
    params:add_file(i .. "sample", i .. " sample")
    params:set_action(i .. "sample", function(file) engine.read(i, file) end)
    
    params:add_taper(i .. "volume", i .. " volume", -60, 20, 0, 0, "dB")
    params:set_action(i .. "volume", function(value) engine.volume(i, math.pow(10, value / 20)) end)
 
    params:add_taper(i .."pan", i .. " pan", -100, 100, 0, 0, "%")
    params:set_action(i .."pan", function(value) engine.pan(i, value / 100) end)
  
    params:add_taper(i .. "speed", i .. " speed", -400, 400, 0, 0, "%")
    params:set_action(i .. "speed", function(value) engine.speed(i, value / 100) end)
  
    params:add_taper(i .. "jitter", i .. " jitter", 0, 500, 250, 5, "ms")
    params:set_action(i .. "jitter", function(value) engine.jitter(i, value / 1000) end)
  
    params:add_taper(i .. "size", i .. " size", 1, 500, 100, 5, "ms")
    params:set_action(i .. "size", function(value) engine.size(i, value / 1000) end)
  
    params:add_taper(i .. "density", i .. " density", 0, 50, 20, 6)
    params:set_action(i .. "density", function(value) engine.density(i, value) end)
  
    params:add_taper(i .. "pitch", i .. " pitch", -48, 48, 0, 0)
    params:set_action(i .. "pitch", function(value) engine.pitch(i, math.pow(0.5, -value / 12)) end)
    
    params:add_taper(i .. "spread", i .. " spread", 0, 100, 0, 0, "%")
    params:set_action(i .. "spread", function(value) engine.spread(i, value / 100) end)
    
    params:add_control(i .. "seek", i .. " seek", controlspec.new(0, 100, "lin", 0.01, 0, "%", 0.01/100))
    params:set_action(i .. "seek", function(value) engine.seek(i, value / 10) end)
    
    params:hide(i .. "speed")
    params:hide(i .. "volume")
    params:hide(i .. "jitter")
    params:hide(i .. "size")
    params:hide(i .. "pitch")
    params:hide(i .. "spread")
    params:hide(i .. "seek")
  end

params:add_separator("Transition")

  params:add_control("steps", "steps", controlspec.new(10, 500000, "lin", 1, 600, ""))
  params:set_action("steps", function(value) steps = value end)

  halfsecond.init()
  
  params:add_group("Fverb2",12)

params:add_taper("reverb_mix", "Mix", 0, 100, 16.5, 0, "%")
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


params:add_group("Randomizer",10)
  params:add_taper("min_jitter", "jitter (min)", 0, 500, 0, 5, "ms")
  params:add_taper("max_jitter", "jitter (max)", 0, 500, 500, 5, "ms")
  
  params:add_taper("min_size", "size (min)", 1, 500, 1, 5, "ms")
  params:add_taper("max_size", "size (max)", 1, 500, 500, 5, "ms")
  
  params:add_taper("min_density", "density (min)", 0, 50, 0, 6, "Hz")
  params:add_taper("max_density", "density (max)", 0, 512, 50, 6, "Hz")
  
  params:add_taper("min_spread", "spread (min)", 0, 100, 0, 0, "%")
  params:add_taper("max_spread", "spread (max)", 0, 100, 100, 0, "%")
  
  params:add_control("min_pitch", "pitch (min)", controlspec.new(-48, 48, "lin", 1, -12, "st"))
  params:add_control("max_pitch", "pitch (max)", controlspec.new(-48, 48, "lin", 1, 12, "st"))

  params:add_group("Locking",10) 
  for i=1,2 do
    params:add_option(i .. "lock_jitter", i .. " lock jitter", {"off", "on"}, 1)
    params:add_option(i .. "lock_size", i .. " lock size", {"off", "on"}, 1)
    params:add_option(i .. "lock_density", i .. " lock density", {"off", "on"}, 1)
    params:add_option(i .. "lock_spread", i .. " lock spread", {"off", "on"}, 1)
    params:add_option(i .. "lock_pitch", i .. " lock pitch", {"off", "on"}, 1)
  end
  
  params:bang()
end

local function random_float(l, h)
    return l + math.random() * (h - l)
end

local function interpolate(start_val, end_val, factor)
  return start_val + (end_val - start_val) * factor
end

local function randomize(n)
    if not randomize_metro[n] then
        randomize_metro[n] = metro.init()
    end
  
    randomize_metro[n]:stop()
  
    local targets = {}
    if params:get(n .. "lock_jitter") == 1 then
        targets.jitter = random_float(params:get("min_jitter"), params:get("max_jitter"))
    end
    if params:get(n .. "lock_size") == 1 then
        targets.size = random_float(params:get("min_size"), params:get("max_size"))
    end
    if params:get(n .. "lock_density") == 1 then
        targets.density = random_float(params:get("min_density"), params:get("max_density"))
    end
    if params:get(n .. "lock_spread") == 1 then
        targets.spread = random_float(params:get("min_spread"), params:get("max_spread"))
    end
    if params:get(n .. "lock_pitch") == 1 then
        targets.pitch = math.floor(random_float(params:get("min_pitch"), params:get("max_pitch")) + 0.5)
    end
  
    local step_duration = 0.05
  
    randomize_metro[n].time = step_duration
    randomize_metro[n].count = steps
    randomize_metro[n].event = function(count)
        local factor = count / steps
        for param, target in pairs(targets) do
            params:set(n .. param, interpolate(params:get(n .. param), target, factor))
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
  
local function crossfade_seek(delta)
  enc1_position = enc1_position + 0.5 * delta
  enc1_position = wrap_value(enc1_position, 0, 100)
  local seek1 = wrap_value(initial_seek1 + enc1_position, 0, 100)
  local seek2 = wrap_value(initial_seek2 - enc1_position, 0, 100)
  params:set("1seek", seek1)
  params:set("2seek", seek2)
end

local function automate_seek1()
  if automation_metro1 == nil then
    automation_metro1 = metro.init()
    automation_metro1.time = 0.1  
    automation_metro1.event = function()
      local current_seek = params:get("1seek")
      local new_seek = wrap_value(current_seek + automation_speed1 * speed_scale, 0, 100)
      params:set("1seek", new_seek)
    end
  end
  if automation_active1 then
    automation_metro1:start()
  else
    automation_metro1:stop()
  end
end
  
local function automate_seek2()
  if automation_metro2 == nil then
    automation_metro2 = metro.init()
    automation_metro2.time = 0.1  
    automation_metro2.event = function()
      local current_seek = params:get("2seek")
      local new_seek = wrap_value(current_seek + automation_speed2 * speed_scale, 0, 100)
      params:set("2seek", new_seek)
    end
  end

  if automation_active2 then
    automation_metro2:start()
  else
    automation_metro2:stop()
  end
end
  
function enc(n, d)
  if automation_active1 and n == 2 and not key1_pressed then
    automation_speed1 = util.clamp(automation_speed1 + d * speed_increment, min_speed, max_speed)
  elseif automation_active2 and n == 3 and not key1_pressed then
    automation_speed2 = util.clamp(automation_speed2 + d * speed_increment, min_speed, max_speed)
  elseif key1_pressed then
    if n == 1 then
      crossfade_seek(d)
    elseif n == 2 then
      adjust_volume("1", d)
    elseif n == 3 then
      adjust_volume("2", d)
    end
  else
    if n == 1 then
      adjust_volume("1", d)
      adjust_volume("2", d)
    elseif n == 2 then
      local current_seek = params:get("1seek")
      local new_seek = wrap_value(current_seek + 0.1 * d, 0, 100)
      params:set("1seek", new_seek)
    elseif n == 3 then
      local current_seek = params:get("2seek")
      local new_seek = wrap_value(current_seek + 0.1 * d, 0, 100)
      params:set("2seek", new_seek)
    end
  end
end
  
function key(n, z)
  if n == 1 then
    key1_pressed = z == 1
    if z == 1 then
      initial_seek1 = params:get("1seek")
      initial_seek2 = params:get("2seek")
      enc1_position = 0
    else
      enc1_position = 0
    end
  elseif n == 2 then
    key2_pressed = z == 1
    if z == 1 and not key1_pressed then -- Only trigger randomization if key1 is NOT pressed
      local current_time = util.time()
      if current_time - last_key2_press_time < double_press_threshold then
        -- Double press: freeze randomization for track 1
        if randomize_metro[1] then
          randomize_metro[1]:stop()
        end
      else
        -- Single press: restart randomization for track 1
        randomize(1)
      end
      last_key2_press_time = current_time
    end
  elseif n == 3 then
    key3_pressed = z == 1
    if z == 1 and not key1_pressed then -- Only trigger randomization if key1 is NOT pressed
      local current_time = util.time()
      if current_time - last_key3_press_time < double_press_threshold then
        -- Double press: freeze randomization for track 2
        if randomize_metro[2] then
          randomize_metro[2]:stop()
        end
      else
        -- Single press: restart randomization for track 2
        randomize(2)
      end
      last_key3_press_time = current_time
    end
  end

  if z == 1 and key1_pressed and key2_pressed then
    automation_active1 = not automation_active1
    automate_seek1()
  end

  if z == 1 and key1_pressed and key3_pressed then
    automation_active2 = not automation_active2
    automate_seek2()
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
  return string.format("%.1f%%", value)
end

-- Helper function to check if a parameter is locked
local function is_param_locked(track_num, param)
  return params:get(track_num .. "lock_" .. param) == 2
end

local function draw_param_row(y, label, param1, param2, is_density, is_pitch)
    -- Determine if the parameter is locked for either track
    local param_name = string.match(label, "%a+") -- Extract the parameter name (e.g., "jitter" from "jitter:")
    local is_locked1 = is_param_locked(1, param_name)
    local is_locked2 = is_param_locked(2, param_name)

    -- Draw the label
    screen.move(0, y)
    screen.level(15)
    screen.text(label)

    -- Draw the parameter values with blinking effect if locked
    screen.move(ALI_X, y)
    if is_locked1 and blink_state then
        screen.level(0) -- Hide the value when blinking
    else
        screen.level(5)
    end
    if is_density then
        screen.text(format_density(params:get(param1)))
    elseif is_pitch then
        screen.text(format_pitch(params:get(param1)))
    else
        screen.text(params:string(param1))
    end

    screen.move(ALIDASH_X, y)
    screen.level(1)
    screen.text(" / ")

    screen.move(ALI2_X, y)
    if is_locked2 and blink_state then
        screen.level(0) -- Hide the value when blinking
    else
        screen.level(5)
    end
    if is_density then
        screen.text(format_density(params:get(param2)))
    elseif is_pitch then
        screen.text(format_pitch(params:get(param2)))
    else
        screen.text(params:string(param2))
    end
end

local function is_audio_loaded(track_num)
    local file_param = track_num .. "sample"
    local file_path = params:get(file_param)
    return file_path ~= nil and file_path ~= "" and file_path ~= "none" and file_path ~= "-"
end

function redraw()
  screen.clear()

  draw_param_row(10, "jitter:    ", "1jitter", "2jitter")
  draw_param_row(20, "size:     ", "1size", "2size")
  draw_param_row(30, "density:  ", "1density", "2density", true)
  draw_param_row(40, "spread:   ", "1spread", "2spread")
  draw_param_row(50, "pitch:    ", "1pitch", "2pitch", false, true)

  screen.move(0, 60)
  screen.level(15)
  screen.text("seek:     ")

  if is_audio_loaded(1) then
    screen.level(15)
  else
    screen.level(5)
  end
  screen.move(ALI_X, 60)
  screen.text(format_seek(params:get("1seek")))

  if is_audio_loaded(2) then
    screen.level(15)
  else
    screen.level(5)
  end
  screen.move(ALI2_X, 60)
  screen.text(format_seek(params:get("2seek")))

  if automation_active1 then
    screen.move(69, 60)
    screen.level(15)
    screen.text("|>")
  end

  if automation_active2 then
    screen.move(116, 60)
    screen.level(15)
    screen.text("|>")
  end

  screen.update()
end