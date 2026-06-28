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
  O = {{1,1,1},{1,0,1},{1,1,1}},
  W = {{1,0,1},{1,1,1},{1,1,1}},
  M = {{1,0,1},{0,1,0},{1,0,1}}
}

local function plot_text(plot, x, y, text, level)
  local cursor_x = x
  for i = 1, #text do
    local char  = text:sub(i, i)
    local glyph = font.micro_font[char]
    if glyph then
      local w = #glyph[1]
      for row = 1, 3 do
        for col = 1, w do
          if glyph[row][col] == 1 then
            plot(level or 1, cursor_x + col - 1, y + row - 1)
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

function font.draw_micro_text_bucketed(P_func, x, y, text, level)
  plot_text(P_func, x, y, text, level)
end

local function is_locked(lock_key)
  return params.lookup[lock_key] and params:get(lock_key) == 2
end

local _lock_cache = {}
local _blink_level = 1

local function value_to_level(val)
  return 1 + math.floor((val / 100) * 14)
end

local function tape_active(cache)
  return cache.tape_mix == 2 or cache.sine_drive_wet > 0 or cache.drive > 0
      or cache.wobble_mix > 0 or cache.chew_depth > 0 or cache.lossdegrade_mix > 0
end

local function tape_intensity(cache)
  local vals = {
    cache.tape_mix == 2 and 100 or 0,
    cache.sine_drive_wet,
    cache.drive,
    cache.wobble_mix,
    cache.chew_depth,
    cache.lossdegrade_mix
  }
  local maxv = 0
  for _, v in ipairs(vals) do
    if v > maxv then maxv = v end
  end
  return maxv
end

local function stereo_active(cache)
  return cache.Width ~= 100 or cache.dimension_mix > 0
      or cache.haas == 2 or cache.rspeed > 0 or cache.monobass_mix == 2
end

local function stereo_intensity(cache)
  local width_dev = math.abs(cache.Width - 100) / 100
  local dim = cache.dimension_mix / 100
  local haas_val = cache.haas == 2 and 1 or 0
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

local FX_SPECS = {
  {glyph = "D", lock = "lock_delay",   show = function(c) return c.delay_mix > 0 end,                 val = function(c) return c.delay_mix end},
  {glyph = "R", lock = "lock_reverb",  show = function(c) return c.reverb_mix > 0 end,                val = function(c) return c.reverb_mix end},
  {glyph = "X", lock = "lock_shimmer", show = function(c) return c.shimmer_mix1 > 0 end,              val = function(c) return c.shimmer_mix1 end},
  {glyph = "T", lock = "lock_tape",    show = tape_active,                                            val = tape_intensity},
  {glyph = "Z", lock = nil,            show = stereo_active,                                          val = stereo_intensity},
  {glyph = "B", lock = nil,            show = function(c) return c.bitcrush_mix > 0 end,              val = function(c) return c.bitcrush_mix end},
  {glyph = "F", lock = "lock_filter",  show = filter_active,                                          val = filter_intensity},
  {glyph = "G", lock = "lock_glitch",  show = function(c) return c.glitch_ratio > 0 and c.glitch_mix > 0 end, val = function(c) return c.glitch_ratio end},
  {glyph = "O", lock = nil,            show = function(c) return c.resonator_mix > 0 end,            val = function(c) return c.resonator_mix end},
  {glyph = "W", lock = nil,            show = function(c) return c.wavefold_mix > 0 end,             val = function(c) return c.wavefold_mix end},
  {glyph = "M", lock = nil,            show = function(c) return c.ringmod_mix > 0 end,              val = function(c) return c.ringmod_mix end},
}

local function refresh_draw_caches()
  local phase = (util.time() * 2) % 1
  _blink_level = phase < 0.5 and 4 or 1
  for _, spec in ipairs(FX_SPECS) do
    if spec.lock then _lock_cache[spec.lock] = is_locked(spec.lock) end
  end
end

local _pixel_cache = nil
local _last_update = 0
local _update_interval = 1 / 10

function font.draw_fx_status_bucketed(P_func)
  local now = util.time()
  if _pixel_cache == nil or now - _last_update >= _update_interval then
    _pixel_cache = {}
    _last_update = now
    refresh_draw_caches()

    local collect = function(level, px, py)
      table.insert(_pixel_cache, {level, px, py})
    end

    local y = 0
    local x = 7
    for _, spec in ipairs(FX_SPECS) do
      if spec.show(fx_cache) then
        local level = value_to_level(spec.val(fx_cache))
        if spec.lock and _lock_cache[spec.lock] then
          level = math.min(15, level + (_blink_level == 4 and 2 or 0))
        end
        x = plot_text(collect, x, y, spec.glyph, level)
      end
    end
  end

  for _, px in ipairs(_pixel_cache) do
    P_func(px[1], px[2], px[3])
  end
end

return font