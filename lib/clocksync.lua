local clocksync = {}
local lfo_ref    = nil
local set_density = function(v, hz) if engine then engine.density(v, hz) end end
local enabled       = false
local delay_div     = 1.0
local lfo_div_beats = 1.0
local density_gpb   = {2, 1}
local density_label = {"1/8", "1/4"}
local density_idx   = {9, 7}
local DIVISIONS = {
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

local clamp = util.clamp
local function t60() return (clock.get_tempo() or 120) / 60 end

local function push()
  if not enabled then return end
  local t = t60()
  if lfo_ref then lfo_ref.apply_clock_sync(t / lfo_div_beats) end
  set_density(1, clamp(t * density_gpb[1], 0.1, 250))
  set_density(2, clamp(t * density_gpb[2], 0.1, 250))
  if params.lookup["delay_time"] then
    params:set("delay_time", clamp(delay_div / t, 0.02, 2))
  end
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
    end
  end)
  params:add_option("clock_lfo_div", "LFO Division", DIV_LABELS, 3)
  params:set_action("clock_lfo_div", function(v)
    lfo_div_beats = DIVISIONS[v].beats
    push()
  end)
  params:add_option("clock_sync_delay_div", "Delay Division", DIV_LABELS, 7)
  params:set_action("clock_sync_delay_div", function(v)
    delay_div = DIVISIONS[v].beats
    push()
  end)
end

local DIV_RAND_MIN, DIV_RAND_MAX = 5, 13

local function apply_div(voice, idx)
  local d = DIVISIONS[idx]
  density_idx[voice]   = idx
  density_gpb[voice]   = 1 / d.beats
  density_label[voice] = d.label
end

function clocksync.step_grain_div(voice, delta)
  apply_div(voice, clamp(density_idx[voice] + delta, 1, NDIV))
  push()
end

local LFO_DIV_MIN, LFO_DIV_MAX = 1, 11

function clocksync.step_lfo_div(delta)
  params:set("clock_lfo_div", clamp(params:get("clock_lfo_div") + delta, LFO_DIV_MIN, LFO_DIV_MAX))
end

function clocksync.randomize_grain_div(voice, mirror_voice)
  if not enabled then return end
  local idx = math.random(DIV_RAND_MIN, DIV_RAND_MAX)
  apply_div(voice, idx)
  if mirror_voice then apply_div(mirror_voice, idx) end
  push()
end

function clocksync.div_index_for_norm(t)
  local span = DIV_RAND_MAX - DIV_RAND_MIN
  return clamp(math.floor(DIV_RAND_MIN + t * span + 0.5), DIV_RAND_MIN, DIV_RAND_MAX)
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

function clocksync.div_index_to_norm(idx)
  local span = DIV_RAND_MAX - DIV_RAND_MIN
  if span == 0 then return 0 end
  local nt = (idx - DIV_RAND_MIN) / span
  if nt < 0 then nt = 0 elseif nt > 1 then nt = 1 end
  return nt
end

function clocksync.lfo_synced()            return enabled end
function clocksync.grain_synced()          return enabled end
function clocksync.grain_division_label(v) return density_label[v] end

function clocksync.grain_division_norm(voice)
  return clocksync.div_index_to_norm(density_idx[tonumber(voice)])
end

function clocksync.grain_density(v)
  if not enabled then return nil end
  return clamp(t60() * density_gpb[v], 0.1, 250)
end

function clocksync.init(opts)
  opts = opts or {}
  lfo_ref = opts.lfo
  if opts.set_density then set_density = opts.set_density end
  delay_div     = DIVISIONS[params:get("clock_sync_delay_div")].beats
  lfo_div_beats = DIVISIONS[params:get("clock_lfo_div")].beats
  if params:get("clock_sync") == 2 then params:set("clock_sync", 2) end
end

function clocksync.cleanup()
  if sync_co then clock.cancel(sync_co) sync_co = nil end
  if lfo_ref then lfo_ref.apply_clock_sync(nil) lfo_ref.set_sine_all(false) end
end

return clocksync