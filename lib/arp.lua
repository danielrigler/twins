local arp = {}

local MusicUtil = require("musicutil")
local clamp = util.clamp
local floor = math.floor
local random = math.random
local MAX_STEPS = 8
local DEG_MIN, DEG_MAX = -14, 14
local SU = nil
local clocksync = nil
local is_voice_active = function(_) return true end
local checkpoint = function() end
local running   = false
local nsteps    = 4
local mode      = 1
local twin      = 1
local octaves   = 1
local step_deg  = {0, 0, 0, 0, 0, 0, 0, 0}
local step_vol  = {100, 100, 100, 100, 100, 100, 100, 100}
local step_rat  = {1, 1, 1, 1, 1, 1, 1, 1}
local ratio     = {1, 1}
local tickn        = {0, 0}
local pre_arp_size = {nil, nil}
local pre_arp_prob = {nil, nil}
local co           = {nil, nil}
local DEG_PALETTE  = {-7, -5, -4, -3, 0, 0, 2, 4, 4, 6, 7}

local ivs_cache = {}
local function scale_intervals(scale_name)
  scale_name = SU.normalize(scale_name)
  if scale_name == "none" then return nil end
  local ivs = ivs_cache[scale_name]
  if not ivs then
    local ok, r = pcall(MusicUtil.generate_scale, 0, scale_name, 1)
    ivs = (ok and r) or MusicUtil.generate_scale(0, "major", 1)
    ivs_cache[scale_name] = ivs
  end
  return ivs
end

local PITCH_KEYS   = {"1pitch", "2pitch"}
local SIZE_KEYS    = {"1size", "2size"}
local DENSITY_KEYS = {"1density", "2density"}
local RAT_KEYS     = {"1ratcheting_prob", "2ratcheting_prob"}
local scale_idx, scale_name, scale_ivs = nil, "off", nil
local last_po = {nil, nil}

local function refresh_scale()
  local si = params:get("pitch_quantize_scale")
  if si ~= scale_idx then
    scale_idx = si
    scale_name = params:string("pitch_quantize_scale")
    scale_ivs = scale_intervals(scale_name)
  end
end

local function degree_to_st(deg)
  local ivs = scale_ivs
  if not ivs then return deg end
  local n = #ivs - 1
  local oct = floor(deg / n)
  return ivs[deg - oct * n + 1] + oct * 12
end

local function fire(v, idx, invert, oct)
  if not is_voice_active(v) then return end
  refresh_scale()
  local deg   = step_deg[idx] * (invert and -1 or 1)
  local st    = degree_to_st(deg) + oct * 12
  local base  = SU.quantize(params:get(PITCH_KEYS[v]), scale_name)
  local total = clamp(base + st, -48, 48)
  ratio[v] = 2 ^ ((total - base) / 12)
  local po = 2 ^ (total / 12)
  if po ~= last_po[v] then
    last_po[v] = po
    engine.pitch_offset(v, po)
  end
  engine.vel_amp(v, step_vol[idx] * 0.01)
  engine.key_grain(v)
end

local function index_for(t, count)
  if count <= 1 then return 1 end
  if mode == 1 then return (t - 1) % count + 1 end
  if mode == 2 then return count - ((t - 1) % count) end
  if mode == 3 then
    local p = (t - 1) % (2 * count - 2)
    return p < count and (p + 1) or (2 * count - 1 - p)
  end
  return random(count)
end

local function twin_index(i1, count)
  if twin == 2 then return (i1 - 1 + floor(count / 2)) % count + 1 end
  if twin == 3 then return count + 1 - i1 end
  return i1
end

local function rebang_pitch(v)
  local i = params.lookup and params.lookup[PITCH_KEYS[v]]
  if i then params.params[i]:bang() end
end

local function get_hz(v)
  local cs = clocksync
  if cs and cs.grain_synced() then return cs.grain_density(v) or params:get(DENSITY_KEYS[v]) end
  return params:get(DENSITY_KEYS[v])
end

local eff_size = {nil, nil}

local function apply_size_cap(v, hz, half)
  local id = SIZE_KEYS[v]
  if not params.lookup[id] then return end
  local cap = (half and 500 or 1000) / hz
  local desired = params:get(id)
  local eff = desired > cap and cap or desired
  if half or eff ~= eff_size[v] then
    eff_size[v] = eff
    engine.size(v, eff * 0.001)
  end
end

local function rebang_size(v)
  local i = params.lookup and params.lookup[SIZE_KEYS[v]]
  if i then params.params[i]:bang() end
end

local function refire(v)
  if not is_voice_active(v) then return end
  engine.key_grain(v)
end

local function tick(v, hz)
  local t = tickn[v] + 1
  tickn[v] = t
  local count = nsteps
  local i1  = index_for(t, count)
  local idx = (v == 1) and i1 or twin_index(i1, count)
  local oct = floor((t - 1) / count) % octaves
  local ratchet = (step_rat[idx] * 100) < params:get(RAT_KEYS[v])
  apply_size_cap(v, hz, ratchet)
  fire(v, idx, v == 2 and twin == 3, oct)
  return ratchet
end

local function stop_clock()
  for v = 1, 2 do
    if co[v] then clock.cancel(co[v]); co[v] = nil end
  end
end

local function start_clock()
  stop_clock()
  local sync, sleep, get_tempo = clock.sync, clock.sleep, clock.get_tempo
  for v = 1, 2 do
    co[v] = clock.run(function()
      local carry = 0
      while true do
        local hz = clamp(get_hz(v), 0.1, 250)
        if clocksync.grain_synced() then
          sync(get_tempo() / (60 * hz))
        else
          sleep((1 - carry) / hz)
        end
        carry = 0
        hz = clamp(get_hz(v), 0.1, 250)
        if tick(v, hz) then
          if clocksync.grain_synced() then
            sync(get_tempo() / (60 * hz) * 0.5)
          else
            sleep(0.5 / hz)
          end
          refire(v)
          carry = 0.5
        end
      end
    end)
  end
end

local function set_running(on)
  if on == running then return end
  running = on
  if on then
    tickn = {0, 0}
    last_po = {nil, nil}
    eff_size = {nil, nil}
    for v = 1, 2 do
      local id_size = SIZE_KEYS[v]
      local id_prob = v .. "probability"
      if params.lookup[id_size] and pre_arp_size[v] == nil then pre_arp_size[v] = params:get(id_size) end
      if params.lookup[id_prob] then
        local cur = params:get(id_prob)
        if pre_arp_prob[v] == nil and cur > 0 then pre_arp_prob[v] = cur end
        params:set(id_prob, 0)
      end
      apply_size_cap(v, clamp(get_hz(v), 0.1, 250))
    end
    start_clock()
  else
    stop_clock()
    last_po = {nil, nil}
    for v = 1, 2 do
      ratio[v] = 1
      engine.vel_amp(v, 1)
      rebang_pitch(v)
      local id_size = SIZE_KEYS[v]
      local id_prob = v .. "probability"
      if pre_arp_size[v] and params.lookup[id_size] then params:set(id_size, pre_arp_size[v]) end
      rebang_size(v)
      eff_size[v] = nil
      if params.lookup[id_prob] then
        local pp = pre_arp_prob[v]
        params:set(id_prob, (pp and pp > 0) and pp or 100)
      end
      pre_arp_size[v] = nil
      pre_arp_prob[v] = nil
    end
  end
end

local function randomize()
  checkpoint()
  nsteps  = random(2, MAX_STEPS)
  mode    = random(1, 4)
  twin    = random(1, 3)
  octaves = random(1, 2)
  local prev
  for i = 1, MAX_STEPS do
    local d
    repeat d = DEG_PALETTE[random(#DEG_PALETTE)] until d ~= prev
    step_deg[i] = d
    prev = d
  end
  if nsteps > 1 and step_deg[nsteps] == step_deg[1] then
    local d
    repeat d = DEG_PALETTE[random(#DEG_PALETTE)] until d ~= step_deg[1] and d ~= step_deg[nsteps - 1]
    step_deg[nsteps] = d
  end
  local lo, hi = step_deg[1], step_deg[1]
  for i = 2, nsteps do lo = math.min(lo, step_deg[i]); hi = math.max(hi, step_deg[i]) end
  local guard = 0
  while (hi - lo) < 4 and guard < 20 do
    local i = random(1, nsteps)
    local d
    repeat d = DEG_PALETTE[random(#DEG_PALETTE)]
    until d ~= step_deg[(i - 2) % nsteps + 1] and d ~= step_deg[i % nsteps + 1]
    step_deg[i] = d
    lo, hi = step_deg[1], step_deg[1]
    for k = 2, nsteps do lo = math.min(lo, step_deg[k]); hi = math.max(hi, step_deg[k]) end
    guard = guard + 1
  end
  for i = 1, MAX_STEPS do
    step_vol[i] = (random(6) == 1) and 0 or random(55, 100)
    step_rat[i] = random()
  end
  step_vol[1] = math.max(step_vol[1], 80)
end

function arp.ratio(v) return ratio[v] end

function arp.is_running() return running end

function arp.max_size_ms(v)
  if not running then return math.huge end
  local hz = get_hz(tonumber(v)) or 1
  return (1 / hz) * 1000
end

function arp.snapshot()
  local deg, vol, rat = {}, {}, {}
  for i = 1, MAX_STEPS do deg[i] = step_deg[i]; vol[i] = step_vol[i]; rat[i] = step_rat[i] end
  return { nsteps = nsteps, mode = mode, twin = twin, octaves = octaves,
           deg = deg, vol = vol, rat = rat,
           pre_size1 = pre_arp_size[1], pre_size2 = pre_arp_size[2],
           pre_prob1 = pre_arp_prob[1], pre_prob2 = pre_arp_prob[2] }
end

function arp.restore(s)
  if type(s) ~= "table" then return end
  nsteps  = clamp(tonumber(s.nsteps) or nsteps, 1, MAX_STEPS)
  mode    = clamp(tonumber(s.mode) or mode, 1, 4)
  twin    = clamp(tonumber(s.twin) or twin, 1, 3)
  octaves = clamp(tonumber(s.octaves) or octaves, 1, 2)
  if type(s.deg) == "table" and type(s.vol) == "table" then
    for i = 1, MAX_STEPS do
      step_deg[i] = clamp(tonumber(s.deg[i]) or 0, DEG_MIN, DEG_MAX)
      step_vol[i] = clamp(tonumber(s.vol[i]) or 100, 0, 100)
    end
  end
  if type(s.rat) == "table" then
    for i = 1, MAX_STEPS do
      step_rat[i] = clamp(tonumber(s.rat[i]) or 1, 0, 1)
    end
  end
  pre_arp_size[1], pre_arp_size[2] = tonumber(s.pre_size1), tonumber(s.pre_size2)
  pre_arp_prob[1], pre_arp_prob[2] = tonumber(s.pre_prob1), tonumber(s.pre_prob2)
  tickn = {0, 0}
end

function arp.set_clocksync_reference(cs)
  clocksync = cs
end

function arp.add_params()
  params:add_group("ARP!", 2)
  params:add_option("arp_on", "Arp!", {"off", "on"}, 1)
  params:set_action("arp_on", function(v) set_running(v == 2) end)
  params:add_binary("arp_randomize", "RaNd0m1ze!", "trigger", 0)
  params:set_action("arp_randomize", function() randomize() end)
end

function arp.init(opts)
  SU = opts.scale_utils
  if opts.is_voice_active then is_voice_active = opts.is_voice_active end
  randomize()
  if opts.checkpoint then checkpoint = opts.checkpoint end
end

function arp.cleanup()
  stop_clock()
  running = false
end

return arp