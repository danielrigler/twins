local randomize_metro = metro.init()
local targets, active_interpolations = {}, {}
local interpolation_speed = 1 / 30

------------------------------------------------------------
-- Utilities
------------------------------------------------------------

local function random_float(l, h)
  return l + math.random() * (h - l)
end

local function interpolate(current, target, threshold, factor)
  if math.abs(current - target) < threshold then
    return target
  end
  return current + (target - current) * (1 - math.exp(-4 * factor))
end

local function clear_table(t)
  for k in pairs(t) do t[k] = nil end
end

------------------------------------------------------------
-- Interpolation Engine
------------------------------------------------------------

local function start_interpolation(steps, symmetry)
  if not next(targets) then return end
  steps = (steps and steps > 0) and steps or 30

  randomize_metro.time = interpolation_speed
  randomize_metro.count = -1
  randomize_metro.event = function(count)
    local factor, all_done = count / steps, true

    for param, data in pairs(targets) do
      if active_interpolations[param] then
        local current, target, threshold = params:get(param), data.target, data.threshold
        local new_value = interpolate(current, target, threshold, factor)
        params:set(param, new_value)

        -- Symmetry: mirror to paired track param
        if symmetry and param:match("^%d") then
          local mirrored = param:gsub("^(%d)(.*)", function(num, rest)
            return (tonumber(num) % 2) + 1 .. rest
          end)
          if params.lookup[mirrored] then
            local mdata = targets[mirrored] or { target = target, threshold = threshold }
            local mnew = interpolate(params:get(mirrored), mdata.target, mdata.threshold, factor)
            params:set(mirrored, mnew)
            if math.abs(mnew - mdata.target) > mdata.threshold then all_done = false end
          end
        end

        -- Check convergence
        if math.abs(new_value - target) > threshold then
          all_done = false
        else
          active_interpolations[param] = nil
        end
      end
    end

    if all_done then
      randomize_metro:stop()
      clear_table(targets)
      clear_table(active_interpolations)
    end
  end
  randomize_metro:start()
end

------------------------------------------------------------
-- Parameter Helpers
------------------------------------------------------------

local function set_param(param, prob, default, random, direct)
  if direct then
    params:set(param,
      (math.random() <= prob)
        and (type(default) == "function" and default() or default)
        or random())
    return
  end

  local val = (math.random() <= prob)
    and (type(default) == "function" and default() or default)
    or random()

  targets[param] = { target = val, threshold = math.max(0.001, math.abs(val) * 0.01) }
  active_interpolations[param] = true
end

local function randomize_param_group(config)
  if params:get(config.lock_param) == 2 then return end
  for _, p in ipairs(config.params) do
    set_param(p.name, p.prob, p.default, p.random, p.direct_set)
  end
end

------------------------------------------------------------
-- Parameter Configurations
------------------------------------------------------------

local param_configs = {
  jpverb = {
    lock_param = "lock_reverb",
    params = {
      {name="t60", prob=0.5, default=4, random=function() return random_float(0.8, 6) end},
      {name="damp", prob=0.4, default=0, random=function() return random_float(0, 25) end},
      {name="rsize", prob=0.3, default=function() return 1 end, random=function() return random_float(1, 4.5) end, direct_set=true},
      {name="earlyDiff", prob=0.5, default=70.7, random=function() return random_float(40.7, 100) end},
      {name="modDepth", prob=0.6, default=10, random=function() return math.random(0, 100) end},
      {name="modFreq", prob=0.6, default=2, random=function() return random_float(0.5, 4) end},
      {name="low", prob=0.6, default=1, random=function() return random_float(0.7, 1) end},
      {name="mid", prob=0.6, default=1, random=function() return random_float(0.7, 1) end},
      {name="high", prob=0.6, default=1, random=function() return random_float(0.7, 1) end},
      {name="lowcut", prob=0.6, default=500, random=function() return math.random(250, 750) end},
      {name="highcut", prob=0.6, default=2000, random=function() return math.random(1500, 3500) end},
    }
  },

  shimmer = {
    lock_param = "lock_shimmer",
    params = {
      {name="o2", prob=0.9, default=function() return 1 end, random=function() return 2 end, direct_set=true},
      {name="pitchv", prob=0.5, default=0.0, random=function() return math.random(0, 2) end},
      {name="lowpass", prob=0.5, default=13000, random=function() return math.random(6000, 15000) end},
      {name="hipass", prob=0.5, default=1300, random=function() return math.random(400, 1500) end},
      {name="fb", prob=0.7, default=15, random=function() return math.random(10, 25) end},
      {name="fbDelay", prob=0.7, default=0.2, random=function() return random_float(0.15, 0.35) end},
    }
  },

  delay = {
    lock_param = "lock_delay",
    params = {
      {name="delay_mix", prob=0.5, default=0, random=function() return math.random(0, 80) end},
      {name="delay_time", prob=0.3, default=function() return 0.5 end, random=function() return random_float(0.15, 1) end, direct_set=true},
      {name="delay_feedback", prob=0.5, default=nil, random=function() return math.random(20, 80) end},
      {name="stereo", prob=0.5, default=25, random=function() return math.random(0, 70) end},
      {name="delay_lowpass", prob=0, default=nil, random=function() return math.random(600, 20000) end},
      {name="delay_highpass", prob=0, default=nil, random=function() return math.random(20, 250) end},
      {name="wiggle_depth", prob=0.7, default=1, random=function() return math.random(0, 10) end},
      {name="wiggle_rate", prob=0.6, default=2, random=function() return random_float(0.5, 4) end},
    }
  },

  tape = {
    lock_param = "lock_tape",
    params = {
      {name="wobble_amp", prob=0.4, default=10, random=function() return math.random(1, 15) end},
      {name="wobble_rpm", prob=0.4, default=33, random=function() return math.random(30, 70) end},
      {name="flutter_amp", prob=0.4, default=15, random=function() return math.random(1, 30) end},
      {name="flutter_freq", prob=0.4, default=6, random=function() return math.random(2, 10) end},
      {name="flutter_var", prob=0.4, default=2, random=function() return math.random(1, 5) end},
    }
  }
}

local track_param_configs = {
  granular = function(track)
    return {
      lock_param = "lock_granular",
      params = {
        {name=track.."direction_mod", prob=0.5, default=0, random=function() return math.random(0, 20) end},
        {name=track.."size_variation", prob=0.5, default=0, random=function() return math.random(0, 40) end},
        {name=track.."density_mod_amt", prob=0.5, default=0, random=function() return math.random(0, 75) end},
        {name=track.."subharmonics_1", prob=0.5, default=0, random=function() return random_float(0, 0.6) end},
        {name=track.."subharmonics_2", prob=0.5, default=0, random=function() return random_float(0, 0.6) end},
        {name=track.."subharmonics_3", prob=0.5, default=0, random=function() return random_float(0, 0.6) end},
        {name=track.."overtones_1", prob=0.5, default=0, random=function() return random_float(0, 0.6) end},
        {name=track.."overtones_2", prob=0.5, default=0, random=function() return random_float(0, 0.6) end},
        {name=track.."pitch_random_plus", prob=0.8, default=0, random=function() return math.random(0, 25) end},
        {name=track.."pitch_random_minus", prob=0.8, default=0, random=function() return math.random(0, 25) end},
      }
    }
  end,

  eq = function(track)
    return {
      lock_param = "lock_eq",
      params = {
        {name=track.."eq_low_gain", prob=0.4, default=0, random=function() return random_float(-0.15, 0.15) end},
        {name=track.."eq_mid_gain", prob=0.6, default=0, random=function() return random_float(-0.2, 0.05) end},
        {name=track.."eq_high_gain", prob=0.4, default=0.2, random=function() return random_float(-0.1, 0.35) end},
      }
    }
  end
}

------------------------------------------------------------
-- Main Randomizer
------------------------------------------------------------

local function randomize_track(track, steps, group_fns)
  for _, fn in ipairs(group_fns) do
    randomize_param_group(fn(track))
  end
  start_interpolation(steps, params:get("symmetry") == 1)
end

local function randomize_params(steps, track_num)
  track_num = track_num or 1
  if randomize_metro.running then randomize_metro:stop() end
  clear_table(targets)
  clear_table(active_interpolations)

  local symmetry = (params:get("symmetry") == 1)

  -- Global FX
  for _, group in ipairs({param_configs.tape, param_configs.delay, param_configs.jpverb, param_configs.shimmer}) do
    randomize_param_group(group)
  end

  -- Track FX
  if symmetry then
    randomize_track(1, steps, {track_param_configs.eq, track_param_configs.granular})
    -- Mirror track 1 â†’ 2
    for param, data in pairs(targets) do
      if param:sub(1,1) == tostring(track_num) then
        local mirrored = param:gsub("^(%d)(.*)", function(num, rest)
          return (tonumber(num) % 2) + 1 .. rest
        end)
        if params.lookup[mirrored] then
          targets[mirrored] = { target = data.target, threshold = data.threshold }
          active_interpolations[mirrored] = true
        end
      end
    end
  else
    randomize_track(track_num, steps, {track_param_configs.eq, track_param_configs.granular})
  end

  start_interpolation(steps, symmetry)
end

------------------------------------------------------------
-- Convenience Wrappers
------------------------------------------------------------

local function randomize_jpverb_params(steps)
  if randomize_metro.running then randomize_metro:stop() end
  randomize_param_group(param_configs.jpverb)
  start_interpolation(steps, params:get("symmetry") == 1)
end

local function randomize_shimmer_params(steps)
  if randomize_metro.running then randomize_metro:stop() end
  randomize_param_group(param_configs.shimmer)
  start_interpolation(steps, params:get("symmetry") == 1)
end

local function randomize_delay_params(steps)
  if randomize_metro.running then randomize_metro:stop() end
  randomize_param_group(param_configs.delay)
  start_interpolation(steps, params:get("symmetry") == 1)
end

local function randomize_tape_params(steps)
  if randomize_metro.running then randomize_metro:stop() end
  randomize_param_group(param_configs.tape)
  start_interpolation(steps, params:get("symmetry") == 1)
end

local function randomize_granular_params(track, steps)
  if randomize_metro.running then randomize_metro:stop() end
  randomize_param_group(track_param_configs.granular(track))
  start_interpolation(steps, params:get("symmetry") == 1)
end

local function randomize_eq_params(track, steps)
  if randomize_metro.running then randomize_metro:stop() end
  randomize_param_group(track_param_configs.eq(track))
  start_interpolation(steps, params:get("symmetry") == 1)
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------

return {
  randomize_params          = randomize_params,
  randomize_group           = randomize_param_group,

  -- convenience wrappers
  randomize_jpverb_params   = randomize_jpverb_params,
  randomize_shimmer_params  = randomize_shimmer_params,
  randomize_delay_params    = randomize_delay_params,
  randomize_tape_params     = randomize_tape_params,
  randomize_granular_params = randomize_granular_params,
  randomize_eq_params       = randomize_eq_params,
}