local font = {}

font.micro_font = {
  D = {{1,1,0},{1,0,1},{1,1,0}},
  B = {{1,1,0},{0,1,1},{0,0,1}},
  L = {{1,0},{1,0},{1,1}},
  C = {{1,1,1},{1,0,0},{1,1,1}},
  G = {{1,1,0},{1,0,1},{1,1,1}},
  E = {{1,1,1},{1,1,0},{1,1,1}},
  I = {{1,0},{1,0},{1,0}},
  R = {{1,1,1},{1,1,0},{1,0,1}},
  T = {{1,1,1},{0,1,0},{0,1,0}},
  S = {{0,1,1},{0,1,0},{1,1,0}},
  X = {{0,1,1,1,0,1},{0,1,0,1,1,1},{1,1,0,1,0,1}},
  V = {{1,0,1},{1,0,1},{0,1,0}},
  H = {{1,0,1},{1,1,1},{1,0,1}},
  Z = {{0,1,1,1,1},{0,1,0,1,0},{1,1,0,1,0}},
  F = {{1,1,1},{1,1,0},{1,0,0}},
  P = {{1,1,1},{1,1,1},{1,0,0}},
  O = {{1,1,1},{1,0,1},{1,1,1}},
  W = {{1,0,1},{1,1,1},{1,1,1}},
  M = {{1,0,1},{0,1,0},{1,0,1}},
  K = {{0,1,0},{1,0,1},{0,1,0}},
  A = {{0,0,1},{0,1,1},{1,1,1}}
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

local fx_cache = {
  delay_mix       = 0,
  reverb_mix      = 0,
  shimmer_mix1    = 0,
  tape_mix        = 1,
  sine_drive_wet  = 0,
  drive           = 0,
  wobble_mix      = 0,
  chew_depth      = 0,
  lossdegrade_mix = 0,
  Width           = 100,
  dimension_mix   = 0,
  haas            = 1,
  rspeed          = 0,
  monobass_mix    = 1,
  bitcrush_mix    = 0,
  glitch_ratio    = 0,
  glitch_mix      = 0,
  resonator_mix   = 0,
  wavefold_mix    = 0,
  ringmod_mix     = 0,
  ["1cutoff"]     = 20000,
  ["2cutoff"]     = 20000,
  ["1hpf"]        = 20,
  ["2hpf"]        = 20,
  ["1pitch_shift"] = 0,
  ["2pitch_shift"] = 0
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
function font.set_arp_reference(a) font.arp_ref = a end

font.clocksync_ref = nil
function font.set_clocksync_reference(c) font.clocksync_ref = c end

local function value_to_level(val)
  return 1 + math.floor((val / 100) * 14)
end

local BINARY_ON_INTENSITY = 25

local function tape_active(cache)
  return cache.tape_mix == 2 or cache.sine_drive_wet > 0 or cache.drive > 0
      or cache.wobble_mix > 0 or cache.chew_depth > 0 or cache.lossdegrade_mix > 0
end

local function tape_intensity(cache)
  local maxv = cache.tape_mix == 2 and BINARY_ON_INTENSITY or 0
  if cache.sine_drive_wet  > maxv then maxv = cache.sine_drive_wet  end
  if cache.drive           > maxv then maxv = cache.drive           end
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

local function filter_intensity(cache)
  local function cutoff_intensity(cutoff)
    return (20000 - math.min(math.max(cutoff, 20), 20000)) / 19980
  end
  local function hpf_intensity(hpf)
    return (math.min(math.max(hpf, 20), 20000) - 20) / 19980
  end
  local v1 = math.max(cutoff_intensity(cache["1cutoff"]), hpf_intensity(cache["1hpf"]))
  local v2 = math.max(cutoff_intensity(cache["2cutoff"]), hpf_intensity(cache["2hpf"]))
  return math.max(v1, v2) * 100
end

local function pitchshift_active(cache)
  return cache["1pitch_shift"] ~= 0 or cache["2pitch_shift"] ~= 0
end

local function pitchshift_intensity(cache)
  local v1 = math.abs(cache["1pitch_shift"]) / 48
  local v2 = math.abs(cache["2pitch_shift"]) / 48
  return math.max(v1, v2) * 100
end

local FX_SPECS = {
  {glyph = "K", lock = nil,            show = function() return font.clocksync_ref and font.clocksync_ref.grain_synced() end, val = function() return 100 end},
  {glyph = "A", lock = nil,            show = function() return font.arp_ref and font.arp_ref.is_running() end, val = function() return 100 end, gradient = true},
  {glyph = "P", lock = nil,            show = pitchshift_active,                                      val = pitchshift_intensity},
  {glyph = "F", lock = "lock_filter",  show = filter_active,                                          val = filter_intensity},
  {glyph = "B", lock = nil,            show = function(c) return c.bitcrush_mix > 0 end,              val = function(c) return c.bitcrush_mix end},
  {glyph = "O", lock = nil,            show = function(c) return c.resonator_mix > 0 end,             val = function(c) return c.resonator_mix end},
  {glyph = "W", lock = nil,            show = function(c) return c.wavefold_mix > 0 end,              val = function(c) return c.wavefold_mix end},
  {glyph = "M", lock = nil,            show = function(c) return c.ringmod_mix > 0 end,               val = function(c) return c.ringmod_mix end},
  {glyph = "G", lock = "lock_glitch",  show = function(c) return c.glitch_ratio > 0 and c.glitch_mix > 0 end, val = function(c) return c.glitch_ratio end},
  {glyph = "T", lock = "lock_tape",    show = tape_active,                                            val = tape_intensity},
  {glyph = "D", lock = "lock_delay",   show = function(c) return c.delay_mix > 0 end,                 val = function(c) return c.delay_mix end, fade = function() return _delay_duck_gain end},
  {glyph = "X", lock = "lock_shimmer", show = function(c) return c.shimmer_mix1 > 0 end,              val = function(c) return c.shimmer_mix1 end},
  {glyph = "R", lock = "lock_reverb",  show = function(c) return c.reverb_mix > 0 end,                val = function(c) return c.reverb_mix end},
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

function font.draw_fx_status_bucketed(P_func)
  local now = util.time()
  if now - _last_update >= _update_interval then
    _last_update = now
    refresh_draw_caches()
    local n = 0
    local collect = function(level, px, py)
      n = n + 1
      _pc_l[n], _pc_x[n], _pc_y[n] = level, px, py
    end
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
    _pc_n = n
  end
  local l, px, py = _pc_l, _pc_x, _pc_y
  for i = 1, _pc_n do
    P_func(l[i], px[i], py[i])
  end
end

return font
