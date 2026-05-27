local font = {}

font.micro_font = {
  D = {{1,1,0},{1,0,1},{1,1,0}},
  B = {{1,0,0},{1,1,1},{1,1,1}},
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
}

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
  local cursor_x = x
  for i = 1, #text do
    local char  = text:sub(i, i)
    local glyph = font.micro_font[char]
    if glyph then
      local w = #glyph[1]
      for row = 1, 3 do
        for col = 1, w do
          if glyph[row][col] == 1 then
            P_func(level or 1, cursor_x + col - 1, y + row - 1)
          end
        end
      end
      cursor_x = cursor_x + w + 1
    else
      cursor_x = cursor_x + 3
    end
  end
end

local LOCK_KEYS = {
  delay   = "lock_delay",
  reverb  = "lock_reverb",
  shimmer = "lock_shimmer",
  tape    = "lock_tape",
  filter  = "lock_filter",
  glitch  = "lock_glitch",
}

local function is_locked(lock_key)
  return params.lookup[lock_key] and params:get(lock_key) == 2
end

local _lock_cache = {}
local _blink_level = 1

local function refresh_draw_caches()
  local phase = (util.time() * 2) % 1
  _blink_level        = phase < 0.5 and 4 or 1
  _lock_cache.delay   = is_locked(LOCK_KEYS.delay)
  _lock_cache.reverb  = is_locked(LOCK_KEYS.reverb)
  _lock_cache.shimmer = is_locked(LOCK_KEYS.shimmer)
  _lock_cache.tape    = is_locked(LOCK_KEYS.tape)
  _lock_cache.filter  = is_locked(LOCK_KEYS.filter)
  _lock_cache.glitch  = is_locked(LOCK_KEYS.glitch)
end

local function value_to_level(val)
  return 1 + math.floor((val / 100) * 14)
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

local function stereo_intensity(cache)
  local width_dev = math.abs(cache.Width - 100) / 100
  local dim = cache.dimension_mix / 100
  local haas_val = cache.haas == 2 and 1 or 0
  local rspeed_val = cache.rspeed
  local mono_bass = cache.monobass_mix == 2 and 1 or 0
  local maxv = math.max(width_dev, dim, haas_val, rspeed_val, mono_bass)
  return maxv * 100
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

local function glitch_intensity(cache)
  return cache.glitch_ratio
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

    local y = 0
    local x = 7

    local function collect_pixels(tx, ty, text, level)
      local cursor_x = tx
      for i = 1, #text do
        local char = text:sub(i, i)
        local glyph = font.micro_font[char]
        if glyph then
          local w = #glyph[1]
          for row = 1, 3 do
            for col = 1, w do
              if glyph[row][col] == 1 then
                table.insert(_pixel_cache, {level, cursor_x + col - 1, ty + row - 1})
              end
            end
          end
          cursor_x = cursor_x + w + 1
        else
          cursor_x = cursor_x + 3
        end
      end
    end

    -- Delay
    if fx_cache.delay_mix > 0 then
      local level = value_to_level(fx_cache.delay_mix)
      if _lock_cache.delay then level = math.min(15, level + (_blink_level == 4 and 2 or 0)) end
      collect_pixels(x, y, "D", level)
      x = x + 4
    end

    -- Reverb
    if fx_cache.reverb_mix > 0 then
      local level = value_to_level(fx_cache.reverb_mix)
      if _lock_cache.reverb then level = math.min(15, level + (_blink_level == 4 and 2 or 0)) end
      collect_pixels(x, y, "R", level)
      x = x + 4
    end

    -- Shimmer
    if fx_cache.shimmer_mix1 > 0 then
      local level = value_to_level(fx_cache.shimmer_mix1)
      if _lock_cache.shimmer then level = math.min(15, level + (_blink_level == 4 and 2 or 0)) end
      collect_pixels(x, y, "X", level)
      x = x + 7
    end

    -- Tape
    if fx_cache.tape_mix == 2 or fx_cache.sine_drive_wet > 0 or fx_cache.drive > 0
       or fx_cache.wobble_mix > 0 or fx_cache.chew_depth > 0 or fx_cache.lossdegrade_mix > 0 then
      local intensity = tape_intensity(fx_cache)
      local level = value_to_level(intensity)
      if _lock_cache.tape then level = math.min(15, level + (_blink_level == 4 and 2 or 0)) end
      collect_pixels(x, y, "T", level)
      x = x + 4
    end

    -- Stereo
    if fx_cache.Width ~= 100 or fx_cache.dimension_mix > 0
       or fx_cache.haas == 2 or fx_cache.rspeed > 0 or fx_cache.monobass_mix == 2 then
      local intensity = stereo_intensity(fx_cache)
      local level = value_to_level(intensity)
      collect_pixels(x, y, "Z", level)
      x = x + 6
    end

    -- Bitcrush
    if fx_cache.bitcrush_mix > 0 then
      local level = value_to_level(fx_cache.bitcrush_mix)
      collect_pixels(x, y, "B", level)
      x = x + 4
    end

    -- Filter
    if fx_cache["1cutoff"] < 19999 or fx_cache["2cutoff"] < 19999
       or fx_cache["1hpf"] > 20.1 or fx_cache["2hpf"] > 20.1 then
      local intensity = filter_intensity(fx_cache)
      local level = value_to_level(intensity)
      if _lock_cache.filter then level = math.min(15, level + (_blink_level == 4 and 2 or 0)) end
      collect_pixels(x, y, "F", level)
      x = x + 4
    end

    -- Glitch
    if fx_cache.glitch_ratio > 0 and fx_cache.glitch_mix > 0 then
      local intensity = glitch_intensity(fx_cache)
      local level = value_to_level(intensity)
      if _lock_cache.glitch then level = math.min(15, level + (_blink_level == 4 and 2 or 0)) end
      collect_pixels(x, y, "G", level)
      x = x + 4
    end
  end

  for _, px in ipairs(_pixel_cache) do
    P_func(px[1], px[2], px[3])
  end
end

return font