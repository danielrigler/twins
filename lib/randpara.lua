local randomize_metro = metro.init()
local evolution_metro = metro.init()
local targets, active_interpolations = {}, {}
local interpolation_speed = 1 / 30

local evolution_active         = false
local evolution_range          = 0.15
local evolution_states         = {}
local evolution_update_rate    = 1 / 8
local evolvable_params_cache   = {}
local cache_dirty              = true
local evolution_symmetry_state = false

local utils = include("lib/utils")
local random_float    = utils.random_float
local stop_metro_safe = utils.stop_metro_safe

local function clear_table(t) for k in pairs(t) do t[k] = nil end end

local function interpolate(current, target, threshold, factor)
  if math.abs(current - target) < threshold then return target end
  return current + (target - current) * (1 - math.exp(-4 * factor))
end

local function mirror_param_name(param)
  return param:gsub("^(%d)(.*)", function(n, rest)
    return tostring((tonumber(n) % 2) + 1) .. rest
  end)
end

local PARAM_SPECS = {
  ["1direction_mod"]      = {100, {0,100},   "granular"}, ["2direction_mod"]   = {100, {0,100},   "granular"},
  ["1size_variation"]     = {100, {0,100},   "granular"}, ["2size_variation"]  = {100, {0,100},   "granular"},
  ["1density_mod_amt"]    = {100, {0,100},   "granular"}, ["2density_mod_amt"] = {100, {0,100},   "granular"},
  ["1subharmonics_1"]     = {1,   {0,1},     "granular"}, ["2subharmonics_1"]  = {1,   {0,1},     "granular"},
  ["1subharmonics_2"]     = {1,   {0,1},     "granular"}, ["2subharmonics_2"]  = {1,   {0,1},     "granular"},
  ["1subharmonics_3"]     = {1,   {0,1},     "granular"}, ["2subharmonics_3"]  = {1,   {0,1},     "granular"},
  ["1overtones_1"]        = {1,   {0,1},     "granular"}, ["2overtones_1"]     = {1,   {0,1},     "granular"},
  ["1overtones_2"]        = {1,   {0,1},     "granular"}, ["2overtones_2"]     = {1,   {0,1},     "granular"},
  ["1ratcheting_prob"]    = {25,  {0,100},   "granular"}, ["2ratcheting_prob"] = {25,  {0,100},   "granular"},
  ["delay_feedback"]      = {100, {0,100},   "delay"},
  ["delay_time"]          = {2,   {0,2},     "delay"},
  ["stereo"]              = {50,  {0,100},   "delay"},
  ["wiggle_depth"]        = {40,  {0,100},   "delay"},
  ["wiggle_rate"]         = {6,   {0,6},     "delay"},
  ["delay_lowpass"]       = {10000,{500,20000},"delay"},
  ["delay_highpass"]      = {250, {20,20000},"delay"},
  ["t60"]                 = {8,   {0.1,8},   "reverb"},
  ["damp"]                = {100, {0,100},   "reverb"},
  ["shimmer_mix"]         = {25,  {0,100},   "reverb"},
  ["shimmer_preset"]      = {2,   {1,5},     "reverb"},
  ["earlyDiff"]           = {100, {0,100},   "reverb"},
  ["modDepth"]            = {100, {0,100},   "reverb"},
  ["rsize"]               = {0.4, {0.5,5},   "reverb"},
  ["modFreq"]             = {5,   {0,5},     "reverb"},
  ["low"]                 = {1,   {0,1},     "reverb"},
  ["mid"]                 = {1,   {0,1},     "reverb"},
  ["high"]                = {1,   {0,1},     "reverb"},
  ["lowcut"]              = {4000,{100,4000},"reverb"},
  ["highcut"]             = {4000,{1000,4000},"reverb"},
  ["wobble_amp"]          = {100, {0,100},   "tape"},
  ["wobble_rpm"]          = {90,  {30,90},   "tape"},
  ["flutter_amp"]         = {100, {0,100},   "tape"},
  ["flutter_freq"]        = {30,  {3,30},    "tape"},
  ["flutter_var"]         = {10,  {0.1,10},  "tape"},
  ["pitchv1"]             = {4,   {0,4},     "shimmer"},
  ["lowpass1"]            = {20000,{100,20000},"shimmer"},
  ["shimmer_oct1"]        = {2,   {1,5},     "shimmer"},
  ["hipass1"]             = {4000,{20,4000}, "shimmer"},
  ["fb1"]                 = {80,  {0,80},    "shimmer"},
  ["fbDelay1"]            = {1,   {0.02,1},  "shimmer"},
  ["bitcrush_rate"]       = {5500,{3500,5500},"bitcrush"},
  ["bitcrush_bits"]       = {2,   {12,16},   "bitcrush"},
  ["chew_freq"]           = {60,  {1,60},    "chew"},
  ["chew_variance"]       = {70,  {0,70},    "chew"},
  ["1eq_low_gain"]        = {0.2, {0,1},     "eq"}, ["2eq_low_gain"]  = {0.2,{0,1},"eq"},
  ["1eq_mid_gain"]        = {0.2, {0,1},     "eq"}, ["2eq_mid_gain"]  = {0.2,{0,1},"eq"},
  ["1eq_high_gain"]       = {0.2, {0,1},     "eq"}, ["2eq_high_gain"] = {0.2,{0,1},"eq"},
}

local GROUP_LOCK = {
  granular = "lock_granular", delay   = "lock_delay",
  reverb   = "lock_reverb",  tape    = "lock_tape",
  shimmer  = "lock_shimmer", eq      = "lock_eq",
  filter   = "lock_filter",  pitch   = "lock_pitch",
}

local function build_evolvable_params_cache(force)
  if not cache_dirty and not force then return end
  local n = 0
  for param, spec in pairs(PARAM_SPECS) do
    local lock = GROUP_LOCK[spec[3]]
    local locked = lock and params.lookup[lock] and params:get(lock) == 2
    if params.lookup[param] and not locked then
      n = n + 1
      evolvable_params_cache[n] = param
    end
  end
  for i = n + 1, #evolvable_params_cache do evolvable_params_cache[i] = nil end
  local valid = {}
  for i = 1, n do valid[evolvable_params_cache[i]] = true end
  for name in pairs(evolution_states) do
    if not valid[name] then evolution_states[name] = nil end
  end
  cache_dirty = false
end

local function init_evolution_state(name)
  if evolution_states[name] then return end
  local spec = PARAM_SPECS[name]
  local max_range = spec and spec[1] or 1
  evolution_states[name] = {
    center_value         = params:get(name),
    current_drift        = 0,
    velocity             = 0,
    momentum_decay       = random_float(0.92, 0.98),
    direction_change_prob= random_float(0.03, 0.08),
    max_drift_range      = max_range * evolution_range}
end

local function evolve_parameter(name, state)
  if math.random() < state.direction_change_prob then state.velocity = random_float(-state.max_drift_range / 50, state.max_drift_range / 50) end
  state.velocity      = state.velocity * state.momentum_decay
                      + random_float(-1, 1) * (state.max_drift_range / 30)
  state.current_drift = util.clamp(state.current_drift + state.velocity, -state.max_drift_range, state.max_drift_range)
  local new_value = state.center_value + state.current_drift
  local spec = PARAM_SPECS[name]
  local bounds = spec and spec[2]
  if bounds then
    if new_value < bounds[1] then
      new_value = bounds[1]
      state.velocity = -state.velocity * random_float(0.3, 0.7)
      state.current_drift = new_value - state.center_value
    elseif new_value > bounds[2] then
      new_value = bounds[2]
      state.velocity = -state.velocity * random_float(0.3, 0.7)
      state.current_drift = new_value - state.center_value
    end
  end
  return new_value
end

local function evolution_update()
  if not evolution_active then return end
  build_evolvable_params_cache()
  if #evolvable_params_cache == 0 then return end
  local symmetry = evolution_symmetry_state
  local updated  = {}
  for _, name in ipairs(evolvable_params_cache) do
    if params.lookup[name] and not updated[name] then
      init_evolution_state(name)
      local new_value = evolve_parameter(name, evolution_states[name])
      params:set(name, new_value)
      updated[name] = true
      if symmetry and name:match("^%d") then
        local mirror = mirror_param_name(name)
        if params.lookup[mirror] and not updated[mirror] then
          init_evolution_state(mirror)
          local ms = evolution_states[mirror]
          ms.center_value   = new_value
          ms.current_drift  = 0
          params:set(mirror, new_value)
          updated[mirror] = true
        end
      end
    end
  end
end

local function start_evolution()
  if evolution_active then return end
  evolution_active         = true
  evolution_symmetry_state = params:get("symmetry") == 1
  cache_dirty              = true
  clear_table(evolution_states)
  evolution_metro.time  = evolution_update_rate
  evolution_metro.event = evolution_update
  evolution_metro:start()
end

local function stop_evolution()
  if not evolution_active then return end
  evolution_active = false
  stop_metro_safe(evolution_metro)
end

local function reset_evolution_centers()
  cache_dirty = true
  for name, state in pairs(evolution_states) do
    state.center_value  = params:get(name)
    state.current_drift = 0
    state.velocity      = 0
  end
end

local function set_evolution_range(range_pct)
  evolution_range = util.clamp(range_pct / 100, 0.001, 1.0)
  for name, state in pairs(evolution_states) do
    local spec = PARAM_SPECS[name]
    state.max_drift_range = (spec and spec[1] or 1) * evolution_range
  end
end

local function set_evolution_rate(rate)
  evolution_update_rate = rate
  if evolution_active then evolution_metro.time = rate end
end

local function set_param(name, prob, default, random_fn, direct, condition)
  if condition and not condition() then return end
  local val = (math.random() > prob) and (type(default) == "function" and default() or default) or random_fn()
  if direct then
    params:set(name, val)
    local st = evolution_states[name]
    if st then st.center_value = val; st.current_drift = 0 end
  else
    targets[name] = { target = val, threshold = math.max(0.001, math.abs(val) * 0.01) }
    active_interpolations[name] = true
  end
end

local function randomize_param_group(config)
  if params:get(config.lock_param) == 2 then return end
  for _, p in ipairs(config.params) do
    set_param(p.name, p.prob, p.default, p.random, p.direct_set, p.condition)
  end
end

local function start_interpolation(steps, symmetry)
  if not next(targets) then return end
  steps = math.max(1, steps or 30)
  randomize_metro.time  = interpolation_speed
  randomize_metro.count = -1
  randomize_metro.event = function(count)
    local factor   = count / steps
    local all_done = true
    for param, data in pairs(targets) do
      if not active_interpolations[param] then goto next_param end
      local new_value = interpolate(params:get(param), data.target, data.threshold, factor)
      params:set(param, new_value)
      local st = evolution_states[param]
      if st then st.center_value = new_value; st.current_drift = 0 end
      if symmetry and param:match("^%d") then
        local mirror = mirror_param_name(param)
        if params.lookup[mirror] then
          local mdata = targets[mirror] or data
          local mnew  = interpolate(params:get(mirror), mdata.target, mdata.threshold, factor)
          params:set(mirror, mnew)
          local mst = evolution_states[mirror]
          if mst then mst.center_value = mnew; mst.current_drift = 0 end
          if math.abs(mnew - mdata.target) > mdata.threshold then all_done = false end
        end
      end
      if math.abs(new_value - data.target) > data.threshold then
        all_done = false
      else
        active_interpolations[param] = nil
      end
      ::next_param::
    end
    if all_done then
      stop_metro_safe(randomize_metro)
      clear_table(targets)
      clear_table(active_interpolations)
    end
  end
  randomize_metro:start()
end

local function pitch_scale_allowed()
  for _, key in ipairs({ "lock_pitch", "1lock_pitch", "2lock_pitch" }) do if params.lookup[key] and params:get(key) == 2 then return false end end
  return true
end

local param_configs = {
  jpverb = { lock_param = "lock_reverb", params = {
    {name="shimmer_preset", prob=0.15, default=4,    random=function() return math.random(3,5)           end, direct_set=true},
    {name="shimmer_mix",    prob=0.3,  default=0,    random=function() return math.random(0,40)          end},
    {name="t60",            prob=0.5,  default=4,    random=function() return random_float(0.8,6)        end},
    {name="damp",           prob=0.4,  default=0,    random=function() return random_float(0,25)         end},
    {name="rsize",          prob=0.3,  default=1.25, random=function() return random_float(1,4)          end, direct_set=true},
    {name="earlyDiff",      prob=0.5,  default=70.7, random=function() return random_float(40.7,100)     end},
    {name="modDepth",       prob=0.6,  default=10,   random=function() return math.random(0,100)         end},
    {name="modFreq",        prob=0.6,  default=2,    random=function() return random_float(0.5,4)        end},
    {name="low",            prob=0.6,  default=1,    random=function() return random_float(0.7,1)        end},
    {name="mid",            prob=0.6,  default=1,    random=function() return random_float(0.7,1)        end},
    {name="high",           prob=0.6,  default=1,    random=function() return random_float(0.7,1)        end},
    {name="lowcut",         prob=0.6,  default=500,  random=function() return math.random(250,750)       end},
    {name="highcut",        prob=0.6,  default=2000, random=function() return math.random(1500,3500)     end},
  }},
  shimmer = { lock_param = "lock_shimmer", params = {
    {name="shimmer_oct1", prob=0.15, default=4,    random=function() return math.random(3,5)         end, direct_set=true},
    {name="pitchv1",      prob=0.5,  default=0,    random=function() return math.random(0,3)         end, direct_set=true},
    {name="lowpass1",     prob=0.5,  default=13000,random=function() return math.random(5000,15000)  end},
    {name="hipass1",      prob=0.5,  default=1300, random=function() return math.random(300,1600 )   end},
    {name="fb1",          prob=0.3,  default=15,   random=function() return math.random(10,35)       end},
    {name="fbDelay1",     prob=0.3,  default=0.2,  random=function() return random_float(0.1,0.3)    end},
  }},
  delay = { lock_param = "lock_delay", params = {
    {name="delay_time",     prob=0.5, default=0.5,   random=function() return random_float(0.1,1)        end, direct_set=true},
    {name="delay_feedback", prob=1.0, default=30,    random=function() return math.random(10,80)         end},
    {name="stereo",         prob=0.5, default=20,    random=function() return math.random(0,100)         end},
    {name="delay_lowpass",  prob=0.6, default=7500, random=function() return math.random(500,20000)     end},
    {name="delay_highpass", prob=0.6, default=200,   random=function() return math.random(20,800)        end},
    {name="wiggle_depth",   prob=0.5, default=25,    random=function() return math.random(0,100)         end, direct_set=true},
    {name="wiggle_rate",    prob=0.5, default=2,     random=function() return random_float(0.4,6)        end},
  }},
  tape = { lock_param = "lock_tape", params = {
    {name="wobble_amp",  prob=0.4, default=10, random=function() return math.random(1,15)  end},
    {name="wobble_rpm",  prob=0.4, default=33, random=function() return math.random(30,70) end},
    {name="flutter_amp", prob=0.4, default=15, random=function() return math.random(1,30)  end},
    {name="flutter_freq",prob=0.4, default=6,  random=function() return math.random(2,10)  end},
    {name="flutter_var", prob=0.4, default=2,  random=function() return math.random(1,5)   end},
  }},
  pitch = { lock_param = "lock_pitch", params = {
    {name="pitch_quantize_scale", prob=0.3, default=2, direct_set=true,
     condition = pitch_scale_allowed,
     random=function() return math.random(2,12) end},
  }},
}

local track_param_configs = {
  granular = function(track) return { lock_param = "lock_granular", params = {
    {name=track.."direction_mod",    prob=0.4, default=0, random=function() return math.random(0,40)       end},
    {name=track.."size_variation",   prob=0.4, default=0, random=function() return math.random(0,50)       end},
    {name=track.."density_mod_amt",  prob=0.4, default=0, random=function() return math.random(0,80)       end},
    {name=track.."subharmonics_1",   prob=0.5, default=0, random=function() return random_float(0,0.4)     end},
    {name=track.."subharmonics_2",   prob=0.5, default=0, random=function() return random_float(0,0.4)     end},
    {name=track.."subharmonics_3",   prob=0.5, default=0, random=function() return random_float(0,0.4)     end},
    {name=track.."overtones_1",      prob=0.5, default=0, random=function() return random_float(0,0.4)     end},
    {name=track.."overtones_2",      prob=0.5, default=0, random=function() return random_float(0,0.4)     end},
    {name=track.."env_select",       prob=0.5, default=1, random=function() return math.random(1,6)        end},
    {name=track.."ratcheting_prob",  prob=0.2, default=0, random=function() return math.random(1,25)       end},
  }} end,
  pitch = function(track) return { lock_param = track.."lock_pitch", params = {
    {name=track.."pitch_random_prob",       prob=0.2, default=0, random=function() return math.random(10,75) end},
    {name=track.."pitch_random_scale_type", prob=1.0,  default=1, condition=pitch_scale_allowed, random=function() return math.random(1,9) end},
  }} end,
  eq = function(track) return { lock_param = "lock_eq", params = {
    {name=track.."eq_low_gain",  prob=0.5, default=0,    random=function() return random_float(-0.2,0.2) end},
    {name=track.."eq_mid_gain",  prob=0.5, default=0,    random=function() return random_float(-0.1,0.1) end},
    {name=track.."eq_high_gain", prob=0.5, default=0.25, random=function() return random_float(0,0.4)    end},
  }} end,
}

local function randomize_track(track, steps, group_fns)
  for _, fn in ipairs(group_fns) do randomize_param_group(fn(track)) end
end

local function randomize_params(steps, track_num)
  track_num = track_num or 1
  stop_metro_safe(randomize_metro)
  clear_table(targets)
  clear_table(active_interpolations)
  local symmetry = params:get("symmetry") == 1
  for _, group in ipairs({ param_configs.tape, param_configs.delay, param_configs.jpverb, param_configs.shimmer, param_configs.pitch }) do randomize_param_group(group) end
  local track_fns = { track_param_configs.eq, track_param_configs.granular, track_param_configs.pitch }
  if symmetry then
    randomize_track(1, steps, track_fns)
    for param, data in pairs(targets) do
      if param:sub(1,1) == "1" then
        local mirror = mirror_param_name(param)
        if params.lookup[mirror] then
          targets[mirror] = { target = data.target, threshold = data.threshold }
          active_interpolations[mirror] = true
        end
      end
    end
  else
    randomize_track(track_num, steps, track_fns)
  end
  start_interpolation(steps, symmetry)
end

local function create_randomizer(group)
  return function(steps)
    stop_metro_safe(randomize_metro)
    randomize_param_group(param_configs[group])
    start_interpolation(steps, params:get("symmetry") == 1)
  end
end

local function create_track_randomizer(fn)
  return function(track, steps)
    stop_metro_safe(randomize_metro)
    randomize_param_group(fn(track))
    start_interpolation(steps, params:get("symmetry") == 1)
  end
end

local function cleanup()
  stop_evolution()
  stop_metro_safe(randomize_metro)
  clear_table(targets)
  clear_table(active_interpolations)
  clear_table(evolution_states)
  clear_table(evolvable_params_cache)
  cache_dirty = true
end

return {
  randomize_params        = randomize_params,
  randomize_jpverb_params = create_randomizer("jpverb"),
  randomize_delay_params  = create_randomizer("delay"),
  randomize_tape_params   = create_randomizer("tape"),
  randomize_granular_params = create_track_randomizer(track_param_configs.granular),
  randomize_eq_params       = create_track_randomizer(track_param_configs.eq),
  start_evolution         = start_evolution,
  stop_evolution          = stop_evolution,
  set_evolution_range     = set_evolution_range,
  set_evolution_rate      = set_evolution_rate,
  reset_evolution_centers = reset_evolution_centers,
  cleanup                 = cleanup,
}