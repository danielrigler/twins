local clocksync = {}
local clamp = util.clamp
local math_random = math.random
local math_floor = math.floor
local lfo_ref = nil
local set_density = function(v, hz) if engine then engine.density(v, hz) end end
local on_push_cb = nil
local on_sync_off_cb = nil
local enabled = false
local delay_div = 1.0
local lfo_div_beats = {1.0, 1.0}
local reseek_enabled = false
local reseek_beats = 1.0
local reseek_co = nil
local DIVISIONS = {
  {label="8 bar",  beats=32.0},  {label="7 bar",  beats=28.0},
  {label="6 bar",  beats=24.0},  {label="5 bar",  beats=20.0},
  {label="4 bar",  beats=16.0},  {label="3 bar",  beats=12.0},
  {label="2 bar",  beats=8.0},   {label="1 bar.", beats=6.0},
  {label="1 bar",  beats=4.0},   {label="1/2.",   beats=3.0},
  {label="1/2",    beats=2.0},   {label="1/4.",   beats=1.5},
  {label="1/4",    beats=1.0},   {label="1/8.",   beats=0.75},
  {label="1/8",    beats=0.5},   {label="1/16.",  beats=0.375},
  {label="1/16",   beats=0.25},  {label="1/32.",  beats=0.1875},
  {label="1/32",   beats=0.125}, {label="1/64",   beats=0.0625},
  {label="1/128",  beats=0.03125}}
local NDIV = #DIVISIONS
local DIV_LABELS = {}
for i = 1, NDIV do DIV_LABELS[i] = DIVISIONS[i].label end
local DIV = {}
for i = 1, NDIV do DIV[DIVISIONS[i].label] = i end
local function gpb_of(idx) return 1 / DIVISIONS[idx].beats end
local density_idx   = { DIV["1/8"], DIV["1/4"] }
local density_gpb   = { gpb_of(density_idx[1]), gpb_of(density_idx[2]) }
local density_label = { DIVISIONS[density_idx[1]].label, DIVISIONS[density_idx[2]].label }
local function t60() return (clock.get_tempo() or 120) / 60 end
local function symmetry_on() return params and params.lookup and params.lookup["symmetry"] and params:get("symmetry") == 1 end

local function push()
  if not enabled then return end
  local t = t60()
  if lfo_ref then
    local b1 = lfo_div_beats[1]
    local b2 = symmetry_on() and b1 or lfo_div_beats[2]
    lfo_ref.apply_clock_sync(t / b1, t / b2)
  end
  set_density(1, clamp(t * density_gpb[1], 0.1, 250))
  set_density(2, clamp(t * density_gpb[2], 0.1, 250))
  if params.lookup["delay_time"] then params:set("delay_time", clamp(delay_div / t, 0.02, 5)) end
  if on_push_cb then on_push_cb() end
end

local function stop_reseek()
  if reseek_co then
    clock.cancel(reseek_co)
    reseek_co = nil
  end
end

local function start_reseek()
  if reseek_co or not reseek_enabled then return end
  reseek_co = clock.run(function()
    while true do
      clock.sync(reseek_beats)
      if engine then
        engine.reseek(1)
        engine.reseek(2)
      end
    end
  end)
end

local function refresh_reseek()
  stop_reseek()
  start_reseek()
end

local sync_co = nil

function clocksync.add_params()
  params:add_option("clock_sync", "Clock Sync", {"off", "on"}, 1)
  params:set_action("clock_sync", function(v)
    enabled = (v == 2)
    if enabled then
      if params.lookup["clock_source"] then params:set("clock_source", 2) end
      if lfo_ref then lfo_ref.set_sine_all(true) end
      sync_co = sync_co or clock.run(function()
        while true do clock.sync(1) push() end
      end)
      push()
    else
      if sync_co then clock.cancel(sync_co) sync_co = nil end
      if lfo_ref then lfo_ref.apply_clock_sync(nil) lfo_ref.set_sine_all(false) end
      set_density(1, params:get("1density"))
      set_density(2, params:get("2density"))
      if on_sync_off_cb then on_sync_off_cb() end
    end
  end)
  params:add_option("clock_lfo_div", "LFO Division 1", DIV_LABELS, DIV["1 bar"])
  params:set_action("clock_lfo_div", function(v)
    lfo_div_beats[1] = DIVISIONS[v].beats
    push()
  end)
  params:add_option("clock_lfo_div2", "LFO Division 2", DIV_LABELS, DIV["1 bar"])
  params:set_action("clock_lfo_div2", function(v)
    lfo_div_beats[2] = DIVISIONS[v].beats
    push()
  end)
  params:add_option("clock_sync_delay_div", "Delay Division", DIV_LABELS, DIV["1/4"])
  params:set_action("clock_sync_delay_div", function(v)
    delay_div = DIVISIONS[v].beats
    push()
  end)
  params:add_option("clock_reseek", "Beat Repeat", {"off", "on"}, 1)
  params:set_action("clock_reseek", function(v)
    reseek_enabled = (v == 2)
    if reseek_enabled and lfo_ref and not _G.preset_loading then
      lfo_ref.clearLFOs("1", "seek")
      lfo_ref.clearLFOs("2", "seek")
    end
    refresh_reseek()
  end)
  params:add_option("clock_reseek_div", "Repeat Division", DIV_LABELS, DIV["1 bar"])
  params:set_action("clock_reseek_div", function(v)
    reseek_beats = DIVISIONS[v].beats
    refresh_reseek()
  end)
end

local DIV_RAND_MIN, DIV_RAND_MAX = DIV["1/2"], DIV["1/32"]

local function apply_div(voice, idx)
  local d = DIVISIONS[idx]
  density_idx[voice] = idx
  density_gpb[voice] = 1 / d.beats
  density_label[voice] = d.label
end

function clocksync.step_grain_div(voice, delta, mirror_voice)
  apply_div(voice, clamp(density_idx[voice] + delta, 1, NDIV))
  if mirror_voice then
    apply_div(mirror_voice, clamp(density_idx[mirror_voice] + delta, 1, NDIV))
  end
  push()
end

local LFO_DIV_MIN, LFO_DIV_MAX = DIV["4 bar"], DIV["1/16"]
local LFO_DIV_RAND_MIN, LFO_DIV_RAND_MAX = DIV["4 bar"], DIV["1/2"]

function clocksync.step_lfo_div(voice, delta, symmetry)
  local key = (tonumber(voice) == 2) and "clock_lfo_div2" or "clock_lfo_div"
  local nidx = clamp(params:get(key) + delta, LFO_DIV_MIN, LFO_DIV_MAX)
  params:set(key, nidx)
  if symmetry then
    local okey = (key == "clock_lfo_div2") and "clock_lfo_div" or "clock_lfo_div2"
    local onidx = clamp(params:get(okey) + delta, LFO_DIV_MIN, LFO_DIV_MAX)
    params:set(okey, onidx)
  end
end

function clocksync.randomize_lfo_div(voice, mirror_voice)
  if not enabled then return end
  local idx = math_random(LFO_DIV_RAND_MIN, LFO_DIV_RAND_MAX)
  local key = (tonumber(voice) == 2) and "clock_lfo_div2" or "clock_lfo_div"
  params:set(key, idx)
  if mirror_voice then
    local mkey = (tonumber(mirror_voice) == 2) and "clock_lfo_div2" or "clock_lfo_div"
    params:set(mkey, idx)
  end
end

function clocksync.randomize_grain_div(voice, mirror_voice)
  if not enabled then return end
  local idx = math_random(DIV_RAND_MIN, DIV_RAND_MAX)
  apply_div(voice, idx)
  if mirror_voice then apply_div(mirror_voice, idx) end
  push()
end

function clocksync.div_index_for_norm(t)
  local span = DIV_RAND_MAX - DIV_RAND_MIN
  return clamp(math_floor(DIV_RAND_MIN + t * span + 0.5), DIV_RAND_MIN, DIV_RAND_MAX)
end

function clocksync.set_grain_div_norm(voice, t)
  if not enabled then return end
  voice = tonumber(voice)
  local idx = clocksync.div_index_for_norm(t)
  if idx == density_idx[voice] then return end
  apply_div(voice, idx)
  push()
end

function clocksync.grain_division_index(voice) return density_idx[tonumber(voice)] end

function clocksync.set_grain_div_index(voice, idx)
  if not enabled then return end
  voice = tonumber(voice)
  idx = clamp(idx, 1, NDIV)
  if idx == density_idx[voice] then return end
  apply_div(voice, idx)
  push()
end

function clocksync.div_index_for_density(hz)
  if not enabled or not hz or hz <= 0 then return nil end
  local t = t60()
  local target = math.log(clamp(hz, 0.1, 250))
  local best_idx, best_dist = density_idx[1], math.huge
  for i = 1, NDIV do
    local dist = math.abs(math.log(t / DIVISIONS[i].beats) - target)
    if dist < best_dist then best_dist = dist; best_idx = i end
  end
  return best_idx
end

function clocksync.div_index_to_norm(idx)
  local span = DIV_RAND_MAX - DIV_RAND_MIN
  if span == 0 then return 0 end
  return clamp((idx - DIV_RAND_MIN) / span, 0, 1)
end

function clocksync.lfo_synced() return enabled end
function clocksync.grain_synced() return enabled end
function clocksync.div_labels() return DIV_LABELS end
function clocksync.div_index(label) return DIV[label] end
function clocksync.div_rate_hz(idx) return t60() / DIVISIONS[idx].beats end
function clocksync.div_beats(idx) return DIVISIONS[idx].beats end
function clocksync.reseek_active() return reseek_enabled end
function clocksync.grain_division_label(v) return density_label[v] end

function clocksync.grain_division_norm(voice) return clocksync.div_index_to_norm(density_idx[tonumber(voice)]) end

function clocksync.grain_density(v)
  if not enabled then return nil end
  return clamp(t60() * density_gpb[v], 0.1, 250)
end

function clocksync.init(opts)
  opts = opts or {}
  lfo_ref = opts.lfo
  if opts.set_density then set_density = opts.set_density end
  on_push_cb = opts.on_push
  on_sync_off_cb = opts.on_sync_off
  delay_div = DIVISIONS[params:get("clock_sync_delay_div")].beats
  lfo_div_beats[1] = DIVISIONS[params:get("clock_lfo_div")].beats
  lfo_div_beats[2] = DIVISIONS[params:get("clock_lfo_div2")].beats
  reseek_beats = DIVISIONS[params:get("clock_reseek_div")].beats
  reseek_enabled = params:get("clock_reseek") == 2
  if params:get("clock_sync") == 2 then params:set("clock_sync", 2) end
  refresh_reseek()
end

function clocksync.cleanup()
  if sync_co then clock.cancel(sync_co) sync_co = nil end
  stop_reseek()
  if lfo_ref then lfo_ref.apply_clock_sync(nil) lfo_ref.set_sine_all(false) end
end

return clocksync
