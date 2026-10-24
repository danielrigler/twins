--
--
--   __ __|         _)          
--      | \ \  \  / |  \ |  (_< 
--      |  \_/\_/ _| _| _| __/ 
--            by: @dddstudio                       
-- 
--                          
--                           v0.80
-- E1: Master Volume
-- K1+E2/E3: Volume
-- K1+E1: Crossfade/Morph
-- K2/K3: Navigate
-- E2/E3: Adjust Parameters
-- K1+K2/K3: Randomize
-- K2+K3: Lock Parameters
-- Hold K1: Morphing
-- Hold K2: Linked Mode
-- Hold K3: Symmetry
-- K2+K3+E1/E2/E3: Effect Mix
-- K2/K3+E1/E2/E3: Adjust LFO
-- Hold K2+K3: HPF/LPF
-- Hold K2+K3: Add Random LFOs
-- Hold K1+K2: Clock Sync
-- Hold K1+K3: Arp Mode
-- Hold K1+K2+K3: Randomize Arp
-- K1+K2+K3 (tap): Undo
--
--
--
--
--              
--
--
--
--
-- Thanks to:
-- @infinitedigits @cfdrake
-- @justmat @artfwo @nzimas
-- @sonoCircuit @graymazes
-- @Higaru @NiklasKramer
-- @xmacex @vehka @Quixotic7
-- @Aktsom @Boorch
--
-- If you like this,
-- buy them a beer :)
--
--                    Daniel Rigler

local installer = include("lib/installer/installer"):new{requirements = {"AnalogChew", "AnalogLoss", "AnalogDegrade"}, zip = "https://github.com/schollz/portedplugins/releases/download/v0.4.6/PortedPlugins-RaspberryPi.zip"}
engine.name = installer:ready() and 'twins' or nil
local MusicUtil = require("musicutil")
local utils = include("lib/utils")
local font = include("lib/font")
local presets = include("lib/presets")
local randpara = include("lib/randpara")
local lfo = include("lib/lfo")
local morph = include("lib/morph")
local osc_positions = {[1] = 0, [2] = 0}
local Mirror = include("lib/mirror") Mirror.init(osc_positions, lfo, morph.voice_params)
local macro = include("lib/macro")
local drymode = include("lib/drymode")
local undo = include("lib/undo")
local midi_input = include("lib/midi_input")
local arp = include("lib/arp")
local clocksync = include("lib/clocksync")
local ctx = {lfo = lfo, arp = arp, clocksync = clocksync, bend = midi_input.bend, waveforms = {[0] = {}}, sys = {}}
for _, m in ipairs({presets, macro, drymode, font, lfo, arp}) do m.set_context(ctx) end
local randomize_metro = {}
local boot_clock = nil
local key_state = {false, false, false}
local current_mode = "seek"
local current_filter_mode = "lpf"
local audio_active = {[1] = false, [2] = false}
local live_state = {[1] = {input = false, direct = false}, [2] = {input = false, direct = false}}
local steps = 20
local mode_list = {"spread","pitch","density","size","jitter","lpf","eq","pan","speed","seek"}
local mode_indices = {} for i,v in ipairs(mode_list) do mode_indices[v] = i end
local MK = lfo.keys
local key_gesture = nil
local fx_popup = {}
local hlp = {}
function hlp.popup(label, value, sub) fx_popup.label, fx_popup.value, fx_popup.sub, fx_popup.time = label, value, sub, util.time() end
function hlp.flip(id, label, on_v, off_v, sub) local on = params:get(id) ~= on_v params:set(id, on and on_v or off_v) hlp.popup(label .. (on and " ON" or " OFF"), nil, on and sub and sub() or nil) end
function hlp.sample_popup(i)
    local nm = params:string(i .. "sample")
    if #nm > 19 then nm = nm:sub(1, 18) .. "." end
    local now, txt, sp = util.time(), i .. ": " .. nm, hlp.spop
    hlp.spop = {v = i, t = now, txt = txt}
    if sp and sp.v ~= i and now - sp.t < 0.3 then if i == 2 then hlp.popup(sp.txt, nil, txt) else hlp.popup(txt, nil, sp.txt) end else hlp.popup(txt) end
end
local FX_POPUP_DURATION = 1
local longpress_metro = nil
local grain_positions = {[1] = {}, [2] = {}}
local rec_positions = {[1] = 0, [2] = 0}
ctx.seek_pushed = {-1, -1}
ctx.grain_seq = {-1, -1}
ctx.live_wf = {raw = {[1] = {}, [2] = {}}, norm = {[1] = {}, [2] = {}}, col = {-1, -1}, max = {0, 0}}
function ctx.live_wf.reset(i) local raw, nm = ctx.live_wf.raw[i], ctx.live_wf.norm[i] for c = 0, 29 do raw[c] = 0 nm[c] = 0 end ctx.live_wf.col[i] = -1 ctx.live_wf.max[i] = 0 end
ctx.live_wf.reset(1) ctx.live_wf.reset(2)
local cached_buffer_durations = {[1] = 1, [2] = 1}
local voice_peak_amplitudes = {[1] = {l = 0, r = 0}, [2] = {l = 0, r = 0}}
local link_base = {{}, {}}
local ui_metro = nil
local floor, abs, log, max, min, sqrt, sin = math.floor, math.abs, math.log, math.max, math.min, math.sqrt, math.sin
local clamp = util.clamp
local _pobj = utils.param_obj
local function pget(id) local o = _pobj(id) if o then return o:get() end return nil end
local function pset(id, v, silent) local o = _pobj(id) if o then o:set(v, silent) end end
local function rev_route()
    local db, sys = params:get("reverb_mix"), params:get("rev_type") == 2
    local on = db > -40
    local w = (on and not sys) and 10 ^ (db / 20) or 0
    if hlp.rev_w ~= w then hlp.rev_w = w engine.rev_mix(w) end
    if not (sys and on) then params:set("reverb", 1) return end
    params:set("reverb", 2)
    params:set("rev_eng_input", db)
end
hlp.REV_PLATE = {"rev_decay", "rev_damp", "rev_pre", "rev_mdepth", "rev_mrate", "rev_series", "delay_series"}
function hlp.rev_vis()
    local pl = params:get("rev_type") == 1
    for _, id in ipairs(hlp.REV_PLATE) do if pl then params:show(id) else params:hide(id) end end
    for _, id in ipairs(hlp.rev_sys or {}) do if pl then params:hide(id) else params:show(id) end end
    if _menu and type(_menu.rebuild_params) == "function" then _menu.rebuild_params() end
end
local TRACK_KEYS = {}
for t = 1, 2 do
    TRACK_KEYS[t] = {
        volume = t.."volume", pan = t.."pan", speed = t.."speed",
        cutoff = t.."cutoff", hpf = t.."hpf", lpf_gain = t.."lpf_gain",
        eq_low = t.."eq_low_gain", eq_mid = t.."eq_mid_gain", eq_high = t.."eq_high_gain", eq_tilt = t.."eq_tilt",
        granular_gain = t.."granular_gain", live_input = t.."live_input",
        live_direct = t.."live_direct",
        direction_mod = t.."direction_mod", env_select = t.."env_select",
        pitch_random_prob = t.."pitch_random_prob",
        subharmonics_1 = t.."subharmonics_1", subharmonics_2 = t.."subharmonics_2", subharmonics_3 = t.."subharmonics_3",
        overtones_1 = t.."overtones_1", overtones_2 = t.."overtones_2", smoothbass = t.."smoothbass"}
end
local _HK = {
    size = {"1size", "2size"}, den = {"1density", "2density"}, pitch = {"1pitch", "2pitch"},
    vol = {"1volume", "2volume"}, seek = {"1seek", "2seek"},
    rand_names = {"speed", "jitter", "size", "density", "spread", "pitch", "seek"},
    TAP_TIMEOUT = 2, LONGPRESS = 1, UI_FPS = 60, MAX_FRAMES = 16777216, AUDIO_LIST = "/tmp/twins_audio_files.txt"}
local _grain_pool = {}
local function do_capture_temp_scene() morph.capture_to_temp_scene(lfo.get_active_param_map()) end
local function combo_longpress_fire()
    if current_mode == "lpf" then
        current_filter_mode = current_filter_mode == "lpf" and "hpf" or "lpf"
        hlp.popup(current_filter_mode:upper())
    else
        undo.checkpoint()
        lfo.assign_to_current_row(current_mode)
        hlp.popup("RANDOM LFO")
    end
end
local param_modes = {
    speed = {param = "speed", delta = 1},
    seek = {param = "seek", delta = 1},
    pan = {param = "pan", delta = 5},
    lpf = {param = "cutoff", delta = 1},
    hpf = {param = "hpf", delta = 1},
    jitter = {param = "jitter", delta = 2, y = 12, label = "jitter:"},
    size = {param = "size", delta = 2, y = 22, label = "size:"},
    density = {param = "density", delta = 2, y = 32, label = "density:", hz = true},
    pitch = {param = "pitch", delta = 1, y = 42, label = "pitch:", st = true},
    spread = {param = "spread", delta = 2, y = 52, label = "spread:"},
    eq = {param = "eq_tilt", delta = 2}}
local param_rows = {} for mode, config in pairs(param_modes) do config.pkeys = {"1" .. config.param, "2" .. config.param} if config.y then local lbl = config.label local nm = lbl:match("%a+") param_rows[#param_rows + 1] = {y = config.y, label = lbl, label_upper = lbl:upper(), name = nm, mode = mode, params = config.pkeys, st = config.st, fmt_key = config.hz and "hz" or config.st and "st" or nm} end end table.sort(param_rows, function(a, b) return a.y < b.y end)
local LIMITS = {size={min=20,max=4999},density={min=0.1,max=50},pitch={min=-48,max=48}}
local SU = lfo.scale_utils
local audio_files_cache = nil
local anim_offset_x = 128 local animation_complete = false local animation_start_time = nil
local pan_indicator_x = {[1] = -80, [2] = 80} local pan_indicators_visible = false local pan_slide_start_time = nil
local volume_bar_y = {[1] = 120, [2] = 120} local volume_bars_visible = false
local seek_bar_width = 0 local seek_bars_visible = false
local randomize_flash = {[1] = 0, [2] = 0, held = {false, false}, midi = {0, 0}}
local function flash_level(track, base_level) local f = randomize_flash[track] local m = randomize_flash.held[track] and 1 or randomize_flash.midi[track] if m > f then f = m end if f <= 0.001 then return base_level end return min(base_level + f * 12 // 1, 15) end
local random_float = utils.random_float
local stop_metro_safe = utils.stop_metro_safe
local function is_voice_loaded(i) return audio_active[i] or live_state[i].input or live_state[i].direct end
local function pause_voice_if_idle(i) if not is_voice_loaded(i) then engine.pause_voice(i) osc_positions[i] = 0 end end

local function transport_enabled()
    return not params.lookup["midi_transport"] or params:get("midi_transport") == 2
end
local function transport_start()
    if not transport_enabled() then return end
    if clocksync.lfo_synced() then lfo.reset_phases() end
    for v = 1, 2 do if is_voice_loaded(v) then engine.run_voice(v, 1) end end
end
local function transport_stop()
    if not transport_enabled() then return end
    for v = 1, 2 do engine.run_voice(v, 0) end
end
local function transport_continue()
    if not transport_enabled() then return end
    for v = 1, 2 do if is_voice_loaded(v) then engine.voice_run(v, 1) end end
end

local is_param_locked = utils.is_param_locked
local function is_lfo_active_for_param(param_name) local idx = lfo.get_lfo_for_param(param_name) return idx ~= nil, idx end
hlp.link_suppress_size = false
hlp.link_last_hz = {}
hlp.pre_direct = {}
local function set_clamped_offset(idx, center)
    local depth = pget(MK.depth[idx])
    local offset = clamp(center, depth * 0.01 - 1, 1 - depth * 0.01)
    pset(MK.offset[idx], offset)
    lfo[idx].offset = offset
end
function hlp.apply_lfo_or_set(full_param, val)
    local active, idx = is_lfo_active_for_param(full_param)
    if not active then params:set(full_param, val) return end
    local lo, hi = lfo.get_parameter_range(full_param)
    if lo and hi and hi > lo then
        set_clamped_offset(idx, (val - lo) / (hi - lo) * 2 - 1)
    end
end
function hlp.apply_linked_density(track, target_den)
    local idx = clocksync.div_index_for_density(target_den)
    if not idx then return end
    local active, li = is_lfo_active_for_param(_HK.den[track])
    if active then
        set_clamped_offset(li, clocksync.div_index_to_norm(idx) * 2 - 1)
    else
        hlp.link_suppress_size = true
        clocksync.set_grain_div_index(track, idx)
        hlp.link_suppress_size = false
    end
end
function hlp.set_link_base(i, density)
    local size = params:get(i.."size")
    if size > 0 and density > 0 then
        local lb = link_base[i]
        lb.pitch, lb.size, lb.density, lb.product = params:get(i.."pitch"), size, density, size * density
    end
end
function hlp.ensure_link_base(track)
    local lb = link_base[track]
    if not (lb.pitch and lb.size and lb.density and lb.product) then
        lb.pitch   = params:get(_HK.pitch[track])
        lb.size    = params:get(_HK.size[track])
        lb.density = clocksync.grain_density(track) or params:get(_HK.den[track])
        lb.product = lb.size * lb.density
    end
    return lb
end
_HK.reso_voicings = {
    {0, 7, 12, 19, 24}, {0, 7, 14, 21, 28}, {0, 4, 7, 12, 16}, {0, 3, 7, 12, 15},
    {0, 4, 7, 11, 14}, {0, 3, 7, 10, 14}, {0, 12, 19.0196, 24, 27.8631}, {0, 12, 24, 36, 48}}
_HK.reso_names = {"5th+oct", "fifths", "major", "minor", "maj7", "min7", "harmonic", "octaves"}
local RESO_RATIOS = {}
function hlp.set_reso_voicing(idx)
    local degs = _HK.reso_voicings[idx] or _HK.reso_voicings[1]
    for i = 1, 5 do RESO_RATIOS[i] = 2 ^ (degs[i] / 12) end
end
hlp.set_reso_voicing(1)
function hlp.update_resonator()
    if (pget("resonator_mix") or 0) <= 0 then return end
    local f = 440 * 2 ^ ((params:get("resonator_root") - 69) / 12)
    engine.resonator_freqs(
        f * RESO_RATIOS[1], f * RESO_RATIOS[2],
        f * RESO_RATIOS[3], f * RESO_RATIOS[4],
        f * RESO_RATIOS[5])
end
local function update_pan_positioning()
    if _G.preset_loading then return end
    local p1, p2 = utils.default_pans(is_voice_loaded(1) and is_voice_loaded(2))
    for i = 1, 2 do
        if is_voice_loaded(i) and not is_param_locked(i, "pan") and not lfo.get_lfo_for_param(i.."pan") then params:set(i.."pan", i == 1 and p1 or p2) end
    end
end

local function set_midi_pitch(voice, pitch_value)
    pitch_value = clamp(pitch_value, LIMITS.pitch.min, LIMITS.pitch.max)
    pitch_value = SU.quantize(pitch_value, params:string("pitch_quantize_scale"))
    if params:get("global_pitch_size_density_link") ~= 1 then hlp.apply_lfo_or_set(voice .. "pitch", pitch_value) return end
    local lb = hlp.ensure_link_base(voice)
    local octaves = (pitch_value - lb.pitch) / 12
    hlp.apply_lfo_or_set(voice .. "size",    clamp(lb.size    * (2 ^ -octaves), LIMITS.size.min,    LIMITS.size.max))
    hlp.apply_lfo_or_set(voice .. "density", clamp(lb.density * (2 ^  octaves), LIMITS.density.min, LIMITS.density.max))
    hlp.apply_lfo_or_set(voice .. "pitch",   pitch_value)
end

local function setup_ui_metro()
    if ui_metro then stop_metro_safe(ui_metro) end
    local ui_skip = 0
    local idle_skip = 0
    ui_metro = metro.init(function()
        if _G.preset_loading or presets.is_menu_open() then
            ui_skip = ui_skip + 1
            if ui_skip < 6 then return end
            ui_skip = 0
            redraw()
            return
        end
        ui_skip = 0
        local now = util.time()
        local busy = not animation_complete or pan_slide_start_time ~= nil
            or key_state[1] or key_state[2] or key_state[3]
            or (now - (hlp.last_input or 0)) < 2
            or is_voice_loaded(1) or is_voice_loaded(2)
            or (hlp.saving and now < hlp.saving)
            or (fx_popup.time ~= nil and (now - fx_popup.time) < FX_POPUP_DURATION)
            or randomize_flash[1] > 0.001 or randomize_flash[2] > 0.001
            or randomize_flash.midi[1] > 0.001 or randomize_flash.midi[2] > 0.001
        if not busy then
            idle_skip = idle_skip + 1
            if idle_skip < 4 then return end
        end
        idle_skip = 0
        if not animation_complete then
            animation_start_time = animation_start_time or now
            local elapsed = now - animation_start_time
            local progress = min(elapsed * 2.5, 1)
            local eased = 1 - (1 - progress) ^ 3
            if progress < 1 then
                anim_offset_x = (1 - eased) * 128
            else
                anim_offset_x = 0
            end
            animation_complete = progress >= 1
            if progress >= 0.4 and not pan_slide_start_time then pan_slide_start_time = now end
        end
        if pan_slide_start_time and not (pan_indicators_visible and volume_bars_visible and seek_bars_visible) then
            local slide_progress = min((now - pan_slide_start_time) * 2.5, 1)
            local eased = 1 - (1 - slide_progress) ^ 2
            local done = slide_progress >= 1
            if not pan_indicators_visible then
                pan_indicator_x[1] = done and 0 or (-80 + eased * 80)
                pan_indicator_x[2] = done and 0 or (80 - eased * 80)
                if done then pan_indicators_visible = true end
            end
            if not volume_bars_visible then
                local y_val = done and 0 or (120 - eased * 120)
                volume_bar_y[1] = y_val
                volume_bar_y[2] = y_val
                if done then volume_bars_visible = true end
            end
            if not seek_bars_visible then
                seek_bar_width = done and 1 or eased
                if done then seek_bars_visible = true end
            end
            if pan_indicators_visible and volume_bars_visible and seek_bars_visible then pan_slide_start_time = nil end
        end
        for i = 1, 2 do
            if randomize_flash[i] > 0.001 and not randomize_flash.held[i] then randomize_flash[i] = randomize_flash[i] * 0.9 end
            if randomize_flash.midi[i] > 0.001 and not randomize_flash.held[i] then randomize_flash.midi[i] = randomize_flash.midi[i] * 0.9 end
        end
        redraw()
    end)
    ui_metro.time = 1 / _HK.UI_FPS
    utils.metro_start(ui_metro)
end

local function init_longpress_checker()
    if longpress_metro then stop_metro_safe(longpress_metro) end
    longpress_metro = metro.init()
    longpress_metro.time = 0.2
    longpress_metro.event = function()
        local g = key_gesture
        if not g or g.fired then return end
        local combo = hlp.key_combos[g.id]
        if combo and combo.long and (util.time() - g.press_time) >= _HK.LONGPRESS then
            g.fired = true
            combo.long()
        end
    end
    utils.metro_start(longpress_metro)
end

local function disable_lfos_for_param(param_name, only_self)
    for track = 1, 2 do
        local full_param = only_self and param_name or track .. param_name:sub(2)
        local idx = lfo.get_lfo_for_param(full_param)
        if idx then params:set(MK.lfo[idx], 1) end
        if only_self then return end
    end
end

local function get_audio_duration(filepath)
    if not filepath or not util.file_exists(filepath) then return nil end
    local _, samples, rate = audio.file_info(filepath)
    if samples and rate and rate > 0 then return min(samples, _HK.MAX_FRAMES) / rate end
    return nil
end

local blim = {}
blim.pending = {}
function blim.apply(i, dur)
  if not dur or dur <= 0 then return false end
  cached_buffer_durations[i] = dur
  local ms = dur * 1000
  local mj = min(ms, 99999)
  params:set(i.."max_jitter", mj)
  params:set(i.."min_jitter", min(params:get(i.."min_jitter") or 0, mj))
  local mz = min(ms, 999)
  params:set(i.."max_size", mz)
  if (params:get(i.."min_size") or 20) > mz then
    params:set(i.."min_size", mz)
  end
  return true
end
function blim.on_duration(i, dur)
    local p = blim.pending[i]; if not p then return end
    blim.pending[i] = nil
    if not blim.apply(i, dur) then return end
    if p.rj then local jp = i.."jitter"; disable_lfos_for_param(jp); local up = math.random() < 0.75 and min(500, dur * 1000) or dur * 1000; params:set(jp, clamp(math.random() * up, 0, 99999)) end
end

local function set_track_sample(track_num, file)
    if params:get(track_num .. "live_input") == 1 then return false end
    if params:get(track_num .. "sample") ~= file then params:set(track_num .. "sample", file) end
    return true
end

local function set_sample_live(i) params:set(i.."sample", _path.tape.."live!") end

local function apply_random_tape(track_num)
    if #audio_files_cache == 0 then return false end
    if track_num then
        local file = audio_files_cache[math.random(#audio_files_cache)]
        return set_track_sample(track_num, file)
    end
    local file1 = audio_files_cache[math.random(#audio_files_cache)]
    local file2 = (math.random() < 0.5) and file1 or audio_files_cache[math.random(#audio_files_cache)]
    set_track_sample(1, file1)
    set_track_sample(2, file2)
    return true
end

function hlp.scan_audio()
    if hlp.scan_busy then hlp.scan_again = true return end
    hlp.scan_busy, hlp.scan_again = true, nil
    norns.system_cmd("nice -n 10 find '" .. _path.audio .. "' -type f -not -path '*/.*' \\( -iname '*.wav' -o -iname '*.aif' -o -iname '*.aiff' -o -iname '*.flac' \\) > " .. _HK.AUDIO_LIST .. " 2>/dev/null; echo _done_", function()
        hlp.scan_busy = nil
        if hlp.dead then return end
        if hlp.scan_again then return hlp.scan_audio() end
        local files, f = {}, io.open(_HK.AUDIO_LIST, "r")
        if f then for line in f:lines() do files[#files + 1] = line end f:close() end
        audio_files_cache = files
        local p = hlp.scan_pending
        hlp.scan_pending = nil
        if p then apply_random_tape(p ~= 0 and p or nil) end
    end)
end

function hlp.audio_dirty() audio_files_cache = nil if hlp.scan_busy then hlp.scan_again = true end end

local function load_random_tape_file(track_num)
    if audio_files_cache then return apply_random_tape(track_num) end
    hlp.scan_pending = track_num or 0
    hlp.scan_audio()
    return false
end

local BOUNCE_DIR = _path.tape .. "twins/"

function hlp.start_bounce()
    local b = hlp.bounce_pending
    if b and (util.time() - b.t) < (b.len + 5) then return end
    local inplace = params:get("bounce_mode") == 2
    local mode = inplace and 2 or params:get("bounce_source") - 1
    if inplace and params:get("bounce_source") == 2 then hlp.popup("IN PLACE = DRY") end
    local len = params:get("bounce_length")
    local pre = params:get("bounce_volume") == 1 and mode ~= 1
    local xf = params:get("bounce_xfade")
    local name = "bounce_" .. os.date("%Y%m%d_%H%M%S")
    local paths
    if inplace then paths = {BOUNCE_DIR .. name .. "_1.wav", BOUNCE_DIR .. name .. "_2.wav"}
    else paths = {BOUNCE_DIR .. name .. ".wav"} end
    util.make_dir(BOUNCE_DIR)
    hlp.bounce_pending = {paths = paths, t = util.time(), len = len + xf, mode = mode}
    engine.bounce(mode, len, name, pre and 1 or 0, xf)
end

function hlp.finish_bounce()
    local b = hlp.bounce_pending
    hlp.bounce_pending = nil
    if not b then return end
    hlp.audio_dirty()
    if b.paths[2] then
        for i = 1, 2 do params:set(i .. "sample", b.paths[i]) end
    else
        params:set("unload_all", 1)
        params:set("1sample", b.paths[1])
    end
    local r = params:get("bounce_reset")
    if r > 1 then drymode.reset_dry(r ~= 3, r ~= 2, r == 4 or b.mode == 1) end
    hlp.bounce_done_time = util.time()
end

local function is_used_sample(s)
    return s and s ~= "" and s ~= "-" and s ~= "none" and s ~= (_path.tape .. "live!") and util.file_exists(s)
end
local function delete_unused_bounces()
    local used = {}
    local function mark(s) if is_used_sample(s) then used[s] = true end end
    for i = 1, 2 do mark(params:get(i .. "sample")) end
    for _, name in ipairs(presets.list_presets()) do
        local chunk = loadfile(_path.data .. "twins/" .. name .. ".lua")
        local ok, data = pcall(chunk or error)
        if ok and type(data) == "table" and data.params then for i = 1, 2 do mark(data.params[i .. "sample"]) end end
    end
    local deleted = 0
    if util.file_exists(BOUNCE_DIR) then
        for _, f in ipairs(util.scandir(BOUNCE_DIR)) do
            local full_path = BOUNCE_DIR .. f
            if f:match("^bounce_.*%.wav$") and not used[full_path] then
                os.remove(full_path)
                deleted = deleted + 1
            end
        end
    end
    hlp.audio_dirty()
    hlp.popup("Deleted " .. deleted .. " files")
end

local register_tap
do
    local taps = {}
    register_tap = function()
        local now = util.time()
        local n = #taps
        if n > 0 and now - taps[n] > _HK.TAP_TIMEOUT then taps, n = {}, 0 end
        if n == 3 then table.remove(taps, 1) n = 2 end
        taps[n + 1] = now
        if n > 0 then params:set("delay_time", clamp((now - taps[1]) / n, 0.02, 5)) end
    end
end

local function setup_params()
    for _, p in ipairs(params.params) do if p.id then ctx.sys[p.id] = true end end
    for _, id in ipairs({"arp_steps", "arp_mode", "arp_twin", "arp_octaves", "midi_device", "midi_channel", "delay_series"}) do ctx.sys[id] = true end
    presets.exclude(ctx.sys)
    local LIVE = _path.tape .. "live!"
    params:add_separator("Input")
    for i = 1, 2 do
      local sid = i.."sample"
      params:add_file(sid, "S"..i, _path.audio)
      params:lookup_param(sid).string = function()
        local v = params:get(sid)
        if type(v) ~= "string" or v == "" or v == "-" or v:sub(-1) == "/" then return "-" end
        local b = v:match("([^/]+)%.%w%w?%w?%w?$") or v:match("[^/]+$")
        return #b > 24 and b:sub(1, 22) .. ".." or b
      end
      params:set_action(sid, function(f)
        if f == LIVE then return end
        local valid = f ~= nil and f ~= "" and f ~= "none" and f ~= "-" and not f:match("/$")
        if valid then
          if params:get(i.."live_input") == 1 then engine.set_live_input(i, 0) params:set(i.."live_input", 0, true) live_state[i].input = false end
          if params:get(i.."live_direct") == 1 then engine.live_direct(i, 0) params:set(i.."live_direct", 0, true) live_state[i].direct = false end
        end
        local jitter_locked = is_param_locked(i, "jitter")
        if not jitter_locked then lfo.clearLFOs(i, "jitter") end
        if not valid then audio_active[i] = false osc_positions[i] = 0 update_pan_positioning() return end
        engine.read(i, f)
        ctx.waveforms[i] = nil
        if not _G.preset_loading then params:set(i.."seek", 0) hlp.sample_popup(i) end
        audio_active[i] = true
        update_pan_positioning()
        if _G.preset_loading then blim.apply(i, get_audio_duration(f)) else blim.pending[i] = {rj = not jitter_locked} end
      end)
    end
    params:add_binary("randomtapes", "Random Tapes", "trigger", 0) params:set_action("randomtapes", function() load_random_tape_file() end)
    params:add_group("LIVE!", 10)
    for i = 1, 2 do
      params:add_binary(i.."live_input", "Live Buffer "..i.." ● ►", "toggle", 0) params:set_action(i.."live_input", function(value) live_state[i].input = (value == 1) if value == 1 then if params:get(i.."live_direct") == 1 then params:set(i.."live_direct", 0) end engine.set_live_input(i, 1) engine.live_mono(i, params:get("isMono") - 1) audio_active[i] = true ctx.waveforms[i] = ctx.live_wf.norm[i] ctx.live_wf.col[i] = -1 if not _G.preset_loading then blim.apply(i, params:get("live_buffer_length")) else cached_buffer_durations[i]=params:get("live_buffer_length") end set_sample_live(i) update_pan_positioning() else engine.set_live_input(i, 0) if not audio_active[i] and params:get(i.."live_direct") == 0 then osc_positions[i] = 0 params:set(i.."sample", "-") pause_voice_if_idle(i) else set_sample_live(i) update_pan_positioning() end end end)
    end
    params:add_control("live_buffer_mix", "Overdub", controlspec.new(0, 100, "lin", 1, 100, "%")) params:set_action("live_buffer_mix", function(value) engine.live_buffer_mix(value * 0.01) end)
    params:add_taper("live_buffer_length", "Buffer Length", 0.05, 10, 1, 3, "s") params:set_action("live_buffer_length", function(value) engine.live_buffer_length(value) ctx.live_wf.reset(1) ctx.live_wf.reset(2) for i=1,2 do if params:get(i.."live_input")==1 then if not _G.preset_loading then blim.apply(i, value) else cached_buffer_durations[i]=value end end end end)
    for i = 1, 2 do
      params:add{type = "trigger", id = "save_live_buffer"..i, name = "Buffer"..i.." to Tape", action = function() engine.save_live_buffer(i, "live"..i.."_"..os.date("%Y%m%d_%H%M%S")..".wav") hlp.saving = util.time() + params:get("live_buffer_length") + 3 end}
    end
    for i = 1, 2 do
      params:add_binary(i.."live_direct", "Direct "..i.." ►", "toggle", 0) params:set_action(i.."live_direct", function(value) live_state[i].direct = (value == 1) if value == 1 then hlp.pre_direct[i] = {a = audio_active[i], s = params:get(i.."sample")} local was_live = params:get(i.."live_input") if was_live == 1 then params:set(i.."live_input", 0) end engine.live_direct(i, 1) set_sample_live(i) update_pan_positioning() else engine.live_direct(i, 0) local pd = hlp.pre_direct[i] hlp.pre_direct[i] = nil audio_active[i] = (pd and pd.a) or false if not audio_active[i] and params:get(i.."live_input") == 0 then osc_positions[i] = 0 params:set(i.."sample", "-") pause_voice_if_idle(i) else if pd and pd.s then params:set(i.."sample", pd.s, true) else set_sample_live(i) end update_pan_positioning() end end end)
    end
    params:add_option("isMono", "Input Mode", {"stereo", "mono"}, 1) params:set_action("isMono", function(value) local monoValue = value - 1 for i = 1, 2 do engine.isMono(i, monoValue) if params:get(i.."live_input") == 1 then engine.live_mono(i, monoValue) end end end)
    params:add_binary("dry_mode2", "Dry Mode", "toggle", 0) params:set_action("dry_mode2", function(x) drymode.set_dry_mode2(x == 1) end)
    params:add{type = "trigger", id = "save_preset", name = "Save Preset", action = function() presets.save_complete_preset(nil, morph.scene_data, current_mode, current_filter_mode) end}
    params:add{type = "trigger", id = "load_preset_menu", name = "Preset Browser", action = function() if presets.open_menu() and _menu and _menu.mode then clock.run(function() clock.sleep(0.02) _menu.set_mode(false) end) end end}
    params:add_separator("Settings")
    params:add_group("GRANULAR", 39)
    for i = 1, 2 do
      params:add_separator("SAMPLE "..i)
      params:add_control(i.. "granular_gain", i.. " Mix", controlspec.new(0, 100, "lin", 1, 100, "%")) params:set_action(i.. "granular_gain", function(value) engine.granular_gain(i, value * 0.01) if value < 100 then lfo.clearLFOs(i, "seek") end end)
      local HARMONIC_PARAMS = {{"subharmonics_3","Subharmonics -3oct"},{"subharmonics_2","Subharmonics -2oct"}, {"subharmonics_1","Subharmonics -1oct"},{"overtones_1","Overtones +1oct"},{"overtones_2","Overtones +2oct"}} for _, hp in ipairs(HARMONIC_PARAMS) do local id, lbl = hp[1], hp[2] params:add_control(i..id, i.." "..lbl, controlspec.new(0, 1, "lin", 0.01, 0)) params:set_action(i..id, function(v) engine[id](i, v) end) end
      params:add_option(i.. "smoothbass", i.." Smooth Sub", {"off", "on"}, 1) params:set_action(i.. "smoothbass", function(x) local engine_value = (x == 2) and 2.5 or 1 engine.smoothbass(i, engine_value) end)
      params:add_control(i.."pitch_random_prob", i.." Pitch Variation", controlspec.new(-100, 100, "lin", 1, 0, "%")) params:set_action(i.."pitch_random_prob", function(value) engine.pitch_random_prob(i, value) end)
      params:add_option(i.."pitch_random_scale_type", i.." Pitch Quantize", {"5th+oct", "5th+oct 2", "1 oct", "2 oct", "chrom", "maj", "min", "penta", "whole"}, 1) params:set_action(i.."pitch_random_scale_type", function(value) engine.pitch_random_scale_type(i, value - 1) end)
      params:add_control(i.. "size_variation", i.. " Size Variation", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.. "size_variation", function(value) engine.size_variation(i, value * 0.01) end)
      params:add_control(i.. "amp_randomize", i.. " Amp Variation", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.. "amp_randomize", function(value) engine.amp_randomize(i, value * 0.01) end)
      params:add_control(i.. "direction_mod", i.. " Reverse", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.. "direction_mod", function(value) engine.direction_mod(i, value * 0.01) end)
      params:add_control(i.. "density_mod_amt", i.. " Density Mod", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.. "density_mod_amt", function(value) engine.density_mod_amt(i, value * 0.01) end)
      params:add_control(i.."ratcheting_prob", i.." Ratcheting", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.."ratcheting_prob", function(value) engine.ratcheting_prob(i, value) end)
      params:add_option(i.."env_select", i.." Grain Envelope", {"Sine", "Tukey", "Perc.", "ADSR", "Random"}, 1) params:set_action(i.."env_select", function(value) engine.env_select(i, value - 1) end)
      params:add_control(i.."probability", i.." Trigger Probability", controlspec.new(0, 100, "lin", 1, 100, "%")) params:set_action(i.."probability", function(value) engine.probability(i, value * 0.01) end)
      params:add_option(i.. "pitch_mode", i.. " Pitch Mode", {"match speed", "independent"}, 2) params:set_action(i.. "pitch_mode", function(value) engine.pitch_mode(i, value - 1) end)
    end
    params:add_separator(" ")
    params:add_binary("randomize_granular", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_granular", function() undo.checkpoint() for i=1, 2 do randpara.randomize_granular_params(i, steps) end end)
    params:add_option("lock_granular", "Lock Parameters", {"off", "on"}, 1)
    params:add_group("DELAY", 15)
    params:add_control("delay_mix", "Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("delay_mix", function(x) engine.mix(x * 0.01) font.update_fx_cache("delay_mix", x) end)
    params:add_taper("delay_time", "Time", 0.02, 5, 0.5, 0.1, "s") params:set_action("delay_time", function(value) engine.delay(value) end)
    params:add_binary("tap", "↳ TAP!", "trigger", 0) params:set_action("tap", register_tap)
    local D_RATIO = {0.25, 1 / 3, 0.5, 2 / 3, 0.75, 1, 4 / 3, 1.5, 2, 3, 4}
    params:add_option("delay_ratio", "L/R Ratio", {"4:1", "3:1", "2:1", "3:2", "4:3", "1:1", "3:4", "2:3", "1:2", "1:3", "1:4"}, 6) params:set_action("delay_ratio", function(x) engine.d_ratio(D_RATIO[x]) end)
    params:add_taper("delay_feedback", "Feedback", 0, 120, 40, 1, "%") params:set_action("delay_feedback", function(value) engine.fb_amt(value * 0.01) end)
    params:add_control("delay_lowpass", "LPF", controlspec.new(20, 20000, 'exp', 1, 7500, "Hz")) params:set_action('delay_lowpass', function(value) engine.lpf(value) end)
    params:add_control("delay_highpass", "HPF", controlspec.new(20, 20000, 'exp', 1, 200, "Hz")) params:set_action('delay_highpass', function(value) engine.dhpf(value) end)
    params:add_taper("wiggle_depth", "Mod Depth", 0, 100, 25, 0, "%") params:set_action("wiggle_depth", function(value) engine.w_depth(value * 0.01) end)
    params:add_taper("wiggle_rate", "Mod Freq", 0, 20, 2, 1, "Hz") params:set_action("wiggle_rate", function(value) engine.w_rate(value) end)
    params:add_control("stereo", "Ping-Pong", controlspec.new(0, 100, "lin", 1, 20, "%")) params:set_action("stereo", function(x) engine.stereo(x * 0.01) end)
    params:add_taper("delay_duck", "Ducking", 0, 100, 17, 0, "%") params:set_action("delay_duck", function(value) engine.delay_duck(value * 0.01) end)
    params:add_control("delay_series", "Delay > Reverb", controlspec.new(0, 100, "lin", 1, 25, "%")) params:set_action("delay_series", function(v) params:set("rev_series", v) end) params:lookup_param("delay_series").save = false
    params:add_separator("   ")
    params:add_binary("randomize_delay_params", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_delay_params", function() undo.checkpoint() randpara.randomize_delay_params(steps) end)
    params:add_option("lock_delay", "Lock Parameters", {"off", "on"}, 1)
    local rev_sync = false
    local rev_proxies = {
        {"rv_predelay", "rev_pre_delay",    "Pre-delay"},
        {"rv_lffc",     "rev_lf_fc",        "LPF"},
        {"rv_lowtime",  "rev_low_time",     "Low Time"},
        {"rv_midtime",  "rev_mid_time",     "Mid Time"},
        {"rv_hfdamp",   "rev_hf_damping",   "Damping"}}
    local rev_present = {}
    for _, p in ipairs(rev_proxies) do if params.lookup[p[2]] then rev_present[#rev_present + 1] = p end end
    params:add_group("R3VERB", 10 + #rev_present)
    params:add_option("rev_type", "Type", {"plate", "system"}, 1) params:set_action("rev_type", function() rev_route() hlp.rev_vis() end)
    params:add_taper("reverb_mix", "Mix", -40, 18, -40, 0, "dB") params:set_action("reverb_mix", function(value) rev_route() font.update_fx_cache("reverb_mix", value) end)
    params:add_control("rev_decay", "Decay", controlspec.new(0.3, 60, "exp", 0, 4, "s")) params:set_action("rev_decay", function(v) engine.rev_decay(10 ^ (-0.468 / v)) end)
    params:add_control("rev_damp", "Damping", controlspec.new(0, 100, "lin", 1, 40, "%")) params:set_action("rev_damp", function(v) engine.rev_damp(math.exp(-2.356194 * (1 / 30) ^ (v * 0.01))) end)
    params:add_control("rev_pre", "Pre Delay", controlspec.new(0, 250, "lin", 1, 20, "ms")) params:set_action("rev_pre", function(v) engine.rev_pre(v * 0.001) end)
    params:add_control("rev_mdepth", "Mod Depth", controlspec.new(0, 100, "lin", 1, 30, "%")) params:set_action("rev_mdepth", function(v) engine.rev_mdepth(v * 0.01) end)
    params:add_control("rev_mrate", "Mod Rate", controlspec.new(0.05, 5, "exp", 0, 0.5, "Hz")) params:set_action("rev_mrate", function(v) engine.rev_mrate(v) end)
    hlp.rev_sys = {}
    for _, p in ipairs(rev_present) do
        local proxy_id, sys_id, name = p[1], p[2], p[3]
        local sp = params.params[params.lookup[sys_id]]
        params:add{type = "control", id = proxy_id, name = name, controlspec = sp.controlspec}
        params:set(proxy_id, params:get(sys_id), true)
        params:set_action(proxy_id, function(v)
            if rev_sync then return end
            rev_sync = true; params:set(sys_id, v); rev_sync = false
        end)
        local orig = sp.action
        sp.action = function(v)
            if orig then orig(v) end
            if not rev_sync then rev_sync = true; params:set(proxy_id, v, true); rev_sync = false end
        end
        hlp.rev_sys[#hlp.rev_sys + 1] = proxy_id
    end
    params:add_control("rev_series", "Delay > Reverb", controlspec.new(0, 100, "lin", 1, 25, "%")) params:set_action("rev_series", function(v) engine.rev_series(v * 0.01) params:set("delay_series", v, true) end)
    for _, id in ipairs({"rev_series", "delay_series"}) do
        params:lookup_param(id).string = function(p) local v = p:get() return v <= 0 and "parallel" or v >= 100 and "series" or string.format("%d%%", floor(v + 0.5)) end
    end
    params:add_separator("           ")
    params:add_option("lock_reverb", "Lock Parameters", {"off", "on"}, 2)
    params:add_group("SHIMMER", 10)
    params:add_control("shimmer_mix1", "Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("shimmer_mix1", function(x) engine.shimmer_mix1(x * 0.01) font.update_fx_cache("shimmer_mix1", x) end)
    params:add_option("shimmer_mod1", "Mix Mod", {"off", "on"}, 1) params:set_action("shimmer_mod1", function(x) engine.shimmer_mod1(x - 1) font.update_fx_cache("shimmer_mod1", x) end)
    params:add_option("shimmer_oct1", "Pitch Shift", {"-2 oct", "-1 oct", "0", "+1 oct", "+2 oct"}, 4) params:set_action("shimmer_oct1", function(x) engine.shimmer_oct1(2 ^ (x - 3)) end)
    params:add_control("pitchv1", "Variance", controlspec.new(0, 100, "lin", 1, 2, "%")) params:set_action("pitchv1", function(x) engine.pitchv1(x * 0.01) end)
    params:add_control("lowpass1", "LPF", controlspec.new(20, 20000, "lin", 1, 13000, "Hz")) params:set_action("lowpass1", function(x) engine.lowpass1(x) end)
    params:add_control("hipass1", "HPF", controlspec.new(20, 20000, "exp", 1, 1400, "Hz")) params:set_action("hipass1", function(x) engine.hipass1(x) end)
    params:add_control("fbDelay1", "Delay", controlspec.new(0.01, 0.5, "lin", 0.01, 0.2, "s")) params:set_action("fbDelay1", function(x) engine.fbDelay1(x) end)
    params:add_control("fb1", "Feedback", controlspec.new(0, 100, "lin", 1, 20, "%")) params:set_action("fb1", function(x) engine.fb1(x * 0.01) end)
    params:add_separator("        ")
    params:add_option("lock_shimmer", "Lock Parameters", {"off", "on"}, 1)
    params:add_group("DRIVE", 5)
    params:add_control("analogdrive_mix", "Mix", controlspec.new(0, 100, 'lin', 1, 0, "%")) params:set_action("analogdrive_mix", function(v) engine.analogdrive_mix(v * 0.01) font.update_fx_cache("analogdrive_mix", v) end)
    params:add_option("analogdrive_mod", "Mix Mod", {"off", "on"}, 1) params:set_action("analogdrive_mod", function(v) engine.analogdrive_mod(v - 1) font.update_fx_cache("analogdrive_mod", v) end)
    params:add_control("analogdrive_drive", "Drive", controlspec.new(0, 100, 'lin', 1, 60, "%")) params:set_action("analogdrive_drive", function(v) engine.analogdrive_drive(v * 0.01) end)
    params:add_control("analogdrive_tone", "Tone", controlspec.new(0, 100, 'lin', 1, 60, "%")) params:set_action("analogdrive_tone", function(v) engine.analogdrive_tone(v * 0.01) end)
    params:add_control("analogdrive_mode", "Style", controlspec.new(0, 100, 'lin', 1, 75, "%")) params:set_action("analogdrive_mode", function(v) engine.analogdrive_mode(v * 0.01) end)
    params:add_group("FUZZ", 4)
    params:add_control("fuzz_mix", "Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("fuzz_mix", function(v) engine.fuzz_mix(v * 0.01) font.update_fx_cache("fuzz_mix", v) end)
    params:add_control("fuzz_gain", "Gain", controlspec.new(0, 100, "lin", 1, 60, "%")) params:set_action("fuzz_gain", function(v) engine.fuzz_gain(v * 0.01) end)
    params:add_control("fuzz_octave", "Octave", controlspec.new(0, 100, "lin", 1, 50, "%")) params:set_action("fuzz_octave", function(v) engine.fuzz_octave(v * 0.01) end)
    params:add_control("fuzz_tone", "Tone", controlspec.new(0, 100, "lin", 1, 50, "%")) params:set_action("fuzz_tone", function(v) engine.fuzz_tone(v * 0.01) end)
    params:add_group("TAPE", 17)
    params:add_option("tape_mix", "Tape Sim", {"off", "on"}, 1) params:set_action("tape_mix", function(x) engine.tape_mix(x-1) font.update_fx_cache("tape_mix", x) end)
    params:add_control("reel_mix", "Saturation", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("reel_mix", function(v) engine.reel_mix(v * 0.01) font.update_fx_cache("reel_mix", v) end)
    params:add_control("sine_drive_wet", "Shaper Drive", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("sine_drive_wet", function(value) engine.sine_drive_wet(value * 0.01) font.update_fx_cache("sine_drive_wet", value) end)
    params:add{type = "control", id = "wobble_mix", name = "Wobble", controlspec = controlspec.new(0, 100, "lin", 1, 0, "%"), action = function(value) engine.wobble_mix(value * 0.01) font.update_fx_cache("wobble_mix", value) end}
    params:add{type = "control", id = "wobble_amp", name = "Wow Depth", controlspec = controlspec.new(0, 100, "lin", 1, 20, "%"), action = function(value) engine.wobble_amp(value * 0.01) end}
    params:add{type = "control", id = "wobble_rpm", name = "Wow Speed", controlspec = controlspec.new(30, 90, "lin", 1, 33, "RPM"), action = function(value) engine.wobble_rpm(value) end}
    params:add{type = "control", id = "flutter_amp", name = "Flutter Depth", controlspec = controlspec.new(0, 100, "lin", 1, 35, "%"), action = function(value) engine.flutter_amp(value * 0.01) end}
    params:add{type = "control", id = "flutter_freq", name = "Flutter Speed", controlspec = controlspec.new(3, 30, "lin", 0.01, 6, "Hz"), action = function(value) engine.flutter_freq(value) end}
    params:add{type = "control", id = "flutter_var", name = "Flutter Var.", controlspec = controlspec.new(0.1, 10, "lin", 0.01, 2, "Hz"), action = function(value) engine.flutter_var(value) end}
    params:add{type = "control", id = "chew_depth", name = "Chew", controlspec = controlspec.new(0, 50, "lin", 1, 0, "%"), action = function(value) engine.chew_depth(value * 0.01) font.update_fx_cache("chew_depth", value) end}
    params:add{type = "control", id = "chew_freq", name = "Chew Freq.", controlspec = controlspec.new(0, 60, "lin", 1, 60, "%"), action = function(value) engine.chew_freq(value * 0.01) end}
    params:add{type = "control", id = "chew_variance", name = "Chew Var.", controlspec = controlspec.new(0, 70, "lin", 1, 60, "%"), action = function(value) engine.chew_variance(value * 0.01) end}
    params:add_control("lossdegrade_mix", "Loss / Degrade", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("lossdegrade_mix", function(value) engine.lossdegrade_mix(value * 0.01) font.update_fx_cache("lossdegrade_mix", value) end)
    params:add_control("genloss_mix", "More Tape", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("genloss_mix", function(v) engine.genloss_mix(v * 0.01) font.update_fx_cache("genloss_mix", v) end)
    params:add_separator("    ")
    params:add_binary("randomize_tape", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_tape", function() undo.checkpoint() randpara.randomize_tape_params(steps) end)
    params:add_option("lock_tape", "Lock Parameters", {"off", "on"}, 1)
    params:add_group("EQ", 11)
    for i = 1, 2 do
    params:add_control(i.."eq_low_gain", i.." Bass", controlspec.new(-1, 1, "lin", 0.01, 0, "")) params:set_action(i.."eq_low_gain", function(value) engine.eq_low_gain(i, value*55) end)
    params:add_control(i.."eq_mid_gain", i.." Mid", controlspec.new(-1, 1, "lin", 0.01, 0, "")) params:set_action(i.."eq_mid_gain", function(value) engine.eq_mid_gain(i, value*35) end)
    params:add_control(i.."eq_high_gain", i.." Treble", controlspec.new(-1, 1, "lin", 0.01, 0, "")) params:set_action(i.."eq_high_gain", function(value) engine.eq_high_gain(i, value*45) end)
    params:add_control(i.."eq_tilt", i.." Tilt", controlspec.new(-1, 1, "lin", 0.01, 0, "")) params:set_action(i.."eq_tilt", function(value) engine.eq_tilt(i, value*12) end)
    end
    params:add_separator("     ")
    params:add_binary("randomize_eq", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_eq", function() undo.checkpoint() for i=1, 2 do randpara.randomize_eq_params(i, steps) end end)
    params:add_option("lock_eq", "Lock Parameters", {"off", "on"}, 1)
    params:add_group("LFO", 119)
    params:add_binary("randomize_lfos", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_lfos", function() undo.checkpoint() lfo.clearLFOs() for i = 1, 2 do lfo.randomize_lfos(i, false) end end)
    params:add_binary("lfo.assign_to_current_row", "Assign to Selection", "trigger", 0) params:set_action("lfo.assign_to_current_row", function() undo.checkpoint() lfo.assign_to_current_row(current_mode) end)
    params:add_control("global_lfo_freq_scale", "Freq Scale", controlspec.new(0.01, 10, "exp", 0.01, 1, "x")) params:set_action("global_lfo_freq_scale", function() for i = 1, 16 do lfo.recompute_freq(i) end end)
    params:add_control("global_lfo_depth_scale", "Depth Scale", controlspec.new(0, 2, "lin", 0.01, 1, "x")) params:set_action("global_lfo_depth_scale", function(value) lfo.set_global_depth_scale(value) end)
    params:add_binary("sine_lfos", "Sine LFOs", "toggle", 0) params:set_action("sine_lfos", function(v) lfo.set_sine_all(v == 1) end)
    params:add_binary("lfo_pause", "Pause ⏸︎", "toggle", 0) params:set_action("lfo_pause", function(value) lfo.set_pause(value == 1) end)
    params:add_binary("ClearLFOs", "Clear All", "trigger", 0) params:set_action("ClearLFOs", function() undo.checkpoint() lfo.clearLFOs() update_pan_positioning() end)
    lfo.init()
    params:add_group("STEREO", 4)
    params:add_control("Width", "Stereo Width", controlspec.new(0, 200, "lin", 2, 100, "%")) params:set_action("Width", function(value) engine.width(value * 0.01) font.update_fx_cache("Width", value) end)
    params:add_option("haas", "Haas Effect", {"off", "on"}, 1) params:set_action("haas", function(x) engine.haas(x-1) font.update_fx_cache("haas", x) end)
    params:add_taper("rspeed", "Rotation", 0, 1, 0, 1, "Hz") params:set_action("rspeed", function(value) engine.rspeed(value) font.update_fx_cache("rspeed", value) end)
    params:add_option("monobass_mix", "Mono Bass", {"off", "on"}, 1) params:set_action("monobass_mix", function(x) engine.monobass_mix(x-1) font.update_fx_cache("monobass_mix", x) end)
    params:add_group("CHORUS", 4)
    params:add_control("dimension_mix", "Dimension", controlspec.new(0, 100, "lin", 2, 0, "%")) params:set_action("dimension_mix", function(value) engine.dimension_mix(value * 0.01) font.update_fx_cache("dimension_mix", value) end)
    params:add_control("stchorus_mix", "Stereo Chorus", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("stchorus_mix", function(v) engine.stchorus_mix(v * 0.01) font.update_fx_cache("stchorus_mix", v) end)
    params:add_control("vibe_mix", "Vibe", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("vibe_mix", function(v) engine.vibe_mix(v * 0.01) font.update_fx_cache("vibe_mix", v) end)
    params:add_control("vibe_drift", "Vibe Drift", controlspec.new(0, 100, "lin", 1, 50, "%")) params:set_action("vibe_drift", function(v) engine.vibe_drift(v * 0.01) end)
    params:add_group("BITCRUSH", 4)
    params:add_taper("bitcrush_mix", "Mix", 0, 100, 0.0, 0, "%") params:set_action("bitcrush_mix", function(value) engine.bitcrush_mix(value * 0.01) font.update_fx_cache("bitcrush_mix", value) end)
    params:add_option("bitcrush_mod", "Mix Mod", {"off", "on"}, 1) params:set_action("bitcrush_mod", function(value) engine.bitcrush_mod(value - 1) font.update_fx_cache("bitcrush_mod", value) end)
    params:add_taper("bitcrush_rate", "Rate", 1, 48000, 4500, 3, "Hz") params:set_action("bitcrush_rate", function(value) engine.bitcrush_rate(value) end)
    params:add_taper("bitcrush_bits", "Bits", 1, 24, 14, 1) params:set_action("bitcrush_bits", function(value) engine.bitcrush_bits(value) end)
    params:add_group("RESONATE", 5)
    params:add_control("resonator_mix", "Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("resonator_mix", function(v) engine.resonator_mix(v * 0.01) font.update_fx_cache("resonator_mix", v) if v > 0 then hlp.update_resonator() end end)
    params:add_control("resonator_decay", "Decay", controlspec.new(0.01, 5, "exp", 0, 2, "s")) params:set_action("resonator_decay", function(v) engine.resonator_decay(v) end)
    params:add_number("resonator_root", "Root", 24, 128, 28, function(p) return MusicUtil.note_num_to_name(floor(p:get() + 0.5), true) end) params:set_action("resonator_root", hlp.update_resonator)
    params:add_control("resonator_tone", "LPF", controlspec.new(200, 16000, "exp", 0, 8000, "Hz")) params:set_action("resonator_tone", function(v) engine.resonator_tone(v) end)
    params:add_option("resonator_voicing", "Voicing", _HK.reso_names, 2) params:set_action("resonator_voicing", function(v) hlp.set_reso_voicing(v) hlp.update_resonator() end)
    params:add_group("WAVEFOLD", 3)
    params:add_control("wavefold_mix", "Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("wavefold_mix", function(v) engine.wavefold_mix(v * 0.01) font.update_fx_cache("wavefold_mix", v) end)
    params:add_control("wavefold_drive", "Drive", controlspec.new(0, 100, "lin", 1, 75, "%")) params:set_action("wavefold_drive", function(v) engine.wavefold_drive(v * 0.01) end)
    params:add_control("wavefold_sym", "Symmetry", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("wavefold_sym", function(v) engine.wavefold_sym(v * 0.01) end)
    params:add_group("RINGMOD", 3)
    params:add_control("ringmod_mix", "Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("ringmod_mix", function(v) engine.ringmod_mix(v * 0.01) font.update_fx_cache("ringmod_mix", v) end)
    params:add_control("ringmod_rate", "Freq", controlspec.new(0.1, 4000, "exp", 0, 800, "Hz")) params:set_action("ringmod_rate", function(v) engine.ringmod_rate(v) end)
    params:add_control("ringmod_sweep", "Sweep", controlspec.new(0, 100, "lin", 1, 30, "%")) params:set_action("ringmod_sweep", function(v) engine.ringmod_sweep(v * 0.01) end)
    params:add_group("SPIRAL", 7)
    params:add_control("spiral_mix", "Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("spiral_mix", function(v) engine.spiral_mix(v * 0.01) font.update_fx_cache("spiral_mix", v) end)
    params:add_option("spiral_div", "Division", {"1/32", "1/16T", "1/16", "1/8T", "1/8", "1/8.", "1/4", "1/4."}, 5) local divs = {0.125, 1/6, 0.25, 1/3, 0.5, 0.75, 1, 1.5} params:set_action("spiral_div", function(v) engine.spiral_bpm(clock.get_tempo()) engine.spiral_div(divs[v]) end)
    params:add_control("spiral_feedback", "Feedback", controlspec.new(0, 100, "lin", 1, 50, "%")) params:set_action("spiral_feedback", function(v) engine.spiral_feedback(v * 0.01) end)
    params:add_control("spiral_rise", "Rise", controlspec.new(-100, 100, "lin", 1, 50, "%")) params:set_action("spiral_rise", function(v) engine.spiral_rise((v * 0.01 + 1) * 0.5) end)
    params:add_control("spiral_glide", "Glide", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("spiral_glide", function(v) engine.spiral_glide(v * 0.01) end)
    params:add_control("spiral_span", "Span", controlspec.new(0, 100, "lin", 1, 50, "%")) params:set_action("spiral_span", function(v) engine.spiral_span(v * 0.01) end)
    params:add_control("spiral_tone", "Tone", controlspec.new(0, 100, "lin", 1, 50, "%")) params:set_action("spiral_tone", function(v) engine.spiral_tone(v * 0.01) end)
    clock.tempo_change_handler = function(bpm) engine.spiral_bpm(bpm) end
    params:add_group("SUB", 2)
    params:add_control("sub_mix", "Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("sub_mix", function(v) engine.sub_mix(v * 0.01) font.update_fx_cache("sub_mix", v) end)
    params:add_control("sub_detune", "Detune", controlspec.new(0, 100, "lin", 1, 65, "%")) params:set_action("sub_detune", function(v) engine.sub_detune(v * 0.01) end)
    params:add_group("MULTIBAND", 1)
    params:add_control("ott_mix", "Comp", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("ott_mix", function(v) engine.ott_mix(v * 0.01) font.update_fx_cache("ott_mix", v) end)
    params:add_group("GLITCH", 12)
    params:add_control("glitch_ratio", "Glitch", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("glitch_ratio", function(value) engine.glitch_ratio((value * 0.01) ^ 2) font.update_fx_cache("glitch_ratio", value) end)
    params:add_control("glitch_mix", "Mix", controlspec.new(0, 100, "lin", 1, 100, "%")) params:set_action("glitch_mix", function(value) engine.glitch_mix(value * 0.01) font.update_fx_cache("glitch_mix", value) end)
    params:add_control("glitch_min_length", "Min Length", controlspec.new(10, 500, "lin", 1, 75, "ms")) params:set_action("glitch_min_length", function(value) engine.glitch_min_length(value * 0.001) end)
    params:add_control("glitch_max_length", "Max Length", controlspec.new(20, 500, "lin", 1, 200, "ms")) params:set_action("glitch_max_length", function(value) engine.glitch_max_length(value * 0.001) end)
    params:add_control("glitch_maxstutters", "Max Stutters", controlspec.new(2, 20, "lin", 1, 5, "")) params:set_action("glitch_maxstutters", function(value) engine.glitch_maxstutters(value) end)
    params:add_control("glitch_reverse", "Reverse Prob", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("glitch_reverse", function(value) engine.glitch_reverse(value * 0.01) end)
    params:add_control("glitch_pitch", "Pitch Prob", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("glitch_pitch", function(value) engine.glitch_pitch(value * 0.01) end)
    params:add_control("glitch_gate", "Gate", controlspec.new(5, 100, "lin", 1, 100, "%")) params:set_action("glitch_gate", function(value) engine.glitch_gate(value * 0.01) end)
    params:add_control("glitch_decay", "Decay", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("glitch_decay", function(value) engine.glitch_decay(value * 0.01) end)
    params:add_separator("       ")
    params:add_binary("randomize_glitch", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_glitch", function() if params:get("lock_glitch") == 1 then undo.checkpoint() params:set("glitch_min_length", math.random(10, 200)) params:set("glitch_max_length", math.random(100, 500)) params:set("glitch_reverse", math.random(0, 100)) params:set("glitch_pitch", math.random(0, 100)) end end)
    params:add_option("lock_glitch", "Lock Parameters", {"off", "on"}, 1)
    params:add_group("EVOLVE", 16)
    params:add_binary("evolution", "Evolve!", "toggle", 0) params:set_action("evolution", function(value) if value == 1 then randpara.reset_evolution_centers() randpara.start_evolution() else randpara.stop_evolution() end end)
    params:add_control("evolution_range", "Evolution Range", controlspec.new(0, 100, "lin", 1, 10, "%")) params:set_action("evolution_range", randpara.set_evolution_range)
    params:add_option("evolution_rate", "Evolution Rate", {"slowest", "slow", "moderate", "medium", "fast", "crazy"}, 2) local rates = {1/0.5, 1/1.5, 1/4, 1/8, 1/15, 1/30} params:set_action("evolution_rate", function(value) randpara.set_evolution_rate(rates[value]) end)
    params:add_separator("                               ")
    for _, e in ipairs({{"granular", "Granular", 2}, {"delay", "Delay", 1}, {"reverb", "Reverb", 1}, {"tape", "Tape", 2}, {"shimmer", "Shimmer", 2}, {"eq", "EQ", 2}, {"bitcrush", "Bitcrush", 2}, {"glitch", "Glitch", 2}, {"ringmod", "Ringmod", 2}, {"fuzz", "Fuzz", 2}, {"sub", "Sub", 2}, {"spiral", "Spiral", 2}}) do
      local g = e[1]
      params:add_option("evolve_"..g, "Evolve "..e[2], {"off", "on"}, e[3]) params:set_action("evolve_"..g, function(v) randpara.set_group_evolution(g, v == 2) end)
    end
    params:add_group("SYMMETRY", 6)
    params:add_binary("symmetry", "Symmetry", "toggle", 0)
    params:set_action("symmetry", function(value)
      local on, active_map = value == 1, {}
      for i = 1, 16 do
        local o = lfo[i]
        o.sync_to, o.sync_invert = nil, false
        if on and o.active and o.target_name ~= "none" then active_map[o.target_name] = i end
      end
      if on then
        for i = 1, 16 do
          local o = lfo[i]
          local t = o.target_name
          if o.active and t:sub(1, 1) == "1" and t ~= "1volume" then
            local pname = t:sub(2)
            local j = active_map["2"..pname]
            if j then
              local d, is_pan = lfo[j], pname == "pan"
              d.sync_to, d.sync_invert, d.walk_value, d.walk_velocity = i, is_pan, o.walk_value, o.walk_velocity
              d.prev = is_pan and -o.prev or o.prev
            end
          end
        end
      end
      lfo.rebuild_order()
    end)
    params:add_separator("Copy")
    local COPY_DIRS = {{1, 2, "→"}, {2, 1, "←"}}
    for _, cd in ipairs(COPY_DIRS) do
      local from, to, ar = cd[1], cd[2], cd[3]
      local id = "copy_"..from.."_to_"..to
      params:add_binary(id, "Params 1 "..ar.." 2", "trigger", 0) params:set_action(id, function() Mirror.copy_voice_params(tostring(from), tostring(to), true) end)
    end
    for _, cd in ipairs(COPY_DIRS) do
      local from, to, ar = cd[1], cd[2], cd[3]
      local id = "copy_buffer_"..from.."_to_"..to
      params:add_binary(id, "Sample 1 "..ar.." 2", "trigger", 0) params:set_action(id, function() local f = params:get(from.."sample") if f and f ~= "" and f ~= "-" and f ~= "none" then set_track_sample(to, f) audio_active[to] = audio_active[from] update_pan_positioning() end end)
    end
    params:add_group("FILTER", 9)
    for i = 1, 2 do
      params:add_control(i.."cutoff",i.." LPF",controlspec.new(20,20000,"exp",0,20000,"Hz")) params:set_action(i.."cutoff", function(value) engine.cutoff(i, value) font.update_fx_cache(i.."cutoff", value) end)
      params:add_control(i.."hpf",i.." HPF",controlspec.new(20,20000,"exp",0,20,"Hz")) params:set_action(i.."hpf", function(value) engine.hpf(i, value) font.update_fx_cache(i.."hpf", value) end)
      params:add_taper(i.."lpf_gain", i.." Q", 0, 1, 0, 1, "") params:set_action(i.."lpf_gain", function(value) engine.lpf_gain(i, 4 * value) end)
    end
    params:add_separator("                   ")
    params:add_binary("randomizefilters", "RaNd0m1ze!", "trigger", 0) params:set_action("randomizefilters", function() for i = 1, 2 do local band = 2 ^ (2 + math.random() * 5) local cutoff, hpf if is_param_locked(i, "cutoff") or is_lfo_active_for_param(i.."cutoff") then cutoff = params:get(i.."cutoff") hpf = 20 * ((max(cutoff / band, 20) / 20) ^ math.random()) else hpf = 20 * ((max(19999 / band, 20) / 20) ^ math.random()) cutoff = clamp(hpf * band, 20, 19999) params:set(i.."cutoff", cutoff) params:set(i.."lpf_gain", math.random() * 0.85) end if not is_param_locked(i, "hpf") then params:set(i.."hpf", hpf) end end end)
    params:add_binary("resetfilters", "Reset", "trigger", 0) params:set_action("resetfilters", function() for i=1, 2 do params:set(i.."cutoff", 20000) params:set(i.."hpf", 20) params:set(i.."lpf_gain", 0.0) end end)
    params:add_group("LOCKING", 20)
    for i = 1, 2 do
        for _, l in ipairs({{"jitter", "Jitter"}, {"size", "Size"}, {"density", "Density"}, {"spread", "Spread"}, {"pitch", "Pitch"}, {"speed", "Speed"}, {"seek", "Seek"}, {"pan", "Pan"}, {"cutoff", "LPF", 2}, {"hpf", "HPF", 2}}) do
          params:add_option(i.."lock_"..l[1], i.." Lock "..l[2], {"off", "on"}, l[3] or 1)
        end
    end
    params:add_group("LIMITS", 30)
    for i = 1, 2 do
        params:add_separator("Voice "..i)
        for _, l in ipairs({{"jitter", 0, 999999, 0, 4999, 5, "ms"}, {"size", 20, 999, 40, 999, 5, "ms"}, {"density", 0.1, 50, 0.25, 20, 5, "Hz"}, {"spread", 0, 100, 0, 100, 0, "%"}, {"pitch"}, {"speed", -2, 2, -0.1, 0.25, 0, "x"}, {"seek", 0, 100, 0, 100, 0, "%"}}) do
            local s = l[1]
            local lo, hi = i.."min_"..s, i.."max_"..s
            if s == "pitch" then
                params:add_control(lo, i.." pitch (min)", controlspec.new(-48, 48, "lin", 1, -31, "st"))
                params:add_control(hi, i.." pitch (max)", controlspec.new(-48, 48, "lin", 1, 31, "st"))
            else
                params:add_taper(lo, i.." "..s.." (min)", l[2], l[3], l[4], l[6], l[7])
                params:add_taper(hi, i.." "..s.." (max)", l[2], l[3], l[5], l[6], l[7])
            end
            params:set_action(lo, lfo.invalidate_limits) params:set_action(hi, lfo.invalidate_limits)
        end
    end
    params:add_group("ACTIONS", 4)
    params:add_binary("undo_action", "UNDO", "trigger", 0) params:set_action("undo_action", undo.undo)
    params:add_binary("redo_action", "REDO", "trigger", 0) params:set_action("redo_action", undo.redo)
    params:add_binary("macro_more", "More+", "trigger", 0) params:set_action("macro_more", function() undo.checkpoint() macro.macro_more() end)
    params:add_binary("macro_less", "Less-", "trigger", 0) params:set_action("macro_less", function() undo.checkpoint() macro.macro_less() end)
    params:add_group("MORPHING", 5)
    params:add_option("scene_mode", "Morph Mode", {"off", "on"}, 1) params:set_action("scene_mode", function(value) morph.scene_mode = value == 2 and "on" or "off" if value ~= 2 then return end for t = 1, 2 do for sc = 1, 2 do local d = morph.scene_data[t] and morph.scene_data[t][sc] if d and next(d) then return end end end morph.initialize_scenes_with_current_params() end)
    params:add_control("morph_amount", "Morph", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("morph_amount", function(value) local prev = morph.amount if (prev == 0 or prev == 100) and value ~= prev and not _G.preset_loading then morph.auto_save_to_scene() end morph.amount = value morph.apply() end)
    params:add{type = "trigger", id = "save_to_scene1", name = "Morph Target A", action = function() morph.store_scene_pair(1) end}
    params:add{type = "trigger", id = "save_to_scene2", name = "Morph Target B", action = function() morph.store_scene_pair(2) end}
    params:add{type = "trigger", id = "delete_morph_data", name = "Delete Morph Data", action = function() morph.scene_data = {[1] = {[1] = {}, [2] = {}}, [2] = {[1] = {}, [2] = {}}} morph.temp_scene = {} params:set("morph_amount", 0, true) morph.sync_amount(0) morph.invalidate_scene_cache() params:set("scene_mode", 1) morph.scene_mode = "off" end}
    params:add_group("PITCH", 4)
    params:add_option("pitch_quantize_scale", "Pitch Quantize", {"off", "major", "minor", "dorian", "phrygian", "lydian", "mixolydian", "locrian", "major pent.", "minor pent.", "blues", "whole tone"}, 2) params:set_action("pitch_quantize_scale", function() local scale = params:string("pitch_quantize_scale") if scale ~= "off" then for i = 1, 2 do local current_pitch = params:get(i.."pitch") local quantized = SU.quantize(current_pitch, scale) if current_pitch ~= quantized then params:set(i.."pitch", quantized) end end end end)
    params:add_option("pitch_lag", "Pitch Lag", {"off", "very small", "small", "medium", "high", "very high"}, 1) params:set_action("pitch_lag", function(value) local lag = value > 1 and 2 ^ (value - 2) or 0 for i = 1, 2 do engine.pitch_lag(i, lag) end end)
    params:add_separator("                                   ")
    params:add_option("lock_pitch", "Lock Parameters", {"off", "on"}, 1)
    params:add_group("MIDI/SYNC", 19)
    midi_input.add_params({set_pitch = set_midi_pitch, on_voice_trigger = function(v) randomize_flash.midi[v] = 1; randomize_flash.held[v] = true end, on_voice_release = function(v) randomize_flash.held[v] = false end, voice_loaded = is_voice_loaded, on_transport_start = transport_start, on_transport_stop = transport_stop, on_transport_continue = transport_continue, on_bend = function(v) if not _G.preset_loading then local o = _pobj(v .. "pitch") if o then o:bang() end end end})
    params:add_option("midi_gate", "Drone Mode", { "off", "on" }, 2) params:set_action("midi_gate", midi_input.refresh)
    params:add_option("midi_voice_mode", "MIDI control", { "both", "paraphonic", "voice 1", "voice 2" }, 2) params:set_action("midi_voice_mode", midi_input.refresh)
    params:add_control("midi_attack", "Attack", controlspec.new(0.001, 20, "exp", 0, 2.5, "s")) params:set_action("midi_attack", midi_input.push_ad)
    params:add_control("midi_decay", "Release", controlspec.new(0.005, 20, "exp", 0, 5, "s")) params:set_action("midi_decay", midi_input.push_ad)
    params:add_option("midi_velocity", "Velocity", { "off", "on" }, 2) params:set_action("midi_velocity", function(v) if v == 1 then engine.vel_amp(1, 1); engine.vel_amp(2, 1) end end)
    params:add_option("midi_cc1_dest", "Mod Wheel to", { "off", "morph", "reverb", "delay" }, 2)
    do
        local devs, chans = {}, {"all"}
        for i = 1, 16 do local n = midi.vports[i] and midi.vports[i].name or "none" devs[i] = i .. ": " .. (#n > 14 and n:sub(1, 14) or n) chans[i + 1] = tostring(i) end
        params:add_option("midi_device", "MIDI Device", devs, 1) params:set_action("midi_device", midi_input.set_device)
        params:add_option("midi_channel", "MIDI Channel", chans, 1) params:set_action("midi_channel", function(v) midi_input.set_channel(v - 1) end)
        params:add_number("midi_bend", "Bend Range", 0, 24, 2, function(p) return p:get() .. " st" end) params:set_action("midi_bend", midi_input.set_bend_range)
    end
    params:add_separator("                                 ")
    clocksync.add_params()
    params:add_option("midi_transport", "Transport", { "off", "on" }, 2)
    params:add_separator("                                    ")
    params:add_option("lock_sync", "Lock Parameters", {"off", "on"}, 1)
    arp.add_params()
    params:add_group("BOUNCE", 9)
    params:add_binary("bounce", "Bounce!", "trigger", 0) params:set_action("bounce", hlp.start_bounce)
    params:add_option("bounce_mode", "Bounce to", {"voice 1", "in place"}, 1)
    params:add_option("bounce_source", "Source", {"dry", "final mix"}, 2)
    params:add_option("bounce_volume", "Volume", {"pre", "post"}, 1)
    params:add_taper("bounce_length", "Length", 0.1, 60, 5, 0, "s")
    params:add_taper("bounce_xfade", "Crossfade", 0, 5, 1, 0, "s")
    params:add_option("bounce_reset", "Reset After", {"off", "voice 1", "voice 2", "both"}, 2)
    params:add_separator("                        ")
    params:add_binary("delete_unused_bounces", "Delete Unused Files", "trigger", 0) params:set_action("delete_unused_bounces", delete_unused_bounces)
    params:add_group("OTHER", 27)
    params:add_binary("dry_mode", "Dry Mode", "toggle", 0) params:set_action("dry_mode", function(x) drymode.set_dry_mode(x == 1) end)
    for i = 1, 2 do
      params:add_binary("randomtape"..i, "Random Tape "..i, "trigger", 0) params:set_action("randomtape"..i, function() load_random_tape_file(i) end)
    end
    params:add_binary("unload_all", "Unload All Audio", "trigger", 0) params:set_action("unload_all", function() for i=1, 2 do params:set(i.."seek", 0) params:set(i.."sample", "-") params:set(i.."live_input", 0) params:set(i.."live_direct", 0) audio_active[i] = false osc_positions[i] = 0 ctx.live_wf.reset(i) end engine.unload_all() update_pan_positioning() end)
    params:add_option("norm_load", "Normalize Load", {"off", "on"}, 2) params:set_action("norm_load", function(x) engine.norm_load(x - 1) end)
    params:add_option("limiter", "Output Limiter", {"off", "on"}, 1) params:set_action("limiter", function(x) engine.limiter(x - 1) end)
    params:add_binary("global_pitch_size_density_link", "Linked Mode", "toggle", 0) params:set_action("global_pitch_size_density_link", function(value) if value == 1 then for i = 1, 2 do hlp.set_link_base(i, clocksync.grain_density(i) or params:get(i.."density")) end end end)
    params:add_option("steps", "Transition Time", {"short", "medium", "long"}, 1) params:set_action("steps", function(value) steps = utils.STEP_COUNTS[value] end)
    params:add_separator("                                  ")
    for i = 1, 2 do
      params:add_taper(i.. "volume", i.. " volume", -70, 10, -15, 0, "dB") params:set_action(i.. "volume", function(value) engine.volume(i, value == -70 and 0 or 10 ^ (value / 20)) end)
      params:add_taper(i.. "pan", i.. " pan", -100, 100, 0, 0, "%") params:set_action(i.. "pan", function(value) engine.pan(i, value * 0.01)  end)
      params:add_taper(i.. "speed", i.. " speed", -2, 2, 0, 0) params:set_action(i.. "speed", function(value) if abs(value) < 0.01 then engine.speed(i, 0) else engine.speed(i, drymode.stereo_dry_active() and value or value * clocksync.speed_scale()) end end)
      params:add_taper(i.. "density", i.. " density", 0.1, 250, ({5, 2.5})[i], 5) params:set_action(i.. "density", function(value) engine.density(i, clocksync.grain_density(i) or value) end)
      params:add_control(i.. "pitch", i.. " pitch", controlspec.new(-48, 48, "lin", 1, 0, "st")) params:set_action(i.. "pitch", function(value) engine.pitch_offset(i, 2 ^ (SU.quantize(value, params:string("pitch_quantize_scale")) / 12) * arp.ratio(i) * midi_input.bend(i)) end)
      params:add_taper(i.. "jitter", i.. " jitter", 0, 999900, 250, 10, "ms") params:set_action(i.. "jitter", function(value) engine.jitter(i, value * 0.001) end)
      params:add_taper(i.. "size", i.. " size", 20, 5000, ({500, 1000})[i], 1, "ms") params:set_action(i.. "size", function(value) engine.size(i, arp.grain_size_ms(i, value) * 0.001) end)
      params:add_taper(i.. "spread", i.. " spread", 0, 100, 75, 0, "%") params:set_action(i.. "spread", function(value) engine.spread(i, value * 0.01) end)
      params:add_control(i.. "seek", i.. " seek", controlspec.new(0, 100, "lin", 0.01, 0, "%")) params:set_action(i.. "seek", function(value) engine.seek(i, value * 0.01) end) params:lookup_param(i.."seek").save = false
    end
    params:bang()
    params:set("reverb_mix", -40) params:set("rv_predelay", 20) params:set("rv_lffc", 50) params:set("rv_lowtime", 0.1) params:set("rv_midtime", 11) params:set("rv_hfdamp", 4500)
    presets.record_defaults()
end

local function set_pitch(track, other_track, new_pitch, symmetry)
    local scale = params:string("pitch_quantize_scale")
    new_pitch = SU.quantize(new_pitch, scale)
    local current = params:get(track.."pitch")
    if current ~= new_pitch then params:set(track.."pitch", new_pitch) if symmetry then params:set(other_track.."pitch", new_pitch) end end
end

local function randomize_pitch(track, other_track, symmetry)
    local current_pitch = params:get(track .. "pitch")
    local min_pitch = max(params:get(track.."min_pitch"), current_pitch - 48)
    local max_pitch = min(params:get(track.."max_pitch"), current_pitch + 48)
    if min_pitch >= max_pitch then return end
    local base_pitch = params:get(other_track .. "pitch")
    local scale = SU.intervals(params:string("pitch_quantize_scale")) or SU.intervals("major")
    if not scale then return end
    local strong = {}
    for i = 3, 6 do local d = scale[i] if d then strong[d] = true end end
    local weights, wide = {}, {}
    for octave = -2, 2 do
        for _, degree in ipairs(scale) do
            local interval = octave * 12 + degree
            local mag = abs(interval)
            if interval ~= 0 then
                if mag <= 12 then weights[interval] = (degree == 0 and 3) or (strong[degree] and 2) or 1
                elseif mag <= 24 then wide[#wide + 1] = interval end
            end
        end
    end
    weights[0] = 2
    local picks, n, total = {}, 0, 0
    for interval, weight in pairs(weights) do
        local candidate = base_pitch + interval
        if candidate >= min_pitch and candidate <= max_pitch then
            picks[n + 1], picks[n + 2] = interval, weight
            n = n + 2
            total = total + weight
        end
    end
    if total > 0 then
        local draw, acc = math.random(total), 0
        for i = 2, n, 2 do
            acc = acc + picks[i]
            if draw <= acc then set_pitch(track, other_track, base_pitch + picks[i - 1], symmetry) return end
        end
    end
    local fitting = {}
    for i = 1, #wide do
        local candidate = base_pitch + wide[i]
        if candidate >= min_pitch and candidate <= max_pitch then fitting[#fitting + 1] = candidate end
    end
    if #fitting > 0 then set_pitch(track, other_track, fitting[math.random(#fitting)], symmetry) end
end

local _rand_targets = {{}, {}}
local function randomize(n)
    if randomize_metro[n] then stop_metro_safe(randomize_metro[n]) else randomize_metro[n] = metro.init() end
    local m_rand = randomize_metro[n]
    if not m_rand then print("Error: Hardware metro limit reached!") return end
    local symmetry = params:get("symmetry") == 1
    local other_track = 3 - n
    local targets = _rand_targets[n]
    for k in pairs(targets) do targets[k] = nil end
    local param_names = _HK.rand_names
    local pitch_size_density_linked = params:get("global_pitch_size_density_link") == 1
    if not is_param_locked(n, "pitch") then randomize_pitch(n, other_track, symmetry) end
    for i = 1, #param_names do
        local key = param_names[i]
        local cfg_name = n .. key
        if key ~= "pitch" and not is_param_locked(n, key) then
            if key == "seek" then
                local val = random_float(params:get(n .. "min_seek"), params:get(n .. "max_seek"))
                local val_norm = val * 0.01
                params:set(n.."seek", val); osc_positions[n] = val_norm
                if symmetry then params:set(other_track.."seek", val); osc_positions[other_track] = val_norm end
            elseif key == "density" and clocksync.grain_synced() then
                if not is_lfo_active_for_param(cfg_name) then clocksync.randomize_grain_div(n, symmetry and other_track or nil) end
            else
                local min_val = params:get(n .. "min_" .. key)
                local max_val = params:get(n .. "max_" .. key)
                if min_val and max_val and min_val < max_val and not is_lfo_active_for_param(cfg_name) then
                    local val
                    if key == "jitter" and math.random() < 0.75 then
                        val = random_float(0, min(500, max_val))
                    else
                        val = random_float(min_val, max_val)
                    end
                    targets[cfg_name] = val
                    if symmetry then targets[other_track .. key] = (key == "pan") and -val or val end
                end
            end
        end
    end
    if clocksync.lfo_synced() then clocksync.randomize_lfo_div(n, symmetry and other_track or nil) end
    if next(targets) then
        m_rand.time = 1 / 30
        local tolerance = 0.01
        m_rand.event = function(count)
            local factor = min(count / steps, 1)
            local all_done = true
            for param, target in pairs(targets) do
                local current = params:get(param)
                local new_val = current + (target - current) * factor
                params:set(param, new_val)
                all_done = all_done and (abs(new_val - target) < tolerance)
            end
            if all_done then
                if pitch_size_density_linked then for t = symmetry and 1 or n, symmetry and 2 or n do hlp.set_link_base(t, params:get(t.."density")) end end
                stop_metro_safe(m_rand)
            end
        end
        utils.metro_start(m_rand)
    end
    if morph.amount > 0 and morph.amount < 100 then do_capture_temp_scene() end
end

local function offset_key_to_db(k, fallback_param)
    return k and ((params:get(k) + 1) * 40 - 70) or params:get(fallback_param)
end
local function db_to_offset_value(db)
    return clamp((db + 70) / 40 - 1, -0.99, 0.99)
end
function hlp.volume_lfo_key(track)
    local active, idx = is_lfo_active_for_param(_HK.vol[track])
    return active and MK.offset[idx]
end
function hlp.volume_db(track, k)
    return offset_key_to_db(k or hlp.volume_lfo_key(track), _HK.vol[track])
end
function hlp.adjust_volume(track, delta, k)
    k = k or hlp.volume_lfo_key(track)
    if k then params:delta(k, delta * 1.5) else params:delta(_HK.vol[track], delta * 3) end
    return k
end
local function handle_volume_lfo(track, delta, crossfade_mode)
    if key_state[2] or key_state[3] then return end
    if crossfade_mode then
        local k1 = hlp.adjust_volume(track, delta)
        local k2 = hlp.adjust_volume(3 - track, -delta)
        _G.master_vol_diff = hlp.volume_db(track, k1) - hlp.volume_db(3 - track, k2)
        return
    end
    local k1, k2 = hlp.volume_lfo_key(track), hlp.volume_lfo_key(3 - track)
    local c1, c2 = offset_key_to_db(k1, _HK.vol[track]), offset_key_to_db(k2, _HK.vol[3 - track])
    if c1 > (k1 and -69.5 or -70) and c2 > (k2 and -69.5 or -70) then _G.master_vol_diff = c1 - c2 end
    local diff = _G.master_vol_diff or 0
    local lead, follow, lead_k, follow_k, sign = track, 3 - track, k1, k2, -1
    if diff < 0 then lead, follow, lead_k, follow_k, sign = 3 - track, track, k2, k1, 1 end
    lead_k = hlp.adjust_volume(lead, delta, lead_k)
    local fdb = clamp(hlp.volume_db(lead, lead_k) + sign * diff, -70, 10)
    if follow_k then params:set(follow_k, db_to_offset_value(fdb)) else params:set(_HK.vol[follow], fdb) end
end

local _LINK_SPEED = {pitch = 1, size = 5, density = 0.5}
function hlp.update_linked_params(tr, delta_mult, param, delta)
    local lb = hlp.ensure_link_base(tr)
    local bp, bs, bd, prod = lb.pitch, lb.size, lb.density, lb.product
    local SZ, DN, PT = LIMITS.size, LIMITS.density, LIMITS.pitch
    local synced = clocksync.grain_synced()
    local step = delta * delta_mult
    local new_pitch, new_size, new_den = bp
    if param == "density" then
        new_den = clamp(bd + step * 0.1, DN.min, DN.max)
        new_size = clamp(prod / new_den, SZ.min, SZ.max)
        if new_size == SZ.min or new_size == SZ.max then new_den = clamp(prod / new_size, DN.min, DN.max) end
    else
        local ratio = 0
        if param == "pitch" then
            local scale = params:string("pitch_quantize_scale")
            new_pitch = clamp(scale ~= "off" and SU.step(bp, scale, step > 0 and 1 or -1) or bp + step, PT.min, PT.max)
            ratio = (new_pitch - bp) / 12
            new_size = clamp(bs * 2 ^ -ratio, SZ.min, SZ.max)
        else
            new_size = clamp(bs + step, SZ.min, SZ.max)
        end
        if synced then
            hlp.apply_linked_density(tr, clamp(prod / new_size, DN.min, DN.max))
            new_den = clocksync.grain_density(tr) or bd
        elseif param == "pitch" then
            new_den = clamp(bd * 2 ^ ratio, DN.min, DN.max)
        else
            new_den = clamp(prod / new_size, DN.min, DN.max)
            if new_den == DN.min or new_den == DN.max then new_size = clamp(prod / new_den, SZ.min, SZ.max) end
        end
    end
    hlp.apply_lfo_or_set(_HK.size[tr], new_size)
    if not synced then hlp.apply_lfo_or_set(_HK.den[tr], new_den) end
    hlp.apply_lfo_or_set(_HK.pitch[tr], new_pitch)
    lb.pitch, lb.size, lb.density = new_pitch, new_size, new_den
    if not synced then lb.product = new_size * new_den end
end
local function handle_pitch_size_density_link(track, config, delta)
    local speed = _LINK_SPEED[config.param]
    if not speed or params:get("global_pitch_size_density_link") ~= 1 then return false end
    hlp.update_linked_params(track, speed, config.param, delta)
    if params:get("symmetry") == 1 then hlp.update_linked_params(3 - track, speed, config.param, delta) end
    return true
end

local function clocksync_set_density(voice, hz)
    engine.density(voice, hz)
    local last = hlp.link_last_hz[voice]
    hlp.link_last_hz[voice] = hz
    if params:get("global_pitch_size_density_link") ~= 1 then return end
    local lb = hlp.ensure_link_base(voice)
    if not (hlp.link_suppress_size or last == hz or is_lfo_active_for_param(_HK.den[voice])) then
        lb.size = clamp(lb.product / hz, LIMITS.size.min, LIMITS.size.max)
        hlp.apply_lfo_or_set(_HK.size[voice], lb.size)
    end
    lb.density = hz
end

local function handle_seek_param(track, config, delta)
    if config.param ~= "seek" then return false end
    local sym = params:get("symmetry") == 1
    disable_lfos_for_param(_HK.seek[track], not sym)
    for t = sym and 1 or track, sym and 2 or track do
        local pos = (floor(osc_positions[t] * 100 + 0.5) + delta) % 100
        osc_positions[t] = pos * 0.01
        params:set(t.."seek", pos, true)
        engine.seek(t, pos * 0.01)
    end
    return true
end

local function handle_standard_param(track, config, delta)
    local sym = params:get("symmetry") == 1
    local p, op = config.pkeys[track], config.pkeys[3 - track]
    disable_lfos_for_param(p, not sym)
    if config.param == "pitch" then
        local old_value = params:get(p)
        local scale = params:string("pitch_quantize_scale")
        if scale ~= "off" then
            local dir, lim = delta > 0 and 1 or -1, LIMITS.pitch
            params:set(p, clamp(SU.step(old_value, scale, dir), lim.min, lim.max))
            if sym then params:set(op, clamp(SU.step(params:get(op), scale, dir), lim.min, lim.max)) end
        else
            params:delta(p, delta)
            if sym then params:set(op, params:get(op) + (params:get(p) - old_value)) end
        end
    else
        params:delta(p, delta)
        if sym then params:delta(op, delta) end
    end
    if config.param == "size" and delta < 0 and arp.is_running() then
        local cap = arp.max_size_ms(track)
        if params:get(p) > cap then params:set(p, cap) end
        if sym then cap = arp.max_size_ms(3 - track) if params:get(op) > cap then params:set(op, cap) end end
    end
end

local function handle_param_change(track, config, delta)
    if key_state[2] or key_state[3] then return end
    if handle_pitch_size_density_link(track, config, delta) then return end
    if handle_seek_param(track, config, delta) then return end
    handle_standard_param(track, config, delta)
end

local function handle_randomize_track(n)
    local track = n == 3 and 2 or 1
    undo.checkpoint()
    lfo.clearLFOs(track, nil, lfo.PRESERVE_ON_RANDOMIZE)
    lfo.randomize_lfos(track, false)
    randomize(track)
    randpara.randomize_params(steps, track)
    randpara.reset_evolution_centers()
    update_pan_positioning()
    randomize_flash[track] = 1
end

local function handle_mode_navigation(n)
    local idx = mode_indices[current_mode] or 1
    local offset = n == 2 and 0 or -2
    current_mode = mode_list[((idx + offset) % #mode_list) + 1]
end

local function handle_parameter_lock()
    if current_mode == "eq" then
        params:set("lock_eq", params:get("lock_eq") == 2 and 1 or 2)
        return
    end
    local param_name = (current_mode == "lpf" or current_mode == "hpf") and (current_filter_mode == "lpf" and "cutoff" or "hpf") or current_mode
    local lock1, lock2 = "1lock_" .. param_name, "2lock_" .. param_name
    local new_state = (params:get(lock1) == 2 or params:get(lock2) == 2) and 1 or 2
    params:set(lock1, new_state)
    params:set(lock2, new_state)
end

local function find_or_create_lfo_for_param(track, param_name, only_existing, create_with_depth, source_lfo_idx)
    local full_param = track .. param_name
    local lfo_targets = lfo.lfo_targets
    for i = 1, 16 do
        local lfo_state = pget(MK.lfo[i])
        if lfo_state == 2 or (only_existing and lfo_state == 1) then if lfo_targets[pget(MK.target[i])] == full_param then return i end end
    end
    if only_existing then return nil end
    local new_target_idx = lfo.target_index[full_param]
    if not new_target_idx or new_target_idx == 1 then return nil end
    local min_val, max_val = lfo.get_parameter_range(full_param)
    if not min_val or max_val <= min_val then return nil end
    local current_val = pget(full_param)
    local offset = lfo.range_to_norm(full_param, min_val, max_val, current_val) * 2 - 1
    if param_name == "density" and clocksync.grain_synced() then
        offset = clocksync.grain_division_norm(track) * 2 - 1
    end
    local conflicts = {}
    for j = 1, 16 do if pget(MK.lfo[j]) == 2 then conflicts[lfo_targets[pget(MK.target[j])]] = true end end
    for i = 1, 16 do
        if pget(MK.lfo[i]) == 1 then
            local target_name = lfo_targets[pget(MK.target[i])]
            if target_name == "none" or target_name == full_param or not conflicts[target_name] then
                params:set(MK.target[i], new_target_idx)
                if source_lfo_idx then
                    params:set(MK.shape[i], params:get(MK.shape[source_lfo_idx]))
                    params:set(MK.freq[i], params:get(MK.freq[source_lfo_idx]))
                    lfo[i].phase = lfo[source_lfo_idx].phase
                    local is_pan    = param_name == "pan"
                    local is_volume = param_name == "volume"
                    if is_pan then
                        lfo[i].sync_to = source_lfo_idx
                        lfo[i].sync_invert = true
                    elseif not is_volume then
                        lfo[i].sync_to = source_lfo_idx
                    end
                else
                    local default_shape = (param_name == "volume" or clocksync.lfo_synced()) and 1 or 4
                    params:set(MK.shape[i], default_shape)
                    params:set(MK.freq[i], random_float(0.1, 0.7))
                end
                params:set(MK.depth[i], create_with_depth and 0.01 or 0)
                params:set(MK.offset[i], offset)
                params:set(MK.lfo[i], create_with_depth and 2 or 1)
                return i
            end
        end
    end
    return nil
end

local function adjust_lfo_offset(lfo_idx, delta)
    local target_param = lfo.lfo_targets[pget(MK.target[lfo_idx])] or ""
    local sensitivity  = (target_param:match("size$") or target_param:match("density$")) and 0.004 or 0.008
    set_clamped_offset(lfo_idx, pget(MK.offset[lfo_idx]) + delta * sensitivity)
end

local function adjust_lfo_depth(lfo_idx, delta)
    local dk, ok, lk = MK.depth[lfo_idx], MK.offset[lfo_idx], MK.lfo[lfo_idx]
    local current_depth = pget(dk)
    local target_param  = lfo.lfo_targets[pget(MK.target[lfo_idx])]
    local full_min, full_max = lfo.get_parameter_range(target_param)
    local rand_min, rand_max = lfo.get_parameter_range(target_param, true)
    local full_range   = (full_max and full_min) and (full_max - full_min) or 1
    local narrow_range = (rand_max and rand_min) and (rand_max - rand_min) or full_range
    local remap_ratio  = narrow_range / full_range
    local step = 0.75 * remap_ratio * delta
    if current_depth == 0 and delta > 0 then
        local min_val, max_val = full_min, full_max
        if min_val and max_val and max_val > min_val then
            local current_val = pget(target_param)
            local normalized = lfo.range_to_norm(target_param, min_val, max_val, current_val)
            local initial_depth = abs(step)
            local initial_offset = clamp(normalized * 2 - 1, -0.9999, 0.9999)
            lfo[lfo_idx].depth = initial_depth
            lfo[lfo_idx].offset = initial_offset
            pset(ok, initial_offset)
            pset(dk, initial_depth)
            pset(lk, 2)
        end
        return
    end
    local proposed_depth = current_depth + step
    if proposed_depth <= 0 then if current_depth > 0 then pset(lk, 1) end return end
    local offset_floor   = proposed_depth * 0.01 - 1
    local offset_ceiling = 1 - proposed_depth * 0.01
    local current_offset = pget(ok)
    local new_offset     = clamp(current_offset, offset_floor, offset_ceiling)
    lfo[lfo_idx].depth  = proposed_depth
    pset(dk, proposed_depth)
    if new_offset ~= current_offset then
        lfo[lfo_idx].offset = new_offset
        pset(ok, new_offset)
    end
end

local function mark_key_interaction() if key_gesture then key_gesture.fired = true end end
local FINALIZE_DEBOUNCE = 0.25
local finalize_metro = nil
local finalize_pending = false
local last_e1_autosave = 0
local function run_finalize()
    if not finalize_pending then return end
    finalize_pending = false
    local amt = morph.amount
    if amt > 0 and amt < 100 then do_capture_temp_scene() else morph.auto_save_to_scene() end
end
local function flush_finalize() if finalize_pending then run_finalize() end end
local function finalize_change()
    finalize_pending = true
    if not finalize_metro then finalize_metro = metro.init(run_finalize, FINALIZE_DEBOUNCE, 1) end
    finalize_metro:stop()
    utils.metro_start(finalize_metro)
end

local function adjust_lfo_with_symmetry(track, param_name, lfo_idx, adjustment_fn, d, other_d, only_existing, create_with_depth)
    adjustment_fn(lfo_idx, d)
    if params:get("symmetry") == 1 then
        local other_lfo = find_or_create_lfo_for_param(3 - track, param_name, only_existing, create_with_depth, lfo_idx)
        if other_lfo then adjustment_fn(other_lfo, other_d) end
    end
end

local function apply_freq_step(idx, d)
    local fk = MK.freq[idx]
    local cur = pget(fk)
    local step = max(cur * 0.06, 0.001) * (d > 0 and 1 or -1)
    pset(fk, clamp(cur + step, 0.01, 10))
    lfo.recompute_freq(idx)
end

local FX_MAP = { "reverb_mix", "delay_mix", "shimmer_mix1" }
local FX_LABELS = { "reverb", "delay", "shimmer" }

local function active_edit_mode()
    if current_mode == "lpf" or current_mode == "hpf" then return current_filter_mode end
    return current_mode
end

function enc(n, d)
    hlp.last_input = util.time()
    if not installer:ready() or installer:pending() then return end
    if presets.is_menu_open() then presets.menu_enc(n, d) return end
    local k1, k2, k3 = key_state[1], key_state[2], key_state[3]
    if k2 and k3 and not k1 then
        local fx = FX_MAP[n]
        if fx then
            mark_key_interaction()
            params:delta(fx, d)
            hlp.popup(FX_LABELS[n], params:get(fx))
            finalize_change()
        end
        return
    end
    if (k2 or k3) and not (k2 and k3) then
        local voice = k2 and 1 or 2
        local param_name
        if k1 then
            param_name = "volume"
        else
            local mode_name = active_edit_mode()
            param_name = param_modes[mode_name] and param_modes[mode_name].param or mode_name
        end
        mark_key_interaction()
        local lfo_idx
        if n == 1 then
            if clocksync.lfo_synced() then
                clocksync.step_lfo_div(voice, d, params:get("symmetry") == 1)
                finalize_change()
            else
                lfo_idx = find_or_create_lfo_for_param(voice, param_name, true, false)
                if lfo_idx then
                    adjust_lfo_with_symmetry(voice, param_name, lfo_idx, apply_freq_step, d, d, true, false)
                    finalize_change()
                end
            end
        elseif n == 2 then
            lfo_idx = find_or_create_lfo_for_param(voice, param_name, false, true)
            if lfo_idx then
                adjust_lfo_with_symmetry(voice, param_name, lfo_idx, adjust_lfo_depth, d, d, false, true)
                finalize_change()
            end
        elseif n == 3 then
            lfo_idx = find_or_create_lfo_for_param(voice, param_name, true, false)
            if lfo_idx then
                local other_d = (param_name == "pan") and -d or d
                adjust_lfo_with_symmetry(voice, param_name, lfo_idx, adjust_lfo_offset, d, other_d, true, false)
                finalize_change()
            end
        end
        hlp.hint = {t = util.time(), n = n, idx = lfo_idx, v = voice}
        if k1 then local tx = hlp.hint_text(hlp.hint.t) if tx then hlp.popup(voice .. " vol " .. tx) end hlp.hint = nil end
        return
    end
    if n == 1 then
        mark_key_interaction()
        if morph.amount == 0 or morph.amount == 100 then
            local now = util.time()
            if (now - last_e1_autosave) > FINALIZE_DEBOUNCE then morph.auto_save_to_scene() end
            last_e1_autosave = now
        end
        if k1 and morph.scene_mode == "on" then
            params:set("morph_amount", clamp(morph.amount + (d * 3), 0, 100))
        else
            handle_volume_lfo(1, d, k1)
            if morph.amount > 0 and morph.amount < 100 then finalize_change() end
        end
        return
    end
    if n == 2 or n == 3 then
        local track = n - 1
        mark_key_interaction()
        stop_metro_safe(randomize_metro[track])
        if k1 then
            hlp.adjust_volume(track, d)
            _G.master_vol_diff = hlp.volume_db(1) - hlp.volume_db(2)
        else
            local mode = active_edit_mode()
            if mode == "density" and clocksync.grain_synced() then
                local sym = params:get("symmetry") == 1
                disable_lfos_for_param(_HK.den[track], not sym)
                clocksync.step_grain_div(track, d, sym and (3 - track) or nil)
            else
                local config = param_modes[mode]
                if config then handle_param_change(track, config, config.delta * d) end
            end
        end
        finalize_change()
    end
end

hlp.key_combos = {
    ["1"]   = {long  = function() hlp.flip("scene_mode", "MORPH", 2, 1) end},
    ["2"]   = {short = function() handle_mode_navigation(2) end, long  = function() hlp.flip("global_pitch_size_density_link", "LINKED", 1, 0) end},
    ["3"]   = {short = function() handle_mode_navigation(3) end, long  = function() hlp.flip("symmetry", "SYMMETRY", 1, 0) end},
    ["12"]  = {short = function() handle_randomize_track(2) end, long  = function() hlp.flip("clock_sync", "CLOCK SYNC", 2, 1, function() return floor(clock.get_tempo() + 0.5) .. " BPM" end) end},
    ["13"]  = {short = function() handle_randomize_track(3) end, long  = function() hlp.flip("arp_on", "ARP", 2, 1) end},
    ["23"]  = {short = handle_parameter_lock, long  = combo_longpress_fire},
    ["123"] = {short = function() undo.undo() end, long  = function() params:set("arp_randomize", 1) hlp.popup("RANDOM ARP") end},
}
function hlp.hint_text(now)
    local h = hlp.hint
    if not h or now - h.t > 1.5 then return nil end
    if h.n == 1 and clocksync.lfo_synced() then return "~" .. params:string(h.v == 2 and "clock_lfo_div2" or "clock_lfo_div") end
    local i = h.idx
    if not i or pget(MK.lfo[i]) ~= 2 then return "lfo off" end
    if h.n == 1 then local f = lfo[i].freq return string.format(f < 10 and "~%.2fhz" or "~%.1fhz", f) end
    if h.n == 2 then return "dep " .. floor(pget(MK.depth[i]) + 0.5) end
    return string.format("ofs %+d", floor(pget(MK.offset[i]) * 100 + 0.5))
end

local function gesture_id() return (key_state[1] and "1" or "") .. (key_state[2] and "2" or "") .. (key_state[3] and "3" or "") end
local function handle_key_press() flush_finalize() key_gesture = {id = gesture_id(), press_time = util.time(), fired = false} end
local function handle_key_release()
    local g = key_gesture
    if g and not g.fired then
        g.fired = true
        local combo = hlp.key_combos[g.id]
        if combo then
            local action = (util.time() - g.press_time) >= _HK.LONGPRESS and combo.long or combo.short
            if action then action() end
        end
    end
    local id = gesture_id()
    if id == "" then key_gesture = nil
    else key_gesture = {id = id, press_time = g and g.press_time or util.time(), fired = true}
    end
end

function key(n, z)
    hlp.last_input = util.time()
    if not installer:ready() or installer:pending() then installer:key(n, z) return end
    if presets.is_menu_open() then
        if n == 1 and z == 1 then presets.close_menu() return end
        if presets.menu_key(n, z, morph.scene_data, update_pan_positioning, audio_active, current_mode, current_filter_mode, function(mode, filter)
            if mode then current_mode = mode end
            if filter then current_filter_mode = filter end
            morph.restore_synced_divisions()
            undo.clear()
            redraw()
        end) then return end
    end
    key_state[n] = (z == 1)
    if z == 1 then handle_key_press()
    else handle_key_release()
    end
end

local function format_speed(s)
  local a = abs(s)
  if a < 0.01 then return ".00x" end
  if a < 1    then return string.format("%s.%02dx", s < 0 and "-" or "", floor(a * 100)) end
  return string.format("%.2fx", s)
end

local LEVEL = {hi=15, dim=9, val=2}
local TRACK_X, VOL_X, PAN_X = {51, 92}, {0,126}, {52,93}
local BAR_W, Y = 30, {bottom=61, seek=63}
_HK.inv_bar_w = 1 / BAR_W
_HK.harm_alpha = 0.55
_HK.harm_def = {
  {key = "subharmonics_1", ratio = 0.5,   sub = true},
  {key = "subharmonics_2", ratio = 0.25,  sub = true},
  {key = "subharmonics_3", ratio = 0.125, sub = true},
  {key = "overtones_1",    ratio = 2.0,   sub = false},
  {key = "overtones_2",    ratio = 4.0,   sub = false},
}
local UPPER = {jitter=true, size=true, density=true, spread=true, pitch=true}
local FORMAT = {
  hz = function(value) return string.format("%.1f Hz", value) end,
  st = function(value, _, pitch_rand) return string.format(value > 0 and "+%.0f%s" or "%.0f%s", value, pitch_rand and ".. st" or " st") end,
  spread = function(v) return string.format("%.0f%%", v) end,
  jitter = function(value) return value > 999 and string.format("%.1f s", value / 1000) or string.format("%.0f ms", value) end,
  size = function(value) return value > 999 and string.format("%.2f s", value / 1000) or string.format("%.0f ms", value) end}
local buckets = {}
for _i = 1, 15 do
  buckets[_i] = {rx={}, ry={}, rw={}, rh={}, px={}, py={},
                 tx={}, ty={}, ts={}, ta={}, r_len=0, p_len=0, t_len=0}
end
local function clear_ops() for i=1,15 do local b=buckets[i] b.r_len, b.p_len, b.t_len = 0, 0, 0 end end
local function R(l,x,y,w,h) local b=buckets[l] local i=b.r_len+1 b.r_len=i b.rx[i]=x b.ry[i]=y b.rw[i]=w b.rh[i]=h end
local function P(l,x,y) local b=buckets[l] local i=b.p_len+1 b.p_len=i b.px[i]=x b.py[i]=y end
local function T(l,x,y,s,a) local b=buckets[l] local i=b.t_len+1 b.t_len=i b.tx[i]=x b.ty[i]=y b.ts[i]=s b.ta[i]=a end
local draw_lock, draw_size_link
do
  local LOCK_OFFSETS = {{-3,0},{-4,0},{-4,-1},{-4,-2}}
  draw_lock = function(x,y) for i=1,4 do local o=LOCK_OFFSETS[i] P(LEVEL.dim, x+o[1], y+o[2]) end end
  local SIZE_LINK_PTS = {}
  for _, offset in ipairs({1,3,5,7,9,11,13,15}) do local level = floor(10 * (1 - abs(offset - 8) / 8)) SIZE_LINK_PTS[#SIZE_LINK_PTS+1] = level SIZE_LINK_PTS[#SIZE_LINK_PTS+1] = offset end
  draw_size_link = function(x,y) for i = 1, 16, 2 do P(SIZE_LINK_PTS[i], x-4, y+SIZE_LINK_PTS[i+1]) end end
end
local function flush()
  local s_level, s_rect, s_pixel, s_fill = screen.level, screen.rect, screen.pixel, screen.fill
  local s_move, s_text, s_text_center = screen.move, screen.text, screen.text_center
  for l = 1, 15 do
    local b = buckets[l]
    local rn, pn, tn = b.r_len, b.p_len, b.t_len
    if rn > 0 or pn > 0 or tn > 0 then
      s_level(l)
      if rn > 0 then
        local rx, ry, rw, rh = b.rx, b.ry, b.rw, b.rh
        for i = 1, rn do s_rect(rx[i], ry[i], rw[i], rh[i]) end
      end
      if pn > 0 then
        local px, py = b.px, b.py
        for i = 1, pn do s_pixel(px[i], py[i]) end
      end
      if rn > 0 or pn > 0 then s_fill() end
      if tn > 0 then
        local tx, ty, ts, ta = b.tx, b.ty, b.ts, b.ta
        for i = 1, tn do
          s_move(tx[i], ty[i])
          if ta[i] == "center" then s_text_center(ts[i]) else s_text(ts[i]) end
        end
      end
    end
  end
end
local SYM_CACHE = {}
for sy = 4, 64, 2 do local lvl = max(1, floor(10 * (1 - abs(sy - 34) / 32))); SYM_CACHE[#SYM_CACHE+1] = sy; SYM_CACHE[#SYM_CACHE+1] = lvl end
local _LOG_FILTER_INV = 1.0 / log(20000 / 20)
local _VOL_LINLIN_MUL = 64.0 / 80.0
local LABEL_CACHE, LABEL_UPPER_CACHE = {}, {}
for _, m in ipairs({"lpf","hpf","pan","speed","seek","eq"}) do local pad = (m == "lpf" or m == "hpf") and "       " or "      " LABEL_CACHE[m] = m .. ":" .. pad LABEL_UPPER_CACHE[m] = string.upper(m) .. ":" .. pad end
local _GLUT_N = 256
local _GLUT_NM = _GLUT_N - 1
local _ENV_LUT, _FADE_LUT = {}, {}
local _ENV_PEAK = {}
do
  local cos, exp, pi = math.cos, math.exp, math.pi
  local lv_scale = LEVEL.hi - 1
  local function bld(fn) local t={} local mx=0 for i=0,_GLUT_N-1 do local v=fn((i+0.5)/_GLUT_N)*lv_scale t[i]=v if v>mx then mx=v end end _ENV_PEAK[t]=mx return t end
  for i=0,_GLUT_N-1 do _FADE_LUT[i]=sin(pi*(i+0.5)/_GLUT_N) end
  _ENV_LUT[1]=bld(function(p) return sin(pi*p) end)
  _ENV_LUT[2]=bld(function(p) if p<0.25 then return 0.5*(1-cos(pi*p*4)) elseif p>0.75 then return 0.5*(1-cos(pi*(1-p)*4)) else return 1.0 end end)
  _ENV_LUT[3]=bld(function(p) if p<0.08 then return p*12.5 else return exp(-4*(p-0.08)/0.92) end end)
  _ENV_LUT[4]=bld(function(p) if p<0.1 then return p*10 elseif p<0.3 then return 1-1.75*(p-0.1) elseif p<0.75 then return 0.65 else return 0.65*(1-(p-0.75)*4) end end)
  _ENV_LUT[5]=bld(function(p) return abs(sin(pi*p))*(0.6+0.4*sin(p*11.3+2.7)) end)
end
local function _tanh(z) local e = math.exp(2 * z) return (e - 1) / (e + 1) end
_HK.eq = {zy = 59, amp = 5, low = {}, high = {}, mid = {}, tilt = {}}
do
  local eq = _HK.eq
  local exp = math.exp
  local tanh = _tanh
  local p_low, w_low, p_high, w_high, p_mid, w_mid, p_tilt, w_tilt = 0.15, 0.13, 0.76, 0.13, 0.51, 0.14, 0.53, 0.30
  for c = 0, BAR_W - 1 do
    local p = c / (BAR_W - 1)
    eq.low[c] = 0.5 * (1 - tanh((p - p_low) / w_low))
    eq.high[c] = 0.5 * (1 + tanh((p - p_high) / w_high))
    local dm = (p - p_mid) / w_mid
    eq.mid[c] = exp(-dm * dm)
    eq.tilt[c] = tanh((p - p_tilt) / w_tilt)
  end
end
_HK.filt_sh = {}
do
  local sh = _HK.filt_sh
  local tanh = _tanh
  local w = 3.5
  for d = -(BAR_W - 1), BAR_W - 1 do sh[d] = 0.5 * (1 - tanh(d / w)) end
end
_HK.filt_r2 = {}
do
  local r2 = _HK.filt_r2
  local exp = math.exp
  local k = 2 * math.log(1000) / (BAR_W - 1)
  for d = -(BAR_W - 1), BAR_W - 1 do r2[d] = exp(k * d) end
end
_HK.filt_cache = { {fv = -1, q = -1, lo = false, y = {}}, {fv = -1, q = -1, lo = false, y = {}} }
_HK.eq_cache = { {lo = 1e9, mi = 1e9, hi = 1e9, ti = 1e9, y = {}}, {lo = 1e9, mi = 1e9, hi = 1e9, ti = 1e9, y = {}} }
_HK.rle = function(cache)
  local yv = cache.y
  local segs = cache.segs
  if not segs then segs = {} cache.segs = segs end
  local n = 0
  local prev, run_x, run_y0, run_y1
  for c = 0, BAR_W - 1 do
    local yc = yv[c]
    local y0, y1
    if c == 0 then y0, y1 = yc, yc else y0, y1 = prev, yc if y0 > y1 then y0, y1 = y1, y0 end end
    if run_x == nil or y0 ~= run_y0 or y1 ~= run_y1 then
      if run_x ~= nil then segs[n+1], segs[n+2], segs[n+3], segs[n+4] = run_x, run_y0, c - run_x, run_y1 - run_y0 + 1 n = n + 4 end
      run_x, run_y0, run_y1 = c, y0, y1
    end
    prev = yc
  end
  segs[n+1], segs[n+2], segs[n+3], segs[n+4] = run_x, run_y0, BAR_W - run_x, run_y1 - run_y0 + 1
  cache.nsegs = n + 4
end
local PARAM_CACHE = { track = { {locked={},lfo_on={}}, {locked={},lfo_on={}} } }
local _LFO_RANGE_CACHE = {}
local function fill_range_cache(fk)
  local rc = _LFO_RANGE_CACHE[fk]
  if not rc then rc = {0,0,0} _LFO_RANGE_CACHE[fk] = rc end
  local a, b = lfo.get_parameter_range(fk, true)
  local _, fb = lfo.get_parameter_range(fk, false)
  rc[1], rc[2], rc[3] = a, b, fb
  return rc
end
local _LOCK_PARAMS = {"jitter","size","density","spread","pitch","speed","seek","pan"}
local _FULL_PARAM_KEYS = {{},{}}
for t = 1, 2 do for i = 1, #_LOCK_PARAMS do _FULL_PARAM_KEYS[t][i] = t .. _LOCK_PARAMS[i] end end
local _slow_refresh_countdown = 0
local function refresh_redraw_cache()
  local spd_scale = drymode.stereo_dry_active() and 1 or clocksync.speed_scale()
  local eq_locked = pget("lock_eq") == 2
  for t = 1,2 do
    local C = PARAM_CACHE.track[t]
    local K = TRACK_KEYS[t]
    C.vol = pget(K.volume)
    C.pan = pget(K.pan)
    C.spd = pget(K.speed) * spd_scale
    C.cut = pget(K.cutoff)
    C.hpf = pget(K.hpf)
    C.q = pget(K.lpf_gain)
    C.loaded = audio_active[t] or C.in_ == 1 or C.dir_ == 1
    C.locked.eq = eq_locked
  end
  _slow_refresh_countdown = _slow_refresh_countdown - 1
  if _slow_refresh_countdown > 0 then return end
  _slow_refresh_countdown = 4
  PARAM_CACHE.link = pget("global_pitch_size_density_link") == 1
  PARAM_CACHE.dry = pget("dry_mode") == 1
  PARAM_CACHE.sym = pget("symmetry") == 1
  PARAM_CACHE.evo = pget("evolution") == 1
  local amap = lfo.get_active_param_map()
  for t = 1,2 do
    local C = PARAM_CACHE.track[t]
    local K = TRACK_KEYS[t]
    C.gran = pget(K.granular_gain)
    C.in_ = pget(K.live_input)
    C.dir_ = pget(K.live_direct)
    C.dir_mod = (pget(K.direction_mod) or 0) * 0.01
    C.env_sel = pget(K.env_select)
    local locked = C.locked
    local lfo_on = C.lfo_on
    local fullkeys = _FULL_PARAM_KEYS[t]
    for i = 1, #_LOCK_PARAMS do
      local nm = _LOCK_PARAMS[i]
      local fk = fullkeys[i]
      locked[nm] = is_param_locked(t, nm)
      local act = amap[fk] ~= nil
      lfo_on[fk] = act
      if act then fill_range_cache(fk) end
    end
    locked.lpf = is_param_locked(t, "cutoff")
    locked.hpf = is_param_locked(t, "hpf")
    C.pitch_rand = (pget(K.pitch_random_prob) or 0) ~= 0
    local smoothbass_mult = (pget(K.smoothbass) == 2) and 2.5 or 1
    local hl = C.harm_layers or {}
    local hn = 0
    local hch = false
    for hi = 1, 5 do
      local d = _HK.harm_def[hi]
      local amt = pget(K[d.key]) or 0
      if amt > 0.001 then
        hn = hn + 1
        local e = hl[hn] or {}
        local sm = d.sub and smoothbass_mult or 1
        local al = (amt < 1 and amt or 1) * _HK.harm_alpha
        if e.ratio ~= d.ratio or e.size_mult ~= sm or e.alpha ~= al then e.ratio, e.size_mult, e.alpha, hch = d.ratio, sm, al, true end
        hl[hn] = e
      end
    end
    if hch or hl.n ~= hn then C.harm_gen = (C.harm_gen or 0) + 1 end
    hl.n = hn
    C.harm_layers = hl
  end
end
local fast_percent, fast_db, fast_int
do
  local _PCT_CACHE, _INT_CACHE, _DB_CACHE = {}, {}, {}
  fast_percent = function(v) v = floor(v + 0.5) local s = _PCT_CACHE[v] if not s then s = v .. "%" _PCT_CACHE[v] = s end return s end
  fast_db = function(v) if v <= -40 then return "OFF" end v = floor(v + 0.5) local s = _DB_CACHE[v] if not s then s = v .. " dB" _DB_CACHE[v] = s end return s end
  fast_int = function(v) v = floor(v + 0.5) local s = _INT_CACHE[v] if not s then s = tostring(v) _INT_CACHE[v] = s end return s end
end
_HK.fq_cache = {}
_HK.fq = function(v) if v < 1000 then return fast_int(v) end local k = floor(v / 100 + 0.5) local c = _HK.fq_cache local s = c[k] if not s then s = string.format("%.1fk", k / 10) c[k] = s end return s end
local _VAL_TXT = {}
local function val_text(param, val, fmt, t, aux)
  local c = _VAL_TXT[param]
  if c and c.v == val and c.a == aux then return c.s end
  local s = fmt(val, t, aux)
  if c then c.v, c.a, c.s = val, aux, s else _VAL_TXT[param] = {v = val, a = aux, s = s} end
  return s
end
local _SPD_TXT = {{}, {}}
local function speed_text(t, s)
  local q = floor(s * 100 + (s >= 0 and 0.5 or -0.5))
  local c = _SPD_TXT[t]
  if c.v == q then return c.s end
  local str = format_speed(s)
  c.v, c.s = q, str
  return str
end
_HK.smear = function(acc, start_pos, end_pos, gsz, forward, lut, alpha)
  local dl = start_pos * BAR_W // 1
  local dr = -(-(end_pos * BAR_W) // 1) - 1
  if dr <= dl or gsz * BAR_W <= 1 then
    local v = _ENV_PEAK[lut] * alpha
    local px = (start_pos + end_pos) * 0.5 * BAR_W // 1 % BAR_W
    if v > acc[px] then acc[px] = v end
  else
    local inv_gsz = 1 / gsz
    local inv_bar_w = _HK.inv_bar_w
    local sp
    if forward then sp = ((dl + 0.5) * inv_bar_w - start_pos) * inv_gsz else sp = 1 - (((dl + 0.5) * inv_bar_w - start_pos) * inv_gsz) end
    local sp_dt = inv_gsz * inv_bar_w
    if not forward then sp_dt = -sp_dt end
    local N, NM, BW = _GLUT_N, _GLUT_NM, BAR_W
    local lo_v, hi_v = lut[0], lut[NM]
    for px_unwrapped = dl, dr do
      local idx = sp * N // 1
      local L = lut[idx]
      if L == nil then L = idx < 0 and lo_v or hi_v end
      L = L * alpha
      local px = px_unwrapped % BW
      if L > acc[px] then acc[px] = L end
      sp = sp + sp_dt
    end
  end
end
_HK.acc = {}
_HK.viz = {{gen = 0}, {gen = 0}}
_HK.profile = function(g, dur, spd_fwd, dir_mod, is_random_env, lut_default, hl)
  local acc, smear = _HK.acc, _HK.smear
  for i = 0, BAR_W - 1 do acc[i] = 0 end
  local pos = g.pos
  local base_w = g.size * g.pitch / dur
  local gsz = base_w < 1 and base_w or 1
  local forward = spd_fwd ~= (g.rv < dir_mod)
  local lut = is_random_env and (_ENV_LUT[g.rv * 4 // 1 + 1] or _ENV_LUT[1]) or lut_default
  if forward then smear(acc, pos, pos + gsz, gsz, true, lut, 1) else smear(acc, pos - gsz, pos, gsz, false, lut, 1) end
  if hl then
    for hi = 1, hl.n do
      local e = hl[hi]
      local hw = base_w * e.ratio * e.size_mult
      if hw > 1 then hw = 1 end
      if forward then smear(acc, pos, pos + hw, hw, true, lut, e.alpha) else smear(acc, pos - hw, pos, hw, false, lut, e.alpha) end
    end
  end
  local px, pv = g.px, g.pv
  if not px then px, pv = {}, {} g.px, g.pv = px, pv end
  local n = 0
  for i = 0, BAR_W - 1 do local v = acc[i] if v > 0 then n = n + 1 px[n] = i pv[n] = v end end
  g.pn = n
end
_HK.advance_grains = function(t, now)
  local grains = grain_positions[t]
  if not grains then return end
  local keep = 0
  for gi = 1, #grains do
    local g = grains[gi]
    local gsize = g.size
    local dlife = gsize < 0.15 and 0.15 or gsize
    local age = now - g.t
    if age > dlife then
      _grain_pool[#_grain_pool + 1] = g
    else
      keep = keep + 1
      grains[keep] = g
      g.lf = age / dlife
    end
  end
  for i = keep + 1, #grains do grains[i] = nil end
end
_HK.recycle_grains = function(grains) if not grains then return end for i = #grains, 1, -1 do _grain_pool[#_grain_pool + 1] = grains[i] grains[i] = nil end end
local function draw_grains(t, col)
  local grains = grain_positions[t]
  if not grains then return end
  local C = PARAM_CACHE.track[t]
  local dur = cached_buffer_durations[t]
  if not dur or dur <= 0 then return end
  local drawn = 0
  local spd_fwd = C.spd >= -0.01
  local dir_mod = C.dir_mod
  local env_sel = C.env_sel
  local vz = _HK.viz[t]
  if vz.dur ~= dur or vz.fwd ~= spd_fwd or vz.dm ~= dir_mod or vz.env ~= env_sel or vz.hg ~= C.harm_gen then
    vz.dur, vz.fwd, vz.dm, vz.env, vz.hg, vz.gen = dur, spd_fwd, dir_mod, env_sel, C.harm_gen, vz.gen + 1
  end
  local gen = vz.gen
  local is_random_env = env_sel == 5
  local lut_default = _ENV_LUT[env_sel] or _ENV_LUT[1]
  local lut_n = _GLUT_N
  local lut_nm = _GLUT_NM
  local harm_layers = C.harm_layers
  local profile = _HK.profile
  for gi = 1, #grains do
    local g = grains[gi]
    if drawn < 50 or not g.shown then
      drawn = drawn + 1
      g.shown = true
      if g.pg ~= gen then profile(g, dur, spd_fwd, dir_mod, is_random_env, lut_default, harm_layers) g.pg = gen end
      local fi = g.lf * lut_n // 1
      if fi > lut_nm then fi = lut_nm end
      local fade = _FADE_LUT[fi]
      local px, pv = g.px, g.pv
      for k = 1, g.pn do
        local i = px[k]
        local v = pv[k] * fade
        if v > col[i] then col[i] = v end
      end
    end
  end
end
local _PAN_COL = {}
_HK.draw_grain_pans = function(t, base_x)
  local grains = grain_positions[t]
  if not grains then return end
  local n = #grains
  if n == 0 then return end
  local slide = pan_indicator_x[t]
  local hi_x = base_x + 25
  local pc = _PAN_COL
  local origin = floor(base_x + slide + 0.5) - 1
  for k = 0, 27 do pc[k] = 0 end
  for gi = 1, n do
    local g = grains[gi]
    local lf = g.lf
    local lv = (24 * lf * (1 - lf) + 0.5) // 1
    if lv > 0 then
      local px = base_x + (g.pan + 1) * 12.5
      if px < base_x then px = base_x elseif px > hi_x then px = hi_x end
      local i0 = (px + slide + 0.5) // 1 - origin
      local i1 = i0
      if lf > 0.25 and lf < 0.75 then i0 = i0 - 1 i1 = i1 + 1 end
      for k = i0, i1 do if lv > pc[k] then pc[k] = lv end end
    end
  end
  local run_k, run_lv = 0, pc[0]
  for k = 1, 27 do
    local lv = pc[k]
    if lv ~= run_lv then
      if run_lv > 0 then R(run_lv, origin + run_k, 1, k - run_k, 1) end
      run_k, run_lv = k, lv
    end
  end
  if run_lv > 0 then R(run_lv, origin + run_k, 1, 28 - run_k, 1) end
end
local function grain_column(t)
  local gran = PARAM_CACHE.track[t].gran
  if gran and gran > 0 then
    local col = ctx.waveforms[0]
    for i = 0, BAR_W - 1 do col[i] = 0 end
    draw_grains(t, col)
    for i = 0, BAR_W - 1 do local v = col[i] if v > 0 then col[i] = -(-v // 1) end end
    return col
  end
  _HK.recycle_grains(grain_positions[t])
  return nil
end
local function draw_seek_bar_viz(t, x, mode, wf, active)
  local C = PARAM_CACHE.track[t]
  local loaded = C.loaded
  if mode == "speed" then
    local half_w = floor(BAR_W * 0.5)
    local cx = x + half_w
    local span = half_w - 1
    R(1, x, Y.seek, BAR_W, 1)
    if loaded then
      local off = floor(clamp(C.spd * 0.5, -1, 1) * span)
      if off >= 0 then R(LEVEL.dim, cx, Y.seek, off + 1, 1) else R(LEVEL.dim, cx + off, Y.seek, -off + 1, 1) end
      R(LEVEL.hi, cx + off, Y.seek - 1, 1, 2)
    end
    return
  end
  local animated_bar_w = floor(BAR_W * seek_bar_width)
  if wf ~= nil then
    local wmid = Y.seek - 4
    if wf then
      local col = #grain_positions[t] > 0 and grain_column(t) or nil
      local base = flash_level(t, 1)
      local run_x, run_lv, run_hh = 0, -1, 0
      for i = 0, animated_bar_w - 1 do
        local lv = base
        if col then local g = col[i] if g > lv then lv = g end end
        local hh = wf[i]
        if lv ~= run_lv or hh ~= run_hh then
          if run_lv > 0 then R(run_lv, x + run_x, wmid - run_hh, i - run_x, run_hh + run_hh + 1) end
          run_x, run_lv, run_hh = i, lv, hh
        end
      end
      if run_lv > 0 then R(run_lv, x + run_x, wmid - run_hh, animated_bar_w - run_x, run_hh + run_hh + 1) end
    elseif animated_bar_w > 0 then
      T(flash_level(t, active and LEVEL.hi or LEVEL.val), x, wmid + 3, "empty")
    end
    if loaded and animated_bar_w > 0 then
      local ph = floor(osc_positions[t] * animated_bar_w)
      if ph >= BAR_W then ph = BAR_W - 1 end
      if active then
        R(LEVEL.hi, x + ph, wmid - 4, 1, 9)
        R(LEVEL.hi, x + ph - 1, wmid - 4, 3, 1)
        R(LEVEL.hi, x + ph - 1, wmid + 4, 3, 1)
      else
        for dy = wmid - 4, wmid + 4, 2 do P(LEVEL.hi, x + ph, dy) end
      end
      if C.in_ == 1 then
        local rh = floor(rec_positions[t] * animated_bar_w)
        if rh >= BAR_W then rh = BAR_W - 1 end
        R(LEVEL.hi, x + rh, wmid - 4, 2, 9)
      end
    end
    return
  end
  if C.dir_ ~= 1 then R(1, x, Y.seek, animated_bar_w, 1) end
  local col = grain_column(t)
  if col then
    local sy = Y.seek
    local run_x, run_lv = 0, col[0]
    for i = 1, BAR_W - 1 do
      local lv = col[i]
      if lv ~= run_lv then
        if run_lv > 0 then R(run_lv, x + run_x, sy, i - run_x, 1) end
        run_x, run_lv = i, lv
      end
    end
    if run_lv > 0 then R(run_lv, x + run_x, sy, BAR_W - run_x, 1) end
  end
  if loaded and C.dir_ ~= 1 then R(LEVEL.hi, x + floor(osc_positions[t] * animated_bar_w), Y.seek - 1, 1, 2) end
end

local OFFS, TXP = {0, 0}, {0, 0}

function redraw()
  if not installer:ready() or installer:pending() then installer:redraw(); return end
  if presets.draw_menu() then return end
  if _G.preset_loading then screen.clear(); screen.level(15); screen.move(64, 32); screen.text_center("Loading..."); screen.update(); return end
  refresh_redraw_cache()
  local now = util.time()
  _HK.advance_grains(1, now)
  _HK.advance_grains(2, now)
  local cur_mode = current_mode
  local cur_filter = current_filter_mode
  local upper = UPPER[cur_mode]
  local mode = upper and "seek" or cur_mode
  local active = not upper
  screen.clear()
  clear_ops()
  local left_slide = -anim_offset_x
  local hint = hlp.hint and hlp.hint_text(now)
  OFFS[1], OFFS[2] = -anim_offset_x, anim_offset_x
  TXP[1], TXP[2] = TRACK_X[1] + OFFS[1], TRACK_X[2] + OFFS[2]
  for ri = 1, #param_rows do local row = param_rows[ri]
    local name = row.name
    local hi = cur_mode == row.mode
    local y = row.y
    T(LEVEL.hi, 6 + left_slide, y, hi and (hint or row.label_upper) or row.label)
    local fmt = FORMAT[row.fmt_key]
    local density_synced = (name == "density" and clocksync.grain_synced())
    local is_size_row = (name == "size")
    for t = 1,2 do
      local x = TXP[t]
      local param = row.params[t]
      local C = PARAM_CACHE.track[t]
      if is_size_row and PARAM_CACHE.link then draw_size_link(x, y) end
      if C.locked[name] then draw_lock(x, y - 1) end
      local val = pget(param)
      if is_size_row then local cap = arp.max_size_ms(t) if val > cap then val = cap end end
      local sync_label = density_synced and clocksync.grain_division_label(t) or nil
      local txt = sync_label or (fmt and val_text(param, val, fmt, t, row.st and C.pitch_rand or nil) or params:string(param))
      T(flash_level(t, hi and LEVEL.hi or LEVEL.val), x, y, txt)
      if name ~= "spread" and C.lfo_on[param] then
        if sync_label then
          R(LEVEL.dim + 2, x, y + 1, clamp(floor(clocksync.grain_division_norm(t) * BAR_W), 0, BAR_W), 1)
        else
          local rc = _LFO_RANGE_CACHE[param] or fill_range_cache(param)
          local a, b, fb = rc[1], rc[2], rc[3]
          R(LEVEL.dim + 2, x, y + 1, clamp(floor(((val - a) / (b - a)) * BAR_W), 0, BAR_W), 1)
          if val > b and fb > b then R(LEVEL.hi, x, y + 1, max(1, floor(sqrt(clamp((val - b) / (fb - b), 0, 1)) * BAR_W)), 1) end
        end
      end
    end
  end
  local disp_mode = (mode == "lpf" or mode == "hpf") and cur_filter or mode
  local y_bot = Y.bottom
  T(LEVEL.hi, 6 + left_slide, y_bot + 1, active and (hint or LABEL_UPPER_CACHE[disp_mode]) or LABEL_CACHE[disp_mode])
  for t = 1,2 do
    local x = TXP[t]
    local C = PARAM_CACHE.track[t]
    local vL = active and LEVEL.hi or LEVEL.val
    local wf
    if mode == "seek" and C.dir_ ~= 1 then wf = (audio_active[t] or C.in_ == 1) and ctx.waveforms[t] end
    if C.locked[(mode == "lpf" or mode == "hpf") and cur_filter or mode] then draw_lock(x, y_bot) end
    if mode == "seek" then
      if wf == nil then
        local txt
        if C.in_ == 1 then txt = "live" elseif C.dir_ == 1 then txt = "direct" else txt = fast_percent(osc_positions[t] * 100) end
        T(flash_level(t, vL), x, y_bot + 1, txt)
      end
    elseif mode == "speed" then
      T(flash_level(t, LEVEL.hi), x, y_bot + 1, speed_text(t, C.spd))
    elseif mode == "pan" then
      local txt = (abs(C.pan) < 0.5) and "0%" or fast_percent(C.pan)
      T(flash_level(t, LEVEL.hi), x, y_bot + 1, txt)
    elseif mode == "eq" then
      local K = TRACK_KEYS[t]
      local low, mid, high, tilt = pget(K.eq_low), pget(K.eq_mid), pget(K.eq_high), pget(K.eq_tilt)
      local cache = _HK.eq_cache[t]
      local yv = cache.y
      if cache.lo ~= low or cache.mi ~= mid or cache.hi ~= high or cache.ti ~= tilt then
        cache.lo, cache.mi, cache.hi, cache.ti = low, mid, high, tilt
        local EQ = _HK.eq
        local zy, amp, elo, ehi, emi, eti = EQ.zy, EQ.amp, EQ.low, EQ.high, EQ.mid, EQ.tilt
        for c = 0, BAR_W - 1 do
          local dy = (low * elo[c] + high * ehi[c] + mid * emi[c] + tilt * eti[c]) * amp
          if dy > amp then dy = amp elseif dy < -amp then dy = -amp end
          yv[c] = zy - floor(dy + 0.5)
        end
        _HK.rle(cache)
      end
      R(LEVEL.val, x, _HK.eq.zy, BAR_W, 1)
      local segs, ns = cache.segs, cache.nsegs
      for j = 1, ns, 4 do R(vL, x + segs[j], segs[j+1], segs[j+2], segs[j+3]) end
    else
      local lo = cur_filter == "lpf"
      local fv = lo and C.cut or C.hpf
      local qv = lo and C.q or 0
      local cache = _HK.filt_cache[t]
      local yv = cache.y
      if cache.fv ~= fv or cache.q ~= qv or cache.lo ~= lo then
        cache.fv, cache.q, cache.lo = fv, qv, lo
        local ln = log(fv / 20) * _LOG_FILTER_INV
        if ln < 0 then ln = 0 elseif ln > 1 then ln = 1 end
        local knee = floor(ln * (BAR_W - 1) + 0.5)
        local SH = _HK.filt_sh
        local R2 = _HK.filt_r2
        local res = sqrt(qv)
        local pass = 1 - res * 0.34
        local pt = pass / 1.14
        local iq = pt * pt
        local b = res * 2.2
        if b > 1 then b = 1 end
        for c = 0, BAR_W - 1 do
          local mag
          if not lo then mag = SH[knee - c]
          elseif b <= 0 then mag = pass * SH[c - knee]
          elseif b >= 1 then local r2 = R2[c - knee] local m = 1 - r2 mag = pass / sqrt(m * m + r2 * iq)
          else local s = pass * SH[c - knee] local r2 = R2[c - knee] local m = 1 - r2 mag = s + b * (pass / sqrt(m * m + r2 * iq) - s) end
          if mag > 1 then mag = 1 end
          yv[c] = Y.seek - floor(mag * 8 + 0.5)
        end
        _HK.rle(cache)
      end
      local clvl = flash_level(t, 1)
      local segs, ns = cache.segs, cache.nsegs
      for j = 1, ns, 4 do R(clvl, x + segs[j], segs[j+1], segs[j+2], segs[j+3]) end
      T(LEVEL.hi, x + 15, y_bot + 1, _HK.fq(fv), "center")
    end
    if mode == "seek" or mode == "speed" then
      if C.loaded and C.dir_ ~= 1 and not wf then
        local icon
        if abs(C.spd) < 0.01 then icon = "⏸" elseif C.spd > 0 then icon = "▶" else icon = "◀" end
        T(vL, (t == 1 and 77 or 118) + OFFS[t], y_bot + 1, icon)
      end
      draw_seek_bar_viz(t, x, mode, wf, active)
    end
  end
  for t = 1,2 do
    local offset_x = OFFS[t]
    local current_vol_x = VOL_X[t] + offset_x
    local current_pan_x = PAN_X[t] + offset_x
    local C = PARAM_CACHE.track[t]
    local h = (C.vol + 70) * _VOL_LINLIN_MUL
    if h < 0 then h = 0 elseif h > 64 then h = 64 end
    R(LEVEL.dim - 3, current_vol_x, 64 - h + volume_bar_y[t], 2, h)
    local loaded = C.loaded
    local peak_amp = loaded and max(voice_peak_amplitudes[t].l, voice_peak_amplitudes[t].r) or 0
    if peak_amp > 0 then
      local peak_db = log(peak_amp) * 9
      local pre_fader_db = peak_db - C.vol
      local pre_fader_ratio = (pre_fader_db + 70) / 70
      if pre_fader_ratio < 0 then pre_fader_ratio = 0 elseif pre_fader_ratio > 1 then pre_fader_ratio = 1 end
      local peak_h = pre_fader_ratio * h
      if peak_h > 0 then R(LEVEL.hi - 1, current_vol_x, 64 - peak_h + volume_bar_y[t], 2, peak_h) end
    end
    if loaded then
      _HK.draw_grain_pans(t, current_pan_x)
      local pan_pos = util.linlin(-100, 100, current_pan_x, current_pan_x + 25, C.pan)
      R(LEVEL.hi, floor(pan_pos + pan_indicator_x[t] + 0.5), 0, 1, 3)
    end
  end
  if PARAM_CACHE.dry then for x = 7,15,4 do P(LEVEL.hi, x, 0) end end
  if PARAM_CACHE.sym then local sc = SYM_CACHE; for i = 1,62,2 do P(sc[i + 1], 85, sc[i]) end end
  if PARAM_CACHE.evo then local t2 = now * 4; for i = 0,2 do P(floor(8 + 7 * sin(t2 - i * 0.8)), (i * 2) + 6, 63) end end
  local bp = hlp.bounce_pending
  if bp then
    local bx = 7 + left_slide
    local tw = font.plot_text_cached(P, bx, 0, "BOUNCING", LEVEL.dim) - bx - 1
    local pw = floor(min((now - bp.t) / bp.len, 1) * tw)
    R(1, bx, 3, tw, 1)
    if pw > 0 then R(LEVEL.hi, bx, 3, pw, 1) end
  elseif hlp.bounce_done_time and (now - hlp.bounce_done_time) < 2 then
    font.plot_text_cached(P, 7 + left_slide, 0, "BOUNCED", LEVEL.hi)
  else
    font.draw_fx_status_bucketed(P)
    if morph.scene_mode == "on" then
      R(1, 7 + left_slide, 4, 22, 1)
      if morph.amount > 0 then R(LEVEL.hi, 7 + left_slide, 4, util.linlin(0, 100, 0, 22, morph.amount), 1) end
    end
  end
  local pop, sub = nil, nil
  if fx_popup.time and (now - fx_popup.time) < FX_POPUP_DURATION then
    sub = fx_popup.sub
    if fx_popup._src ~= fx_popup.label or fx_popup._val ~= fx_popup.value or fx_popup._sub ~= sub then
      local txt = fx_popup.value and (fx_popup.label .. ": " .. ((fx_popup.label == "reverb") and fast_db(fx_popup.value) or fast_percent(fx_popup.value))) or fx_popup.label
      fx_popup._src, fx_popup._val, fx_popup._sub, fx_popup._txt, fx_popup._w = fx_popup.label, fx_popup.value, sub, txt, max(#txt, sub and #sub or 0) * 5 + 8
    end
    pop = fx_popup._txt
  elseif hlp.saving and now < hlp.saving then
    pop = "SAVING..."
    fx_popup._w = 56
  end
  flush()
  if pop then
    local w = fx_popup._w
    local x, y, h = 64 - floor(w * 0.5), sub and 22 or 26, sub and 20 or 12
    screen.level(0) screen.rect(x - 1, y - 1, w + 2, h + 2) screen.fill()
    screen.level(1) screen.rect(x, y, w, h) screen.fill()
    screen.level(LEVEL.hi)
    screen.move(64, y + 8) screen.text_center(pop)
    if sub then screen.move(64, y + 16) screen.text_center(sub) end
  end
  screen.update()
end

local function push_grain(vid, pos, size, rv, pitch, pan, now) if audio_active[vid] or live_state[vid].direct then local b = grain_positions[vid] local n = #b if n < 64 then local np = #_grain_pool local g if np > 0 then g = _grain_pool[np] _grain_pool[np] = nil else g = {} end g.pos, g.size, g.t, g.rv, g.pitch, g.pan, g.shown, g.pg = pos, size, now, rv or 0.5, pitch or 1, pan or 0, false, false b[n+1] = g end end end
local osc_handlers = {
    ["/twins/rec_pos"] = function(args)
        local vid, pos, peak = args[1] + 1, args[2], args[3]
        if live_state[vid].input then
            rec_positions[vid] = pos
            if peak then
                local lw = ctx.live_wf
                local raw = lw.raw[vid]
                local col = floor(pos * BAR_W)
                if col >= BAR_W then col = BAR_W - 1 end
                local last = lw.col[vid]
                if col ~= last then
                    local c = last >= 0 and (last + 1) % BAR_W or col
                    while true do raw[c] = 0 if c == col then break end c = (c + 1) % BAR_W end
                    lw.col[vid] = col
                end
                local reset_happened = col ~= last
                if peak > raw[col] then raw[col] = peak end
                local nm = lw.norm[vid]
                local mx = lw.max[vid]
                if reset_happened or raw[col] > mx then
                    if reset_happened then
                        mx = 0
                        for c = 0, BAR_W - 1 do local v = raw[c] if v > mx then mx = v end end
                    else
                        mx = raw[col]
                    end
                    lw.max[vid] = mx
                    local s = mx > 0 and 4 / mx or 0
                    for c = 0, BAR_W - 1 do nm[c] = floor(raw[c] * s + 0.5) end
                else
                    local s = mx > 0 and 4 / mx or 0
                    nm[col] = floor(raw[col] * s + 0.5)
                end
            end
        end
    end,
    ["/twins/voice_peak"] = function(args)
        local voice, peakL, peakR = args[1] + 1, args[2], args[3]
        voice_peak_amplitudes[voice].l = abs(peakL)
        voice_peak_amplitudes[voice].r = abs(peakR)
    end,
    ["/twins/delay_duck"] = function(args)
        font.set_delay_duck(args[1])
    end,
    ["/twins/save_complete"] = function()
        hlp.saving = nil
        hlp.audio_dirty()
        hlp.popup("SAVED TO TAPE")
    end,
    ["/twins/bounce_done"] = hlp.finish_bounce,
    ["/twins/duration"] = function(args) blim.on_duration(args[1] + 1, args[2]) end,
    ["/twins/voice_state"] = function(args)
    local vid, pos = args[1] + 1, args[2]
    local va = voice_peak_amplitudes[vid]
    va.l, va.r = abs(args[3]), abs(args[4])
    local gc = args[5]
    if gc and gc ~= ctx.grain_seq[vid] then
        ctx.grain_seq[vid] = gc
        push_grain(vid, args[6], args[7], args[8], args[9], args[10], util.time())
    end
    if is_voice_loaded(vid) then
        osc_positions[vid] = pos
        local pct = pos * 100
        if abs(pct - ctx.seek_pushed[vid]) >= 0.34 then
            ctx.seek_pushed[vid] = pct
            pset(_HK.seek[vid], pct, true)
        end
    end
    end,
    ["/twins/waveform"] = function(args)
    local vid = args[1] + 1
    local wf, mx = {}, 0
    for c = 0, BAR_W - 1 do local v = args[c + 2] or 0 wf[c] = v if v > mx then mx = v end end
    local s = mx > 0 and 4 / mx or 0
    for c = 0, BAR_W - 1 do wf[c] = floor(wf[c] * s + 0.5) end
    ctx.waveforms[vid] = wf
    end}
local function setup_osc() osc.event = function(path, args) local h = osc_handlers[path] if h then h(args) end end end

local function snapshot_scene_data()
    local sd = morph.scene_data
    local s1, s2 = sd[1], sd[2]
    return {[1] = {s1 and s1[1], s1 and s1[2]},
            [2] = {s2 and s2[1], s2 and s2[2]}}
end

local function setup_undo()
    undo.init{
        lfo = lfo,
        capture_extra = function()
            return {
                morph_amount = params:get("morph_amount"),
                scene_mode   = params:get("scene_mode"),
                scene_data   = snapshot_scene_data(),
                temp_scene   = utils.deep_copy(morph.temp_scene),
                arp          = arp.snapshot()}
        end,
        restore_extra = function(s)
            morph.scene_data = utils.deep_copy(s.scene_data)
            morph.temp_scene = utils.deep_copy(s.temp_scene)
            params:set("scene_mode", s.scene_mode, true)
            morph.scene_mode = (s.scene_mode == 2) and "on" or "off"
            params:set("morph_amount", s.morph_amount, true)
            morph.sync_amount(s.morph_amount)
            if s.arp then arp.restore(s.arp) end
        end,
        on_before_restore = function()
            for i = 1, 2 do stop_metro_safe(randomize_metro[i]) end
            randpara.stop_interpolation()
        end,
        on_after_restore = randpara.reset_evolution_centers,
        on_action = hlp.popup,
        exclude = ctx.sys}
end

function init()
    if not installer:ready() then boot_clock = clock.run(function() while true do redraw() clock.sleep(1 / 10) end end) do return end end
    hlp.sysrev = {}
    for _, k in ipairs({"rev_eng_input", "rev_pre_delay", "rev_lf_fc", "rev_low_time", "rev_mid_time", "rev_hf_damping", "reverb", "monitor_level"}) do if params.lookup[k] then hlp.sysrev[#hlp.sysrev + 1] = {k, params:get(k)} end end
    params:set('reverb', 1)
    params:set('monitor_level', -math.huge)
    setup_ui_metro()
    setup_params()
    setup_undo()
    setup_osc()
    morph.init(lfo, clocksync)
    clocksync.init({lfo = lfo, set_density = clocksync_set_density})
    arp.init({scale_utils = SU, is_voice_active = is_voice_loaded, checkpoint = undo.checkpoint})
    font.init_fx_cache()
    init_longpress_checker()
    for i = 1, 2 do params:set(i.."sample", _path.audio, true) end
    for i = 1, 2 do engine.pause_voice(i) end
    clock.transport.start = transport_start
    clock.transport.stop  = transport_stop
    clock.transport.reset = transport_start
    morph.initialize_scenes_with_current_params()
    hlp.scan_audio()
    hlp.check_co = clock.run(function() clock.sleep(10) hlp.check_co = nil installer:check() end)
end

function cleanup()
    clock.tempo_change_handler = nil
    flush_finalize()
    if boot_clock then pcall(clock.cancel, boot_clock) boot_clock = nil end
    hlp.dead = true
    if hlp.check_co then pcall(clock.cancel, hlp.check_co) hlp.check_co = nil end
    stop_metro_safe(ui_metro)
    stop_metro_safe(longpress_metro)
    stop_metro_safe(finalize_metro)
    for i = 1, 2 do stop_metro_safe(randomize_metro[i]) end
    lfo.cleanup()
    clock.transport.start = nil
    clock.transport.stop  = nil
    clock.transport.reset = nil
    clocksync.cleanup()
    arp.cleanup()
    midi_input.cleanup()
    randpara.cleanup()
    for _, kv in ipairs(hlp.sysrev or {}) do params:set(kv[1], kv[2]) end
    osc.event = nil
end