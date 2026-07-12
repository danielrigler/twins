--
--
--   __ __|         _)          
--      | \ \  \  / |  \ |  (_< 
--      |  \_/\_/ _| _| _| __/ 
--            by: @dddstudio                       
-- 
--                          
--                           v0.73
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

installer_ = include("lib/installer/installer")
installer = installer_:new{requirements = {"AnalogTape", "AnalogChew", "AnalogLoss", "AnalogDegrade"}, zip = "https://github.com/schollz/portedplugins/releases/download/v0.4.6/PortedPlugins-RaspberryPi.zip"}
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
local ctx = {lfo = lfo, arp = arp, clocksync = clocksync, waveforms = {[0] = {}}}
for _, m in ipairs({presets, macro, drymode, font, lfo, arp}) do m.set_context(ctx) end
local randomize_metro = { [1] = nil, [2] = nil }
local active_clocks = {}
local key_state = {} for n = 1, 3 do key_state[n] = false end
local current_mode = "seek"
local current_filter_mode = "lpf"
local tap_times = {}
local initial_monitor_level, initial_reverb_onoff;
local audio_active = {[1] = false, [2] = false}
local steps = 20
local mode_list = {"spread","pitch","density","size","jitter","lpf","pan","speed","seek"}
local mode_indices = {} for i,v in ipairs(mode_list) do mode_indices[v] = i end
local MK = lfo.keys
local key_gesture = nil
local showing_save_message = false
local fx_popup = {label = nil, value = nil, time = nil}
local FX_POPUP_DURATION = 1
local longpress_metro = nil
local grain_positions = {[1] = {}, [2] = {}}
local rec_positions = {[1] = 0, [2] = 0}
ctx.live_wf = {raw = {[1] = {}, [2] = {}}, norm = {[1] = {}, [2] = {}}, col = {-1, -1}, max = {0, 0}}
function ctx.live_wf.reset(i) local raw, nm = ctx.live_wf.raw[i], ctx.live_wf.norm[i] for c = 0, 29 do raw[c] = 0 nm[c] = 0 end ctx.live_wf.col[i] = -1 ctx.live_wf.max[i] = 0 end
ctx.live_wf.reset(1) ctx.live_wf.reset(2)
local cached_buffer_durations = {[1] = 1, [2] = 1}
local voice_peak_amplitudes = {[1] = {l = 0, r = 0}, [2] = {l = 0, r = 0}}
local link_base = {[1]={pitch=nil,size=nil,density=nil,product=nil}, [2]={pitch=nil,size=nil,density=nil,product=nil}}
local ui_metro = nil
local floor, abs, log, max, min, sqrt, ceil, sin = math.floor, math.abs, math.log, math.max, math.min, math.sqrt, math.ceil, math.sin
local clamp = util.clamp
local _param_obj = {}
local function _pobj(id)
    local o = _param_obj[id]
    if o == nil then
        local idx = params.lookup and params.lookup[id]
        if not idx then return nil end
        o = params.params[idx]
        _param_obj[id] = o
    end
    return o
end
local function pget(id) local o = _pobj(id) if o then return o:get() end return nil end
local function pset(id, v, silent) local o = _pobj(id) if o then o:set(v, silent) end end
local function nrev_set_mix(db)
    if db <= -40 then
        params:set("reverb", 1)
        return
    end
    params:set("reverb", 2)
    params:set("rev_eng_input", db)
end
local TRACK_KEYS = {}
for t = 1, 2 do
    TRACK_KEYS[t] = {
        volume = t.."volume", pan = t.."pan", speed = t.."speed",
        cutoff = t.."cutoff", hpf = t.."hpf", size = t.."size",
        granular_gain = t.."granular_gain", live_input = t.."live_input",
        live_direct = t.."live_direct",
        direction_mod = t.."direction_mod", env_select = t.."env_select",
        pitch_random_prob = t.."pitch_random_prob"}
end
local _lock_key_cache = {}
local _HK = {
    size = {"1size", "2size"}, den = {"1density", "2density"}, pitch = {"1pitch", "2pitch"},
    vol = {"1volume", "2volume"}, seek = {"1seek", "2seek"},
    reso_degs = {0, 7, 12, 19, 24},
    rand_names = {"speed", "jitter", "size", "density", "spread", "pitch", "seek"},
    TAP_TIMEOUT = 2, LONGPRESS = 1, UI_FPS = 60,
    audio_exts = {[".wav"]=true,[".aif"]=true,[".aiff"]=true,[".flac"]=true}}
local function lock_key(track_num, param)
    local tk = _lock_key_cache[track_num]
    if not tk then tk = {} _lock_key_cache[track_num] = tk end
    local k = tk[param]
    if not k then k = track_num .. "lock_" .. param tk[param] = k end
    return k
end
local _grain_pool = {}
local invalidate_lfo_cache = lfo.invalidate_lfo_param_cache
local function do_capture_temp_scene() morph.capture_to_temp_scene(lfo.get_active_param_map()) end
local function combo_longpress_fire()
    if current_mode == "lpf" or current_mode == "hpf" then
        current_filter_mode = current_filter_mode == "lpf" and "hpf" or "lpf"
    else
        undo.checkpoint()
        lfo.assign_to_current_row(current_mode, current_filter_mode)
        invalidate_lfo_cache()
    end
end
local param_modes = {
    speed = {param = "speed", delta = 1, engine = true, has_lock = true},
    seek = {param = "seek", delta = 1, engine = true, has_lock = true},
    pan = {param = "pan", delta = 5, engine = true, has_lock = true, invert = true},
    lpf = {param = "cutoff", delta = 1, engine = true, has_lock = false},
    hpf = {param = "hpf", delta = 1, engine = true, has_lock = false},
    jitter = {param = "jitter", delta = 2, engine = true, has_lock = true, y = 11, label = "jitter:"},
    size = {param = "size", delta = 2, engine = true, has_lock = true, y = 21, label = "size:"},
    density = {param = "density", delta = 2, engine = true, has_lock = true, y = 31, label = "density:", hz = true},
    pitch = {param = "pitch", delta = 1, engine = true, has_lock = true, y = 41, label = "pitch:", st = true},
    spread = {param = "spread", delta = 2, engine = true, has_lock = true, y = 51, label = "spread:"}}
local param_rows = {} for mode, config in pairs(param_modes) do config.pkeys = {"1" .. config.param, "2" .. config.param} if config.y then local lbl = config.label local nm = lbl:match("%a+") table.insert(param_rows, {y = config.y, label = lbl, label_upper = lbl:upper(), name = nm, mode = mode, params = config.pkeys, hz = config.hz, st = config.st, fmt_key = config.hz and "hz" or config.st and "st" or nm}) end end table.sort(param_rows, function(a, b) return a.y < b.y end)
local LIMITS = {size={min=20,max=4999},density={min=0.1,max=50},pitch={min=-48,max=48}}
local SU = lfo.scale_utils
local audio_files_cache = nil
local anim_offset_x = 128 local animation_complete = false local animation_start_time = nil
local pan_indicator_x = {[1] = -80, [2] = 80} local pan_indicators_visible = false local pan_slide_start_time = nil
local volume_bar_y = {[1] = 120, [2] = 120} local volume_bars_visible = false
local seek_bar_width = 0 local seek_bars_visible = false
local randomize_flash = {[1] = 0, [2] = 0, held = {false, false}, midi = {0, 0}}
local FLASH_INTENSITY = 12
local FLASH_DECAY = 0.9
local function flash_level(track, base_level) local f = randomize_flash[track] local m = randomize_flash.held[track] and 1 or randomize_flash.midi[track] if m > f then f = m end if f <= 0.001 then return base_level end return min(base_level + floor(f * FLASH_INTENSITY), 15) end
local random_float = utils.random_float
local stop_metro_safe = utils.stop_metro_safe
function is_voice_loaded(i) return audio_active[i] or params:get(i.."live_input") == 1 or params:get(i.."live_direct") == 1 end
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
local function tracked_clock_run(func) local co = clock.run(func) table.insert(active_clocks, co) return co end
local function cancel_all_clocks() for i = #active_clocks, 1, -1 do local co = active_clocks[i] if co then pcall(function() clock.cancel(co) end) end end active_clocks = {} end
local function is_param_locked(track_num, param) return pget(lock_key(track_num, param)) == 2 end
local function is_lfo_active_for_param(param_name) local idx = lfo.get_lfo_for_param(param_name) return idx ~= nil, idx end
local hlp = {}
hlp.link_suppress_size = false
hlp.link_last_hz = {}
function hlp.apply_lfo_or_set(full_param, val)
    local active, idx = is_lfo_active_for_param(full_param)
    if not active then params:set(full_param, val) return end
    local lo, hi = lfo.get_parameter_range(full_param)
    if lo and hi and hi > lo then
        local depth = pget(MK.depth[idx])
        local offset = clamp((val - lo) / (hi - lo) * 2 - 1, depth * 0.01 - 1, 1 - depth * 0.01)
        pset(MK.offset[idx], offset)
        lfo[idx].offset = offset
    end
end
function hlp.apply_linked_density(track, target_den)
    local idx = clocksync.div_index_for_density(target_den)
    if not idx then return end
    local active, li = is_lfo_active_for_param(_HK.den[track])
    if active then
        local depth = pget(MK.depth[li])
        local center = clocksync.div_index_to_norm(idx) * 2 - 1
        local offset = clamp(center, depth * 0.01 - 1, 1 - depth * 0.01)
        pset(MK.offset[li], offset)
        lfo[li].offset = offset
    else
        hlp.link_suppress_size = true
        clocksync.set_grain_div_index(track, idx)
        hlp.link_suppress_size = false
    end
end
function hlp.ensure_link_base(track)
    local lb = link_base[track]
    if not (lb.pitch and lb.size and lb.density and lb.product) then
        lb.pitch   = params:get(_HK.pitch[track])
        lb.size    = params:get(_HK.size[track])
        lb.density = (clocksync.grain_synced() and clocksync.grain_density(track)) or params:get(_HK.den[track])
        lb.product = lb.size * lb.density
    end
    return lb
end
local RESO_RATIOS = {}
for i, d in ipairs(_HK.reso_degs) do RESO_RATIOS[i] = 2 ^ (d / 12) end
function hlp.update_resonator()
    if (pget("resonator_mix") or 0) <= 0 then return end
    local f = 440 * 2 ^ ((params:get("resonator_root") - 69) / 12)
    engine.resonator_freqs(
        f * RESO_RATIOS[1], f * RESO_RATIOS[2],
        f * RESO_RATIOS[3], f * RESO_RATIOS[4],
        f * RESO_RATIOS[5])
end
local function update_pan_positioning() if _G.preset_loading then return end; local l1,l2=audio_active[1],audio_active[2]; local function ok(v,id) return v and not is_param_locked(id,"pan") and not is_lfo_active_for_param(id.."pan") end; if l1 and l2 then if ok(l1,1) then params:set("1pan",-25) end; if ok(l2,2) then params:set("2pan",25) end else if ok(l1,1) then params:set("1pan",0) end; if ok(l2,2) then params:set("2pan",0) end end end

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
            if randomize_flash[i] > 0.001 and not randomize_flash.held[i] then randomize_flash[i] = randomize_flash[i] * FLASH_DECAY end
            if randomize_flash.midi[i] > 0.001 and not randomize_flash.held[i] then randomize_flash.midi[i] = randomize_flash.midi[i] * FLASH_DECAY end
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
    local base_param = param_name:sub(2)
    if only_self then
        local is_active, lfo_index = is_lfo_active_for_param(param_name)
        if is_active then params:set(MK.lfo[lfo_index], 1) invalidate_lfo_cache() end
    else
        local did_disable = false
        for track = 1, 2 do
            local full_param = track .. base_param
            local is_active, lfo_index = is_lfo_active_for_param(full_param)
            if is_active then params:set(MK.lfo[lfo_index], 1) did_disable = true end
        end
        if did_disable then invalidate_lfo_cache() end
    end
end

local function get_audio_duration(filepath)
    if not filepath or not util.file_exists(filepath) then return nil end
    local _, samples, rate = audio.file_info(filepath)
    if samples and rate and rate > 0 then return samples / rate end
    return nil
end

local blim = {}
function blim.apply(i, dur)
  if not dur or dur <= 0 then return false end
  cached_buffer_durations[i] = dur
  local ms = dur * 1000
  local mj = math.min(ms, 99999)
  params:set(i.."max_jitter", mj)
  params:set(i.."min_jitter", math.min(params:get(i.."min_jitter") or 0, mj))
  local mz = math.min(ms, 999)
  params:set(i.."max_size", mz)
  if (params:get(i.."min_size") or 20) > mz then
    params:set(i.."min_size", mz)
  end

  return true
end
function blim.load(i, f, rand_jitter)
    local dur = get_audio_duration(f); if not blim.apply(i, dur) then return end
    if rand_jitter then local jp = i.."jitter"; disable_lfos_for_param(jp); local up = math.random() < 0.75 and min(500, dur * 1000) or dur * 1000; params:set(jp, clamp(math.random() * up, 0, 99999)) end
end

local function scan_audio_files(dir, files)
    files = files or {}
    for _, entry in ipairs(util.scandir(dir)) do
        local path = dir .. entry
        if entry:sub(-1) == "/" then scan_audio_files(path, files)
        elseif _HK.audio_exts[path:lower():match("^.+(%..+)$") or ""] then files[#files+1] = path end
    end
    return files
end

local function set_track_sample(track_num, file)
    if params:get(track_num .. "live_input") == 1 then return false end
    if params:get(track_num .. "sample") ~= file then params:set(track_num .. "sample", file) end
    return true
end

local function set_sample_live(i) params:set(i.."sample", _path.tape.."live!") end

local function load_random_tape_file(track_num)
    if not audio_files_cache then audio_files_cache = scan_audio_files(_path.tape) end
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

local BOUNCE_DIR = _path.tape .. "twins/"

function hlp.start_bounce()
    local b = hlp.bounce_pending
    if b and (util.time() - b.t) < (b.len + 5) then return end
    local inplace = params:get("bounce_mode") == 2
    local mode = inplace and 2 or params:get("bounce_source") - 1
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
    audio_files_cache = nil
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

local function delete_unused_bounces()
    local used_paths = {}
    local PRESETS_PATH = _path.data .. "twins"
    for i = 1, 2 do
        local sample = params:get(i .. "sample")
        if sample and sample ~= "" and sample ~= "-" and sample ~= "none" and sample ~= (_path.tape .. "live!") and util.file_exists(sample) then
            used_paths[sample] = true
        end
    end
    local preset_names = presets.list_presets()
    for _, name in ipairs(preset_names) do
        local path = PRESETS_PATH .. "/" .. name .. ".lua"
        if util.file_exists(path) then
            local chunk, err = loadfile(path)
            if chunk then
                local ok, data = pcall(chunk)
                if ok and type(data) == "table" and data.params then
                    for i = 1, 2 do
                        local sample = data.params[i .. "sample"]
                        if sample and sample ~= "" and sample ~= "-" and sample ~= "none" and sample ~= (_path.tape .. "live!") and util.file_exists(sample) then
                            used_paths[sample] = true
                        end
                    end
                end
            end
        end
    end
    local deleted = 0
    if util.file_exists(BOUNCE_DIR) then
        local files = util.scandir(BOUNCE_DIR)
        for _, f in ipairs(files) do
            if f:match("%.wav$") then
                local full_path = BOUNCE_DIR .. f
                if util.file_exists(full_path) and not used_paths[full_path] then
                    os.remove(full_path)
                    deleted = deleted + 1
                end
            end
        end
    end
    audio_files_cache = nil
    fx_popup.label = "Deleted " .. deleted .. " files"
    fx_popup.value = nil
    fx_popup.time = util.time()
end

local function register_tap()
    local now = util.time()
    if #tap_times > 0 and (now - tap_times[#tap_times]) > _HK.TAP_TIMEOUT then tap_times = {} end
    table.insert(tap_times, now)
    if #tap_times > 3 then tap_times = {tap_times[#tap_times-2], tap_times[#tap_times-1], tap_times[#tap_times]} end
    if #tap_times >= 2 then
        local sum, count = 0, 0
        for i = max(2, #tap_times - 2), #tap_times do
            sum = sum + (tap_times[i] - tap_times[i - 1])
            count = count + 1
        end
        local avg_interval = sum / count
        params:set("delay_time", clamp(avg_interval, 0.02, 5))
    end
end

local function setup_params()
    params:add_separator("Input")
    for i = 1, 2 do
      params:add_file(i.."sample","Sample "..i, _path.tape); params:set_action(i.."sample",function(f) if f~=nil and f~="" and f~="none" and f~="-" and f~=(_path.tape.."live!") and not f:match("/$") then if params:get(i.."live_input")==1 then engine.set_live_input(i,0) params:set(i.."live_input",0,true) end if params:get(i.."live_direct")==1 then engine.live_direct(i,0) params:set(i.."live_direct",0,true) end local jitter_locked=is_param_locked(i,"jitter"); if not jitter_locked then lfo.clearLFOs(tostring(i),"jitter"); end engine.read(i,f); ctx.waveforms[i]=nil; if not _G.preset_loading then params:set(i.."seek",0) end; audio_active[i]=true; update_pan_positioning(); if _G.preset_loading then blim.apply(i, get_audio_duration(f)) else blim.load(i, f, not jitter_locked) end elseif f==(_path.tape.."live!") then do end else local jitter_locked=is_param_locked(i,"jitter"); if not jitter_locked then lfo.clearLFOs(tostring(i),"jitter"); end audio_active[i]=false; osc_positions[i]=0; update_pan_positioning(); end end)
    end
    params:add_binary("randomtapes", "Random Tapes", "trigger", 0) params:set_action("randomtapes", function() load_random_tape_file() end)

    params:add_group("LIVE!", 10)
    for i = 1, 2 do
      params:add_binary(i.."live_input", "Live Buffer "..i.." ● ►", "toggle", 0) params:set_action(i.."live_input", function(value) if value == 1 then if params:get(i.."live_direct") == 1 then params:set(i.."live_direct", 0) end engine.set_live_input(i, 1) engine.live_mono(i, params:get("isMono") - 1) audio_active[i] = true ctx.waveforms[i] = ctx.live_wf.norm[i] ctx.live_wf.col[i] = -1 if not _G.preset_loading then blim.apply(i, params:get("live_buffer_length")) else cached_buffer_durations[i]=params:get("live_buffer_length") end set_sample_live(i) update_pan_positioning() else engine.set_live_input(i, 0) if not audio_active[i] and params:get(i.."live_direct") == 0 then osc_positions[i] = 0 params:set(i.."sample", "-") pause_voice_if_idle(i) else set_sample_live(i) update_pan_positioning() end end end)
    end
    params:add_control("live_buffer_mix", "Overdub", controlspec.new(0, 100, "lin", 1, 100, "%")) params:set_action("live_buffer_mix", function(value) engine.live_buffer_mix(value * 0.01) end)
    params:add_taper("live_buffer_length", "Buffer Length", 0.05, 10, 1, 3, "s") params:set_action("live_buffer_length", function(value) engine.live_buffer_length(value) ctx.live_wf.reset(1) ctx.live_wf.reset(2) for i=1,2 do if params:get(i.."live_input")==1 then if not _G.preset_loading then blim.apply(i, value) else cached_buffer_durations[i]=value end end end end)
    params:add{type = "trigger", id = "save_live_buffer1", name = "Buffer1 to Tape", action = function() local timestamp = os.date("%Y%m%d_%H%M%S") local filename = "live1_"..timestamp..".wav" engine.save_live_buffer(1, filename) audio_files_cache = nil end}
    params:add{type = "trigger", id = "save_live_buffer2", name = "Buffer2 to Tape", action = function() local timestamp = os.date("%Y%m%d_%H%M%S") local filename = "live2_"..timestamp..".wav" engine.save_live_buffer(2, filename) audio_files_cache = nil end}
    for i = 1, 2 do
      params:add_binary(i.."live_direct", "Direct "..i.." ►", "toggle", 0) params:set_action(i.."live_direct", function(value) if value == 1 then local was_live = params:get(i.."live_input") if was_live == 1 then params:set(i.."live_input", 0) end engine.live_direct(i, 1) audio_active[i] = true set_sample_live(i) update_pan_positioning() else engine.live_direct(i, 0) audio_active[i] = false if not audio_active[i] and params:get(i.."live_input") == 0 then osc_positions[i] = 0 params:set(i.."sample", "-") pause_voice_if_idle(i) else set_sample_live(i) update_pan_positioning() end end end)
    end
    params:add_option("isMono", "Input Mode", {"stereo", "mono"}, 1) params:set_action("isMono", function(value) local monoValue = value - 1 for i = 1, 2 do if params:get(i.."live_direct") == 1 then engine.isMono(i, monoValue) end if params:get(i.."live_input") == 1 then engine.live_mono(i, monoValue) end end end)
    params:add_binary("dry_mode2", "Dry Mode", "toggle", 0) params:set_action("dry_mode2", function(x) drymode.toggle_dry_mode2() end)

    params:add{type = "trigger", id = "save_preset", name = "Save Preset", action = function() presets.save_complete_preset(nil, morph.scene_data, current_mode, current_filter_mode) end}
    params:add{type = "trigger", id = "load_preset_menu", name = "Preset Browser", action = function() presets.open_menu() end}

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

    params:add_group("DELAY", 13)
    params:add_control("delay_mix", "Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("delay_mix", function(x) engine.mix(x * 0.01) font.update_fx_cache("delay_mix", x) end)
    params:add_taper("delay_time", "Time", 0.02, 5, 0.5, 0.1, "s") params:set_action("delay_time", function(value) engine.delay(value) end)
    params:add_binary("tap", "↳ TAP!", "trigger", 0) params:set_action("tap", function() register_tap() end)
    params:add_taper("delay_feedback", "Feedback", 0, 120, 40, 1, "%") params:set_action("delay_feedback", function(value) engine.fb_amt(value * 0.01) end)
    params:add_control("delay_lowpass", "LPF", controlspec.new(20, 20000, 'exp', 1, 7500, "Hz")) params:set_action('delay_lowpass', function(value) engine.lpf(value) end)
    params:add_control("delay_highpass", "HPF", controlspec.new(20, 20000, 'exp', 1, 200, "Hz")) params:set_action('delay_highpass', function(value) engine.dhpf(value) end)
    params:add_taper("wiggle_depth", "Mod Depth", 0, 100, 25, 0, "%") params:set_action("wiggle_depth", function(value) engine.w_depth(value * 0.01) end)
    params:add_taper("wiggle_rate", "Mod Freq", 0, 20, 2, 1, "Hz") params:set_action("wiggle_rate", function(value) engine.w_rate(value) end)
    params:add_control("stereo", "Ping-Pong", controlspec.new(0, 100, "lin", 1, 20, "%")) params:set_action("stereo", function(x) engine.stereo(x * 0.01) end)
    params:add_taper("delay_duck", "Ducking", 0, 100, 17, 0, "%") params:set_action("delay_duck", function(value) engine.delay_duck(value * 0.01) end)
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
    
    params:add_group("R3VERB", 3 + #rev_present)
    params:add_taper("reverb_mix", "Mix", -40, 18, -40, 0, "dB") params:set_action("reverb_mix", function(value) nrev_set_mix(value) font.update_fx_cache("reverb_mix", value) end)
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
    end
    params:add_separator("           ")
    params:add_option("lock_reverb", "Lock Parameters", {"off", "on"}, 2)

    params:add_group("SHIMMER", 10)
    params:add_control("shimmer_mix1", "Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("shimmer_mix1", function(x) engine.shimmer_mix1(x * 0.01) font.update_fx_cache("shimmer_mix1", x) end)
    params:add_option("shimmer_mod1", "Mix Mod", {"off", "on"}, 1) params:set_action("shimmer_mod1", function(x) engine.shimmer_mod1(x - 1) font.update_fx_cache("shimmer_mod1", x) end)
    params:add_option("shimmer_oct1", "Pitch Shift", {"-2 oct", "-1 oct", "0", "+1 oct", "+2 oct"}, 4) params:set_action("shimmer_oct1", function(x) local octave_values = {0.25, 0.5, 1, 2, 4} engine.shimmer_oct1(octave_values[x]) end)
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

    params:add_group("TAPE", 15)
    params:add_option("tape_mix", "Analog Tape", {"off", "on"}, 1) params:set_action("tape_mix", function(x) engine.tape_mix(x-1) font.update_fx_cache("tape_mix", x) end)
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
    params:add_separator("    ")
    params:add_binary("randomize_tape", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_tape", function() undo.checkpoint() randpara.randomize_tape_params(steps) end)
    params:add_option("lock_tape", "Lock Parameters", {"off", "on"}, 1)

    params:add_group("EQ", 9)
    for i = 1, 2 do
    params:add_control(i.."eq_low_gain", i.." Bass", controlspec.new(-1, 1, "lin", 0.01, 0, "")) params:set_action(i.."eq_low_gain", function(value) engine.eq_low_gain(i, value*55) end)
    params:add_control(i.."eq_mid_gain", i.." Mid", controlspec.new(-1, 1, "lin", 0.01, 0, "")) params:set_action(i.."eq_mid_gain", function(value) engine.eq_mid_gain(i, value*35) end)
    params:add_control(i.."eq_high_gain", i.." Treble", controlspec.new(-1, 1, "lin", 0.01, 0, "")) params:set_action(i.."eq_high_gain", function(value) engine.eq_high_gain(i, value*45) end)
    end
    params:add_separator("     ")
    params:add_binary("randomize_eq", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_eq", function() undo.checkpoint() for i=1, 2 do randpara.randomize_eq_params(i, steps) end end)
    params:add_option("lock_eq", "Lock Parameters", {"off", "on"}, 1)

    params:add_group("LFO", 120)
    params:add_binary("randomize_lfos", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_lfos", function() undo.checkpoint() lfo.clearLFOs() local allow_vol = params:get("allow_volume_lfos") == 2 for i = 1, 2 do lfo.randomize_lfos(i, allow_vol) end invalidate_lfo_cache() end)
    params:add_binary("lfo.assign_to_current_row", "Assign to Selection", "trigger", 0) params:set_action("lfo.assign_to_current_row", function() undo.checkpoint() lfo.assign_to_current_row(current_mode, current_filter_mode) invalidate_lfo_cache() end)
    params:add_control("global_lfo_freq_scale", "Freq Scale", controlspec.new(0.01, 10, "exp", 0.01, 1, "x")) params:set_action("global_lfo_freq_scale", function(value) for i = 1, 16 do lfo.recompute_freq(i) end end)
    params:add_control("global_lfo_depth_scale", "Depth Scale", controlspec.new(0, 2, "lin", 0.01, 1, "x")) params:set_action("global_lfo_depth_scale", function(value) lfo.set_global_depth_scale(value) end)
    params:add_binary("sine_lfos", "Sine LFOs", "toggle", 0) params:set_action("sine_lfos", function(v) lfo.set_sine_all(v == 1) end)
    params:add_binary("lfo_pause", "Pause ⏸︎", "toggle", 0) params:set_action("lfo_pause", function(value) lfo.set_pause(value == 1) end)
    params:add_binary("ClearLFOs", "Clear All", "trigger", 0) params:set_action("ClearLFOs", function() undo.checkpoint() lfo.clearLFOs() invalidate_lfo_cache() update_pan_positioning() end)
    params:add_option("allow_volume_lfos", "Allow Volume LFOs", {"no", "yes"}, 1) params:set_action("allow_volume_lfos", function(value) if value == 2 then lfo.clearLFOs("1", "volume") lfo.clearLFOs("2", "volume") lfo.assign_volume_lfos() else lfo.clearLFOs("1", "volume") lfo.clearLFOs("2", "volume") end invalidate_lfo_cache() end)
    lfo.init()

    params:add_group("STEREO", 5)
    params:add_control("Width", "Stereo Width", controlspec.new(0, 200, "lin", 2, 100, "%")) params:set_action("Width", function(value) engine.width(value * 0.01) font.update_fx_cache("Width", value) end)
    params:add_control("dimension_mix", "Dimension", controlspec.new(0, 100, "lin", 2, 0, "%")) params:set_action("dimension_mix", function(value) engine.dimension_mix(value * 0.01) font.update_fx_cache("dimension_mix", value) end)
    params:add_option("haas", "Haas Effect", {"off", "on"}, 1) params:set_action("haas", function(x) engine.haas(x-1) font.update_fx_cache("haas", x) end)
    params:add_taper("rspeed", "Rotation", 0, 1, 0, 1, "Hz") params:set_action("rspeed", function(value) engine.rspeed(value) font.update_fx_cache("rspeed", value) end)
    params:add_option("monobass_mix", "Mono Bass", {"off", "on"}, 1) params:set_action("monobass_mix", function(x) engine.monobass_mix(x-1) font.update_fx_cache("monobass_mix", x) end)

    params:add_group("BITCRUSH", 4)
    params:add_taper("bitcrush_mix", "Mix", 0, 100, 0.0, 0, "%") params:set_action("bitcrush_mix", function(value) engine.bitcrush_mix(value * 0.01) font.update_fx_cache("bitcrush_mix", value) end)
    params:add_option("bitcrush_mod", "Mix Mod", {"off", "on"}, 1) params:set_action("bitcrush_mod", function(value) engine.bitcrush_mod(value - 1) font.update_fx_cache("bitcrush_mod", value) end)
    params:add_taper("bitcrush_rate", "Rate", 1, 48000, 4500, 3, "Hz") params:set_action("bitcrush_rate", function(value) engine.bitcrush_rate(value) end)
    params:add_taper("bitcrush_bits", "Bits", 1, 24, 14, 1) params:set_action("bitcrush_bits", function(value) engine.bitcrush_bits(value) end)

    params:add_group("RESONATE", 4)
    params:add_control("resonator_mix", "Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("resonator_mix", function(v) engine.resonator_mix(v * 0.01) font.update_fx_cache("resonator_mix", v) if v > 0 then hlp.update_resonator() end end)
    params:add_control("resonator_decay", "Decay", controlspec.new(0.01, 5, "exp", 0, 2, "s")) params:set_action("resonator_decay", function(v) engine.resonator_decay(v) end)
    params:add_number("resonator_root", "Root", 24, 128, 48, function(p) return MusicUtil.note_num_to_name(p:get(), true) end) params:set_action("resonator_root", function(v) hlp.update_resonator() end)
    params:add_control("resonator_tone", "LPF", controlspec.new(200, 16000, "exp", 0, 8000, "Hz")) params:set_action("resonator_tone", function(v) engine.resonator_tone(v) end)

    params:add_group("WAVEFOLD", 3)
    params:add_control("wavefold_mix", "Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("wavefold_mix", function(v) engine.wavefold_mix(v * 0.01) font.update_fx_cache("wavefold_mix", v) end)
    params:add_control("wavefold_drive", "Drive", controlspec.new(0, 100, "lin", 1, 75, "%")) params:set_action("wavefold_drive", function(v) engine.wavefold_drive(v * 0.01) end)
    params:add_control("wavefold_sym", "Symmetry", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("wavefold_sym", function(v) engine.wavefold_sym(v * 0.01) end)

    params:add_group("RINGMOD", 3)
    params:add_control("ringmod_mix", "Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("ringmod_mix", function(v) engine.ringmod_mix(v * 0.01) font.update_fx_cache("ringmod_mix", v) end)
    params:add_control("ringmod_rate", "Rate", controlspec.new(0.1, 4000, "exp", 0, 200, "Hz")) params:set_action("ringmod_rate", function(v) engine.ringmod_rate(v) end)
    params:add_option("ringmod_freqmod", "Freq Mod", {"off", "on"}, 1) params:set_action("ringmod_freqmod", function(value) engine.ringmod_freqmod(value - 1) end)

    params:add_group("GLITCH", 11)
    params:add_control("glitch_ratio", "Glitch", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("glitch_ratio", function(value) engine.glitch_ratio(value * 0.01) font.update_fx_cache("glitch_ratio", value) end)
    params:add_control("glitch_mix", "Mix", controlspec.new(0, 100, "lin", 1, 100, "%")) params:set_action("glitch_mix", function(value) engine.glitch_mix(value * 0.01) font.update_fx_cache("glitch_mix", value) end)
    params:add_taper("glitch_probability", "Frequency", 0.1, 20, 5, 1, "Hz") params:set_action("glitch_probability", function(value) engine.glitch_probability(value) end)
    params:add_control("glitch_min_length", "Min Length", controlspec.new(10, 500, "lin", 1, 75, "ms")) params:set_action("glitch_min_length", function(value) engine.glitch_min_length(value * 0.001) end)
    params:add_control("glitch_max_length", "Max Length", controlspec.new(20, 500, "lin", 1, 200, "ms")) params:set_action("glitch_max_length", function(value) engine.glitch_max_length(value * 0.001) end)
    params:add_control("glitch_maxstutters", "Max Stutters", controlspec.new(2, 20, "lin", 1, 5, "")) params:set_action("glitch_maxstutters", function(value) engine.glitch_maxstutters(value) end)
    params:add_control("glitch_reverse", "Reverse Prob", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("glitch_reverse", function(value) engine.glitch_reverse(value * 0.01) end)
    params:add_control("glitch_pitch", "Pitch Prob", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("glitch_pitch", function(value) engine.glitch_pitch(value * 0.01) end)
    params:add_separator("       ")
    params:add_binary("randomize_glitch", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_glitch", function() if params:get("lock_glitch") == 1 then undo.checkpoint() params:set("glitch_probability", math.random(1, 150) / 10) params:set("glitch_min_length", math.random(10, 200)) params:set("glitch_max_length", math.random(100, 500)) params:set("glitch_reverse", math.random(0, 100)) params:set("glitch_pitch", math.random(0, 100)) end end)
    params:add_option("lock_glitch", "Lock Parameters", {"off", "on"}, 1)

    params:add_group("EVOLVE", 12)
    params:add_binary("evolution", "Evolve!", "toggle", 0) params:set_action("evolution", function(value) if value == 1 then randpara.reset_evolution_centers() randpara.start_evolution() else randpara.stop_evolution() end end)
    params:add_control("evolution_range", "Evolution Range", controlspec.new(0, 100, "lin", 1, 10, "%")) params:set_action("evolution_range", function(value) randpara.set_evolution_range(value) end)
    params:add_option("evolution_rate", "Evolution Rate", {"slowest", "slow", "moderate", "medium", "fast", "crazy"}, 2) params:set_action("evolution_rate", function(value) local rates = {1/0.5, 1/1.5, 1/4, 1/8, 1/15, 1/30} randpara.set_evolution_rate(rates[value]) end)
    params:add_separator("                               ")
    params:add_option("evolve_granular", "Evolve Granular", {"off", "on"}, 2) params:set_action("evolve_granular", function(value) randpara.set_group_evolution("granular", value == 2) end)
    params:add_option("evolve_delay", "Evolve Delay", {"off", "on"}, 1) params:set_action("evolve_delay", function(value) randpara.set_group_evolution("delay", value == 2) end)
    params:add_option("evolve_reverb", "Evolve Reverb", {"off", "on"}, 1) params:set_action("evolve_reverb", function(value) randpara.set_group_evolution("reverb", value == 2) end)
    params:add_option("evolve_tape", "Evolve Tape", {"off", "on"}, 2) params:set_action("evolve_tape", function(value) randpara.set_group_evolution("tape", value == 2) end)
    params:add_option("evolve_shimmer", "Evolve Shimmer", {"off", "on"}, 2) params:set_action("evolve_shimmer", function(value) randpara.set_group_evolution("shimmer", value == 2) end)
    params:add_option("evolve_eq", "Evolve EQ", {"off", "on"}, 2) params:set_action("evolve_eq", function(value) randpara.set_group_evolution("eq", value == 2) end)
    params:add_option("evolve_bitcrush", "Evolve Bitcrush", {"off", "on"}, 2) params:set_action("evolve_bitcrush", function(value) randpara.set_group_evolution("bitcrush", value == 2) end)
    params:add_option("evolve_glitch", "Evolve Glitch", {"off", "on"}, 2) params:set_action("evolve_glitch", function(value) randpara.set_group_evolution("glitch", value == 2) end)

    params:add_group("SYMMETRY", 6)
    params:add_binary("symmetry", "Symmetry", "toggle", 0)
  params:set_action("symmetry", function(value) if value == 0 then for i=1,16 do lfo[i].sync_to=nil; lfo[i].sync_invert=false end else local active_map={} for i=1,16 do if lfo[i].active and lfo[i].target_name and lfo[i].target_name~="none" then active_map[lfo[i].target_name]=i end end for i=1,16 do local obj=lfo[i] if obj.active and obj.target_name and obj.target_name~="none" then local target=obj.target_name local track=target:sub(1,1) local pname=target:sub(2) if pname=="volume" then obj.sync_to=nil; obj.sync_invert=false elseif track=="1" then local j=active_map["2"..pname] if j then local is_pan=(pname=="pan") lfo[j].sync_to=i; lfo[j].sync_invert=is_pan; lfo[j].walk_value=obj.walk_value; lfo[j].walk_velocity=obj.walk_velocity; lfo[j].prev=is_pan and -obj.prev or obj.prev end end end end end end)
    params:add_separator("Copy")
    params:add_binary("copy_1_to_2", "Params 1 → 2", "trigger", 0) params:set_action("copy_1_to_2", function() Mirror.copy_voice_params("1", "2", true) end)
    params:add_binary("copy_2_to_1", "Params 1 ← 2", "trigger", 0) params:set_action("copy_2_to_1", function() Mirror.copy_voice_params("2", "1", true) end)
    params:add_binary("copy_buffer_1_to_2", "Sample 1 → 2", "trigger", 0) params:set_action("copy_buffer_1_to_2", function() local f = params:get("1sample") if f and f ~= "" and f ~= "-" and f ~= "none" then set_track_sample(2, f) audio_active[2] = audio_active[1] update_pan_positioning() end end)
    params:add_binary("copy_buffer_2_to_1", "Sample 1 ← 2", "trigger", 0) params:set_action("copy_buffer_2_to_1", function() local f = params:get("2sample") if f and f ~= "" and f ~= "-" and f ~= "none" then set_track_sample(1, f) audio_active[1] = audio_active[2] update_pan_positioning() end end)

    params:add_group("FILTER", 9)
    for i = 1, 2 do
      params:add_control(i.."cutoff",i.." LPF",controlspec.new(20,20000,"exp",0,20000,"Hz")) params:set_action(i.."cutoff", function(value) engine.cutoff(i, value) font.update_fx_cache(i.."cutoff", value) end)
      params:add_control(i.."hpf",i.." HPF",controlspec.new(20,20000,"exp",0,20,"Hz")) params:set_action(i.."hpf", function(value) engine.hpf(i, value) font.update_fx_cache(i.."hpf", value) end)
      params:add_taper(i.."lpf_gain", i.." Q", 0, 1, 0, 1, "") params:set_action(i.."lpf_gain", function(value) engine.lpf_gain(i, 4 * value) end)
    end
    params:add_separator("                   ")
    params:add_binary("randomizefilters", "RaNd0m1ze!", "trigger", 0) params:set_action("randomizefilters", function(value) for i = 1, 2 do local cutoff if is_param_locked(i, "cutoff") then cutoff = params:get(i.."cutoff") else cutoff = is_lfo_active_for_param(i.."cutoff") and math.random(20, 20000) or 20000 params:set(i.."cutoff", cutoff) params:set(i.."lpf_gain", math.random()) end if not is_param_locked(i, "hpf") then params:set(i.."hpf", math.random(20, floor(cutoff))) end end end)
    params:add_binary("resetfilters", "Reset", "trigger", 0) params:set_action("resetfilters", function(value) for i=1, 2 do params:set(i.."cutoff", 20000) params:set(i.."hpf", 20) params:set(i.."lpf_gain", 0.0) end end)

    params:add_group("LOCKING", 20)
    for i = 1, 2 do
        params:add_option(i.. "lock_jitter", i.. " Lock Jitter", {"off", "on"}, 1)
        params:add_option(i.. "lock_size", i.. " Lock Size", {"off", "on"}, 1)
        params:add_option(i.. "lock_density", i.. " Lock Density", {"off", "on"}, 1)
        params:add_option(i.. "lock_spread", i.. " Lock Spread", {"off", "on"}, 1)
        params:add_option(i.. "lock_pitch", i.. " Lock Pitch", {"off", "on"}, 1)
        params:add_option(i.. "lock_speed", i.. " Lock Speed", {"off", "on"}, 1)
        params:add_option(i.. "lock_seek", i.. " Lock Seek", {"off", "on"}, 1)
        params:add_option(i.. "lock_pan", i.. " Lock Pan", {"off", "on"}, 1)
        params:add_option(i.. "lock_cutoff", i.. " Lock LPF", {"off", "on"}, 1)
        params:add_option(i.. "lock_hpf", i.. " Lock HPF", {"off", "on"}, 1)
    end

    params:add_group("LIMITS", 30)
    for i = 1, 2 do
        params:add_separator("Voice "..i)
        params:add_taper(i.."min_jitter", i.." jitter (min)", 0, 999999, 0, 5, "ms")
        params:add_taper(i.."max_jitter", i.." jitter (max)", 0, 999999, 4999, 5, "ms")
        params:add_taper(i.."min_size", i.." size (min)", 20, 999, 40, 5, "ms")
        params:add_taper(i.."max_size", i.." size (max)", 20, 999, 999, 5, "ms")
        params:add_taper(i.."min_density", i.." density (min)", 0.1, 50, 0.25, 5, "Hz")
        params:add_taper(i.."max_density", i.." density (max)", 0.1, 50, 20, 5, "Hz")
        params:add_taper(i.."min_spread", i.." spread (min)", 0, 100, 0, 0, "%")
        params:add_taper(i.."max_spread", i.." spread (max)", 0, 100, 100, 0, "%")
        params:add_control(i.."min_pitch", i.." pitch (min)", controlspec.new(-48, 48, "lin", 1, -31, "st"))
        params:add_control(i.."max_pitch", i.." pitch (max)", controlspec.new(-48, 48, "lin", 1, 31, "st"))
        params:add_taper(i.."min_speed", i.." speed (min)", -2, 2, -1, 0, "x")
        params:add_taper(i.."max_speed", i.." speed (max)", -2, 2, 1, 0, "x")
        params:add_taper(i.."min_seek", i.." seek (min)", 0, 100, 0, 0, "%")
        params:add_taper(i.."max_seek", i.." seek (max)", 0, 100, 100, 0, "%")
    end

    params:add_group("ACTIONS", 4)
    params:add_binary("undo_action", "UNDO", "trigger", 0) params:set_action("undo_action", function() undo.undo() end)
    params:add_binary("redo_action", "REDO", "trigger", 0) params:set_action("redo_action", function() undo.redo() end)
    params:add_binary("macro_more", "More+", "trigger", 0) params:set_action("macro_more", function() undo.checkpoint() macro.macro_more() end)
    params:add_binary("macro_less", "Less-", "trigger", 0) params:set_action("macro_less", function() undo.checkpoint() macro.macro_less() end)

    params:add_group("MORPHING", 5)
    params:add_option("scene_mode", "Morph Mode", {"off", "on"}, 1) params:set_action("scene_mode", function(value) morph.scene_mode = (value == 2) and "on" or "off" if morph.scene_mode == "on" then local scenes_empty = true for track = 1, 2 do for scene = 1, 2 do if morph.scene_data[track] and morph.scene_data[track][scene] and next(morph.scene_data[track][scene]) ~= nil then scenes_empty = false break end end if not scenes_empty then break end end if scenes_empty then morph.initialize_scenes_with_current_params() end end end)
    params:add_control("morph_amount", "Morph", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("morph_amount", function(value) local prev = morph.amount if (prev == 0 or prev == 100) and value ~= prev then morph.auto_save_to_scene() end morph.amount = value morph.apply() end)
    params:add{type = "trigger", id = "save_to_scene1", name = "Morph Target A", action = function() morph.store_scene(1, 1) morph.store_scene(2, 1) end}
    params:add{type = "trigger", id = "save_to_scene2", name = "Morph Target B", action = function() morph.store_scene(1, 2) morph.store_scene(2, 2) end}
    params:add{type = "trigger", id = "delete_morph_data", name = "Delete Morph Data", action = function() morph.scene_data = {[1] = {[1] = {}, [2] = {}}, [2] = {[1] = {}, [2] = {}}} morph.amount = 0 params:set("morph_amount", 0) params:set("scene_mode", 1) morph.scene_mode = "off" end}

    params:add_group("PITCH", 4)
    params:add_option("pitch_quantize_scale", "Pitch Quantize", {"off", "major", "minor", "dorian", "phrygian", "lydian", "mixolydian", "locrian", "major pent.", "minor pent.", "blues", "whole tone"}, 2) params:set_action("pitch_quantize_scale", function(value) local scale = params:string("pitch_quantize_scale") if scale ~= "off" then for i = 1, 2 do local current_pitch = params:get(i.."pitch") local quantized = SU.quantize(current_pitch, scale) if current_pitch ~= quantized then params:set(i.."pitch", quantized) end end end end)
    params:add_option("pitch_lag", "Pitch Lag", {"off", "very small", "small", "medium", "high", "very high"}, 1) params:set_action("pitch_lag", function(value) local lag_times = {0, 1, 2, 4, 8, 16} local lag_time = lag_times[value] for i = 1, 2 do engine.pitch_lag(i, lag_time) end end)
    params:add_separator("                                   ")
    params:add_option("lock_pitch", "Lock Parameters", {"off", "on"}, 1)

    params:add_group("MIDI/SYNC", 16)
    midi_input.add_params({set_pitch = set_midi_pitch, on_voice_trigger = function(v) randomize_flash.midi[v] = 1; randomize_flash.held[v] = true end, on_voice_release = function(v) randomize_flash.held[v] = false end, voice_loaded = is_voice_loaded, on_transport_start = transport_start, on_transport_stop = transport_stop, on_transport_continue = transport_continue})
    params:add_option("midi_gate", "Drone Mode", { "off", "on" }, 2) params:set_action("midi_gate", function() if midi_input then midi_input.set_gate_mode() end end)
    params:add_option("midi_voice_mode", "MIDI control", { "both", "paraphonic", "voice 1", "voice 2" }, 2) params:set_action("midi_voice_mode", function() if midi_input then midi_input.set_voice_mode() end end)
    params:add_control("midi_attack", "Attack", controlspec.new(0.001, 20, "exp", 0, 2.5, "s")) params:set_action("midi_attack", function() if midi_input then midi_input.push_ad() end end)
    params:add_control("midi_decay", "Release", controlspec.new(0.005, 20, "exp", 0, 5, "s")) params:set_action("midi_decay", function() if midi_input then midi_input.push_ad() end end)
    params:add_option("midi_velocity", "Velocity", { "off", "on" }, 2) params:set_action("midi_velocity", function(v) if midi_input and v == 1 then engine.vel_amp(1, 1); engine.vel_amp(2, 1) end end)
    params:add_option("midi_cc1_dest", "Mod Wheel to", { "off", "morph", "reverb", "delay" }, 2)
    params:add_separator("                                 ")
    clocksync.add_params()
    params:add_option("midi_transport", "Transport", { "off", "on" }, 2)
    params:add_separator("                                    ")
    params:add_option("lock_sync", "Lock Parameters", {"off", "on"}, 1)

    arp.add_params()

    params:add_group("BOUNCE", 9)
    params:add_binary("bounce", "Bounce!", "trigger", 0) params:set_action("bounce", function() hlp.start_bounce() end)
    params:add_option("bounce_mode", "Bounce to", {"voice 1", "in place"}, 1)
    params:add_option("bounce_source", "Source", {"dry", "final mix"}, 2)
    params:add_option("bounce_volume", "Volume", {"pre", "post"}, 1)
    params:add_taper("bounce_length", "Length", 0.1, 60, 5, 0, "s")
    params:add_taper("bounce_xfade", "Crossfade", 0, 5, 1, 0, "s")
    params:add_option("bounce_reset", "Reset After", {"off", "voice 1", "voice 2", "both"}, 2)
    params:add_separator("                        ")
    params:add_binary("delete_unused_bounces", "Delete Unused Files", "trigger", 0) params:set_action("delete_unused_bounces", function() delete_unused_bounces() end)

    params:add_group("OTHER", 26)
    params:add_binary("dry_mode", "Dry Mode", "toggle", 0) params:set_action("dry_mode", function(x) drymode.toggle_dry_mode() end)
    params:add_binary("randomtape1", "Random Tape 1", "trigger", 0) params:set_action("randomtape1", function() load_random_tape_file(1) end)
    params:add_binary("randomtape2", "Random Tape 2", "trigger", 0) params:set_action("randomtape2", function() load_random_tape_file(2) end)
    params:add_binary("unload_all", "Unload All Audio", "trigger", 0) params:set_action("unload_all", function() for i=1, 2 do params:set(i.."seek", 0) params:set(i.."sample", "-") params:set(i.."live_input", 0) params:set(i.."live_direct", 0) audio_active[i] = false osc_positions[i] = 0 ctx.live_wf.reset(i) end engine.unload_all() update_pan_positioning() end)
    params:add_option("norm_load", "Normalize Load", {"off", "on"}, 2) params:set_action("norm_load", function(x) engine.norm_load(x - 1) end)
    params:add_binary("global_pitch_size_density_link", "Linked Mode", "toggle", 0) params:set_action("global_pitch_size_density_link", function(value) if value == 1 then for i = 1, 2 do local pitch = params:get(i.."pitch") local size = params:get(i.."size") local density = (clocksync.grain_synced() and clocksync.grain_density(i)) or params:get(i.."density") if size > 0 and density > 0 then local lb = link_base[i] lb.pitch = pitch lb.size = size lb.density = density lb.product = size * density end end end end)
    params:add_option("steps", "Transition Time", {"short", "medium", "long"}, 1) params:set_action("steps", function(value) steps = ({20, 300, 800})[value] end)
    params:add_separator("                                  ")
    for i = 1, 2 do
      params:add_taper(i.. "volume", i.. " volume", -70, 10, -15, 0, "dB") params:set_action(i.. "volume", function(value) if value == -70 then engine.volume(i, 0) else engine.volume(i, math.pow(10, value / 20)) end end)
      params:add_taper(i.. "pan", i.. " pan", -100, 100, 0, 0, "%") params:set_action(i.. "pan", function(value) engine.pan(i, value * 0.01)  end)
      params:add_taper(i.. "speed", i.. " speed", -2, 2, 0, 0) params:set_action(i.. "speed", function(value) if abs(value) < 0.01 then engine.speed(i, 0) else engine.speed(i, drymode.stereo_dry_active() and value or value * clocksync.speed_scale()) end end)
      params:add_taper(i.. "density", i.. " density", 0.1, 250, 2.5, 5) params:set_action(i.. "density", function(value) engine.density(i, clocksync.grain_density(i) or value) end)
      params:add_control(i.. "pitch", i.. " pitch", controlspec.new(-48, 48, "lin", 1, 0, "st")) params:set_action(i.. "pitch", function(value) local scale = params:string("pitch_quantize_scale") local quantized = SU.quantize(value, scale) engine.pitch_offset(i, math.pow(0.5, -quantized / 12) * arp.ratio(i)) end)
      params:add_taper(i.. "jitter", i.. " jitter", 0, 999900, 250, 10, "ms") params:set_action(i.. "jitter", function(value) engine.jitter(i, value * 0.001) end)
      params:add_taper(i.. "size", i.. " size", 20, 5000, 1000, 1, "ms") params:set_action(i.. "size", function(value) engine.size(i, math.min(value, arp.max_size_ms(i)) * 0.001) end)
      params:add_taper(i.. "spread", i.. " spread", 0, 100, 60, 0, "%") params:set_action(i.. "spread", function(value) engine.spread(i, value * 0.01) end)
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
    local scale_name = params:string("pitch_quantize_scale")
    local scale = SU.intervals(scale_name) or SU.intervals("major")
    if not scale then return end
    local weighted_intervals = {}
    local larger_intervals = {}
    for octave = -2, 2 do
        for _, degree in ipairs(scale) do
            local interval = octave * 12 + degree
            if interval ~= 0 then
                if abs(interval) <= 12 then
                    if degree == 0 then weighted_intervals[interval] = 3
                    elseif degree == scale[3] or degree == scale[4] then weighted_intervals[interval] = 2
                    elseif degree == scale[5] or degree == scale[6] then weighted_intervals[interval] = 2
                    elseif degree == scale[2] then weighted_intervals[interval] = 1
                    else weighted_intervals[interval] = 1 end
                elseif abs(interval) <= 24 then
                    table.insert(larger_intervals, interval)
                end
            end
        end
    end
    weighted_intervals[0] = 2
    local valid_intervals = {}
    local total_weight = 0
    for interval, weight in pairs(weighted_intervals) do
        local candidate_pitch = base_pitch + interval
        if candidate_pitch >= min_pitch and candidate_pitch <= max_pitch then
            valid_intervals[#valid_intervals + 1] = {interval = interval, weight = weight}
            total_weight = total_weight + weight
        end
    end
    if #valid_intervals > 0 then
        local random_weight = math.random(total_weight)
        local cumulative_weight = 0
        for i = 1, #valid_intervals do
            local v = valid_intervals[i]
            cumulative_weight = cumulative_weight + v.weight
            if random_weight <= cumulative_weight then set_pitch(track, other_track, base_pitch + v.interval, symmetry) return end
        end
    end
    for i = 1, #larger_intervals do
        local candidate_pitch = base_pitch + larger_intervals[i]
        if candidate_pitch >= min_pitch and candidate_pitch <= max_pitch then	set_pitch(track, other_track, candidate_pitch, symmetry) return end
    end
end

local _rand_can_randomize = {}
local _rand_targets = {}
local function randomize(n)
    if randomize_metro[n] then stop_metro_safe(randomize_metro[n]) else randomize_metro[n] = metro.init() end
    local m_rand = randomize_metro[n]
    local symmetry = params:get("symmetry") == 1
    local other_track = 3 - n
    for k in pairs(_rand_can_randomize) do _rand_can_randomize[k] = nil end
    for k in pairs(_rand_targets) do _rand_targets[k] = nil end
    local can_randomize = _rand_can_randomize
    local targets = _rand_targets
    local param_names = _HK.rand_names
    local pitch_size_density_linked = params:get("global_pitch_size_density_link") == 1
    for i = 1, #param_names do can_randomize[param_names[i]] = not is_param_locked(n, param_names[i]) end
    if can_randomize.pitch then randomize_pitch(n, other_track, symmetry) end
    if not m_rand then print("Error: Hardware metro limit reached!") return end
    for i = 1, #param_names do
        local key = param_names[i]
        if key == "pitch" then goto continue end
        local cfg_name = n .. key
        if not can_randomize[key] then goto continue end
        if key == "seek" then
            local min_val = params:get(n .. "min_seek")
            local max_val = params:get(n .. "max_seek")
            local val = random_float(min_val, max_val)
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
                if key == "jitter" then
                    if math.random() < 0.75 then
                        local upper_limit = min(500, max_val)
                        val = random_float(0, upper_limit)
                    else
                        val = random_float(min_val, max_val)
                    end
                else
                    val = random_float(min_val, max_val)
                end
                targets[cfg_name] = val
                if symmetry then targets[other_track .. key] = (key == "pan") and -val or val end
            end
        end
        ::continue::
    end
    if clocksync.lfo_synced() then clocksync.randomize_lfo_div(n, symmetry and other_track or nil) end
    if next(targets) then
        m_rand.time = 1 / 30
        local tolerance = 0.01
        m_rand.event = function(count)
            local factor = count / steps
            local all_done = true
            for param, target in pairs(targets) do
                local current = params:get(param)
                local new_val = current + (target - current) * factor
                params:set(param, new_val)
                all_done = all_done and (abs(new_val - target) < tolerance)
            end
            if pitch_size_density_linked and all_done then
                local tracks = symmetry and {1, 2} or {n}
                for i = 1, #tracks do
                    local track = tracks[i]
                    local size_val = params:get(track.."size")
                    local density_val = params:get(track.."density")
                    local pitch_val = params:get(track.."pitch")
                    if size_val > 0 and density_val > 0 then
                        local lb = link_base[track]
                        lb.pitch   = pitch_val
                        lb.size    = size_val
                        lb.density = density_val
                        lb.product = size_val * density_val
                    end
                end
            end
            if all_done then stop_metro_safe(m_rand) end
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
local function handle_volume_lfo(track, delta, crossfade_mode)
    if key_state[2] or key_state[3] then return end
    local p = _HK.vol[track]
    local op = _HK.vol[3 - track]
    local a1, i1 = is_lfo_active_for_param(p)
    local a2, i2 = is_lfo_active_for_param(op)
    local k1 = a1 and MK.offset[i1]
    local k2 = a2 and MK.offset[i2]
    local lfo_delta = delta * 1.5
    local vol_delta = delta * 3
    if crossfade_mode then
        local od = -delta
        if k1 then params:delta(k1, lfo_delta) else params:delta(p, vol_delta) end
        if k2 then params:delta(k2, od * 1.5)  else params:delta(op, od * 3)    end
        local c1 = offset_key_to_db(k1, p)
        local c2 = offset_key_to_db(k2, op)
        _G.master_vol_diff = c1 - c2
        return
    end
    local c1 = offset_key_to_db(k1, p)
    local c2 = offset_key_to_db(k2, op)
    if c1 > (k1 and -69.5 or -70) and c2 > (k2 and -69.5 or -70) then _G.master_vol_diff = c1 - c2 end
    local diff = _G.master_vol_diff or 0
    local lk, lp, fk, fp, sign
    if diff >= 0 then lk, lp, fk, fp, sign = k1, p, k2, op, -1 else lk, lp, fk, fp, sign = k2, op, k1, p,  1 end
    if lk then params:delta(lk, lfo_delta) else params:delta(lp, vol_delta) end
    local lead = offset_key_to_db(lk, lp)
    local fdb  = clamp(lead + sign * diff, -70, 10)
    if fk then params:set(fk, db_to_offset_value(fdb)) else params:set(fp, fdb) end
end

local _LINK_SPEED = {pitch = 1, size = 5, density = 0.5}
function hlp.update_linked_params(tr, delta_mult, param, delta)
    local lb = hlp.ensure_link_base(tr)
    local base_pitch   = lb.pitch
    local base_size    = lb.size
    local base_density = lb.density
    local size_den_prod = lb.product
    local new_pitch, new_size, new_den
    if param == "pitch" then
        local old_pitch = base_pitch
        local scale = params:string("pitch_quantize_scale")
        if scale ~= "off" then
            local direction = (delta * delta_mult) > 0 and 1 or -1
            new_pitch = SU.step(old_pitch, scale, direction)
            new_pitch = clamp(new_pitch, LIMITS.pitch.min, LIMITS.pitch.max)
        else new_pitch = clamp(old_pitch + delta * delta_mult, LIMITS.pitch.min, LIMITS.pitch.max)
        end
        local pitch_ratio = (new_pitch - base_pitch) / 12
        new_size = clamp(base_size * (2 ^ -pitch_ratio), LIMITS.size.min, LIMITS.size.max)
        if clocksync.grain_synced() then
            local target_den = clamp(size_den_prod / new_size, LIMITS.density.min, LIMITS.density.max)
            hlp.apply_linked_density(tr, target_den)
            new_den = clocksync.grain_density(tr) or base_density
        else new_den = clamp(base_density * (2 ^ pitch_ratio), LIMITS.density.min, LIMITS.density.max)
        end
    elseif param == "size" then
        local old_size = base_size
        new_size = clamp(old_size + delta * delta_mult, LIMITS.size.min, LIMITS.size.max)
        if clocksync.grain_synced() then
            local target_den = clamp(size_den_prod / new_size, LIMITS.density.min, LIMITS.density.max)
            hlp.apply_linked_density(tr, target_den)
            new_den = clocksync.grain_density(tr) or base_density
        else new_den = clamp(size_den_prod / new_size, LIMITS.density.min, LIMITS.density.max)
            local den_min, den_max = LIMITS.density.min, LIMITS.density.max
            if new_den == den_min or new_den == den_max then new_size = clamp(size_den_prod / new_den, LIMITS.size.min, LIMITS.size.max) end
        end
        new_pitch = base_pitch
    else
        local old_den = base_density
        new_den = clamp(old_den + delta * delta_mult * 0.1, LIMITS.density.min, LIMITS.density.max)
        new_size = clamp(size_den_prod / new_den, LIMITS.size.min, LIMITS.size.max)
        local size_min, size_max = LIMITS.size.min, LIMITS.size.max
        if new_size == size_min or new_size == size_max then new_den = clamp(size_den_prod / new_size, LIMITS.density.min, LIMITS.density.max) end
        new_pitch = base_pitch
    end
    local synced = clocksync.grain_synced()
    hlp.apply_lfo_or_set(_HK.size[tr], new_size)
    if not synced then hlp.apply_lfo_or_set(_HK.den[tr], new_den) end
    hlp.apply_lfo_or_set(_HK.pitch[tr], new_pitch)
    lb.pitch   = new_pitch
    lb.size    = new_size
    lb.density = new_den
    if not synced then lb.product = new_size * new_den end
end
local function handle_pitch_size_density_link(track, config, delta)
    local param = config.param
    if params:get("global_pitch_size_density_link") ~= 1 then return false end
    if not _LINK_SPEED[param] then return false end
    local symmetry = params:get("symmetry") == 1
    local other_track = 3 - track
    local speed = _LINK_SPEED[param]
    hlp.update_linked_params(track, speed, param, delta)
    if symmetry then hlp.update_linked_params(other_track, speed, param, delta) end
    return true
end

local function clocksync_set_density(voice, hz)
    engine.density(voice, hz)
    if params:get("global_pitch_size_density_link") ~= 1 then hlp.link_last_hz[voice] = hz return end
    local lb = hlp.ensure_link_base(voice)
    if hlp.link_suppress_size or hlp.link_last_hz[voice] == hz or is_lfo_active_for_param(_HK.den[voice]) then
        lb.density = hz
        hlp.link_last_hz[voice] = hz
        return
    end
    local new_size = clamp(lb.product / hz, LIMITS.size.min, LIMITS.size.max)
    hlp.apply_lfo_or_set(_HK.size[voice], new_size)
    lb.size    = new_size
    lb.density = hz
    hlp.link_last_hz[voice] = hz
end

function hlp.update_seek(tr, current_pos, delta)
    local new_pos = (current_pos + delta) % 100
    local norm_pos = new_pos * 0.01
    osc_positions[tr] = norm_pos
    params:set(tr.."seek", new_pos)
    engine.seek(tr, norm_pos)
end
local function handle_seek_param(track, config, delta)
    if config.param ~= "seek" then return false end
    local sym = params:get("symmetry") == 1
    disable_lfos_for_param(_HK.seek[track], not sym)
    if sym then
        hlp.update_seek(1, floor(osc_positions[1] * 100 + 0.5), delta)
        hlp.update_seek(2, floor(osc_positions[2] * 100 + 0.5), delta)
    else
        hlp.update_seek(track, floor(osc_positions[track] * 100 + 0.5), delta)
    end
    return true
end

local function handle_standard_param(track, config, delta)
    local sym = params:get("symmetry") == 1
    local pkeys = config.pkeys
    local p = pkeys[track]
    disable_lfos_for_param(p, not sym)
    if config.param == "pitch" then
        local old_value = params:get(p)
        local scale = params:string("pitch_quantize_scale")
        local lim = LIMITS[config.param] or LIMITS.pitch
        if scale ~= "off" then
            local direction = delta > 0 and 1 or -1
            local new_value = clamp(SU.step(old_value, scale, direction), lim.min, lim.max)
            params:set(p, new_value)
            if sym then
                local other_p = pkeys[3 - track]
                params:set(other_p, clamp(SU.step(params:get(other_p), scale, direction), lim.min, lim.max))
            end
        else
            params:delta(p, delta)
            if sym then
                local other_p = pkeys[3 - track]
                params:set(other_p, params:get(other_p) + (params:get(p) - old_value))
            end
        end
    else
        params:delta(p, delta)
        if sym then params:delta(pkeys[3 - track], delta) end
    end
    if config.param == "size" and arp.is_running() and delta < 0 then
        local cap = arp.max_size_ms(track)
        if params:get(p) > cap then params:set(p, cap) end
        if sym then local op = pkeys[3 - track] local ocap = arp.max_size_ms(3 - track) if params:get(op) > ocap then params:set(op, ocap) end end
    end
end

local function handle_param_change(track, config, delta)
    if key_state[2] or key_state[3] then return end
    if handle_pitch_size_density_link(track, config, delta) then return end
    if handle_seek_param(track, config, delta) then return end
    handle_standard_param(track, config, delta)
end

local function handle_randomize_track(n, force)
    if not force and not key_state[1] then return end
    local track = n == 3 and 2 or 1
    undo.checkpoint()
    stop_metro_safe(randomize_metro[track])
    lfo.clearLFOs(tostring(track), nil, lfo.PRESERVE_ON_RANDOMIZE)
    lfo.randomize_lfos(tostring(track), params:get("allow_volume_lfos") == 2)
    invalidate_lfo_cache()
    randomize(track)
    randpara.randomize_params(steps, track)
    randpara.reset_evolution_centers()
    update_pan_positioning()
    randomize_flash[track] = 1
end

local function handle_mode_navigation(n)
    if key_state[1] then return end
    local idx = mode_indices[current_mode] or 1
    local offset = n == 2 and 0 or -2
    current_mode = mode_list[((idx + offset) % #mode_list) + 1]
end

local function handle_parameter_lock()
    local param_name = (current_mode == "lpf" or current_mode == "hpf") and (current_filter_mode == "lpf" and "cutoff" or "hpf") or string.match(current_mode, "%a+")
    local lock1 = "1lock_" .. param_name
    local lock2 = "2lock_" .. param_name
    local is_locked1 = params:get(lock1) == 2
    local is_locked2 = params:get(lock2) == 2
    local new_state = (is_locked1 == is_locked2) and (is_locked1 and 1 or 2) or 1
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
    local offset = (current_val - min_val) / (max_val - min_val) * 2 - 1
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
                invalidate_lfo_cache()
                return i
            end
        end
    end
    return nil
end

local function adjust_lfo_offset(lfo_idx, delta)
    local ok = MK.offset[lfo_idx]
    local current_offset = pget(ok)
    local current_depth  = pget(MK.depth[lfo_idx])
    local offset_floor   = current_depth * 0.01 - 1
    local offset_ceiling = 1 - current_depth * 0.01
    local target_param   = lfo.lfo_targets[pget(MK.target[lfo_idx])] or ""
    local sensitivity    = (target_param:match("size$") or target_param:match("density$")) and 0.004 or 0.008
    local proposed_offset = clamp(current_offset + delta * sensitivity, offset_floor, offset_ceiling)
    pset(ok, proposed_offset)
    lfo[lfo_idx].offset = proposed_offset
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
            local normalized = (current_val - min_val) / (max_val - min_val)
            local initial_depth = abs(step)
            local initial_offset = clamp(normalized * 2 - 1, -0.9999, 0.9999)
            lfo[lfo_idx].depth = initial_depth
            lfo[lfo_idx].offset = initial_offset
            pset(ok, initial_offset)
            pset(dk, initial_depth)
            pset(lk, 2)
            invalidate_lfo_cache()
        end
        return
    end
    local proposed_depth = current_depth + step
    if proposed_depth <= 0 then if current_depth > 0 then pset(lk, 1) invalidate_lfo_cache() end return end
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

local function apply_freq_step(idx, dir)
    local fk = MK.freq[idx]
    local cur = pget(fk)
    local step = max(cur * 0.06, 0.005) * (dir > 0 and 1 or -1)
    local new_freq = max(cur + step, 0.01)
    pset(fk, new_freq)
    lfo[idx].freq = new_freq * pget("global_lfo_freq_scale")
end

local FX_MAP = { "reverb_mix", "delay_mix", "shimmer_mix1" }
local FX_LABELS = { "reverb", "delay", "shimmer" }

local function active_edit_mode()
    if current_mode == "lpf" or current_mode == "hpf" then return current_filter_mode end
    return current_mode
end

function enc(n, d)
    if not installer:ready() or installer:pending() then return end
    if presets.is_menu_open() then presets.menu_enc(n, d) return end
    local k1, k2, k3 = key_state[1], key_state[2], key_state[3]
    if k2 and k3 and not k1 then
        local fx = FX_MAP[n]
        if fx then
            mark_key_interaction()
            params:delta(fx, d)
            fx_popup.label = FX_LABELS[n]
            fx_popup.value = params:get(fx)
            fx_popup.time = util.time()
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
        if n == 1 then
            if clocksync.lfo_synced() then
                clocksync.step_lfo_div(voice, d, params:get("symmetry") == 1)
                finalize_change()
                return
            end
            local lfo_idx = find_or_create_lfo_for_param(voice, param_name, true, false)
            if lfo_idx then
                apply_freq_step(lfo_idx, d)
                if params:get("symmetry") == 1 then
                    local other_lfo = find_or_create_lfo_for_param(3 - voice, param_name, true, false, lfo_idx)
                    if other_lfo then apply_freq_step(other_lfo, d) end
                end
                finalize_change()
            end
        elseif n == 2 then
            local lfo_idx = find_or_create_lfo_for_param(voice, param_name, false, true)
            if lfo_idx then
                adjust_lfo_with_symmetry(voice, param_name, lfo_idx, adjust_lfo_depth, d, d, false, true)
                finalize_change()
            end
        elseif n == 3 then
            local lfo_idx = find_or_create_lfo_for_param(voice, param_name, true, false)
            if lfo_idx then
                local other_d = (param_name == "pan") and -d or d
                adjust_lfo_with_symmetry(voice, param_name, lfo_idx, adjust_lfo_offset, d, other_d, true, false)
                finalize_change()
            end
        end
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
        local r_metro = randomize_metro[track]
        if r_metro then stop_metro_safe(r_metro) end
        if k1 then
            local p = _HK.vol[track]
            disable_lfos_for_param(p, true)
            if params:get("symmetry") == 1 then disable_lfos_for_param(p) end
            params:delta(p, 3 * d)
            _G.master_vol_diff = params:get("1volume") - params:get("2volume")
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
    ["1"]   = {long  = function() params:set("scene_mode", params:get("scene_mode") == 1 and 2 or 1) end},
    ["2"]   = {short = function() handle_mode_navigation(2) end, long  = function() params:set("global_pitch_size_density_link", params:get("global_pitch_size_density_link") == 1 and 0 or 1) end},
    ["3"]   = {short = function() handle_mode_navigation(3) end, long  = function() params:set("symmetry", params:get("symmetry") == 1 and 0 or 1) end},
    ["12"]  = {short = function() handle_randomize_track(2, true) end, long  = function() params:set("clock_sync", params:get("clock_sync") == 2 and 1 or 2) end},
    ["13"]  = {short = function() handle_randomize_track(3, true) end, long  = function() params:set("arp_on", params:get("arp_on") == 2 and 1 or 2) end},
    ["23"]  = {short = handle_parameter_lock, long  = combo_longpress_fire},
    ["123"] = {long  = function() params:set("arp_randomize", 1) fx_popup.label = "RANDOM ARP" fx_popup.value = nil fx_popup.time = util.time() end},
}

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
  local abs = abs(s)
  if abs < 0.01 then return ".00x" end
  if abs < 1    then return string.format("%s.%02dx", s < 0 and "-" or "", floor(abs * 100)) end
  return string.format("%.2fx", s)
end

local LEVEL = {hi=15, dim=9, val=2}
local TRACK_X, VOL_X, PAN_X = {51, 92}, {0,126}, {52,93}
local BAR_W, Y = 30, {bottom=60, seek=63}
local UPPER = {jitter=true, size=true, density=true, spread=true, pitch=true}
local FORMAT = {
  hz = function(value) return string.format("%.1f Hz", value) end,
  st = function(value, track, pitch_rand) if not track then return value > 0 and string.format("+%.0f", value) or string.format("%.0f", value) end local suffix = pitch_rand and ".. st" or " st" return value > 0 and string.format("+%.0f%s", value, suffix) or string.format("%.0f%s", value, suffix) end,
  spread = function(v) return string.format("%.0f%%", v) end,
  jitter = function(value) if value > 999 then return string.format("%.1f s", value / 1000) else return string.format("%.0f ms", value) end end,
  size = function(value) if value > 999 then return string.format("%.2f s", value / 1000) else return string.format("%.0f ms", value) end end}
local buckets = {}
for _i = 1, 15 do buckets[_i] = {r={}, p={}, t={}, r_len=0, p_len=0, t_len=0} end
local function clear_ops() for i=1,15 do local b=buckets[i] b.r_len, b.p_len, b.t_len = 0, 0, 0 end end
local function R(l,x,y,w,h) local b=buckets[l]; local i=b.r_len+1; b.r_len=i local t=b.r[i]; if t then t[1],t[2],t[3],t[4]=x,y,w,h else b.r[i]={x,y,w,h} end end
local function P(l,x,y) local b=buckets[l]; local i=b.p_len+1; b.p_len=i local t=b.p[i]; if t then t[1],t[2]=x,y else b.p[i]={x,y} end end
local function T(l,x,y,s,a) local b=buckets[l]; local i=b.t_len+1; b.t_len=i local t=b.t[i]; if t then t[1],t[2],t[3],t[4]=x,y,s,a else b.t[i]={x,y,s,a} end end
local LOCK_OFFSETS = {{-3,0},{-4,0},{-4,-1},{-4,-2}} local function draw_lock(x,y) for i=1,4 do local o=LOCK_OFFSETS[i] P(LEVEL.dim, x+o[1], y+o[2]) end end
local SIZE_LINK_PTS = {}
for _, offset in ipairs({1,3,5,7,9,11,13,15}) do local level = floor(10 * (1 - abs(offset - 8) / 8)) SIZE_LINK_PTS[#SIZE_LINK_PTS+1] = level SIZE_LINK_PTS[#SIZE_LINK_PTS+1] = offset end
local function draw_size_link(x,y) for i = 1, 16, 2 do P(SIZE_LINK_PTS[i], x-4, y+SIZE_LINK_PTS[i+1]) end end
local function flush() for l=1,15 do local b=buckets[l] if b.r_len>0 or b.p_len>0 or b.t_len>0 then screen.level(l) local filled=false for i=1,b.r_len do local r=b.r[i] screen.rect(r[1],r[2],r[3],r[4]) filled=true end for i=1,b.p_len do local p=b.p[i] screen.pixel(p[1],p[2]) filled=true end if filled then screen.fill() end for i=1,b.t_len do local t=b.t[i] screen.move(t[1],t[2]) if t[4]=="center" then screen.text_center(t[3]) else screen.text(t[3]) end end end end end
local SYM_CACHE = {}
for sy = 4, 64, 2 do local lvl = max(1, floor(10 * (1 - abs(sy - 34) / 32))); SYM_CACHE[#SYM_CACHE+1] = sy; SYM_CACHE[#SYM_CACHE+1] = lvl end
local _LOG_FILTER_INV = 1.0 / log(20000 / 20)
local _VOL_LINLIN_MUL = 64.0 / 80.0
local LABEL_CACHE, LABEL_UPPER_CACHE = {}, {}
for _, m in ipairs({"spread","pitch","density","size","jitter","lpf","hpf","pan","speed","seek"}) do local pad = (m == "lpf" or m == "hpf") and "       " or "      " LABEL_CACHE[m] = m .. ":" .. pad LABEL_UPPER_CACHE[m] = string.upper(m) .. ":" .. pad end
local _GLUT_N = 256
local _GLUT_NM = _GLUT_N - 1
local _ENV_LUT, _FADE_LUT = {}, {}
do
  local sin,cos,exp,abs,pi=sin,math.cos,math.exp,abs,math.pi
  local lv_scale = LEVEL.hi - 1
  local function bld(fn) local t={} local mx=0 for i=0,_GLUT_N-1 do local v=fn((i+0.5)/_GLUT_N)*lv_scale t[i]=v if v>mx then mx=v end end t[-1]=mx return t end
  for i=0,_GLUT_N-1 do _FADE_LUT[i]=sin(pi*(i+0.5)/_GLUT_N) end
  _ENV_LUT[1]=bld(function(p) return sin(pi*p) end)
  _ENV_LUT[2]=bld(function(p) if p<0.25 then return 0.5*(1-cos(pi*p*4)) elseif p>0.75 then return 0.5*(1-cos(pi*(1-p)*4)) else return 1.0 end end)
  _ENV_LUT[3]=bld(function(p) if p<0.08 then return p*12.5 else return exp(-4*(p-0.08)/0.92) end end)
  _ENV_LUT[4]=bld(function(p) if p<0.1 then return p*10 elseif p<0.3 then return 1-1.75*(p-0.1) elseif p<0.75 then return 0.65 else return 0.65*(1-(p-0.75)*4) end end)
  _ENV_LUT[5]=bld(function(p) return abs(sin(pi*p))*(0.6+0.4*sin(p*11.3+2.7)) end)
end
local PARAM_CACHE = { track = { {locked={},lfo_on={}}, {locked={},lfo_on={}} } }
local _LFO_RANGE_CACHE = {}
local _LOCK_PARAMS = {"jitter","size","density","spread","pitch","speed","seek","pan"}
local _FULL_PARAM_KEYS = {{},{}}
for t = 1, 2 do for i = 1, #_LOCK_PARAMS do _FULL_PARAM_KEYS[t][i] = t .. _LOCK_PARAMS[i] end end
local _slow_refresh_countdown = 0
local function refresh_redraw_cache()
  local spd_scale = drymode.stereo_dry_active() and 1 or clocksync.speed_scale()
  for t = 1,2 do
    local C = PARAM_CACHE.track[t]
    local K = TRACK_KEYS[t]
    C.vol = pget(K.volume)
    C.pan = pget(K.pan)
    C.spd = pget(K.speed) * spd_scale
    C.cut = pget(K.cutoff)
    C.hpf = pget(K.hpf)
  end
  _slow_refresh_countdown = _slow_refresh_countdown - 1
  if _slow_refresh_countdown > 0 then return end
  _slow_refresh_countdown = 4
  PARAM_CACHE.link = pget("global_pitch_size_density_link") == 1
  PARAM_CACHE.dry = pget("dry_mode") == 1
  PARAM_CACHE.sym = pget("symmetry") == 1
  PARAM_CACHE.evo = pget("evolution") == 1
  for t = 1,2 do
    local C = PARAM_CACHE.track[t]
    local K = TRACK_KEYS[t]
    C.size = pget(K.size)
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
      local act = is_lfo_active_for_param(fk)
      lfo_on[fk] = act
      if act then
        local rc = _LFO_RANGE_CACHE[fk]
        if not rc then rc = {0,0,0}; _LFO_RANGE_CACHE[fk] = rc end
        local a, b = lfo.get_parameter_range(fk, true)
        local _, fb = lfo.get_parameter_range(fk, false)
        rc[1], rc[2], rc[3] = a, b, fb
      end
    end
    locked["lpf"] = is_param_locked(t, "cutoff")
    locked["hpf"] = is_param_locked(t, "hpf")
    C.pitch_rand = (pget(K.pitch_random_prob) or 0) ~= 0
  end
end
local _PCT_CACHE, _INT_CACHE, _DB_CACHE = {}, {}, {}
local function fast_percent(v) v = floor(v + 0.5) local s = _PCT_CACHE[v] if not s then s = v .. "%" _PCT_CACHE[v] = s end return s end
local function fast_db(v) if v <= -40 then return "OFF" end v = floor(v + 0.5) local s = _DB_CACHE[v] if not s then s = v .. " dB" _DB_CACHE[v] = s end return s end
local function fast_int(v) v = floor(v + 0.5) local s = _INT_CACHE[v] if not s then s = tostring(v) _INT_CACHE[v] = s end return s end
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
local function draw_grains(t, x, now, col)
  local grains = grain_positions[t]
  if not grains then return end
  local C = PARAM_CACHE.track[t]
  local dur = cached_buffer_durations[t]
  if not dur or dur <= 0 then return end
  local keep = 0
  local drawn = 0
  local spd_fwd = C.spd >= -0.01
  local dir_mod = C.dir_mod
  local env_sel = C.env_sel
  local is_random_env = env_sel == 5
  local lut_default = _ENV_LUT[env_sel] or _ENV_LUT[1]
  local lut_n = _GLUT_N
  local lut_nm = _GLUT_NM
  local seek_y = Y.seek
  local inv_bar_w = 1 / BAR_W
  for gi = 1, #grains do
    local g = grains[gi]
    local age = now - g.t
    local gsize = g.size
    local dlife = gsize < 0.15 and 0.15 or gsize
    if age > dlife then
      _grain_pool[#_grain_pool + 1] = g
    else
      keep = keep + 1
      grains[keep] = g
      if drawn < 25 or not g.shown then
        drawn = drawn + 1
        g.shown = true
        local gsz = min(gsize / dur, 1)
        local forward = spd_fwd ~= (g.rv < dir_mod)
        local lut = is_random_env and (_ENV_LUT[floor(g.rv * 4) + 1] or _ENV_LUT[1]) or lut_default
        local fi = floor(age / dlife * lut_n)
        if fi > lut_nm then fi = lut_nm end
        local fade = _FADE_LUT[fi]
        local start_pos, end_pos
        if forward then start_pos = g.pos; end_pos = g.pos + gsz else start_pos = g.pos - gsz; end_pos = g.pos end
        local dl = floor(start_pos * BAR_W)
        local dr = ceil(end_pos * BAR_W) - 1
        if dr <= dl or gsz * BAR_W <= 1 then
          local lv = ceil(lut[-1] * fade)
          if lv < 1 then lv = 1 end
          local px = floor((start_pos + end_pos) * 0.5 * BAR_W) % BAR_W
          if col then
            if lv > col[px] then col[px] = lv end
          else
            P(lv, x + px, seek_y)
          end
        else
        local inv_gsz = 1 / gsz
        local sp
        if forward then sp = ((dl + 0.5) * inv_bar_w - start_pos) * inv_gsz else sp = 1 - (((dl + 0.5) * inv_bar_w - start_pos) * inv_gsz) end
        local sp_dt = inv_gsz * inv_bar_w
        if not forward then sp_dt = -sp_dt end
        if col then
          for px_unwrapped = dl, dr do
            local idx = floor(sp * lut_n)
            if idx < 0 then idx = 0 elseif idx > lut_nm then idx = lut_nm end
            local lv = ceil(lut[idx] * fade)
            local px = px_unwrapped % BAR_W
            if lv > col[px] then col[px] = lv end
            sp = sp + sp_dt
          end
        else
          for px_unwrapped = dl, dr do
            local idx = floor(sp * lut_n)
            if idx < 0 then idx = 0 elseif idx > lut_nm then idx = lut_nm end
            local lv = ceil(lut[idx] * fade)
            if lv < 1 then lv = 1 end
            local px = px_unwrapped % BAR_W
            P(lv, x + px, seek_y)
            sp = sp + sp_dt
          end
        end
        end
      end
    end
  end
  for i = keep + 1, #grains do grains[i] = nil end
end
local function draw_seek_bar_viz(t, x, mode, now, wf, active)
  local C = PARAM_CACHE.track[t]
  local loaded = audio_active[t] or C.in_ == 1 or C.dir_ == 1
  if mode == "speed" then
    R(1, x, Y.seek, BAR_W, 1)
    if loaded then
      local half_w = floor(BAR_W * 0.5)
      local cx = x + half_w
      local off = floor(clamp(C.spd * 0.5, -1, 1) * half_w)
      local dir = off >= 0 and 1 or -1
      local mag = abs(off)
      for i = 0, mag, 2 do P(4 + floor((LEVEL.hi - 4) * (1 - i / max(mag, 1))), cx + dir * i, Y.seek) end
      R(LEVEL.hi, cx + off, Y.seek - 1, 1, 2)
    end
    return
  end
  local animated_bar_w = floor(BAR_W * seek_bar_width)
  if wf ~= nil then
    local wmid = Y.seek - 5
    if wf then
      local col
      local grains = grain_positions[t]
      if #grains > 0 then
        if C.gran and C.gran > 0 then
          col = ctx.waveforms[0]
          for i = 0, BAR_W - 1 do col[i] = 0 end
          draw_grains(t, x, now, col)
        else
          for i = #grains, 1, -1 do _grain_pool[#_grain_pool + 1] = grains[i] grains[i] = nil end
        end
      end
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
      R(active and 4 or 1, x, wmid, animated_bar_w, 1)
    end
    if animated_bar_w > 0 then
      local ph = floor(osc_positions[t] * animated_bar_w)
      if ph >= BAR_W then ph = BAR_W - 1 end
      if active then
        R(LEVEL.hi, x + ph, wmid - 4, 1, 9)
        R(LEVEL.hi, x + ph - 1, wmid - 4, 3, 1)
        R(LEVEL.hi, x + ph - 1, wmid + 4, 3, 1)
      else
        R(15, x + ph, wmid - 4, 1, 9)
      end
      if C.in_ == 1 then
        local rh = floor(rec_positions[t] * animated_bar_w)
        if rh >= BAR_W then rh = BAR_W - 1 end
        R(active and LEVEL.hi or LEVEL.dim, x + rh, wmid - 4, 2, 9)
      end
    end
    return
  end
  if C.dir_ ~= 1 then R(1, x, Y.seek, animated_bar_w, 1) end
  if C.gran and C.gran > 0 then draw_grains(t, x, now)
  else
    local grains = grain_positions[t]
    for i = #grains, 1, -1 do _grain_pool[#_grain_pool + 1] = grains[i] grains[i] = nil end
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
  local cur_mode = current_mode
  local cur_filter = current_filter_mode
  local upper = UPPER[cur_mode]
  local mode = upper and "seek" or cur_mode
  local active = not upper
  screen.clear()
  screen.save()
  clear_ops()
  local left_slide = -anim_offset_x
  OFFS[1], OFFS[2] = -anim_offset_x, anim_offset_x
  TXP[1], TXP[2] = TRACK_X[1] + OFFS[1], TRACK_X[2] + OFFS[2]
  for ri = 1, #param_rows do local row = param_rows[ri]
    local name = row.name
    local hi = cur_mode == row.mode
    local y = row.y
    if hi then
      T(LEVEL.hi, 6 + left_slide, y, row.label_upper)
    else
      T(LEVEL.hi, 6 + left_slide, y, row.label)
    end
    local fmt = FORMAT[row.fmt_key]
    local density_synced = (row.name == "density" and clocksync.grain_synced())
    local is_size_row = (name == "size")
    local size_cap1 = is_size_row and arp.max_size_ms(1) or nil
    local size_cap2 = is_size_row and arp.max_size_ms(2) or nil
    for t = 1,2 do
      local x = TXP[t]
      local param = row.params[t]
      local C = PARAM_CACHE.track[t]
      if name == "size" and PARAM_CACHE.link then draw_size_link(x, y) end
      if C.locked[name] then draw_lock(x, y - 1) end
      local val = pget(param)
      local size_cap = (t == 2) and size_cap2 or size_cap1
      if size_cap and val > size_cap then val = size_cap end
      local sync_label = density_synced and clocksync.grain_division_label(t) or nil
      local txt = sync_label or (fmt and val_text(param, val, fmt, t, row.st and C.pitch_rand or nil) or params:string(param))
      T(flash_level(t, hi and LEVEL.hi or LEVEL.val), x, y, txt)
      if name ~= "spread" and C.lfo_on[param] and not sync_label then
        local rc = _LFO_RANGE_CACHE[param]
        if not rc then
          rc = {0,0,0} _LFO_RANGE_CACHE[param] = rc
          local a0, b0 = lfo.get_parameter_range(param, true)
          local _, fb0 = lfo.get_parameter_range(param, false)
          rc[1], rc[2], rc[3] = a0, b0, fb0
        end
        local a, b, fb = rc[1], rc[2], rc[3]
        local bar_w = clamp(floor(((val - a) / (b - a)) * BAR_W), 0, BAR_W)
        R(LEVEL.dim + 2, x, y + 1, bar_w, 1)
        if val > b and fb > b then
          local overflow_ratio = clamp((val - b) / (fb - b), 0, 1)
          local overflow_w = max(1, floor(sqrt(overflow_ratio) * BAR_W))
          R(LEVEL.hi, x, y + 1, overflow_w, 1)
        end
      elseif name ~= "spread" and C.lfo_on[param] and sync_label then
        local bar_w = clamp(floor(clocksync.grain_division_norm(t) * BAR_W), 0, BAR_W)
        R(LEVEL.dim + 2, x, y + 1, bar_w, 1)
      end
    end
  end
  local disp_mode = (mode == "lpf" or mode == "hpf") and cur_filter or mode
  local label = LABEL_CACHE[disp_mode] or (disp_mode .. ":      ")
  local label_upper = LABEL_UPPER_CACHE[disp_mode] or string.upper(label)
  local y_bot = Y.bottom
  T(LEVEL.hi, 6 + left_slide, y_bot + 1, active and label_upper or label)
  for t = 1,2 do
    local x = TXP[t]
    local C = PARAM_CACHE.track[t]
    local vL = active and LEVEL.hi or LEVEL.val
    local wf
    if mode == "seek" and C.dir_ ~= 1 then wf = (audio_active[t] or C.in_ == 1) and ctx.waveforms[t] end
    if mode == "seek" then
      if C.locked["seek"] then draw_lock(x, y_bot) end
      if wf == nil then
        local txt
        if C.in_ == 1 then txt = "live" elseif C.dir_ == 1 then txt = "direct" else txt = fast_percent(osc_positions[t] * 100) end
        T(flash_level(t, vL), x, y_bot + 1, txt)
      end
    elseif mode == "speed" then
      if C.locked["speed"] then draw_lock(x, y_bot) end
      T(flash_level(t, LEVEL.hi), x, y_bot + 1, speed_text(t, C.spd))
    elseif mode == "pan" then
      if C.locked["pan"] then draw_lock(x, y_bot) end
      local txt = (abs(C.pan) < 0.5) and "0%" or fast_percent(C.pan)
      T(flash_level(t, LEVEL.hi), x, y_bot + 1, txt)
    else
      if C.locked[cur_filter] then draw_lock(x, y_bot) end
      local v = cur_filter == "lpf" and C.cut or C.hpf
      T(flash_level(t, LEVEL.hi), x, y_bot + 1, fast_int(v))
    end
    if mode == "seek" or mode == "speed" then
      local audio_loaded = audio_active[t] or C.in_ == 1 or C.dir_ == 1
      if audio_loaded and C.dir_ ~= 1 and not wf then
        local icon
        if abs(C.spd) < 0.01 then icon = "⏸" elseif C.spd > 0 then icon = "▶" else icon = "◀" end
        T(vL, (t == 1 and 77 or 118) + OFFS[t], y_bot + 1, icon)
      end
      draw_seek_bar_viz(t, x, mode, now, wf, active)
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
    local peak_amp = (audio_active[t] or C.in_ == 1 or C.dir_ == 1) and max(voice_peak_amplitudes[t].l, voice_peak_amplitudes[t].r) or 0
    if peak_amp > 0 then
      local peak_db = log(peak_amp) * 9
      local pre_fader_db = peak_db - C.vol
      local pre_fader_ratio = (pre_fader_db + 70) / 70
      if pre_fader_ratio < 0 then pre_fader_ratio = 0 elseif pre_fader_ratio > 1 then pre_fader_ratio = 1 end
      local peak_h = pre_fader_ratio * h
      if peak_h > 0 then R(LEVEL.hi - 1, current_vol_x, 64 - peak_h + volume_bar_y[t], 2, peak_h) end
    end
    local pan_pos = util.linlin(-100, 100, current_pan_x, current_pan_x + 25, C.pan)
    R(LEVEL.dim, pan_pos - 1 + pan_indicator_x[t], 1, 4, 1)
  end
  if cur_mode == "lpf" or cur_mode == "hpf" then
    for t = 1,2 do
      local C = PARAM_CACHE.track[t]
      local x = TXP[t]
      R(1, x, Y.seek, BAR_W, 1)
      local filter_val = cur_filter == "lpf" and C.cut or C.hpf
      local log_normalized = log(filter_val / 20) * _LOG_FILTER_INV
      if log_normalized < 0 then log_normalized = 0 elseif log_normalized > 1 then log_normalized = 1 end
      local bar_width = floor(log_normalized * BAR_W)
      if bar_width < 1 then bar_width = 1 end
      R(LEVEL.hi, x, Y.seek, bar_width, 1)
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
  elseif morph.scene_mode == "on" then
    R(1, 7 + left_slide, 1, 22, 1)
    if morph.amount > 0 then R(LEVEL.hi, 7 + left_slide, 1, util.linlin(0, 100, 0, 22, morph.amount), 1) end
  else
    font.draw_fx_status_bucketed(P)
  end
  if showing_save_message then R(1, 40, 25, 48, 10); T(LEVEL.hi, 64, 33, "SAVING...", "center") end
  if fx_popup.time and (now - fx_popup.time) < FX_POPUP_DURATION then
    if fx_popup._src ~= fx_popup.label or fx_popup._val ~= fx_popup.value then
      local txt = fx_popup.value and (fx_popup.label .. ": " .. ((fx_popup.label == "reverb") and fast_db(fx_popup.value) or fast_percent(fx_popup.value))) or fx_popup.label
      fx_popup._src, fx_popup._val, fx_popup._txt, fx_popup._w = fx_popup.label, fx_popup.value, txt, #txt * 5 + 8
    end
    R(1, 64 - floor(fx_popup._w * 0.5), 27, fx_popup._w, 10)
    T(LEVEL.hi, 64, 35, fx_popup._txt, "center")
  end
  flush()
  screen.restore()
  screen.update()
end

local function make_grain_handler(bucket) return function(args) local vid = args[1]+1 if audio_active[vid] then local b = bucket[vid] local n = #b if n < 64 then local np = #_grain_pool local g if np > 0 then g = _grain_pool[np] _grain_pool[np] = nil else g = {} end g.pos, g.size, g.t, g.rv, g.shown = args[2], args[3], util.time(), args[4] or 0.5, false b[n+1] = g end end end end
local SEEK_KEYS = {"1seek", "2seek"}
local LIVE_IN_KEYS = {"1live_input", "2live_input"}
local LIVE_DIR_KEYS = {"1live_direct", "2live_direct"}
local osc_handlers = {
    ["/twins/buf_pos"] = function(args)
        local vid, pos = args[1] + 1, args[2]
        if audio_active[vid] or pget(LIVE_IN_KEYS[vid]) == 1 or pget(LIVE_DIR_KEYS[vid]) == 1 then
            osc_positions[vid] = pos
            pset(SEEK_KEYS[vid], pos * 100, true)
        end
    end,
    ["/twins/rec_pos"] = function(args)
        local vid, pos, peak = args[1] + 1, args[2], args[3]
        if pget(LIVE_IN_KEYS[vid]) == 1 then
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
    ["/twins/save_complete"] = function(args)
        showing_save_message = false
    end,
    ["/twins/bounce_done"] = function(args)
        hlp.finish_bounce()
    end}
osc_handlers["/twins/grain_pos"]   = make_grain_handler(grain_positions)
osc_handlers["/twins/waveform"] = function(args)
    local vid = args[1] + 1
    local wf, mx = {}, 0
    for c = 0, BAR_W - 1 do local v = args[c + 2] or 0 wf[c] = v if v > mx then mx = v end end
    local s = mx > 0 and 4 / mx or 0
    for c = 0, BAR_W - 1 do wf[c] = floor(wf[c] * s + 0.5) end
    ctx.waveforms[vid] = wf
end
local function setup_osc() osc.event = function(path, args) local handler = osc_handlers[path] if handler then handler(args) end end end

local function setup_undo()
    undo.init{
        lfo = lfo,
        capture_extra = function()
            return {
                morph_amount = params:get("morph_amount"),
                scene_mode   = params:get("scene_mode"),
                scene_data   = utils.deep_copy(morph.scene_data),
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
            for i = 1, 2 do if randomize_metro[i] then stop_metro_safe(randomize_metro[i]) end end
            if randpara.stop_interpolation then randpara.stop_interpolation() end
        end,
        on_after_restore = function()
            randpara.reset_evolution_centers()
        end,
        on_action = function(msg)
            fx_popup.label = msg
            fx_popup.value = nil
            fx_popup.time = util.time()
        end}
end

function init()
    if not installer:ready() then tracked_clock_run(function() while true do redraw() clock.sleep(1 / 10) end end) do return end end
    initial_reverb_onoff = params:get('reverb')
    params:set('reverb', 1)
    initial_monitor_level = params:get('monitor_level')
    params:set('monitor_level', -math.huge)
    setup_ui_metro()
    setup_params()
    setup_undo()
    setup_osc()
    morph.init(lfo, invalidate_lfo_cache, clocksync)
    clocksync.init({lfo = lfo, set_density = clocksync_set_density})
    arp.init({scale_utils = SU, is_voice_active = function(v) return audio_active[v] end, checkpoint = undo.checkpoint})
    font.init_fx_cache()
    init_longpress_checker()
    for i = 1, 2 do params:set(i.."sample", _path.tape, true) end
    for i = 1, 2 do engine.pause_voice(i) end
    clock.transport.start = transport_start
    clock.transport.stop  = transport_stop
    clock.transport.reset = transport_start
    morph.initialize_scenes_with_current_params()
    installer:check()
end

function cleanup()
    flush_finalize()
    cancel_all_clocks()
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
    if initial_monitor_level then params:set('monitor_level', initial_monitor_level) end
    if initial_reverb_onoff then params:set('reverb', initial_reverb_onoff) end
    osc.event = nil
end