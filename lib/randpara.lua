local randomize_metro = metro.init()
local evolution_metro = metro.init()
local interpolation_speed = 1 / 30

local abs, exp, random = math.abs, math.exp, math.random
local utils = include("lib/utils")
local random_float      = utils.random_float
local stop_metro_safe   = utils.stop_metro_safe
local clear_table       = utils.clear_table
local mirror_param_name = utils.mirror_param_name

local PARAM_SPECS = {
  ["1direction_mod"]      = {100, {0,100},   "granular"}, ["2direction_mod"]   = {100, {0,100},   "granular"},
  ["1size_variation"]     = {100, {0,100},   "granular"}, ["2size_variation"]  = {100, {0,100},   "granular"},
  ["1amp_randomize"]      = {100, {0,100},   "granular"}, ["2amp_randomize"]   = {100, {0,100},   "granular"},
  ["1density_mod_amt"]    = {100, {0,100},   "granular"}, ["2density_mod_amt"] = {100, {0,100},   "granular"},
  ["1subharmonics_1"]     = {1,   {0,1},     "granular"}, ["2subharmonics_1"]  = {1,   {0,1},     "granular"},
  ["1subharmonics_2"]     = {1,   {0,1},     "granular"}, ["2subharmonics_2"]  = {1,   {0,1},     "granular"},
  ["1subharmonics_3"]     = {1,   {0,1},     "granular"}, ["2subharmonics_3"]  = {1,   {0,1},     "granular"},
  ["1overtones_1"]        = {1,   {0,1},     "granular"}, ["2overtones_1"]     = {1,   {0,1},     "granular"},
  ["1overtones_2"]        = {1,   {0,1},     "granular"}, ["2overtones_2"]     = {1,   {0,1},     "granular"},
  ["1ratcheting_prob"]    = {25,  {0,100},   "granular"}, ["2ratcheting_prob"] = {25,  {0,100},   "granular"},
  ["delay_feedback"]      = {100, {0,100},   "delay"},
  ["stereo"]              = {100, {0,100},   "delay"},
  ["wiggle_depth"]        = {40,  {0,100},   "delay"},
  ["wiggle_rate"]         = {6,   {0,6},     "delay"},
  ["delay_lowpass"]       = {10000,{500,20000},"delay"},
  ["delay_highpass"]      = {250, {20,20000},"delay"},
  ["rev_pre_delay"]       = {20,  {0,100},   "reverb"},
  ["rev_lf_fc"]           = {300, {50,1000}, "reverb"},
  ["rev_low_time"]        = {3,   {0.1,10},  "reverb"},
  ["rev_mid_time"]        = {9,   {1,16},    "reverb"},
  ["rev_hf_damping"]      = {7000,{1500,12000},"reverb"},
  ["wobble_amp"]          = {100, {0,100},   "tape"},
  ["wobble_rpm"]          = {90,  {30,90},   "tape"},
  ["flutter_amp"]         = {100, {0,100},   "tape"},
  ["flutter_freq"]        = {30,  {3,30},    "tape"},
  ["flutter_var"]         = {10,  {0.1,10},  "tape"},
  ["chew_freq"]           = {50,  {1,60},    "tape"},
  ["chew_variance"]       = {50,  {0,70},    "tape"},
  ["pitchv1"]             = {4,   {0,4},     "shimmer"},
  ["lowpass1"]            = {10000,{100,20000},"shimmer"},
  ["hipass1"]             = {4000,{20,4000}, "shimmer"},
  ["fb1"]                 = {70,  {0,85},    "shimmer"},
  ["fbDelay1"]            = {0.5, {0.02,1},  "shimmer"},
  ["bitcrush_rate"]       = {5500,{2000,5500},"bitcrush"},
  ["bitcrush_bits"]       = {2,   {10,16},   "bitcrush"},
  ["1eq_low_gain"]        = {0.4, {0,1},     "eq"}, ["2eq_low_gain"]    = {0.4, {0,1},"eq"},
  ["1eq_mid_gain"]        = {0.4, {0,1},     "eq"}, ["2eq_mid_gain"]    = {0.4, {0,1},"eq"},
  ["1eq_high_gain"]       = {0.4, {0,1},     "eq"}, ["2eq_high_gain"]   = {0.4, {0,1},"eq"},
  ["glitch_mix"]          = {40,  {0,100},   "glitch"},
  ["glitch_probability"]  = {5,   {0.1,20},  "glitch"},
  ["glitch_min_length"]   = {100, {10,150},  "glitch"},
  ["glitch_max_length"]   = {100, {50,300},  "glitch"},
  ["glitch_maxstutters"]  = {5,   {2,20},    "glitch"},
  ["glitch_reverse"]      = {50,  {0,100},   "glitch"},
  ["glitch_pitch"]        = {50,  {0,100},   "glitch"},
}

local GROUP_LOCK = {
  granular = "lock_granular", delay   = "lock_delay",
  reverb   = "lock_reverb",   tape    = "lock_tape",
  shimmer  = "lock_shimmer",  eq      = "lock_eq",
  glitch   = "lock_glitch",
}

local evolution_active      = false
local evolution_range       = 0.15
local evolution_states      = {}
local evolution_update_rate = 1 / 8
local cache_dirty           = true
local evolution_group_enabled = {
  granular = true, delay = true, reverb = true, tape = true,
  shimmer = true, eq = true, glitch = true, bitcrush = true}

local evo_names, evo_groups, evo_pobjs, evo_mirror_idx = {}, {}, {}, {}
local evo_index_of = {}
local lock_pobj = {}
local sym_pobj

local function set_group_evolution(group, enabled)
  if evolution_group_enabled[group] ~= nil then
    evolution_group_enabled[group] = enabled
    cache_dirty = true
  end
end

local function build_evolvable_params_cache()
  if not cache_dirty then return end
  local pp, lk = params.params, params.lookup
  local n = 0
  for param, spec in pairs(PARAM_SPECS) do
    local group = spec[3]
    local idx = lk[param]
    if evolution_group_enabled[group] and idx then
      n = n + 1
      evo_names[n]  = param
      evo_groups[n] = group
      evo_pobjs[n]  = pp[idx]
    end
  end
  for i = n + 1, #evo_names do
    evo_names[i]      = nil
    evo_groups[i]     = nil
    evo_pobjs[i]      = nil
    evo_mirror_idx[i] = nil
  end
  clear_table(evo_index_of)
  for i = 1, n do evo_index_of[evo_names[i]] = i end
  for i = 1, n do
    local name = evo_names[i]
    evo_mirror_idx[i] = name:match("^%d")
      and evo_index_of[mirror_param_name(name)] or false
  end
  for group, lock in pairs(GROUP_LOCK) do
    local li = lk[lock]
    lock_pobj[group] = li and pp[li] or nil
  end
  local si = lk["symmetry"]
  sym_pobj = si and pp[si] or nil
  for name in pairs(evolution_states) do
    if not evo_index_of[name] then evolution_states[name] = nil end
  end
  cache_dirty = false
end

local function init_evolution_state(name, cur)
  local spec = PARAM_SPECS[name]
  local max_range = spec and spec[1] or 1
  local bounds = spec and spec[2]
  local state = {
    center_value         = cur,
    current_drift        = 0,
    velocity             = 0,
    momentum_decay       = random_float(0.92, 0.98),
    direction_change_prob= random_float(0.03, 0.08),
    bound_lo             = bounds and bounds[1] or nil,
    bound_hi             = bounds and bounds[2] or nil,
    range_base           = max_range,
    max_drift_range      = max_range * evolution_range}
  evolution_states[name] = state
  return state
end

local function evolve_parameter(state)
  local mx = state.max_drift_range
  local v  = state.velocity
  if random() < state.direction_change_prob then
    v = random_float(-mx / 50, mx / 50)
  end
  v = v * state.momentum_decay + random_float(-1, 1) * (mx / 30)
  local d = state.current_drift + v
  if d > mx then d = mx elseif d < -mx then d = -mx end
  local new_value = state.center_value + d
  local lo = state.bound_lo
  if lo then
    if new_value < lo then
      new_value = lo
      v = -v * random_float(0.3, 0.7)
      d = lo - state.center_value
    elseif new_value > state.bound_hi then
      new_value = state.bound_hi
      v = -v * random_float(0.3, 0.7)
      d = state.bound_hi - state.center_value
    end
  end
  state.velocity      = v
  state.current_drift = d
  return new_value
end

local evo_updated, evo_locked = {}, {}
local function evolution_update()
  if not evolution_active then return end
  build_evolvable_params_cache()
  local n = #evo_names
  if n == 0 then return end
  local states   = evolution_states
  local symmetry = sym_pobj ~= nil and sym_pobj:get() == 1
  for group in pairs(GROUP_LOCK) do
    local obj = lock_pobj[group]
    evo_locked[group] = obj ~= nil and obj:get() == 2
  end
  for i = 1, n do evo_updated[i] = false end
  for i = 1, n do
    if not evo_updated[i] and not evo_locked[evo_groups[i]] then
      local name  = evo_names[i]
      local obj   = evo_pobjs[i]
      local cur   = obj:get()
      local state = states[name]
      if not state then
        state = init_evolution_state(name, cur)
      elseif state.last_set ~= nil and cur ~= state.last_set then
        state.center_value  = cur
        state.current_drift = 0
        state.velocity      = 0
      end
      obj:set(evolve_parameter(state))
      local set_value = obj:get()
      state.last_set = set_value
      evo_updated[i] = true
      local mi = evo_mirror_idx[i]
      if symmetry and mi and not evo_updated[mi] then
        local mobj  = evo_pobjs[mi]
        local mname = evo_names[mi]
        local ms = states[mname] or init_evolution_state(mname, set_value)
        ms.center_value  = set_value
        ms.current_drift = 0
        ms.velocity      = 0
        mobj:set(set_value)
        ms.last_set = mobj:get()
        evo_updated[mi] = true
      end
    end
  end
end

local function start_evolution()
  if evolution_active then return end
  evolution_active = true
  cache_dirty      = true
  clear_table(evolution_states)
  evolution_metro.time  = evolution_update_rate
  evolution_metro.event = evolution_update
  utils.metro_start(evolution_metro)
end

local function stop_evolution()
  if not evolution_active then return end
  evolution_active = false
  stop_metro_safe(evolution_metro)
end

local function reset_evolution_centers()
  for name, state in pairs(evolution_states) do
    state.center_value  = params:get(name)
    state.current_drift = 0
    state.velocity      = 0
    state.last_set      = nil
  end
end

local function set_evolution_range(range_pct)
  evolution_range = util.clamp(range_pct / 100, 0.001, 1.0)
  for _, state in pairs(evolution_states) do
    state.max_drift_range = state.range_base * evolution_range
  end
end

local function set_evolution_rate(rate)
  evolution_update_rate = rate
  if evolution_active then evolution_metro.time = rate end
end

local interp_list, interp_index = {}, {}
local interp_count = 0
local interp_steps, interp_max = 30, 120

local function queue_target(name, val)
  local li = params.lookup[name]
  if not li then return end
  local idx = interp_index[name]
  if not idx then
    interp_count = interp_count + 1
    idx = interp_count
    interp_index[name] = idx
  end
  local e = interp_list[idx]
  if not e then e = {} interp_list[idx] = e end
  e.name      = name
  e.pobj      = params.params[li]
  e.target    = val
  e.threshold = val * 0.01
  if e.threshold < 0 then e.threshold = -e.threshold end
  if e.threshold < 0.001 then e.threshold = 0.001 end
  e.done      = false
  e.mobj      = nil
end

local function clear_interpolation()
  for i = 1, interp_count do
    local e = interp_list[i]
    e.pobj = nil
    e.mobj = nil
  end
  clear_table(interp_index)
  interp_count = 0
end

local function interp_event(count)
  local alpha = 1 - exp(-4 * count / interp_steps)
  local force = count >= interp_max
  local all_done = true
  for i = 1, interp_count do
    local e = interp_list[i]
    if not e.done then
      local target, thr = e.target, e.threshold
      local obj = e.pobj
      local nv
      if force then
        nv = target
      else
        local d = target - obj:get()
        nv = (d < thr and d > -thr) and target or target - d + d * alpha
      end
      obj:set(nv)
      local diff = nv - target
      if diff < thr and diff > -thr then e.done = true else all_done = false end
      local mobj = e.mobj
      if mobj then
        local mnv
        if force then
          mnv = target
        else
          local md = target - mobj:get()
          mnv = (md < thr and md > -thr) and target or target - md + md * alpha
        end
        mobj:set(mnv)
        local mdiff = mnv - target
        if mdiff >= thr or mdiff <= -thr then all_done = false e.done = false end
      end
    end
  end
  if all_done or force then
    stop_metro_safe(randomize_metro)
    clear_interpolation()
  end
end

local function start_interpolation(steps, symmetry)
  if interp_count == 0 then return end
  interp_steps = steps or 30
  if interp_steps < 1 then interp_steps = 1 end
  interp_max   = interp_steps * 4
  local pp, lk = params.params, params.lookup
  for i = 1, interp_count do
    local e = interp_list[i]
    e.mobj = nil
    if symmetry and e.name:match("^%d") then
      local mname = mirror_param_name(e.name)
      if not interp_index[mname] then
        local li = lk[mname]
        if li then e.mobj = pp[li] end
      end
    end
  end
  randomize_metro.time  = interpolation_speed
  randomize_metro.count = -1
  randomize_metro.event = interp_event
  utils.metro_start(randomize_metro)
end

local function stop_interpolation()
  stop_metro_safe(randomize_metro)
  clear_interpolation()
end

local function set_param(name, prob, default, random_fn, direct, condition)
  if condition and not condition() then return end
  local val
  if random() < prob then
    val = random_fn()
  else
    val = type(default) == "function" and default() or default
  end
  if direct then
    params:set(name, val)
  else
    queue_target(name, val)
  end
end

local function randomize_param_group(config)
  if params:get(config.lock_param) == 2 then return end
  for _, p in ipairs(config.params) do
    set_param(p.name, p.prob, p.default, p.random, p.direct_set, p.condition)
  end
end

local PITCH_LOCK_KEYS = { "lock_pitch", "1lock_pitch", "2lock_pitch" }
local function pitch_scale_allowed()
  for i = 1, #PITCH_LOCK_KEYS do
    local key = PITCH_LOCK_KEYS[i]
    if params.lookup[key] and params:get(key) == 2 then return false end
  end
  return true
end

local param_configs = {
  dverb = { lock_param = "lock_reverb", params = {
    {name="rev_pre_delay",  prob=0.5,  default=20,   random=function() return random(20,100)        end, direct_set=true},
    {name="rev_lf_fc",      prob=0.5,  default=50,   random=function() return random(50,1000)       end},
    {name="rev_low_time",   prob=0.5,  default=0.1,  random=function() return random_float(0.1,9)   end},
    {name="rev_mid_time",   prob=0.5,  default=11,   random=function() return random_float(1,16)    end},
    {name="rev_hf_damping", prob=0.5,  default=4500, random=function() return random(1500,12000)    end},
  }},
  shimmer = { lock_param = "lock_shimmer", params = {
    {name="shimmer_oct1", prob=0.15, default=4,     random=function() return random(3,5)          end, direct_set=true},
    {name="pitchv1",      prob=0.5,  default=0,     random=function() return random(0,2)          end, direct_set=true},
    {name="lowpass1",     prob=0.5,  default=13000, random=function() return random(5000,15000)   end},
    {name="hipass1",      prob=0.5,  default=1300,  random=function() return random(300,1600)     end},
    {name="fb1",          prob=0.3,  default=20,    random=function() return random(10,35)        end},
    {name="fbDelay1",     prob=0.3,  default=0.2,   random=function() return random_float(0.1,0.3) end},
  }},
  delay = { lock_param = "lock_delay", params = {
    {name="delay_time",     prob=0.75, default=0.5,  random=function() return random_float(0.1,1)  end, direct_set=true, condition=function() return params:get("clock_sync") ~= 2 end},
    {name="delay_feedback", prob=1.0,  default=35,   random=function() return random(5,90)         end},
    {name="stereo",         prob=1.0,  default=20,   random=function() return random(0,100)        end},
    {name="delay_lowpass",  prob=0.6,  default=5000, random=function() return random(400,16000)    end},
    {name="delay_highpass", prob=0.6,  default=200,  random=function() return random(20,800)       end},
    {name="wiggle_depth",   prob=0.3,  default=20,   random=function() return random(0,100)        end, direct_set=true},
    {name="wiggle_rate",    prob=0.75, default=2,    random=function() return random_float(0.4,4)  end},
  }},
  tape = { lock_param = "lock_tape", params = {
    {name="wobble_amp",  prob=0.75, default=10, random=function() return random(1,15)  end},
    {name="wobble_rpm",  prob=0.75, default=33, random=function() return random(30,70) end},
    {name="flutter_amp", prob=0.75, default=15, random=function() return random(1,30)  end},
    {name="flutter_freq",prob=0.75, default=6,  random=function() return random(2,10)  end},
    {name="flutter_var", prob=0.75, default=2,  random=function() return random(1,5)   end},
  }},
  pitch = { lock_param = "lock_pitch", params = {
    {name="pitch_quantize_scale", prob=0.3, default=2, random=function() return random(1,9) end, direct_set=true},
  }},
  sync = { lock_param = "lock_sync", params = {
    {name="clock_sync_delay_div", prob=0.75, default=13, random=function() return random(9,18) end, direct_set=true, condition=function() return params:get("clock_sync") == 2 end},
  }},
}

local GLOBAL_GROUP_ORDER = {
  param_configs.tape, param_configs.delay, param_configs.dverb,
  param_configs.shimmer, param_configs.pitch, param_configs.sync }

local track_param_configs = {
  granular = function(track) return { lock_param = "lock_granular", params = {
    {name=track.."direction_mod",    prob=0.4,  default=0, random=function() return random(0,40)         end},
    {name=track.."size_variation",   prob=0.4,  default=0, random=function() return random(0,35)         end},
    {name=track.."amp_randomize",    prob=0.35, default=0, random=function() return random(0,40)         end},
    {name=track.."density_mod_amt",  prob=0.25, default=0, random=function() return random(0,40)         end},
    {name=track.."subharmonics_1",   prob=0.4,  default=0, random=function() return random_float(0,0.4)  end},
    {name=track.."subharmonics_2",   prob=0.4,  default=0, random=function() return random_float(0,0.4)  end},
    {name=track.."subharmonics_3",   prob=0.4,  default=0, random=function() return random_float(0,0.4)  end},
    {name=track.."overtones_1",      prob=0.4,  default=0, random=function() return random_float(0,0.4)  end},
    {name=track.."overtones_2",      prob=0.4,  default=0, random=function() return random_float(0,0.4)  end},
    {name=track.."env_select",       prob=0.5,  default=1, random=function() return random(1,5)          end},
    {name=track.."ratcheting_prob",  prob=0.25, default=0, random=function() return random(1,25)         end},
  }} end,
  pitch = function(track) return { lock_param = track.."lock_pitch", params = {
    {name=track.."pitch_random_prob",       prob=0.2, default=0, random=function() return random(10,75) end},
    {name=track.."pitch_random_scale_type", prob=1.0, default=1, condition=pitch_scale_allowed, random=function() return random(1,9) end},
  }} end,
  eq = function(track) return { lock_param = "lock_eq", params = {
    {name=track.."eq_low_gain",  prob=0.5, default=0,    random=function() return random_float(-0.2,0.2) end},
    {name=track.."eq_mid_gain",  prob=0.5, default=0,    random=function() return random_float(-0.2,0.2) end},
    {name=track.."eq_high_gain", prob=0.5, default=0.25, random=function() return random_float(0,0.5)    end},
  }} end,
}

local TRACK_CONFIGS = {}
for key, fn in pairs(track_param_configs) do
  TRACK_CONFIGS[key] = { fn(1), fn(2) }
end
local TRACK_GROUP_ORDER = { TRACK_CONFIGS.eq, TRACK_CONFIGS.granular, TRACK_CONFIGS.pitch }

local function randomize_track(track)
  for i = 1, #TRACK_GROUP_ORDER do
    randomize_param_group(TRACK_GROUP_ORDER[i][track])
  end
end

local function randomize_params(steps, track_num)
  track_num = track_num or 1
  stop_metro_safe(randomize_metro)
  clear_interpolation()
  local symmetry = params:get("symmetry") == 1
  for i = 1, #GLOBAL_GROUP_ORDER do randomize_param_group(GLOBAL_GROUP_ORDER[i]) end
  if symmetry then
    randomize_track(1)
    local n = interp_count
    for i = 1, n do
      local e = interp_list[i]
      if e.name:sub(1, 1) == "1" then
        queue_target(mirror_param_name(e.name), e.target)
      end
    end
  else
    randomize_track(track_num)
  end
  start_interpolation(steps, symmetry)
end

local function create_randomizer(group)
  local config = param_configs[group]
  return function(steps)
    stop_metro_safe(randomize_metro)
    randomize_param_group(config)
    start_interpolation(steps, params:get("symmetry") == 1)
  end
end

local function create_track_randomizer(configs)
  return function(track, steps)
    stop_metro_safe(randomize_metro)
    randomize_param_group(configs[track])
    start_interpolation(steps, params:get("symmetry") == 1)
  end
end

local function cleanup()
  stop_evolution()
  stop_interpolation()
  clear_table(evolution_states)
  clear_table(evo_names)
  clear_table(evo_groups)
  clear_table(evo_pobjs)
  clear_table(evo_mirror_idx)
  clear_table(evo_index_of)
  cache_dirty = true
end

return {
  randomize_params          = randomize_params,
  randomize_delay_params    = create_randomizer("delay"),
  randomize_tape_params     = create_randomizer("tape"),
  randomize_granular_params = create_track_randomizer(TRACK_CONFIGS.granular),
  randomize_eq_params       = create_track_randomizer(TRACK_CONFIGS.eq),
  start_evolution           = start_evolution,
  stop_evolution            = stop_evolution,
  set_evolution_range       = set_evolution_range,
  set_evolution_rate        = set_evolution_rate,
  reset_evolution_centers   = reset_evolution_centers,
  cleanup                   = cleanup,
  stop_interpolation        = stop_interpolation,
  set_group_evolution       = set_group_evolution,
}