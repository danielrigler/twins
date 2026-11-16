local font = {}

local micro_font = {
  D = {{1,1,0},{1,0,1},{1,1,0}},
  B = {{1,1,0},{0,1,1},{0,0,1}},
  L = {{1,0},{1,0},{1,1}},
  C = {{1,1,1},{1,0,0},{1,1,1}},
  c = {{1,1},{1,0},{1,1}},
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

local micro_font_by_byte = {}
for ch, glyph in pairs(micro_font) do micro_font_by_byte[ch:byte()] = glyph end

local function plot_text(plot, x, y, text, level)
  local cursor_x = x
  local level_is_fn = type(level) == "function"
  local col_levels = (not level_is_fn) and type(level) == "table" and level or nil
  local col_last = col_levels and col_levels[#col_levels] or nil
  for i = 1, #text do
    local glyph = micro_font_by_byte[text:byte(i)]
    if glyph then
      local w = #glyph[1]
      for row = 1, 3 do
        for col = 1, w do
          if glyph[row][col] == 1 then
            local lvl
            if level_is_fn then
              lvl = level(row, col)
            else
              lvl = col_levels and (col_levels[col] or col_last) or level
            end
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

local min, max, floor, abs, log = math.min, math.max, math.floor, math.abs, math.log

local IDS = {"delay_mix", "reverb_mix", "rev_freeze", "halo_mix", "shimmer_mix1", "shimmer_mod1", "prism_mix", "analogdrive_mix", "analogdrive_mod",
  "fuzz_mix", "tape_mix", "sine_drive_wet", "wobble_mix", "chew_depth", "lossdegrade_mix", "genloss_mix", "reel_mix",
  "1eq_low_gain", "1eq_mid_gain", "1eq_high_gain", "1eq_tilt", "2eq_low_gain", "2eq_mid_gain", "2eq_high_gain", "2eq_tilt",
  "1cutoff", "2cutoff", "1hpf", "2hpf", "Width", "haas", "rspeed", "monobass_mix", "dimension_mix", "stchorus_mix", "vibe_mix",
  "bitcrush_mix", "bitcrush_mod", "resonator_mix", "wavefold_mix", "ringmod_mix", "spiral_mix", "sub_mix", "ott_mix", "glitch_ratio", "glitch_mix",
  "lock_glitch", "lock_tape", "lock_shimmer", "lock_halo", "lock_delay", "lock_reverb"}
local EQ_IDS = {"1eq_low_gain", "1eq_mid_gain", "1eq_high_gain", "1eq_tilt", "2eq_low_gain", "2eq_mid_gain", "2eq_high_gain", "2eq_tilt"}

local fx, objs, raws, nobj = {}, {}, {}, 0
local function poll()
  for i = 1, nobj do
    local o = objs[i]
    local r = o.raw or o.value or o.selected
    if r ~= raws[i] then raws[i] = r fx[o.id] = o:get() end
  end
end

function font.init_fx_cache()
  nobj = 0
  for _, id in ipairs(IDS) do
    local i = params.lookup[id]
    if i then nobj = nobj + 1 objs[nobj], raws[nobj] = params.params[i], nil end
  end
  for _, id in ipairs(IDS) do fx[id] = 0 end
  poll()
end

local _delay_duck_gain = 1.0
function font.set_delay_duck(gain) _delay_duck_gain = gain end

font.arp_ref = nil
font.clocksync_ref = nil
function font.set_context(ctx)
  font.arp_ref = ctx.arp
  font.clocksync_ref = ctx.clocksync
end

local function tape_on(c) return c.tape_mix == 2 or c.sine_drive_wet > 0 or c.wobble_mix > 0 or c.chew_depth > 0 or c.lossdegrade_mix > 0 or c.genloss_mix > 0 or c.reel_mix > 0 end
local function tape_val(c) return max(c.tape_mix == 2 and 25 or 0, c.sine_drive_wet, c.wobble_mix, c.chew_depth, c.lossdegrade_mix, c.genloss_mix, c.reel_mix) end
local function stereo_on(c) return c.Width ~= 100 or c.haas == 2 or c.rspeed > 0 or c.monobass_mix == 2 end
local function stereo_val(c) return max(abs(c.Width - 100) / 100, (c.haas == 2 or c.monobass_mix == 2) and 0.25 or 0, c.rspeed) * 100 end
local function filter_on(c) return c["1cutoff"] < 19999 or c["2cutoff"] < 19999 or c["1hpf"] > 20.1 or c["2hpf"] > 20.1 end
local LF = 1 / log(1000)
local function fnorm(f) return log(min(max(f, 20), 20000) / 20) * LF end
local function filter_val(c) return max(1 - fnorm(c["1cutoff"]), fnorm(c["1hpf"]), 1 - fnorm(c["2cutoff"]), fnorm(c["2hpf"])) * 100 end
local function eq_val(c) local m = 0 for i = 1, 8 do local v = abs(c[EQ_IDS[i]]) if v > m then m = v end end return m * 100 end
local function eq_on(c) return eq_val(c) > 0.5 end
local function chorus_on(c) return c.dimension_mix > 0 or c.stchorus_mix > 0 or c.vibe_mix > 0 end
local function chorus_val(c) return max(c.dimension_mix, c.stchorus_mix, c.vibe_mix) end
local function glitch_on(c) return c.glitch_ratio > 0 and c.glitch_mix > 0 end
local function reverb_on(c) return c.reverb_mix > -40 end
local function on(id) return function(c) return c[id] > 0 end end
local function val(id) return function(c) return c[id] end end

local function mixmod()
  local cur, nxt, t0 = math.random(), math.random(), util.time()
  return function(now)
    while now - t0 >= 4 do cur, nxt, t0 = nxt, math.random(), t0 + 4 end
    return cur + (nxt - cur) * (now - t0) * 0.25
  end
end
local bc_lfo, sh_lfo, dr_lfo, now_t = mixmod(), mixmod(), mixmod(), 0

local CLOCK = {{1,2},{2,3},{3,2},{2,1}}
local SPECS = {
  {"K", show = function() return font.clocksync_ref and font.clocksync_ref.grain_synced() end, clock = true},
  {"A", show = function() return font.arp_ref and font.arp_ref.is_running() end, val = function() return 100 end, gradient = true},
  {"F", show = filter_on, val = filter_val},
  {"E", show = eq_on, val = eq_val},
  {"B", show = on("bitcrush_mix"), val = function(c) return c.bitcrush_mod == 2 and c.bitcrush_mix * bc_lfo(now_t) or c.bitcrush_mix end},
  {"O", show = on("resonator_mix"), val = val("resonator_mix")},
  {"W", show = on("wavefold_mix"), val = val("wavefold_mix")},
  {"M", show = on("ringmod_mix"), val = val("ringmod_mix")},
  {"V", show = function(c) return c.analogdrive_mix > 0 or c.fuzz_mix > 0 end, val = function(c) return max(c.analogdrive_mod == 2 and c.analogdrive_mix * dr_lfo(now_t) or c.analogdrive_mix, c.fuzz_mix) end},
  {"U", show = on("sub_mix"), val = val("sub_mix")},
  {"c", show = on("ott_mix"), val = val("ott_mix")},
  {"S", show = on("spiral_mix"), val = val("spiral_mix")},
  {"G", lock = "lock_glitch", show = glitch_on, val = val("glitch_ratio")},
  {"T", lock = "lock_tape", show = tape_on, val = tape_val},
  {"P", show = on("prism_mix"), val = val("prism_mix")},
  {"X", lock = "lock_shimmer", show = on("shimmer_mix1"), val = function(c) return c.shimmer_mod1 == 2 and c.shimmer_mix1 * sh_lfo(now_t) or c.shimmer_mix1 end},
  {"H", lock = "lock_halo", show = on("halo_mix"), val = val("halo_mix")},
  {"D", lock = "lock_delay", show = on("delay_mix"), val = val("delay_mix"), fade = true},
  {"R", lock = "lock_reverb", show = reverb_on, val = function(c) return c.rev_freeze == 1 and 100 or (c.reverb_mix + 40) / 58 * 100 end},
  {"Z", show = stereo_on, val = stereo_val},
  {"C", show = chorus_on, val = chorus_val}
}

local GROUPS = {
  {"tw_delay", on("delay_mix"), {delay_mix = 0}},
  {"tw_reverb", reverb_on, {reverb_mix = -40, rev_freeze = 0}},
  {"tw_halo", on("halo_mix"), {halo_mix = 0}},
  {"tw_shimmer", on("shimmer_mix1"), {shimmer_mix1 = 0}},
  {"tw_prism", on("prism_mix"), {prism_mix = 0}},
  {"tw_drive", on("analogdrive_mix"), {analogdrive_mix = 0}},
  {"tw_fuzz", on("fuzz_mix"), {fuzz_mix = 0}},
  {"tw_tape", tape_on, {tape_mix = 1, sine_drive_wet = 0, wobble_mix = 0, chew_depth = 0, lossdegrade_mix = 0, genloss_mix = 0, reel_mix = 0}},
  {"tw_eq", eq_on, {["1eq_low_gain"] = 0, ["1eq_mid_gain"] = 0, ["1eq_high_gain"] = 0, ["1eq_tilt"] = 0, ["2eq_low_gain"] = 0, ["2eq_mid_gain"] = 0, ["2eq_high_gain"] = 0, ["2eq_tilt"] = 0}},
  {"tw_filter", filter_on, {["1cutoff"] = 20000, ["2cutoff"] = 20000, ["1hpf"] = 20, ["2hpf"] = 20}},
  {"tw_stereo", stereo_on, {Width = 100, haas = 1, rspeed = 0, monobass_mix = 1}},
  {"tw_chorus", chorus_on, {dimension_mix = 0, stchorus_mix = 0, vibe_mix = 0}},
  {"tw_bitcrush", on("bitcrush_mix"), {bitcrush_mix = 0}},
  {"tw_reso", on("resonator_mix"), {resonator_mix = 0}},
  {"tw_wavefold", on("wavefold_mix"), {wavefold_mix = 0}},
  {"tw_ringmod", on("ringmod_mix"), {ringmod_mix = 0}},
  {"tw_spiral", on("spiral_mix"), {spiral_mix = 0}},
  {"tw_sub", on("sub_mix"), {sub_mix = 0}},
  {"tw_ott", on("ott_mix"), {ott_mix = 0}},
  {"tw_glitch", glitch_on, {glitch_ratio = 0}}
}

function font.groups(t)
  poll()
  for i = 1, #GROUPS do local g = GROUPS[i] t[g[1]] = g[2](fx) end
  return t
end

function font.clear()
  poll()
  for i = 1, #GROUPS do
    local g = GROUPS[i]
    if g[2](fx) then for id, v in pairs(g[3]) do params:set(id, v) end end
  end
end

local _gradient = {1, 1, 1}
local function column_gradient(peak)
  _gradient[1] = max(1, floor(peak * 0.35))
  _gradient[2] = max(1, floor(peak * 0.65))
  _gradient[3] = peak
  return _gradient
end

local _pc_l, _pc_x, _pc_y, _pc_w, _pc_n = {}, {}, {}, {}, 0
local _last_update = -1
local _collect_n = 0
local function collect(level, px, py)
  local n = _collect_n
  if n > 0 and _pc_y[n] == py and _pc_l[n] == level and _pc_x[n] + _pc_w[n] == px then _pc_w[n] = _pc_w[n] + 1 return end
  n = n + 1
  _collect_n = n
  _pc_l[n], _pc_x[n], _pc_y[n], _pc_w[n] = level, px, py, 1
end

function font.draw_fx_status_bucketed(R_func)
  local now = util.time()
  if now - _last_update >= 0.1 then
    _last_update, now_t = now, now
    poll()
    local blink = (now * 2) % 1 < 0.5
    _collect_n = 0
    local x = 7
    for i = 1, #SPECS do
      local s = SPECS[i]
      if s.show(fx) then
        local level
        if s.clock then
          local pos = CLOCK[(floor(clock.get_beats()) % 4) + 1]
          level = function(row, col) return (row == pos[1] and col == pos[2]) and 15 or 3 end
        else
          level = 1 + floor(min(max(s.val(fx), 0), 100) * 0.14)
          if s.lock and blink and fx[s.lock] == 2 then level = min(15, level + 2) end
          if s.fade then level = max(1, 1 + floor((level - 1) * max(0, min(1, _delay_duck_gain)))) end
          if s.gradient then level = column_gradient(level) end
        end
        x = plot_text(collect, x, 0, s[1], level)
      end
    end
    _pc_n = _collect_n
  end
  local l, px, py, pw = _pc_l, _pc_x, _pc_y, _pc_w
  for i = 1, _pc_n do R_func(l[i], px[i], py[i], pw[i], 1) end
end

return font
