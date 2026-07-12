local font = {}

font.micro_font = {
  D = {{1,1,0},{1,0,1},{1,1,0}},
  B = {{1,1,0},{0,1,1},{0,0,1}},
  L = {{1,0},{1,0},{1,1}},
  C = {{1,1,1},{1,0,0},{1,1,1}},
  G = {{1,1,0},{1,0,1},{1,1,1}},
  E = {{1,1,1},{1,1,0},{1,1,1}},
  I = {{1},{1},{1}},
  R = {{1,1,1},{1,1,0},{1,0,1}},
  T = {{1,1,1},{0,1,0},{0,1,0}},
  S = {{0,1,1},{0,1,0},{1,1,0}},
  X = {{0,1,1,1,0,1},{0,1,0,1,1,1},{1,1,0,1,0,1}},
  V = {{0,0,1},{1,1,1},{1,1,1}},
  H = {{1,0,1},{1,1,1},{1,0,1}},
  Z = {{0,1,1,1,1},{0,1,0,1,0},{1,1,0,1,0}},
  F = {{1,1,1},{1,1,0},{1,0,0}},
  P = {{1,1,1},{1,1,1},{1,0,0}},
  O = {{1,1,1},{1,0,1},{1,1,1}},
  W = {{1,0,1},{1,1,1},{1,1,1}},
  M = {{1,0,1},{0,1,0},{1,0,1}},
  K = {{0,1,0},{1,0,1},{0,1,0}},
  A = {{0,0,1},{0,1,1},{1,1,1}},
  N = {{1,1,1},{1,0,1},{1,0,1}},
  U = {{1,0,1},{1,0,1},{1,1,1}}
}

local function plot_text(plot, x, y, text, level)
  local cursor_x = x
  for i = 1, #text do
    local char  = text:sub(i, i)
    local glyph = font.micro_font[char]
    if glyph then
      local w = #glyph[1]
      local col_levels = type(level) == "table" and level or nil
      for row = 1, 3 do
        for col = 1, w do
          if glyph[row][col] == 1 then
            local lvl = col_levels and (col_levels[col] or col_levels[#col_levels]) or level
            plot(lvl or 1, cursor_x + col - 1, y + row - 1)
          end
        end
      end
      cursor_x = cursor_x + w + 1
    else
      cursor_x = cursor_x + 3
    end
  end
  return cursor_x
end

local _text_cache = {}
function font.plot_text_cached(plot, x, y, text, level)
  local c = _text_cache[text]
  if not c then
    local xs, ys, n = {}, {}, 0
    local w = plot_text(function(_, px, py) n = n + 1 xs[n] = px ys[n] = py end, 0, 0, text, 1) - 1
    c = {xs = xs, ys = ys, n = n, w = w}
    _text_cache[text] = c
  end
  local xs, ys = c.xs, c.ys
  for i = 1, c.n do plot(level, x + xs[i], y + ys[i]) end
  return x + c.w + 1
end

local fx_cache = {
  delay_mix       = 0,
  reverb_mix      = -40,
  shimmer_mix1    = 0,
  tape_mix        = 1,
  sine_drive_wet  = 0,
  wobble_mix      = 0,
  chew_depth      = 0,
  lossdegrade_mix = 0,
  Width           = 100,
  dimension_mix   = 0,
  haas            = 1,
  rspeed          = 0,
  monobass_mix    = 1,
  bitcrush_mix    = 0,
  bitcrush_mod    = 1,
  shimmer_mod1    = 1,
  glitch_ratio    = 0,
  glitch_mix      = 0,
  resonator_mix   = 0,
  wavefold_mix    = 0,
  ringmod_mix     = 0,
  analogdrive_mix = 0,
  analogdrive_mod = 1,
  ["1cutoff"]     = 20000,
  ["2cutoff"]     = 20000,
  ["1hpf"]        = 20,
  ["2hpf"]        = 20
}

function font.update_fx_cache(param_name, value)
  if fx_cache[param_name] ~= nil then
    fx_cache[param_name] = value
  end
end

function font.init_fx_cache()
  for param_name in pairs(fx_cache) do
    if params:lookup_param(param_name) then
      fx_cache[param_name] = params:get(param_name)
    end
  end
end

local function is_locked(lock_key)
  return params.lookup[lock_key] and params:get(lock_key) == 2
end

local _lock_cache = {}
local _blink_level = 1
local _delay_duck_gain = 1.0

function font.set_delay_duck(gain)
  _delay_duck_gain = gain
end

font.arp_ref = nil
font.clocksync_ref = nil
function font.set_context(ctx)
  font.arp_ref = ctx.arp
  font.clocksync_ref = ctx.clocksync
end

local function value_to_level(val)
  return 1 + math.floor((val / 100) * 14)
end

local BINARY_ON_INTENSITY = 25

local function tape_active(cache)
  return cache.tape_mix == 2 or cache.sine_drive_wet > 0 or cache.wobble_mix > 0 or cache.chew_depth > 0 or cache.lossdegrade_mix > 0
end

local function tape_intensity(cache)
  local maxv = cache.tape_mix == 2 and BINARY_ON_INTENSITY or 0
  if cache.sine_drive_wet  > maxv then maxv = cache.sine_drive_wet  end
  if cache.wobble_mix      > maxv then maxv = cache.wobble_mix      end
  if cache.chew_depth      > maxv then maxv = cache.chew_depth      end
  if cache.lossdegrade_mix > maxv then maxv = cache.lossdegrade_mix end
  return maxv
end

local function stereo_active(cache)
  return cache.Width ~= 100 or cache.dimension_mix > 0
      or cache.haas == 2 or cache.rspeed > 0 or cache.monobass_mix == 2
end

local function stereo_intensity(cache)
  local width_dev = math.abs(cache.Width - 100) / 100
  local dim = cache.dimension_mix / 100
  local haas_val = cache.haas == 2 and (BINARY_ON_INTENSITY / 100) or 0
  local rspeed_val = cache.rspeed
  local maxv = math.max(width_dev, dim, haas_val, rspeed_val)
  return maxv * 100
end

local function filter_active(cache)
  return cache["1cutoff"] < 19999 or cache["2cutoff"] < 19999
      or cache["1hpf"] > 20.1 or cache["2hpf"] > 20.1
end

local _LOG_FILTER_INV = 1.0 / math.log(20000 / 20)
local function filter_log_norm(freq)
  local f = freq < 20 and 20 or (freq > 20000 and 20000 or freq)
  return math.log(f / 20) * _LOG_FILTER_INV
end

local function filter_intensity(cache)
  local v1 = math.max(1 - filter_log_norm(cache["1cutoff"]), filter_log_norm(cache["1hpf"]))
  local v2 = math.max(1 - filter_log_norm(cache["2cutoff"]), filter_log_norm(cache["2hpf"]))
  return math.max(v1, v2) * 100
end

local _draw_now = 0
local MIX_MOD_FREQ = 0.25
local MIX_MOD_PERIOD = 1 / MIX_MOD_FREQ
local function make_mix_mod()
  local cur, nxt = math.random(), math.random()
  local seg_start = util.time()
  return function(now)
    local t = now - seg_start
    if t >= MIX_MOD_PERIOD then
      repeat
        cur, nxt = nxt, math.random()
        seg_start = seg_start + MIX_MOD_PERIOD
        t = now - seg_start
      until t < MIX_MOD_PERIOD
    end
    return cur + (nxt - cur) * (t * MIX_MOD_FREQ)
  end
end
local _bitcrush_mod_lfo = make_mix_mod()
local _shimmer_mod_lfo = make_mix_mod()
local _drive_mod_lfo = make_mix_mod()

local FX_SPECS = {
  {glyph = "K", lock = nil,            show = function() return font.clocksync_ref and font.clocksync_ref.grain_synced() end, val = function() return 100 end},
  {glyph = "A", lock = nil,            show = function() return font.arp_ref and font.arp_ref.is_running() end, val = function() return 100 end, gradient = true},
  {glyph = "F", lock = "lock_filter",  show = filter_active,                                          val = filter_intensity},
  {glyph = "B", lock = nil,            show = function(c) return c.bitcrush_mix > 0 end,              val = function(c) return c.bitcrush_mod == 2 and c.bitcrush_mix * _bitcrush_mod_lfo(_draw_now) or c.bitcrush_mix end},
  {glyph = "O", lock = nil,            show = function(c) return c.resonator_mix > 0 end,             val = function(c) return c.resonator_mix end},
  {glyph = "W", lock = nil,            show = function(c) return c.wavefold_mix > 0 end,              val = function(c) return c.wavefold_mix end},
  {glyph = "M", lock = nil,            show = function(c) return c.ringmod_mix > 0 end,               val = function(c) return c.ringmod_mix end},
  {glyph = "V", lock = nil,            show = function(c) return c.analogdrive_mix > 0 end,           val = function(c) return c.analogdrive_mod == 2 and c.analogdrive_mix * _drive_mod_lfo(_draw_now) or c.analogdrive_mix end},
  {glyph = "G", lock = "lock_glitch",  show = function(c) return c.glitch_ratio > 0 and c.glitch_mix > 0 end, val = function(c) return c.glitch_ratio end},
  {glyph = "T", lock = "lock_tape",    show = tape_active,                                            val = tape_intensity},
  {glyph = "X", lock = "lock_shimmer", show = function(c) return c.shimmer_mix1 > 0 end,              val = function(c) return c.shimmer_mod1 == 2 and c.shimmer_mix1 * _shimmer_mod_lfo(_draw_now) or c.shimmer_mix1 end},
  {glyph = "D", lock = "lock_delay",   show = function(c) return c.delay_mix > 0 end,                 val = function(c) return c.delay_mix end, fade = function() return _delay_duck_gain end},
  {glyph = "R", lock = "lock_reverb",  show = function(c) return c.reverb_mix > -40 end,              val = function(c) return util.linlin(-40, 18, 0, 100, c.reverb_mix) end},
  {glyph = "Z", lock = nil,            show = stereo_active,                                          val = stereo_intensity},
}

local _gradient = {1, 1, 1}
local function column_gradient(peak)
  _gradient[1] = math.max(1, math.floor(peak * 0.35))
  _gradient[2] = math.max(1, math.floor(peak * 0.65))
  _gradient[3] = peak
  return _gradient
end

local function refresh_draw_caches()
  local phase = (util.time() * 2) % 1
  _blink_level = phase < 0.5 and 4 or 1
  for _, spec in ipairs(FX_SPECS) do
    if spec.lock then _lock_cache[spec.lock] = is_locked(spec.lock) end
  end
end

local _pc_l, _pc_x, _pc_y, _pc_n = {}, {}, {}, 0
local _last_update = -1
local _update_interval = 1 / 10
local min, max, floor = math.min, math.max, math.floor

local _collect_n = 0
local function collect(level, px, py)
  _collect_n = _collect_n + 1
  _pc_l[_collect_n], _pc_x[_collect_n], _pc_y[_collect_n] = level, px, py
end

function font.draw_fx_status_bucketed(P_func)
  local now = util.time()
  if now - _last_update >= _update_interval then
    _last_update = now
    _draw_now = now
    refresh_draw_caches()
    _collect_n = 0
    local x = 7
    for i = 1, #FX_SPECS do
      local spec = FX_SPECS[i]
      if spec.show(fx_cache) then
        local level = value_to_level(spec.val(fx_cache))
        if spec.lock and _lock_cache[spec.lock] then
          level = min(15, level + (_blink_level == 4 and 2 or 0))
        end
        if spec.fade then
          local f = max(0, min(1, spec.fade(fx_cache)))
          level = max(1, 1 + floor((level - 1) * f))
        end
        if spec.gradient then
          level = column_gradient(level)
        end
        x = plot_text(collect, x, 0, spec.glyph, level)
      end
    end
    _pc_n = _collect_n
  end
  local l, px, py = _pc_l, _pc_x, _pc_y
  for i = 1, _pc_n do
    P_func(l[i], px[i], py[i])
  end
end

return font