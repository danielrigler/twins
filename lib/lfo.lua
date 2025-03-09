local number_of_outputs = 8
local tau = math.pi * 2

local options = {
  lfotypes = {
    "sine",
    "square",
    "random"
  }
}

local lfo = {}
for i = 1, number_of_outputs do
  lfo[i] = {
    freq = 0.01,
    counter = 1,
    waveform = options.lfotypes[1],
    slope = 0,
    depth = 15,
    offset = .25
  }
end

function lfo.clearLFOs()
    for i = 1, 8 do
        if params:get(i .. "lfo") == 2 then
            params:set(i .. "lfo", 1) -- Turn off the LFO
        end
        params:set(i .. "lfo_target", 1) -- Reset LFO target to "none"
    end
end

-- Define lfo_targets as part of the lfo table
lfo.lfo_targets = {
    "none", "1pan", "2pan", "1speed", "2speed", "1seek", "2seek", "1jitter", "2jitter", 
    "1spread", "2spread", "1size", "2size", "1density", "2density", "1volume", "2volume", 
    "1pitch", "2pitch", "1cutoff", "2cutoff", "time", "size", "damp", "diff", "feedback", 
    "mod_depth", "mod_freq"
}


-- Define individual ranges for each LFO target
lfo.target_ranges = {
    ["1pan"] = {
        depth = { min = 20, max = 90 },       
        offset = { min = 0, max = 0 },   
        frequency = { min = 0.02, max = 0.3 }, 
        waveform = { "sine" }, 
        chance = 0.8 
    },
    ["2pan"] = {
        depth = { min = 20, max = 90 },       
        offset = { min = 0, max = 0 },   
        frequency = { min = 0.02, max = 0.3 }, 
        waveform = { "sine" },
        chance = 0.8
    },
    ["1jitter"] = {
        depth = { min = 2, max = 70 },
        offset = { min = -0.5, max = 0.3 },
        frequency = { min = 0.01, max = 0.1 },
        waveform = { "sine" },
        chance = 0.6
    },
    ["2jitter"] = {
        depth = { min = 2, max = 70 },
        offset = { min = -0.5, max = 0.3 },
        frequency = { min = 0.01, max = 0.1 },
        waveform = { "sine" },
        chance = 0.6
    },
    ["1spread"] = {
        depth = { min = 2, max = 50 },
        offset = { min = -0.5, max = 0.2 },
        frequency = { min = 0.01, max = 0.1 },
        waveform = { "sine" },
        chance = 0.6
    },
    ["2spread"] = {
        depth = { min = 2, max = 50 },
        offset = { min = -0.5, max = 0.2 },
        frequency = { min = 0.01, max = 0.1 },
        waveform = { "sine" },
        chance = 0.6
    },
    ["1size"] = {
        depth = { min = 2, max = 50 },
        offset = { min = -0.6, max = 0.6 },
        frequency = { min = 0.01, max = 0.1 },
        waveform = { "sine" },
        chance = 0.6
    },
    ["2size"] = {
        depth = { min = 2, max = 50 },
        offset = { min = -0.6, max = 0.6 },
        frequency = { min = 0.01, max = 0.1 },
        waveform = { "sine" },
        chance = 0.6
    },
    ["1density"] = {
        depth = { min = 2, max = 40 },
        offset = { min = -0.7, max = 0.4 },
        frequency = { min = 0.01, max = 0.1 },
        waveform = { "sine" },
        chance = 0.6
    },
    ["2density"] = {
        depth = { min = 2, max = 40 },
        offset = { min = -0.7, max = 0.4 },
        frequency = { min = 0.01, max = 0.1 },
        waveform = { "sine" },
        chance = 0.6
    }
}

function lfo.randomize_lfos()
      lfo.clearLFOs()
      params:set("1pan", -15)
      params:set("2pan", 15)
    -- Create a list of available LFO targets based on their chances
    local available_targets = {}
    for target, ranges in pairs(lfo.target_ranges) do
        if math.random() < ranges.chance then -- Use the chance value for selection
            table.insert(available_targets, target)
        end
    end

    -- Randomly select 8 targets from the available ones
    local selected_targets = {}
    for i = 1, 8 do
        if #available_targets > 0 then
            -- Randomly pick a target from the available list
            local index = math.random(1, #available_targets)
            table.insert(selected_targets, available_targets[index])
            -- Remove the selected target from the available list to avoid duplicates
            table.remove(available_targets, index)
        else
            -- If no more targets are available, break the loop
            break
        end
    end

    -- Assign random LFO parameters to each selected target
    for i, target in ipairs(selected_targets) do
        -- Find the index of the target in the lfo_targets list
        local target_index = 1
        for j, t in ipairs(lfo.lfo_targets) do
            if t == target then
                target_index = j
                break
            end
        end

        -- Assign the target to the LFO
        params:set(i .. "lfo_target", target_index)

        -- Get the ranges for this target
        local ranges = lfo.target_ranges[target]

        -- Randomize LFO parameters based on the target's ranges
        if ranges.depth then
            -- Randomize depth within the specified range
            lfo[i].depth = math.random(ranges.depth.min, ranges.depth.max)
            -- Update the corresponding parameter
            params:set(i .. "lfo_depth", lfo[i].depth)
        end

        if ranges.offset then
            -- Randomize offset within the specified range
            lfo[i].offset = math.random(ranges.offset.min * 100, ranges.offset.max * 100) / 100
            -- Update the corresponding parameter
            params:set(i .. "offset", lfo[i].offset)
        end

        if ranges.frequency then
            -- Randomize frequency within the specified range
            lfo[i].freq = math.random(ranges.frequency.min * 100, ranges.frequency.max * 100) / 100
            -- Update the corresponding parameter
            params:set(i .. "lfo_freq", lfo[i].freq)
        end

        if ranges.waveform then
            -- Randomly select a waveform from the available options
            local waveform_index = math.random(1, #ranges.waveform)
            lfo[i].waveform = ranges.waveform[waveform_index]
            -- Update the corresponding parameter
            params:set(i .. "lfo_shape", waveform_index)
        end

        -- Turn on the LFO
        params:set(i .. "lfo", 2)
    end
end

function lfo.process()
  for i = 1, 8 do
    local target = params:get(i .. "lfo_target")
    if params:get(i .. "lfo") == 2 then
      if target == 2 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, -100.00, 100.00)) --1pan
      elseif target == 3 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, -100.00, 100.00)) --2pan
      elseif target == 4 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, -2.00, 2.00)) --1speed
      elseif target == 5 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, -2.00, 2.00)) --2speed
      elseif target == 6 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 0, 100)) --1seek
      elseif target == 7 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 0, 100)) --2seek
      elseif target == 8 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 0, 1999)) --1jitter
      elseif target == 9 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 0, 1999)) --2jitter
      elseif target == 10 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 0, 100)) --1spread
      elseif target == 11 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 0, 100)) --2spread
      elseif target == 12 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 1, 400)) --1size
      elseif target == 13 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 1, 400)) --2size
      elseif target == 14 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 1, 20)) --1density
      elseif target == 15 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 1, 20)) --2density
      elseif target == 16 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, -100.00, 100.00)) --1volume
      elseif target == 17 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, -100.00, 100.00)) --2volume
      elseif target == 18 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, -12.00, 12.00)) --1pitch
      elseif target == 19 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, -12.00, 12.00)) --2pitch
      elseif target == 20 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 20, 20000)) --1cutoff
      elseif target == 21 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 1.0, 20, 20000)) --2cutoff
      elseif target == 22 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 2.0, 0.00, 6.00)) --GH time
      elseif target == 23 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 2.0, 0.50, 5.00)) --GH size
      elseif target == 24 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 2.0, 0.00, 1.00)) --GH damp
      elseif target == 25 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 2.0, 0.00, 1.00)) --GH diff
      elseif target == 26 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 2.0, 0.00, 1.00)) --GH fdbck
      elseif target == 27 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 2.0, 0.00, 1.00)) --GH mod dpth
      elseif target == 28 then params:set(lfo.lfo_targets[target], lfo.scale(lfo[i].slope, -1.0, 2.0, 0.00, 10.00)) --GH mod frq
      end
    end
  end
end

function lfo.scale(old_value, old_min, old_max, new_min, new_max)
  -- scale ranges
  local old_range = old_max - old_min

  if old_range == 0 then
    old_range = new_min
  end

  local new_range = new_max - new_min
  local new_value = (((old_value - old_min) * new_range) / old_range) + new_min

  return new_value
end

local function make_sine(n)
  return 1 * math.sin(((tau / 100) * (lfo[n].counter)) - (tau / (lfo[n].freq / 1000)))
end

local function make_square(n)
  return make_sine(n) >= 0 and 1 or -1
end

local function make_sh(n)
  local polarity = make_square(n)
  if lfo[n].prev_polarity ~= polarity then
    lfo[n].prev_polarity = polarity
    return math.random() * (math.random(0, 1) == 0 and 1 or -1)
  else
    return lfo[n].prev
  end
end

function lfo.init()
  for i = 1, number_of_outputs do
    params:add_separator("LFO " .. i)
    -- modulation destination
    params:add_option(i .. "lfo_target", i .. " target", lfo.lfo_targets, 1)
    -- lfo shape
    params:add_option(i .. "lfo_shape", i .. " shape", options.lfotypes, 1)
    params:set_action(i .. "lfo_shape", function(value) lfo[i].waveform = options.lfotypes[value] end)
    -- lfo depth
    params:add_number(i .. "lfo_depth", i .. " depth", 0, 100, 25)
    params:set_action(i .. "lfo_depth", function(value) lfo[i].depth = value end)
    -- lfo offset
    params:add_control(i .."offset", i .. " offset", controlspec.new(-0.99, 1.99, "lin", 0.01, 0.15, ""))
    params:set_action(i .. "offset", function(value) lfo[i].offset = value end)
    -- lfo speed
    params:add_control(i .. "lfo_freq", i .. " freq", controlspec.new(0.01, 10.00, "lin", 0.01, 0.1, ""))
    params:set_action(i .. "lfo_freq", function(value) lfo[i].freq = value end)
    -- lfo on/off
    params:add_option(i .. "lfo", i .. " LFO", {"off", "on"}, 1)
  end

  local lfo_metro = metro.init()
  lfo_metro.time = .01
  lfo_metro.count = -1
  lfo_metro.event = function()
    for i = 1, number_of_outputs do
      if params:get(i .. "lfo") == 2 then
        local slope
        if lfo[i].waveform == "sine" then
          slope = make_sine(i)
        elseif lfo[i].waveform == "square" then
          slope = make_square(i)
        elseif lfo[i].waveform == "random" then
          slope = make_sh(i)
        end
        lfo[i].prev = slope
        lfo[i].slope = math.max(-1.0, math.min(1.0, slope)) * (lfo[i].depth * 0.01) + lfo[i].offset
        lfo[i].counter = lfo[i].counter + lfo[i].freq
      end
    end
    lfo.process()
  end
  lfo_metro:start()
end

return lfo