--
--
--   __ __|         _)          
--      | \ \  \  / |  \ |  (_< 
--      |  \_/\_/ _| _| _| __/ 
--            by: @dddstudio                       
-- 
--                          
--                           v0.52
-- E1: Master Volume
-- K1+E2/E3: Volume
-- K2/K3: Navigate
-- E2/E3: Adjust Parameters
-- K1+K2/K3: Randomize
-- K2+K3: Lock Parameters
-- Hold K1: Morphing
-- Hold K2: Linked Mode
-- Hold K3: Symmetry
-- K1+E1: Crossfade/Morph
-- K2+K3: HPF/LPF
-- K2+K3+E1/E2/E3: Effect Mix
-- Hold K2+K3: Add Random LFO
-- K2/K3+E1/E2/E3: Adjust LFO
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
-- @xmacex @vehka
--
-- If you like this,
-- buy them a beer :)
--
--                    Daniel Rigler

installer_ = include("lib/scinstaller/scinstaller")
installer = installer_:new{requirements = {"AnalogTape", "AnalogChew", "AnalogLoss", "AnalogDegrade"}, zip = "https://github.com/schollz/portedplugins/releases/download/v0.4.6/PortedPlugins-RaspberryPi.zip"}
engine.name = installer:ready() and 'twins' or nil
local MusicUtil = require("musicutil")
local font = include("lib/font")
local presets = include("lib/presets")
local randpara = include("lib/randpara")
local lfo = include("lib/lfo")
local Mirror = include("lib/mirror") Mirror.init(osc_positions, lfo)
local macro = include("lib/macro") macro.set_lfo_reference(lfo)
local drymode = include("lib/drymode") drymode.set_lfo_reference(lfo)
local randomize_metro = { [1] = nil, [2] = nil }
local active_clocks = {}
local key_state = {} for n = 1, 3 do key_state[n] = false end
local current_mode = "seek"
local current_filter_mode = "lpf"
local tap_times = {}
local TAP_TIMEOUT = 2
local initial_monitor_level, initial_reverb_onoff;
local filter_lock_ratio = false
local filter_differences = {[1] = 0, [2] = 0}
local audio_active = {[1] = false, [2] = false}
local morph_amount = 0
local valid_audio_exts = {[".wav"]=true,[".aif"]=true,[".aiff"]=true,[".flac"]=true}
local mode_list = {"spread","pitch","density","size","jitter","lpf","pan","speed","seek"}
local mode_indices = {} for i,v in ipairs(mode_list) do mode_indices[v] = i end
local MORPH_LFO_KEYS, MORPH_TARGET_KEYS, MORPH_SHAPE_KEYS = {}, {}, {}
local MORPH_FREQ_KEYS, MORPH_DEPTH_KEYS, MORPH_OFFSET_KEYS = {}, {}, {}
for _mi = 1, 16 do
  MORPH_LFO_KEYS[_mi]    = _mi .. "lfo"
  MORPH_TARGET_KEYS[_mi] = _mi .. "lfo_target"
  MORPH_SHAPE_KEYS[_mi]  = _mi .. "lfo_shape"
  MORPH_FREQ_KEYS[_mi]   = _mi .. "lfo_freq"
  MORPH_DEPTH_KEYS[_mi]  = _mi .. "lfo_depth"
  MORPH_OFFSET_KEYS[_mi] = _mi .. "offset"
end
local key_trackers = {}
for n = 1, 3 do key_trackers[n] = {press_time = nil, had_interaction = false, long_triggered = false} end
local KEY_LONG_PRESS_THRESHOLD = 1
local key_longpress_actions = {
    [1] = {param = "scene_mode", a = 1, b = 2},
    [2] = {param = "global_pitch_size_density_link", a = 1, b = 0},
    [3] = {param = "symmetry", a = 1, b = 0},
    [23] = {action = "assign_lfo_to_current_row"}}
local showing_save_message = false
local fx_popup = {label = nil, value = nil, time = nil}
local FX_POPUP_DURATION = 1
local longpress_metro = nil
local current_scene_mode = "off"
local scene_data = {[1] = {[1] = {}, [2] = {}}, [2] = {[1] = {}, [2] = {}}}
local morph_temp_scene = {}
local last_morph_amount = 0 
local grain_positions = {[1] = {}, [2] = {}}
local osc_positions = {[1] = 0, [2] = 0}
local rec_positions = {[1] = 0, [2] = 0}
local cached_buffer_durations = {[1] = 1, [2] = 1}
local voice_peak_amplitudes = {[1] = {l = 0, r = 0}, [2] = {l = 0, r = 0}}
local link_base = {[1]={pitch=nil,size=nil,density=nil,product=nil}, [2]={pitch=nil,size=nil,density=nil,product=nil}}
local ui_metro = nil
local lfos_turned_off = {}
local lfo_cache = {}
local lfo_cache_dirty = true
local function invalidate_lfo_cache() lfo_cache_dirty = true end
local function rebuild_lfo_cache()
    for k in pairs(lfo_cache) do lfo_cache[k] = nil end
    local targets = lfo.lfo_targets
    if targets then
        for i = 1, 16 do
            if params:get(MORPH_LFO_KEYS[i]) == 2 then
                local param_name = targets[params:get(MORPH_TARGET_KEYS[i])]
                if param_name and param_name ~= "none" then lfo_cache[param_name] = i end
            end
        end
    end
    lfo_cache_dirty = false
end
local shimmer_presets = {{oct = 0.25, lowpass = 4000, hipass = 20, fb = 0.48}, {oct = 0.5, lowpass = 6000, hipass = 20, fb = 0.48}, {oct = 1, lowpass = 20000, hipass = 20, fb = 0.48}, {oct = 2, lowpass = 9000, hipass = 300, fb = 0.36}, {oct = 4, lowpass = 12000, hipass = 700, fb = 0.36}}
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
    spread = {param = "spread", delta = 2, engine = true, has_lock = true, y = 51, label = "spread:"},
    volume = {param = "volume", engine = true}}
local param_rows = {}
for mode, config in pairs(param_modes) do
  if config.y then
    local lbl = config.label
    table.insert(param_rows, {
      y = config.y, label = lbl, label_upper = lbl:upper(),
      name = lbl:match("%a+"),
      mode = mode, param1 = "1" .. config.param, param2 = "2" .. config.param,
      hz = config.hz, st = config.st
    })
  end
end
table.sort(param_rows, function(a, b) return a.y < b.y end)
local LIMITS = {size={min=20,max=4999},density={min=0.1,max=50},pitch={min=-48,max=48}}
local scale_array_cache = {}
local function normalize_scale_name(scale_name)
    if scale_name == "none" or scale_name == "off" then return "none" end
    local scale_map = {["major pent."] = "major pentatonic", ["minor pent."] = "minor pentatonic"}
    return scale_map[scale_name] or scale_name
end
local function get_scale_array(scale_name)
    scale_name = normalize_scale_name(scale_name)
    if scale_name == "none" then return nil end
    if not scale_array_cache[scale_name] then scale_array_cache[scale_name] = MusicUtil.generate_scale_of_length(60-48, scale_name, 97) end
    return scale_array_cache[scale_name]
end
local function quantize_pitch_to_scale(pitch_value, scale_name)
    local scale_array = get_scale_array(scale_name)
    if not scale_array then return pitch_value end
    return MusicUtil.snap_note_to_array(60 + pitch_value, scale_array) - 60
end
local function get_next_scale_note(pitch_value, scale_name, direction)
    local scale_array = get_scale_array(scale_name)
    if not scale_array then return pitch_value + direction end
    local midi_note = MusicUtil.snap_note_to_array(60 + pitch_value, scale_array)
    local current_idx
    for i, note in ipairs(scale_array) do if note == midi_note then current_idx = i break end end
    if not current_idx then return pitch_value end
    local next_idx = util.clamp(current_idx + (direction > 0 and 1 or -1), 1, #scale_array)
    return scale_array[next_idx] - 60
end
local scale_intervals_cache = {}
local function get_scale_intervals(scale_name)
    scale_name = normalize_scale_name(scale_name)
    if scale_name == "none" then scale_name = "major" end
    if not scale_intervals_cache[scale_name] then scale_intervals_cache[scale_name] = MusicUtil.generate_scale(0, scale_name, 1) or MusicUtil.generate_scale(0, "major", 1) end
    return scale_intervals_cache[scale_name]
end
local animation_y = -64 animation_complete = false animation_start_time = nil
local pan_indicator_x = {[1] = -80, [2] = 80} pan_indicators_visible = false pan_slide_start_time = nil
local volume_bar_y = {[1] = 120, [2] = 120} volume_bars_visible = false
local seek_bar_width = 0 seek_bars_visible = false
local randomize_flash = {[1] = 0, [2] = 0}
local FLASH_INTENSITY = 8
local FLASH_DECAY = 0.9
local function flash_level(track, base_level) return math.min(base_level + math.floor(randomize_flash[track] * FLASH_INTENSITY), 15) end
local function table_find(tbl, value) for i = 1, #tbl do if tbl[i] == value then return i end end return nil end
local function is_audio_loaded(track_num) local file_path = params:get(track_num .. "sample") return (file_path and file_path ~= "-") or audio_active[track_num] end
local function random_float(l, h) return l + math.random() * (h - l) end
local function stop_metro_safe(m) if m then pcall(function() m:stop() end) if m then m.event = nil end end end
local function tracked_clock_run(func) local co = clock.run(func) table.insert(active_clocks, co) return co end
local function cancel_all_clocks() for i = #active_clocks, 1, -1 do local co = active_clocks[i] if co then pcall(function() clock.cancel(co) end) end active_clocks[i] = nil end end
local function is_param_locked(track_num, param) return params:get(track_num .. "lock_" .. param) == 2 end
local function is_lfo_active_for_param(param_name)
    if lfo_cache_dirty then rebuild_lfo_cache() end
    local idx = lfo_cache[param_name]
    return idx ~= nil, idx
end
local function update_pan_positioning() if _G.preset_loading then return end local loaded1 = is_audio_loaded(1) local loaded2 = is_audio_loaded(2) local pan1_locked = is_param_locked(1, "pan") local pan1_has_lfo = is_lfo_active_for_param("1pan") local pan2_locked = is_param_locked(2, "pan") local pan2_has_lfo = is_lfo_active_for_param("2pan") if not pan1_locked and not pan1_has_lfo then params:set("1pan", loaded2 and -25 or 0) end if not pan2_locked and not pan2_has_lfo then params:set("2pan", loaded1 and 25 or 0) end end

local function setup_ui_metro()
    if ui_metro then stop_metro_safe(ui_metro) end
    ui_metro = metro.init(function()
        local now = util.time()
        local needs_redraw = false
        if not animation_complete then
            animation_start_time = animation_start_time or now
            local elapsed = now - animation_start_time
            local progress = math.min(elapsed * 2, 1)
            if progress < 1 then
                animation_y = -64 + ((1 - (1 - progress) ^ 3) * 64)
                needs_redraw = true
            else
                animation_y = 0
            end
            animation_complete = progress >= 1
            if progress >= 0.4 and not pan_slide_start_time then pan_slide_start_time = now end
        end
        if pan_slide_start_time and not (pan_indicators_visible and volume_bars_visible and seek_bars_visible) then
            local slide_progress = math.min((now - pan_slide_start_time) * 2.5, 1)
            local eased = 1 - (1 - slide_progress) ^ 2
            if not pan_indicators_visible then
                if slide_progress < 1 then
                    pan_indicator_x[1] = -80 + (eased * 80)
                    pan_indicator_x[2] = 80 - (eased * 80)
                    needs_redraw = true
                else
                    pan_indicator_x[1] = 0
                    pan_indicator_x[2] = 0
                    pan_indicators_visible = true
                end
            end
            if not volume_bars_visible then
                if slide_progress < 1 then
                    volume_bar_y[1] = 120 - (eased * 120)
                    volume_bar_y[2] = 120 - (eased * 120)
                    needs_redraw = true
                else
                    volume_bar_y[1] = 0
                    volume_bar_y[2] = 0
                    volume_bars_visible = true
                end
            end
            if not seek_bars_visible then
                if slide_progress < 1 then
                    seek_bar_width = eased
                    needs_redraw = true
                else
                    seek_bar_width = 1
                    seek_bars_visible = true
                end
            end
            if pan_indicators_visible and volume_bars_visible and seek_bars_visible then pan_slide_start_time = nil end
        end
        for i = 1, 2 do
            if randomize_flash[i] > 0.001 then
                randomize_flash[i] = randomize_flash[i] * FLASH_DECAY
                needs_redraw = true
            end
        end
        redraw()
    end)
    ui_metro.time = 1/60
    ui_metro:start()
end

local function init_longpress_checker()
    if longpress_metro then stop_metro_safe(longpress_metro) end
    longpress_metro = metro.init()
    longpress_metro.time = 0.2
    longpress_metro.event = function()
        local now = util.time()
        for n = 1, 3 do
            local tracker = key_trackers[n]
            local action = key_longpress_actions[n]
            local blocked = (n == 2 or n == 3) and key_state[1]
            if tracker.press_time and not tracker.had_interaction and 
               not tracker.long_triggered and action and not blocked then
                if (now - tracker.press_time) >= KEY_LONG_PRESS_THRESHOLD then
                    tracker.long_triggered = true
                    tracker.had_interaction = true
                    local curr = params:get(action.param)
                    params:set(action.param, (curr == action.a) and action.b or action.a)
                end
            end
        end
        local combo_tracker = key_trackers[23]
        if combo_tracker and combo_tracker.press_time and not combo_tracker.had_interaction and not combo_tracker.long_triggered then
            if (now - combo_tracker.press_time) >= KEY_LONG_PRESS_THRESHOLD then
                combo_tracker.long_triggered = true
                combo_tracker.had_interaction = true
                lfo.assign_to_current_row(current_mode, current_filter_mode)
                invalidate_lfo_cache()
            end
        end
    end
    longpress_metro:start()
end

local morph_voice_params={"speed","pitch","jitter","size","density","spread","pan","seek","cutoff","hpf","lpfgain","granular_gain","subharmonics_3","subharmonics_2","subharmonics_1","overtones_1","overtones_2","smoothbass","ratcheting_prob","size_variation","direction_mod","density_mod_amt","pitch_random_scale_type","pitch_random_prob","pitch_mode","trig_mode","probability","eq_low_gain","eq_mid_gain","eq_high_gain","env_select","volume"}
local morph_global_params={"delay_mix","delay_time","delay_feedback","delay_lowpass","delay_highpass","wiggle_depth","wiggle_rate","stereo","reverb_mix","t60","damp","rsize","earlyDiff","modDepth","modFreq","low","mid","high","lowcut","highcut","shimmer_mix","shimmer_preset","lock_shimmer","tape_mix","sine_drive_wet","drive","wobble_mix","wobble_amp","wobble_rpm","flutter_amp","flutter_freq","flutter_var","chew_depth","chew_freq","chew_variance","lossdegrade_mix","Width","dimension_mix","haas","rspeed","monobass_mix","bitcrush_mix","bitcrush_rate","bitcrush_bits","evolution","evolution_range","evolution_rate","lock_eq","lock_tape","lock_reverb","lock_delay","global_lfo_freq_scale","pitch_quantize_scale","pitch_lag","shimmer_mix1","shimmer_oct1","pitchv1","lowpass1","hipass1","fbDelay1","fb1", "glitch_probability", "glitch_ratio", "glitch_mix", "glitch_min_length", "glitch_max_length", "glitch_reverse", "glitch_pitch" }
local morph_voice_params_count=#morph_voice_params
local morph_global_params_count=#morph_global_params
local skip_param_set={}
local used_slots={}
local pending={}

local function store_scene(track,scene)
  scene_data[track][scene]={}
  local scene_params=scene_data[track][scene]
  local p_lookup=params.lookup
  local p_get=params.get
  for i=1,morph_voice_params_count do
    local param=morph_voice_params[i]
    local full_param=track..param
    if p_lookup[full_param]then scene_params[full_param]=p_get(params,full_param)end
  end
  for i=1,morph_global_params_count do
    local param=morph_global_params[i]
    if p_lookup[param]then scene_params[param]=p_get(params,param)end
  end
  scene_params.lfo_data={}
  for i=1,16 do
    local lfo_state=p_get(params,MORPH_LFO_KEYS[i])
    if lfo_state==2 then
      scene_params.lfo_data[i]={enabled=true,target=p_get(params,MORPH_TARGET_KEYS[i]),shape=p_get(params,MORPH_SHAPE_KEYS[i]),freq=p_get(params,MORPH_FREQ_KEYS[i]),depth=p_get(params,MORPH_DEPTH_KEYS[i]),offset=p_get(params,MORPH_OFFSET_KEYS[i])}
    else
      scene_params.lfo_data[i]={enabled=false}
    end
  end
end

local function recall_scene(track,scene)
  if not scene_data[track]or not scene_data[track][scene]then return end
  local scene_params=scene_data[track][scene]
  local p_lookup=params.lookup
  local p_set=params.set
  for i=1,16 do p_set(params,MORPH_LFO_KEYS[i],1)end
  for param_name,value in pairs(scene_params)do
    if param_name~="lfo_data"and p_lookup[param_name]then p_set(params,param_name,value)end
  end
  if scene_params.lfo_data then
    for i=1,16 do
      local lfo_entry=scene_params.lfo_data[i]
      if lfo_entry and lfo_entry.enabled then
        p_set(params,MORPH_TARGET_KEYS[i],lfo_entry.target)
        p_set(params,MORPH_SHAPE_KEYS[i],lfo_entry.shape)
        p_set(params,MORPH_FREQ_KEYS[i],lfo_entry.freq)
        p_set(params,MORPH_DEPTH_KEYS[i],lfo_entry.depth)
        p_set(params,MORPH_OFFSET_KEYS[i],lfo_entry.offset)
        p_set(params,MORPH_LFO_KEYS[i],2)
      end
    end
  end
  invalidate_lfo_cache()
end
local function _morph_clamp(x) return x < -1 and -1 or (x > 1 and 1 or x) end
local function _compute_offset(lfo_offset, const_val, target, t_weight, const_weight, get_range)
  if not const_val then return _morph_clamp(lfo_offset * t_weight) end
  local min_val, max_val = get_range(target)
  if not min_val or not max_val or max_val <= min_val then return _morph_clamp(lfo_offset * t_weight) end
  const_val = const_val < min_val and min_val or (const_val > max_val and max_val or const_val)
  local tgt_off = ((const_val - min_val) / (max_val - min_val)) * 2 - 1
  return _morph_clamp(lfo_offset * t_weight + tgt_off * const_weight)
end

local function _ensure_unique_assignment(target, slot, has_tracking, lfo_ref, p_set, params_ref)
  if not has_tracking or not target then return end
  if lfo_ref.is_param_assigned(target) then
    local other = lfo_ref.get_lfo_for_param(target)
    if other and other ~= slot then p_set(params_ref, MORPH_LFO_KEYS[other], 1) end
  end
  lfo_ref.mark_param_assigned(target)
end

local function apply_morph()
  if not lfo or not lfo.get_parameter_range or not lfo.lfo_targets then return end
  local morph_direction=morph_amount-last_morph_amount
  last_morph_amount=morph_amount
  if morph_amount==0 then
    recall_scene(1,1)
    recall_scene(2,1)
    morph_temp_scene={}
    return
  elseif morph_amount==100 then
    recall_scene(1,2)
    recall_scene(2,2)
    morph_temp_scene={}
    return
  end
  local t=morph_amount*0.01
  local t_inv=1.0-t
  local scene1_1=(scene_data[1]and scene_data[1][1])or{}
  local scene1_2=(scene_data[1]and scene_data[1][2])or{}
  local scene2_1=(scene_data[2]and scene_data[2][1])or{}
  local scene2_2=(scene_data[2]and scene_data[2][2])or{}
  local lfo_data_A=(scene1_1.lfo_data or scene2_1.lfo_data)or{}
  local lfo_data_B=(scene1_2.lfo_data or scene2_2.lfo_data)or{}
  local lfo_targets=lfo.lfo_targets
  local lfo_targets_count=#lfo_targets
  local get_range=lfo.get_parameter_range
  local p_set=params.set
  local p_get=params.get
  local p_lookup=params.lookup
  local pitch_scale=params:string("pitch_quantize_scale")
  local has_tracking=lfo.clear_param_assignment and lfo.is_param_assigned and lfo.mark_param_assigned and lfo.get_lfo_for_param
  if has_tracking then
    for i=1,16 do
      local lfo_state=p_get(params,MORPH_LFO_KEYS[i])
      if lfo_state==2 then
        local target_idx=p_get(params,MORPH_TARGET_KEYS[i])
        local target_param=lfo_targets[target_idx]
        if target_param and target_param~="none"then lfo.clear_param_assignment(target_param)end
      end
    end
  end
  local function compute_offset(lfo_offset,const_val,target,t_weight,const_weight)
    return _compute_offset(lfo_offset,const_val,target,t_weight,const_weight,get_range)
  end
  local function ensure_unique_assignment(target,slot)
    _ensure_unique_assignment(target,slot,has_tracking,lfo,p_set,params)
  end
  for k in pairs(skip_param_set)do skip_param_set[k]=nil end
  for k in pairs(used_slots)do used_slots[k]=nil end
  local pending_count=0
  local DEPTH_THRESHOLD=0.01
  for i=1,16 do
    local lfo_A=lfo_data_A[i]
    local lfo_B=lfo_data_B[i]
    local lfo_A_enabled=lfo_A and lfo_A.enabled
    local lfo_B_enabled=lfo_B and lfo_B.enabled
    local should_be_on=lfo_A_enabled or lfo_B_enabled
    if not should_be_on then
      if p_get(params,MORPH_LFO_KEYS[i])==2 then p_set(params,MORPH_LFO_KEYS[i],1)end
      goto continue
    end
    used_slots[i]=true
    local target_A=lfo_A_enabled and lfo_A.target and lfo_targets[lfo_A.target]
    local target_B=lfo_B_enabled and lfo_B.target and lfo_targets[lfo_B.target]
    if lfo_A_enabled and lfo_A.target then
      if lfo_A.target<1 or lfo_A.target>lfo_targets_count then
        lfo_A_enabled=false
        target_A=nil
      end
    end
    if lfo_B_enabled and lfo_B.target then
      if lfo_B.target<1 or lfo_B.target>lfo_targets_count then
        lfo_B_enabled=false
        target_B=nil
      end
    end
    if lfo_A_enabled and lfo_B_enabled and target_A~=target_B and target_B and target_B~="none"then
      pending_count=pending_count+1
      pending[pending_count]={lfo=lfo_B,param=target_B}
    end
    local target=target_A or target_B
    if not target or target=="none"then goto continue end
    ensure_unique_assignment(target,i)
    skip_param_set[target]=true
    morph_temp_scene[target]=nil
    local lfo_enable_k  = MORPH_LFO_KEYS[i]
    local lfo_target_k  = MORPH_TARGET_KEYS[i]
    local lfo_shape_k   = MORPH_SHAPE_KEYS[i]
    local lfo_freq_k    = MORPH_FREQ_KEYS[i]
    local lfo_depth_k   = MORPH_DEPTH_KEYS[i]
    local offset_param_k= MORPH_OFFSET_KEYS[i]
    if lfo_A_enabled and lfo_B_enabled and target_A==target_B then
      p_set(params,lfo_target_k,lfo_A.target)
      p_set(params,lfo_shape_k,t<0.5 and lfo_A.shape or lfo_B.shape)
      p_set(params,lfo_freq_k,lfo_A.freq*t_inv+lfo_B.freq*t)
      local depth_val=lfo_A.depth*t_inv+lfo_B.depth*t
      p_set(params,lfo_depth_k,depth_val)
      p_set(params,offset_param_k,_morph_clamp(lfo_A.offset*t_inv+lfo_B.offset*t))
      p_set(params,lfo_enable_k,depth_val>=DEPTH_THRESHOLD and 2 or 1)
    elseif lfo_A_enabled and target_A==target then
      local const_val=scene1_2[target]or scene2_2[target]
      p_set(params,lfo_target_k,lfo_A.target)
      p_set(params,lfo_shape_k,lfo_A.shape)
      p_set(params,lfo_freq_k,lfo_A.freq)
      local depth_val=lfo_A.depth*t_inv
      p_set(params,lfo_depth_k,depth_val)
      p_set(params,offset_param_k,compute_offset(lfo_A.offset,const_val,target,t_inv,t))
      p_set(params,lfo_enable_k,depth_val>=DEPTH_THRESHOLD and 2 or 1)
    else
      local lfo_val=(lfo_B_enabled and lfo_B)or(lfo_A_enabled and lfo_A)
      if not lfo_val then goto continue end
      local const_val=scene1_1[target]or scene2_1[target]
      p_set(params,lfo_target_k,lfo_val.target)
      p_set(params,lfo_shape_k,lfo_val.shape)
      p_set(params,lfo_freq_k,lfo_val.freq)
      local depth_val=lfo_val.depth*t
      p_set(params,lfo_depth_k,depth_val)
      p_set(params,offset_param_k,compute_offset(lfo_val.offset,const_val,target,t,t_inv))
      p_set(params,lfo_enable_k,depth_val>=DEPTH_THRESHOLD and 2 or 1)
    end
    ::continue::
  end
  if pending_count>0 then
    for idx=1,pending_count do
      local m=pending[idx]
      local slot=nil
      for i=1,16 do
        if not used_slots[i]then
          slot=i
          used_slots[i]=true
          break
        end
      end
      if slot then
        ensure_unique_assignment(m.param,slot)
        skip_param_set[m.param]=true
        morph_temp_scene[m.param]=nil
        local depth_val=m.lfo.depth*t
        local const_val=scene1_1[m.param]or scene2_1[m.param]
        p_set(params,MORPH_TARGET_KEYS[slot],m.lfo.target)
        p_set(params,MORPH_SHAPE_KEYS[slot],m.lfo.shape)
        p_set(params,MORPH_FREQ_KEYS[slot],m.lfo.freq)
        p_set(params,MORPH_DEPTH_KEYS[slot],depth_val)
        p_set(params,MORPH_OFFSET_KEYS[slot],compute_offset(m.lfo.offset,const_val,m.param,t,t_inv))
        p_set(params,MORPH_LFO_KEYS[slot],depth_val>=DEPTH_THRESHOLD and 2 or 1)
      end
    end
  end
  local function interp(pname,valA,valB,track)
    local fparam=track and(track..pname)or pname
    if skip_param_set[fparam]or not p_lookup[fparam]then return end
    if not valA and not valB then return end
    if not valA then p_set(params,fparam,valB)return end
    if not valB or valA==valB then p_set(params,fparam,valA)return end
    local temp=morph_temp_scene[fparam]
    local new_val
    if not temp then
      new_val=valA*t_inv+valB*t
    else
      if morph_direction==0 then p_set(params,fparam,temp)return end
      local is_forward=morph_direction>0
      local tgt=is_forward and valB or valA
      local dist=is_forward and(100-morph_amount)or morph_amount
      if dist<=0 then
        morph_temp_scene[fparam]=nil
        p_set(params,fparam,tgt)
        return
      end
      local abs_dir=is_forward and morph_direction or-morph_direction
      local progress=math.min(abs_dir/dist,1.0)
      new_val=temp+(tgt-temp)*progress
    end
    if pname=="pitch"and track then new_val=quantize_pitch_to_scale(new_val,pitch_scale)end
    p_set(params,fparam,new_val)
    if temp then
      local is_forward=morph_direction>0
      local tgt=is_forward and valB or valA
      local diff=new_val-tgt
      morph_temp_scene[fparam]=(diff>-0.01 and diff<0.01)and nil or new_val
    end
  end
  for i=1,morph_voice_params_count do
    local pname=morph_voice_params[i]
    interp(pname,scene1_1["1"..pname],scene1_2["1"..pname],1)
  end
  for i=1,morph_voice_params_count do
    local pname=morph_voice_params[i]
    interp(pname,scene2_1["2"..pname],scene2_2["2"..pname],2)
  end
  for i=1,morph_global_params_count do
    local pname=morph_global_params[i]
    interp(pname,scene1_1[pname],scene1_2[pname])
  end
  invalidate_lfo_cache()
end

local function capture_to_temp_scene()
  if current_scene_mode~="on"then return end
  if morph_amount==0 or morph_amount==100 then return end
  local lfo_controlled_params={}
  for lfo_idx=1,16 do
    if params:get(lfo_idx.."lfo")==2 then
      local target_index=params:get(lfo_idx.."lfo_target")
      local target_param=lfo.lfo_targets[target_index]
      if target_param then lfo_controlled_params[target_param]=true end
    end
  end
  local p_lookup=params.lookup
  local p_get=params.get
  for track=1,2 do
    for i=1,morph_voice_params_count do
      local param_name=morph_voice_params[i]
      local full_param=track..param_name
      if p_lookup[full_param]and not lfo_controlled_params[full_param]then morph_temp_scene[full_param]=p_get(params,full_param)end
    end
  end
  for i=1,morph_global_params_count do
    local param=morph_global_params[i]
    if p_lookup[param]and not lfo_controlled_params[param]then morph_temp_scene[param]=p_get(params,param)end
  end
end

local function auto_save_to_scene()
  if current_scene_mode~="on"then return end
  if next(morph_temp_scene)~=nil then return end
  if morph_amount==0 then
    store_scene(1,1)
    store_scene(2,1)
    morph_temp_scene={}
  elseif morph_amount==100 then
    store_scene(1,2)
    store_scene(2,2)
    morph_temp_scene={}
  end
end

local function initialize_scenes_with_current_params()
  for track=1,2 do
    for scene=1,2 do
      store_scene(track,scene)
    end
  end
end

local function disable_lfos_for_param(param_name, only_self)
    local base_param = param_name:sub(2)
    if only_self then
        local is_active, lfo_index = is_lfo_active_for_param(param_name)
        if is_active then params:set(lfo_index .. "lfo", 1) invalidate_lfo_cache() end
    else
        for track = 1, 2 do
            local full_param = track .. base_param
            local is_active, lfo_index = is_lfo_active_for_param(full_param)
            if is_active then params:set(lfo_index .. "lfo", 1) invalidate_lfo_cache() end
        end
    end
end

local function get_audio_duration(filepath)
    if not filepath or filepath == "" or filepath == "none" or filepath == "-" then 
        for i = 1, 2 do if params:get(i.."live_input") == 1 then return params:get("live_buffer_length") end end
        return nil 
    end
    if not util.file_exists(filepath) then return nil end
    local ch, samples, rate = audio.file_info(filepath)
    if samples and rate and rate > 0 then return samples / rate end
    return nil
end

local function handle_lfo(param_name, force_disable)
    if force_disable then disable_lfos_for_param(param_name)
    else
        local active, idx = is_lfo_active_for_param(param_name)
        if active then params:set(idx.."lfo", 1) invalidate_lfo_cache() end
    end
end

local last_selected = {[1] = nil, [2] = nil}
local function scan_audio_files(dir)
    local files = {}
    for _, entry in ipairs(util.scandir(dir)) do
        local path = dir .. entry
        if entry:sub(-1) == "/" then for _, f in ipairs(scan_audio_files(path)) do files[#files+1] = f end
        elseif valid_audio_exts[path:lower():match("^.+(%..+)$") or ""] then files[#files+1] = path end
    end
    return files
end

local function set_track_sample(track_num, file)
    if params:get(track_num .. "live_input") == 1 then return false end
    if params:get(track_num .. "sample") ~= file then params:set(track_num .. "sample", file) end
    last_selected[track_num] = file
    return true
end

local function load_random_tape_file(track_num)
    local audio_files = scan_audio_files(_path.tape)
    if #audio_files == 0 then return false end
    if track_num then
        local file = audio_files[math.random(#audio_files)]
        return set_track_sample(track_num, file)
    end
    local file1 = audio_files[math.random(#audio_files)]
    local file2 = (math.random() < 0.5) and file1 or audio_files[math.random(#audio_files)]
    set_track_sample(1, file1)
    set_track_sample(2, file2)
    return true
end

local function register_tap()
    local now = util.time()
    if #tap_times > 0 and (now - tap_times[#tap_times]) > TAP_TIMEOUT then tap_times = {} end
    table.insert(tap_times, now)
    while #tap_times > 3 do table.remove(tap_times, 1) end
    if #tap_times >= 2 then
        local sum, count = 0, 0
        for i = math.max(2, #tap_times - 2), #tap_times do
            sum = sum + (tap_times[i] - tap_times[i - 1])
            count = count + 1
        end
        local avg_interval = sum / count
        params:set("delay_time", util.clamp(avg_interval, 0.02, 2))
    end
end

local function setup_params()
    params:add_separator("Input")
    for i = 1, 2 do
      params:add_file(i.."sample","Sample "..i); params:set_action(i.."sample",function(f) if f~=nil and f~="" and f~="none" and f~="-" then local jitter_locked=is_param_locked(i,"jitter"); if not jitter_locked then lfo.clearLFOs(tostring(i),"jitter"); end engine.read(i,f); audio_active[i]=true; update_pan_positioning(); local is_live=params:get(i.."live_input")==1; local dur=is_live and params:get("live_buffer_length") or get_audio_duration(f); if dur then cached_buffer_durations[i]=dur; local ms=dur*1000; local max_jit=math.min(ms,99999); params:set(i.."max_jitter",max_jit); params:set(i.."min_jitter",0); if not _G.preset_loading and not jitter_locked then local jp=i.."jitter"; handle_lfo(jp,true); local jitter_val; if math.random()<0.75 then local upper_limit=math.min(500,dur*1000); jitter_val=util.clamp(math.random()*upper_limit,0,99999); else jitter_val=util.clamp(math.random()*dur*1000,0,99999); end params:set(jp,jitter_val); end else if not jitter_locked then lfo.clearLFOs(tostring(i),"jitter"); end audio_active[i]=false; osc_positions[i]=0; update_pan_positioning(); end end end)
    end
    params:add_binary("randomtapes", "Random Tapes", "trigger", 0) params:set_action("randomtapes", function() load_random_tape_file() end)
    
    params:add_group("LIVE!", 10)
    for i = 1, 2 do
      params:add_binary(i.."live_input", "Live Buffer "..i.." ● ►", "toggle", 0) params:set_action(i.."live_input", function(value) if value == 1 then if params:get(i.."live_direct") == 1 then params:set(i.."live_direct", 0) end engine.set_live_input(i, 1) engine.live_mono(i, params:get("isMono") - 1) audio_active[i] = true cached_buffer_durations[i]=params:get("live_buffer_length") update_pan_positioning() else engine.set_live_input(i, 0) if not audio_active[i] and params:get(i.."live_direct") == 0 then osc_positions[i] = 0 else update_pan_positioning() end end end)
    end
    params:add_control("live_buffer_mix", "Overdub", controlspec.new(0, 100, "lin", 1, 100, "%")) params:set_action("live_buffer_mix", function(value) engine.live_buffer_mix(value * 0.01) end)
    params:add_taper("live_buffer_length", "Buffer Length", 0.05, 10, 2, 3, "s") params:set_action("live_buffer_length", function(value) engine.live_buffer_length(value) for i=1,2 do if params:get(i.."live_input")==1 then cached_buffer_durations[i]=value end end end)
    params:add{type = "trigger", id = "save_live_buffer1", name = "Buffer1 to Tape", action = function() local timestamp = os.date("%Y%m%d_%H%M%S") local filename = "live1_"..timestamp..".wav" engine.save_live_buffer(1, filename) end}
    params:add{type = "trigger", id = "save_live_buffer2", name = "Buffer2 to Tape", action = function() local timestamp = os.date("%Y%m%d_%H%M%S") local filename = "live2_"..timestamp..".wav" engine.save_live_buffer(2, filename) end}
    for i = 1, 2 do
      params:add_binary(i.."live_direct", "Direct "..i.." ►", "toggle", 0) params:set_action(i.."live_direct", function(value) if value == 1 then local was_live = params:get(i.."live_input") if was_live == 1 then params:set(i.."live_input", 0) end engine.live_direct(i, 1) audio_active[i] = true update_pan_positioning() else engine.live_direct(i, 0) if not audio_active[i] and params:get(i.."live_input") == 0 then osc_positions[i] = 0 else update_pan_positioning() end end end)
    end
    params:add_option("isMono", "Input Mode", {"stereo", "mono"}, 1) params:set_action("isMono", function(value) local monoValue = value - 1 for i = 1, 2 do if params:get(i.."live_direct") == 1 then engine.isMono(i, monoValue) end if params:get(i.."live_input") == 1 then engine.live_mono(i, monoValue) end end end)
    params:add_binary("dry_mode2", "Dry Mode", "toggle", 0) params:set_action("dry_mode2", function(x) drymode.toggle_dry_mode2() end)
    
    params:add{type = "trigger", id = "save_preset", name = "Save Preset", action = function() presets.save_complete_preset(nil, scene_data, current_scene_mode, initialize_scenes_with_current_params) end}
    params:add{type = "trigger", id = "load_preset_menu", name = "Preset Browser", action = function() presets.open_menu() end}

    params:add_separator("Settings")
    params:add_group("GRANULAR", 39)
    for i = 1, 2 do
      params:add_separator("SAMPLE "..i)
      params:add_control(i.. "granular_gain", i.. " Mix", controlspec.new(0, 100, "lin", 1, 100, "%")) params:set_action(i.. "granular_gain", function(value) engine.granular_gain(i, value * 0.01) if value < 100 then lfo.clearLFOs(i, "seek") end end)
      params:add_control(i.. "subharmonics_3", i.. " Subharmonics -3oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0)) params:set_action(i.. "subharmonics_3", function(value) engine.subharmonics_3(i, value) end)
      params:add_control(i.. "subharmonics_2", i.. " Subharmonics -2oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0)) params:set_action(i.. "subharmonics_2", function(value) engine.subharmonics_2(i, value) end)
      params:add_control(i.. "subharmonics_1", i.. " Subharmonics -1oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0)) params:set_action(i.. "subharmonics_1", function(value) engine.subharmonics_1(i, value) end)
      params:add_control(i.. "overtones_1", i.. " Overtones +1oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0)) params:set_action(i.. "overtones_1", function(value) engine.overtones_1(i, value) end)
      params:add_control(i.. "overtones_2", i.. " Overtones +2oct", controlspec.new(0.00, 1.00, "lin", 0.01, 0)) params:set_action(i.. "overtones_2", function(value) engine.overtones_2(i, value) end)
      params:add_option(i.. "smoothbass", i.." Smooth Sub", {"off", "on"}, 1) params:set_action(i.. "smoothbass", function(x) local engine_value = (x == 2) and 2.5 or 1 engine.smoothbass(i, engine_value) end)
      params:add_control(i.."pitch_random_prob", i.." Pitch Randomize", controlspec.new(-100, 100, "lin", 1, 0, "%")) params:set_action(i.."pitch_random_prob", function(value) engine.pitch_random_prob(i, value) end)
      params:add_option(i.."pitch_random_scale_type", i.." Pitch Quantize", {"5th+oct", "5th+oct 2", "1 oct", "2 oct", "chrom", "maj", "min", "penta", "whole"}, 1) params:set_action(i.."pitch_random_scale_type", function(value) engine.pitch_random_scale_type(i, value - 1) end)
      params:add_control(i.."ratcheting_prob", i.." Ratcheting", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.."ratcheting_prob", function(value) engine.ratcheting_prob(i, value) end)
      params:add_option(i.."env_select", i.." Grain Envelope", {"Hann", "Triangle", "Tukey", "Perc.", "Rev. Perc.", "ADSR", "Random"}, 1) params:set_action(i.."env_select", function(value) engine.env_select(i, value - 1) end)
      params:add_control(i.. "size_variation", i.. " Size Variation", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.. "size_variation", function(value) engine.size_variation(i, value * 0.01) end)
      params:add_control(i.. "direction_mod", i.. " Reverse", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.. "direction_mod", function(value) engine.direction_mod(i, value * 0.01) end)
      params:add_control(i.. "density_mod_amt", i.. " Density Mod", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action(i.. "density_mod_amt", function(value) engine.density_mod_amt(i, value * 0.01) end)      
      params:add_option(i.. "trig_mode", i.. " Trigger Mode", {"impulse", "dust"}, 1) params:set_action(i.."trig_mode", function(value) engine.trig_mode(i, value-1) end)
      params:add_control(i.."probability", i.." Trigger Probability", controlspec.new(0, 100, "lin", 1, 100, "%")) params:set_action(i.."probability", function(value) engine.probability(i, value * 0.01) end)
      params:add_option(i.. "pitch_mode", i.. " Pitch Mode", {"match speed", "independent"}, 2) params:set_action(i.. "pitch_mode", function(value) engine.pitch_mode(i, value - 1) end)
    end
    params:add_separator(" ")
    params:add_binary("randomize_granular", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_granular", function() for i=1, 2 do randpara.randomize_granular_params(i) end end)
    params:add_option("lock_granular", "Lock Parameters", {"off", "on"}, 1)

    params:add_group("DELAY", 12)
    params:add_control("delay_mix", "Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("delay_mix", function(x) engine.mix(x * 0.01) font.update_fx_cache("delay_mix", x) end)
    params:add_taper("delay_time", "Time", 0.02, 2, 0.5, 0.1, "s") params:set_action("delay_time", function(value) engine.delay(value) end)
    params:add_binary("tap", "↳ TAP!", "trigger", 0) params:set_action("tap", function() register_tap() end)
    params:add_taper("delay_feedback", "Feedback", 0, 120, 30, 1, "%") params:set_action("delay_feedback", function(value) engine.fb_amt(value * 0.01) end)
    params:add_control("delay_lowpass", "LPF", controlspec.new(20, 20000, 'exp', 1, 20000, "Hz")) params:set_action('delay_lowpass', function(value) engine.lpf(value) end)
    params:add_control("delay_highpass", "HPF", controlspec.new(20, 20000, 'exp', 1, 20, "Hz")) params:set_action('delay_highpass', function(value) engine.dhpf(value) end)
    params:add_taper("wiggle_depth", "Mod Depth", 0, 100, 5, 0, "%") params:set_action("wiggle_depth", function(value) engine.w_depth(value * 0.01) end)
    params:add_taper("wiggle_rate", "Mod Freq", 0, 20, 2, 1, "Hz") params:set_action("wiggle_rate", function(value) engine.w_rate(value) end)
    params:add_control("stereo", "Ping-Pong", controlspec.new(0, 100, "lin", 1, 30, "%")) params:set_action("stereo", function(x) engine.stereo(x * 0.01) end)
    params:add_separator("   ")
    params:add_binary("randomize_delay_params", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_delay_params", function() randpara.randomize_delay_params(steps) end)
    params:add_option("lock_delay", "Lock Parameters", {"off", "on"}, 1)

    params:add_group("R3VERB", 17)
    params:add_taper("reverb_mix", "Mix", 0, 100, 0.0, 0, "%") params:set_action("reverb_mix", function(value) engine.reverb_mix(value * 0.01) font.update_fx_cache("reverb_mix", value) end)
    params:add_taper("shimmer_mix", "Shimmer", 0, 100, 0, 0, "%") params:set_action("shimmer_mix", function(value) engine.shimmer_mix(value * 0.01) end)
    params:add_option("shimmer_preset", "Pitch Shift", {"-2 oct", "-1 oct", "0", "+1 oct", "+2 oct"}, 4) params:set_action("shimmer_preset", function(idx) local preset = shimmer_presets[idx] engine.shimmer_oct(preset.oct) engine.shimmer_lowpass(preset.lowpass) engine.shimmer_hipass(preset.hipass) engine.shimmer_fb(preset.fb) end)
    params:add_taper("t60", "Decay", 0.1, 60, 4, 5, "s") params:set_action("t60", function(value) engine.t60(value) end)
    params:add_taper("damp", "Damping", 0, 100, 0, 0, "%") params:set_action("damp", function(value) engine.damp(value * 0.01) end)
    params:add_taper("rsize", "Size", 0.5, 5, 1.25, 0, "") params:set_action("rsize", function(value) engine.rsize(value) end)
    params:add_taper("earlyDiff", "Early Diffusion", 0, 100, 70.7, 0, "%") params:set_action("earlyDiff", function(value) engine.earlyDiff(value * 0.01) end)
    params:add_taper("modDepth", "Mod Depth", 0, 100, 10, 0, "%") params:set_action("modDepth", function(value) engine.modDepth(value * 0.01) end)
    params:add_taper("modFreq", "Mod Frequency", 0, 10, 0.2, 0, "Hz") params:set_action("modFreq", function(value) engine.modFreq(value) end)
    params:add_control("low", "Low Decay", controlspec.new(0, 1, "lin", 0.01, 1, "x")) params:set_action("low", function(value) engine.low(value) end)
    params:add_control("mid", "Mid Decay", controlspec.new(0, 1, "lin", 0.01, 1, "x")) params:set_action("mid", function(value) engine.mid(value) end)
    params:add_control("high", "High Decay", controlspec.new(0, 1, "lin", 0.01, 1, "x")) params:set_action("high", function(value) engine.high(value) end)
    params:add_taper("lowcut", "Low-Mid X", 100, 6000, 500, 2, "Hz") params:set_action("lowcut", function(value) engine.lowcut(value) end)
    params:add_taper("highcut", "Mid-High X", 1000, 10000, 2000, 2, "Hz") params:set_action("highcut", function(value) engine.highcut(value) end)
    params:add_separator("  ")
    params:add_binary("randomize_jpverb", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_jpverb", function() randpara.randomize_jpverb_params(steps) end)
    params:add_option("lock_reverb", "Lock Parameters", {"off", "on"}, 1)

    params:add_group("SHIMMER", 9)
    params:add_control("shimmer_mix1", "Mix", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("shimmer_mix1", function(x) engine.shimmer_mix1(x * 0.01) font.update_fx_cache("shimmer_mix1", x) end)
    params:add_option("shimmer_oct1", "Pitch Shift", {"-2 oct", "-1 oct", "0", "+1 oct", "+2 oct"}, 4) params:set_action("shimmer_oct1", function(x) local octave_values = {0.25, 0.5, 1, 2, 4} engine.shimmer_oct1(octave_values[x]) end)
    params:add_control("pitchv1", "Variance", controlspec.new(0, 100, "lin", 1, 2, "%")) params:set_action("pitchv1", function(x) engine.pitchv1(x * 0.01) end)
    params:add_control("lowpass1", "LPF", controlspec.new(20, 20000, "lin", 1, 13000, "Hz")) params:set_action("lowpass1", function(x) engine.lowpass1(x) end)
    params:add_control("hipass1", "HPF", controlspec.new(20, 20000, "exp", 1, 1400, "Hz")) params:set_action("hipass1", function(x) engine.hipass1(x) end)
    params:add_control("fbDelay1", "Delay", controlspec.new(0.01, 0.5, "lin", 0.01, 0.2, "s")) params:set_action("fbDelay1", function(x) engine.fbDelay1(x) end)
    params:add_control("fb1", "Feedback", controlspec.new(0, 100, "lin", 1, 15, "%")) params:set_action("fb1", function(x) engine.fb1(x * 0.01) end)
    params:add_separator("        ")
    params:add_option("lock_shimmer", "Lock Parameters", {"off", "on"}, 1)
    
    params:add_group("TAPE", 16) 
    params:add_option("tape_mix", "Analog Tape", {"off", "on"}, 1) params:set_action("tape_mix", function(x) engine.tape_mix(x-1) font.update_fx_cache("tape_mix", x) end)
    params:add_control("sine_drive_wet", "Shaper Drive", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("sine_drive_wet", function(value) engine.sine_drive_wet(value * 0.01) font.update_fx_cache("sine_drive_wet", value) end)
    params:add_control("drive", "Saturation", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("drive", function(x) engine.drive(x * 0.01) font.update_fx_cache("drive", x) end)
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
    params:add_binary("randomize_tape", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_tape", function() randpara.randomize_tape_params(steps) end)
    params:add_option("lock_tape", "Lock Parameters", {"off", "on"}, 1)    
    
    params:add_group("EQ", 9)
    for i = 1, 2 do 
    params:add_control(i.."eq_low_gain", i.." Bass", controlspec.new(-1, 1, "lin", 0.01, 0, "")) params:set_action(i.."eq_low_gain", function(value) engine.eq_low_gain(i, value*55) end)
    params:add_control(i.."eq_mid_gain", i.." Mid", controlspec.new(-1, 1, "lin", 0.01, 0, "")) params:set_action(i.."eq_mid_gain", function(value) engine.eq_mid_gain(i, value*20) end)
    params:add_control(i.."eq_high_gain", i.." Treble", controlspec.new(-1, 1, "lin", 0.01, 0, "")) params:set_action(i.."eq_high_gain", function(value) engine.eq_high_gain(i, value*45) end)
    end
    params:add_separator("     ")
    params:add_binary("randomize_eq", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_eq", function() for i=1, 2 do randpara.randomize_eq_params(i) end end)
    params:add_option("lock_eq", "Lock Parameters", {"off", "on"}, 1)
    
    params:add_group("LFO", 118)
    params:add_binary("randomize_lfos", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_lfos", function() lfo.clearLFOs() local allow_vol = params:get("allow_volume_lfos") == 2 for i = 1, 2 do lfo.randomize_lfos(i, allow_vol) end invalidate_lfo_cache() end)
    params:add_binary("lfo.assign_to_current_row", "Assign to Selection", "trigger", 0) params:set_action("lfo.assign_to_current_row", function() lfo.assign_to_current_row(current_mode, current_filter_mode) invalidate_lfo_cache() end)
    params:add_control("global_lfo_freq_scale", "Freq Scale", controlspec.new(0.1, 10, "exp", 0.01, 1, "x")) params:set_action("global_lfo_freq_scale", function(value) local base_freq for i = 1, 16 do local phase = lfo[i].phase base_freq = params:get(i.."lfo_freq") or 0.05 lfo[i].base_freq = base_freq lfo[i].freq = base_freq * value lfo[i].phase = phase end end)
    params:add_binary("lfo_pause", "Pause ⏸︎", "toggle", 0) params:set_action("lfo_pause", function(value) lfo.set_pause(value == 1) end)
    params:add_binary("ClearLFOs", "Clear All", "trigger", 0) params:set_action("ClearLFOs", function() lfo.clearLFOs() invalidate_lfo_cache() update_pan_positioning() end)
    params:add_option("allow_volume_lfos", "Allow Volume LFOs", {"no", "yes"}, 1) params:set_action("allow_volume_lfos", function(value) if value == 2 then lfo.clearLFOs("1", "volume") lfo.clearLFOs("2", "volume") lfo.assign_volume_lfos() else lfo.clearLFOs("1", "volume") lfo.clearLFOs("2", "volume") end invalidate_lfo_cache() end)
    lfo.init()
    
    params:add_group("STEREO", 5)
    params:add_control("Width", "Stereo Width", controlspec.new(0, 200, "lin", 2, 100, "%")) params:set_action("Width", function(value) engine.width(value * 0.01) font.update_fx_cache("Width", value) end)
    params:add_control("dimension_mix", "Dimension", controlspec.new(0, 100, "lin", 2, 0, "%")) params:set_action("dimension_mix", function(value) engine.dimension_mix(value * 0.01) font.update_fx_cache("dimension_mix", value) end)
    params:add_option("haas", "Haas Effect", {"off", "on"}, 1) params:set_action("haas", function(x) engine.haas(x-1) font.update_fx_cache("haas", x) end)
    params:add_taper("rspeed", "Rotation", 0, 1, 0, 1, "Hz") params:set_action("rspeed", function(value) engine.rspeed(value) font.update_fx_cache("rspeed", value) end)
    params:add_option("monobass_mix", "Mono Bass", {"off", "on"}, 1) params:set_action("monobass_mix", function(x) engine.monobass_mix(x-1) font.update_fx_cache("monobass_mix", x) end)

    params:add_group("BITCRUSH", 3)
    params:add_taper("bitcrush_mix", "Mix", 0, 100, 0.0, 0, "%") params:set_action("bitcrush_mix", function(value) engine.bitcrush_mix(value * 0.01) font.update_fx_cache("bitcrush_mix", value) end)
    params:add_taper("bitcrush_rate", "Rate", 1, 48000, 4500, 3, "Hz") params:set_action("bitcrush_rate", function(value) engine.bitcrush_rate(value) end)
    params:add_taper("bitcrush_bits", "Bits", 1, 24, 14, 1) params:set_action("bitcrush_bits", function(value) engine.bitcrush_bits(value) end)

    params:add_group("GLITCH", 9)
    params:add_control("glitch_ratio", "Glitch", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("glitch_ratio", function(value) engine.glitch_ratio(value * 0.01) font.update_fx_cache("glitch_ratio", value) end)
    params:add_control("glitch_mix", "Mix", controlspec.new(0, 100, "lin", 1, 100, "%")) params:set_action("glitch_mix", function(value) engine.glitch_mix(value * 0.01) font.update_fx_cache("glitch_mix", value) end)
    params:add_taper("glitch_probability", "Frequency", 0.1, 20, 3, 1, "Hz") params:set_action("glitch_probability", function(value) engine.glitch_probability(value) end)
    params:add_control("glitch_min_length", "Min Length", controlspec.new(10, 500, "lin", 1, 100, "ms")) params:set_action("glitch_min_length", function(value) engine.glitch_min_length(value * 0.001) end)
    params:add_control("glitch_max_length", "Max Length", controlspec.new(20, 500, "lin", 1, 250, "ms")) params:set_action("glitch_max_length", function(value) engine.glitch_max_length(value * 0.001) end)
    params:add_control("glitch_reverse", "Reverse Prob", controlspec.new(0, 100, "lin", 1, 25, "%")) params:set_action("glitch_reverse", function(value) engine.glitch_reverse(value * 0.01) end)
    params:add_control("glitch_pitch", "Pitch Prob", controlspec.new(0, 100, "lin", 1, 50, "%")) params:set_action("glitch_pitch", function(value) engine.glitch_pitch(value * 0.01) end)
    params:add_separator("       ")
    params:add_binary("randomize_glitch", "RaNd0m1ze!", "trigger", 0) params:set_action("randomize_glitch", function() if params:get("lock_glitch") == 1 then params:set("glitch_probability", math.random(1, 150) / 10) params:set("glitch_min_length", math.random(10, 200)) params:set("glitch_max_length", math.random(100, 500)) params:set("glitch_reverse", math.random(0, 100)) params:set("glitch_pitch", math.random(0, 100)) end end)

    params:add_group("EVOLVE", 3)
    params:add_binary("evolution", "Evolve!", "toggle", 0) params:set_action("evolution", function(value) if value == 1 then randpara.reset_evolution_centers() randpara.start_evolution() else randpara.stop_evolution() end end)
    params:add_control("evolution_range", "Evolution Range", controlspec.new(0, 100, "lin", 1, 10, "%")) params:set_action("evolution_range", function(value) randpara.set_evolution_range(value) end)
    params:add_option("evolution_rate", "Evolution Rate", {"slowest", "slow", "moderate", "medium", "fast", "crazy"}, 2) params:set_action("evolution_rate", function(value) local rates = {1/0.5, 1/1.5, 1/4, 1/8, 1/15, 1/30} randpara.set_evolution_rate(rates[value]) end)

    params:add_group("SYMMETRY", 3)
    params:add_binary("symmetry", "Symmetry", "toggle", 0)
    params:add_binary("copy_1_to_2", "Copy 1 → 2", "trigger", 0) params:set_action("copy_1_to_2", function() Mirror.copy_voice_params("1", "2", true) end)
    params:add_binary("copy_2_to_1", "Copy 1 ← 2", "trigger", 0) params:set_action("copy_2_to_1", function() Mirror.copy_voice_params("2", "1", true) end)

    params:add_group("FILTER", 10)
    for i = 1, 2 do
      params:add_control(i.."cutoff",i.." LPF",controlspec.new(20,20000,"exp",0,20000,"Hz")) params:set_action(i.."cutoff", function(value) engine.cutoff(i, value) font.update_fx_cache(i.."cutoff", value) if filter_lock_ratio then local new_hpf = value - filter_differences[i] new_hpf = util.clamp(new_hpf, 20, 20000) params:set(i.."hpf", new_hpf) end end)
      params:add_control(i.."hpf",i.." HPF",controlspec.new(20,20000,"exp",0,20,"Hz")) params:set_action(i.."hpf", function(value) engine.hpf(i, value) font.update_fx_cache(i.."hpf", value) if filter_lock_ratio then local new_cutoff = value + filter_differences[i] new_cutoff = util.clamp(new_cutoff, 20, 20000) params:set(i.."cutoff", new_cutoff) end end)
      params:add_taper(i.."lpfgain", i.." Q", 0, 1, 0, 1, "") params:set_action(i.."lpfgain", function(value) engine.lpfgain(i, value * 4) end)
    end
    params:add_separator("                   ")
    params:add_binary("filter_lock_ratio", "Lock Filter Spread", "toggle", 0) params:set_action("filter_lock_ratio", function(value) filter_lock_ratio = value == 1 if filter_lock_ratio then for i = 1, 2 do local cutoff = params:get(i.."cutoff") local hpf = params:get(i.."hpf") filter_differences[i] = cutoff - hpf end end end)
    params:add_binary("randomizefilters", "RaNd0m1ze!", "trigger", 0) params:set_action("randomizefilters", function(value) for i = 1, 2 do local cutoff = math.random(20, 20000) params:set(i.."cutoff", cutoff) params:set(i.."lpfgain", math.random()) params:set(i.."hpf", math.random(20, math.floor(cutoff))) end end)
    params:add_binary("resetfilters", "Reset", "trigger", 0) params:set_action("resetfilters", function(value) params:set("filter_lock_ratio", 0) for i=1, 2 do params:set(i.."cutoff", 20000) params:set(i.."hpf", 20) params:set(i.."lpfgain", 0.0) end end)

    params:add_group("PITCH", 4)
    params:add_option("pitch_quantize_scale", "Pitch Quantize", {"off", "major", "minor", "dorian", "phrygian", "lydian", "mixolydian", "locrian", "major pent.", "minor pent.", "blues", "whole tone"}, 2) params:set_action("pitch_quantize_scale", function(value) local scale = params:string("pitch_quantize_scale") if scale ~= "none" then for i = 1, 2 do local current_pitch = params:get(i.."pitch") local quantized = quantize_pitch_to_scale(current_pitch, scale) if current_pitch ~= quantized then params:set(i.."pitch", quantized) end end end end)
    params:add_option("pitch_lag", "Pitch Lag", {"off", "very small", "small", "medium", "high", "very high"}, 1) params:set_action("pitch_lag", function(value) local lag_times = {0, 1, 2, 4, 8, 16} local lag_time = lag_times[value] for i = 1, 2 do engine.pitch_lag(i, lag_time) end end)
    params:add_separator("                                 ")
    params:add_option("lock_pitch", "Lock Parameters", {"off", "on"}, 1)

    params:add_group("LOCKING", 16)
    for i = 1, 2 do
        params:add_option(i.. "lock_jitter", i.. " Lock Jitter", {"off", "on"}, 1)
        params:add_option(i.. "lock_size", i.. " Lock Size", {"off", "on"}, 1)
        params:add_option(i.. "lock_density", i.. " Lock Density", {"off", "on"}, 1)
        params:add_option(i.. "lock_spread", i.. " Lock Spread", {"off", "on"}, 1)
        params:add_option(i.. "lock_pitch", i.. " Lock Pitch", {"off", "on"}, 1)
        params:add_option(i.. "lock_speed", i.. " Lock Speed", {"off", "on"}, 1)
        params:add_option(i.. "lock_seek", i.. " Lock Seek", {"off", "on"}, 1)
        params:add_option(i.. "lock_pan", i.. " Lock Pan", {"off", "on"}, 1)
    end

    params:add_group("LIMITS", 30) 
    for i = 1, 2 do
        params:add_separator("Voice "..i)
        params:add_taper(i.."min_jitter", i.." jitter (min)", 0, 999999, 0, 5, "ms")
        params:add_taper(i.."max_jitter", i.." jitter (max)", 0, 999999, 4999, 5, "ms") params:set_action(i.."max_jitter", function(value) lfo.clear_range_cache() end)
        params:add_taper(i.."min_size", i.." size (min)", 20, 999, 50, 5, "ms")
        params:add_taper(i.."max_size", i.." size (max)", 20, 999, 599, 5, "ms")
        params:add_taper(i.."min_density", i.." density (min)", 0.1, 50, 0.5, 5, "Hz")
        params:add_taper(i.."max_density", i.." density (max)", 0.1, 50, 25, 5, "Hz")
        params:add_taper(i.."min_spread", i.." spread (min)", 0, 100, 0, 0, "%")
        params:add_taper(i.."max_spread", i.." spread (max)", 0, 100, 100, 0, "%")
        params:add_control(i.."min_pitch", i.." pitch (min)", controlspec.new(-48, 48, "lin", 1, -31, "st"))
        params:add_control(i.."max_pitch", i.." pitch (max)", controlspec.new(-48, 48, "lin", 1, 31, "st"))
        params:add_taper(i.."min_speed", i.." speed (min)", -2, 2, -0.15, 0, "x")
        params:add_taper(i.."max_speed", i.." speed (max)", -2, 2, 0.5, 0, "x")
        params:add_taper(i.."min_seek", i.." seek (min)", 0, 100, 0, 0, "%")
        params:add_taper(i.."max_seek", i.." seek (max)", 0, 100, 100, 0, "%")
    end
    
    params:add_group("ACTIONS", 2)
    params:add_binary("macro_more", "More+", "trigger", 0) params:set_action("macro_more", function() macro.macro_more() end)
    params:add_binary("macro_less", "Less-", "trigger", 0) params:set_action("macro_less", function() macro.macro_less() end)
    
    params:add_group("MORPHING", 5)
    params:add_option("scene_mode", "Morph Mode", {"off", "on"}, 1) params:set_action("scene_mode", function(value) current_scene_mode = (value == 2) and "on" or "off" if current_scene_mode == "on" then local scenes_empty = true for track = 1, 2 do for scene = 1, 2 do if scene_data[track] and scene_data[track][scene] and next(scene_data[track][scene]) ~= nil then scenes_empty = false break end end if not scenes_empty then break end end if scenes_empty then initialize_scenes_with_current_params() end end end)
    params:add_control("morph_amount", "Morph", controlspec.new(0, 100, "lin", 1, 0, "%")) params:set_action("morph_amount", function(value) morph_amount = value apply_morph() end)
    params:add{type = "trigger", id = "save_to_scene1", name = "Morph Target A", action = function() store_scene(1, 1) store_scene(2, 1) end}
    params:add{type = "trigger", id = "save_to_scene2", name = "Morph Target B", action = function() store_scene(1, 2) store_scene(2, 2) end}
    params:add{type = "trigger", id = "delete_morph_data", name = "Delete Morph Data", action = function() scene_data = {[1] = {[1] = {}, [2] = {}}, [2] = {[1] = {}, [2] = {}}} morph_amount = 0 params:set("morph_amount", 0) params:set("scene_mode", 1) current_scene_mode = "off" end}
    
    params:add_group("LOOP", 3)
    params:add{type = "trigger", id = "save_output_buffer_only", name = "Save", action = function() local filename = "twins_output.wav" if engine.save_output_buffer_only then showing_save_message = true engine.save_output_buffer_only(filename) end end}
    params:add{type = "trigger", id = "save_output_buffer", name = "Bounce", action = function() local filename = "twins_output.wav" if engine.save_output_buffer then showing_save_message = true engine.save_output_buffer(filename) end end}
    params:add_control("output_buffer_length", "Loop Length", controlspec.new(1, 60, "lin", 1, 8, "s")) params:set_action("output_buffer_length", function(value) engine.set_output_buffer_length(value + 1) end)    
    
    params:add_group("OTHER", 6)
    params:add_binary("dry_mode", "Dry Mode", "toggle", 0) params:set_action("dry_mode", function(x) drymode.toggle_dry_mode() end)
    params:add_binary("randomtape1", "Random Tape 1", "trigger", 0) params:set_action("randomtape1", function() load_random_tape_file(1) end)
    params:add_binary("randomtape2", "Random Tape 2", "trigger", 0) params:set_action("randomtape2", function() load_random_tape_file(2) end)
    params:add_binary("unload_all", "Unload All Audio", "trigger", 0) params:set_action("unload_all", function() for i=1, 2 do params:set(i.."seek", 0) params:set(i.."sample", "-") params:set(i.."live_input", 0) params:set(i.."live_direct", 0) audio_active[i] = false osc_positions[i] = 0 end engine.unload_all() update_pan_positioning() end)
    params:add_binary("global_pitch_size_density_link", "Linked Mode", "toggle", 0) params:set_action("global_pitch_size_density_link", function(value) if value == 1 then for i = 1, 2 do local pitch = params:get(i.."pitch") local size = params:get(i.."size") local density = params:get(i.."density") if size > 0 and density > 0 then local lb = link_base[i] lb.pitch = pitch lb.size = size lb.density = density lb.product = size * density end end end end)
    params:add_option("steps", "Transition Time", {"short", "medium", "long"}, 1) params:set_action("steps", function(value) steps = ({20, 300, 800})[value] end)

    for i = 1, 2 do
      params:add_taper(i.. "volume", i.. " volume", -70, 10, -15, 0, "dB") params:set_action(i.. "volume", function(value) if value == -70 then engine.volume(i, 0) else engine.volume(i, math.pow(10, value / 20)) end end) params:hide(i.. "volume")
      params:add_taper(i.. "pan", i.. " pan", -100, 100, 0, 0, "%") params:set_action(i.. "pan", function(value) engine.pan(i, value * 0.01)  end) params:hide(i.. "pan")
      params:add_taper(i.. "speed", i.. " speed", -2, 2, 0.10, 0) params:set_action(i.. "speed", function(value) if math.abs(value) < 0.01 then engine.speed(i, 0) else engine.speed(i, value) end end) params:hide(i.. "speed")
      params:add_taper(i.. "density", i.. " density", 0.1, 300, 3.5, 5) params:set_action(i.. "density", function(value) engine.density(i, value) end) params:hide(i.. "density")
      params:add_control(i.. "pitch", i.. " pitch", controlspec.new(-48, 48, "lin", 1, 0, "st")) params:set_action(i.. "pitch", function(value) 
        local scale = params:string("pitch_quantize_scale")
        local quantized = quantize_pitch_to_scale(value, scale)
        engine.pitch_offset(i, math.pow(0.5, -quantized / 12)) 
      end) params:hide(i.. "pitch")
      params:add_taper(i.. "jitter", i.. " jitter", 0, 999900, 250, 10, "ms") params:set_action(i.. "jitter", function(value) engine.jitter(i, value * 0.001) end) params:hide(i.. "jitter")
      params:add_taper(i.. "size", i.. " size", 20, 5999, 500, 1, "ms") params:set_action(i.. "size", function(value) engine.size(i, value * 0.001) end) params:hide(i.. "size")
      params:add_taper(i.. "spread", i.. " spread", 0, 100, 50, 0, "%") params:set_action(i.. "spread", function(value) engine.spread(i, value * 0.01) end) params:hide(i.. "spread")
      params:add_control(i.. "seek", i.. " seek", controlspec.new(0, 100, "lin", 0.01, 0, "%")) params:set_action(i.. "seek", function(value) engine.seek(i, value * 0.01) end) params:hide(i.. "seek")
    end
    params:bang()
end

local function randomize_pitch(track, other_track, symmetry)
    local function set_pitch(track, other_track, new_pitch, symmetry)
		local scale = params:string("pitch_quantize_scale")
		    new_pitch = quantize_pitch_to_scale(new_pitch, scale)
		    local current = params:get(track.."pitch")
		    if current ~= new_pitch then params:set(track.."pitch", new_pitch) if symmetry then params:set(other_track.."pitch", new_pitch) end	end
    end
    local current_pitch = params:get(track .. "pitch")
    local min_pitch = math.max(params:get(track.."min_pitch"), current_pitch - 48)
    local max_pitch = math.min(params:get(track.."max_pitch"), current_pitch + 48)
    if min_pitch >= max_pitch then return end
    local base_pitch = params:get(other_track .. "pitch")
    local scale_name = params:string("pitch_quantize_scale")
    local scale = get_scale_intervals(scale_name)
    if not scale then return end
    local weighted_intervals = {}
    local larger_intervals = {}
    for octave = -2, 2 do
        for _, degree in ipairs(scale) do
            local interval = octave * 12 + degree
            if interval ~= 0 then
                if math.abs(interval) <= 12 then
                    if degree == 0 then weighted_intervals[interval] = 3
                    elseif degree == scale[3] or degree == scale[4] then weighted_intervals[interval] = 2
                    elseif degree == scale[5] or degree == scale[6] then weighted_intervals[interval] = 2
                    elseif degree == scale[2] then weighted_intervals[interval] = 1
                    else weighted_intervals[interval] = 1 end
                elseif math.abs(interval) <= 24 then
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

local function randomize(n)
    randomize_metro[n] = randomize_metro[n] or metro.init()
    local m_rand = randomize_metro[n]
    local active_controlled_params = active_controlled_params or {}
    local symmetry = params:get("symmetry") == 1
    local other_track = 3 - n
    local locked_params = {}
    local param_names = {"speed", "jitter", "size", "density", "spread", "pitch", "seek"}
    local pitch_size_density_linked = params:get("global_pitch_size_density_link") == 1
    for i = 1, #param_names do locked_params[param_names[i]] = params:get(n .. "lock_" .. param_names[i]) == 1 end
    if locked_params.pitch and not active_controlled_params[n .. "pitch"] then randomize_pitch(n, other_track, symmetry) end
    local targets = {}
    for i = 1, #param_names do
        local key = param_names[i]
        if key == "pitch" then goto continue end
        local cfg_name = n .. key
        if not locked_params[key] or active_controlled_params[cfg_name] then goto continue end
        if key == "seek" then
            local min_val = params:get(n .. "min_seek")
            local max_val = params:get(n .. "max_seek")
            local val = random_float(min_val, max_val)
            local val_norm = val * 0.01
            if symmetry then
                params:set(n .. "seek", val)
                params:set(other_track .. "seek", val)
                engine.seek(n, val_norm)
                engine.seek(other_track, val_norm)
                osc_positions[n] = val_norm
                osc_positions[other_track] = val_norm
            else
                params:set(n .. "seek", val)
                engine.seek(n, val_norm)
                osc_positions[n] = val_norm
            end
        else
            local min_val = params:get(n .. "min_" .. key)
            local max_val = params:get(n .. "max_" .. key)
            if min_val and max_val and min_val < max_val and not is_lfo_active_for_param(cfg_name) then
                local val
                if key == "jitter" then
                    if math.random() < 0.75 then
                        local upper_limit = math.min(500, max_val)
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
    if next(targets) then
        m_rand.time = 1 / 30
        m_rand.event = function(count)
            local tolerance = 0.01
            local factor = count / steps
            local all_done = true
            for param, target in pairs(targets) do
                if not active_controlled_params[param] then
                    local current = params:get(param)
                    local new_val = current + (target - current) * factor
                    params:set(param, new_val)
                    all_done = all_done and (math.abs(new_val - target) < tolerance)
                end
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
            if all_done then stop_metro_safe(m_rand) randomize_metro[n] = nil end
        end
        m_rand:start()
    end
    if current_scene_mode == "on" and morph_amount > 0 and morph_amount < 100 then capture_to_temp_scene() end
end

local function handle_volume_lfo(track, delta, crossfade_mode)
    if key_state[2] or key_state[3] then return end
    local p = track .. "volume"
    local op = (3 - track) .. "volume"
    local a1, i1 = is_lfo_active_for_param(p)
    local a2, i2 = is_lfo_active_for_param(op)
    local lfo_delta = delta * 1.5
    local vol_delta = delta * 3
    local other_delta = crossfade_mode and -delta or delta
    if a1 then
        params:delta(i1.."offset", lfo_delta)
        if a2 then params:delta(i2.."offset", other_delta * 1.5)
        else params:delta(op, other_delta * 3) end
    elseif a2 then
        params:delta(i2.."offset", other_delta * 1.5)
        params:delta(p, vol_delta)
    else
        params:delta(p, vol_delta)
        params:delta(op, other_delta * 3)
    end
end

local function handle_pitch_size_density_link(track, config, delta)
    local LINKED_PARAMS = {"pitch", "size", "density"}
    local SPEED = {pitch = 1, size = 5, density = 0.5}
    local param = config.param
    if params:get("global_pitch_size_density_link") ~= 1 then return false end
    if not SPEED[param] then return false end
    local symmetry = params:get("symmetry") == 1
    local other_track = 3 - track
    local function disable_linked_lfos(t) for i = 1, 3 do disable_lfos_for_param(t .. LINKED_PARAMS[i], true) end end
    disable_linked_lfos(track)
    if symmetry then disable_linked_lfos(other_track) end
    handle_lfo(track .. param, symmetry)
    local function update_linked_params(tr, delta_mult)
        local lb = link_base[tr]
        local base_pitch   = lb.pitch
        local base_size    = lb.size
        local base_density = lb.density
        local size_den_prod = lb.product
        if not (base_pitch and base_size and base_density and size_den_prod) then return end
        local new_pitch, new_size, new_den
        if param == "pitch" then
            local old_pitch = params:get(tr.."pitch")
            local scale = params:string("pitch_quantize_scale")
            if scale ~= "none" then
                local direction = (delta * delta_mult) > 0 and 1 or -1
                new_pitch = get_next_scale_note(old_pitch, scale, direction)
                new_pitch = util.clamp(new_pitch, LIMITS.pitch.min, LIMITS.pitch.max)
            else
                new_pitch = util.clamp(old_pitch + delta * delta_mult, LIMITS.pitch.min, LIMITS.pitch.max)
            end
            local pitch_ratio = (new_pitch - base_pitch) / 12
            local half_ratio = pitch_ratio * 0.5
            new_size = util.clamp(base_size * (2 ^ -half_ratio), LIMITS.size.min, LIMITS.size.max)
            new_den = util.clamp(base_density * (2 ^ half_ratio), LIMITS.density.min, LIMITS.density.max)
            params:set(tr.."pitch", new_pitch)
        elseif param == "size" then
            local old_size = params:get(tr.."size")
            new_size = util.clamp(old_size + delta * delta_mult, LIMITS.size.min, LIMITS.size.max)
            new_den = util.clamp(size_den_prod / new_size, LIMITS.density.min, LIMITS.density.max)
            local den_min, den_max = LIMITS.density.min, LIMITS.density.max
            if new_den == den_min or new_den == den_max then new_size = util.clamp(size_den_prod / new_den, LIMITS.size.min, LIMITS.size.max) end
            new_pitch = base_pitch
        else
            local old_den = params:get(tr.."density")
            new_den = util.clamp(old_den + delta * delta_mult * 0.1, LIMITS.density.min, LIMITS.density.max)
            new_size = util.clamp(size_den_prod / new_den, LIMITS.size.min, LIMITS.size.max)
            local size_min, size_max = LIMITS.size.min, LIMITS.size.max
            if new_size == size_min or new_size == size_max then new_den = util.clamp(size_den_prod / new_size, LIMITS.density.min, LIMITS.density.max) end
            new_pitch = base_pitch
        end
        params:set(tr.."size", new_size)
        params:set(tr.."density", new_den)
        lb.pitch   = new_pitch
        lb.size    = new_size
        lb.density = new_den
        lb.product = new_size * new_den
    end
    local speed = SPEED[param]
    update_linked_params(track, speed)
    if symmetry then update_linked_params(other_track, speed) end
    return true
end

local function handle_seek_param(track, config, delta)
    if config.param ~= "seek" then return false end
    local sym = params:get("symmetry") == 1
    handle_lfo(track .. "seek", not sym)
    local current_pos1 = math.floor(osc_positions[1] * 100 + 0.5)
    local current_pos2 = math.floor(osc_positions[2] * 100 + 0.5)
    local function update_seek(tr, current_pos)
        local new_pos = (current_pos + delta) % 100
        if new_pos < 0 then new_pos = new_pos + 100 end
        local norm_pos = new_pos * 0.01
        osc_positions[tr] = norm_pos
        params:set(tr.."seek", new_pos)
        engine.seek(tr, norm_pos)
    end
    if sym then
        update_seek(1, current_pos1)
        update_seek(2, current_pos2)
    else
        update_seek(track, track == 1 and current_pos1 or current_pos2)
    end
    return true
end

local function handle_standard_param(track, config, delta)
    local sym = params:get("symmetry") == 1
    local p = track .. config.param
    handle_lfo(p, sym)
    if sym and config.param == "pitch" then
        local old_value = params:get(p)
        local scale = params:string("pitch_quantize_scale")
        if scale ~= "none" then
            local direction = delta > 0 and 1 or -1
            local new_value = get_next_scale_note(old_value, scale, direction)
            new_value = util.clamp(new_value, LIMITS.pitch.min, LIMITS.pitch.max)
            params:set(p, new_value)
            local other_p = (3 - track) .. config.param
            local other_old = params:get(other_p)
            local other_new = get_next_scale_note(other_old, scale, direction)
            other_new = util.clamp(other_new, LIMITS.pitch.min, LIMITS.pitch.max)
            params:set(other_p, other_new)
        else
            params:delta(p, delta)
            local new_value = params:get(p)
            local actual_change = new_value - old_value
            local other_p = (3 - track) .. config.param
            local other_old = params:get(other_p)
            params:set(other_p, other_old + actual_change)
        end
    elseif config.param == "pitch" then
        local old_value = params:get(p)
        local scale = params:string("pitch_quantize_scale")
        if scale ~= "none" then
            local direction = delta > 0 and 1 or -1
            local new_value = get_next_scale_note(old_value, scale, direction)
            new_value = util.clamp(new_value, LIMITS.pitch.min, LIMITS.pitch.max)
            params:set(p, new_value)
        else
            params:delta(p, delta)
        end
    else
        params:delta(p, delta)
        if sym then params:delta((3 - track) .. config.param, delta) end
    end
end

local function handle_param_change(track, config, delta)
    if key_state[2] or key_state[3] then return end
    if handle_pitch_size_density_link(track, config, delta) then return end
    if handle_seek_param(track, config, delta) then return end
    handle_standard_param(track, config, delta)
end

local function handle_randomize_track(n)
    if not key_state[1] then return false end
    local track = n == 3 and 2 or 1
    stop_metro_safe(randomize_metro[track]) randomize_metro[track] = nil
    lfo.clearLFOs(tostring(track))
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
    if current_mode == "lpf" or current_mode == "hpf" then current_filter_mode = current_filter_mode == "lpf" and "hpf" or "lpf" return end
    local param_name = string.match(current_mode, "%a+")
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
    if not only_existing then lfos_turned_off[full_param] = nil end
    local lfo_targets = lfo.lfo_targets
    for i = 1, 16 do
        local lfo_state = params:get(i .. "lfo")
        if lfo_state == 2 or (only_existing and lfo_state == 1) then if lfo_targets[params:get(i .. "lfo_target")] == full_param then return i end end
    end
    if only_existing then return nil end
    local new_target_idx = nil
    for idx = 2, #lfo_targets do if lfo_targets[idx] == full_param then new_target_idx = idx break end end
    if not new_target_idx then return nil end
    local min_val, max_val = lfo.get_parameter_range(full_param)
    if not min_val or not max_val or max_val <= min_val then return nil end
    local current_val = params:get(full_param)
    local offset = (current_val - min_val) / (max_val - min_val) * 2 - 1
    local conflicts = {}
    for j = 1, 16 do if params:get(j .. "lfo") == 2 then conflicts[lfo_targets[params:get(j .. "lfo_target")]] = true end end
    for i = 1, 16 do
        if params:get(i .. "lfo") == 1 then
            local target_name = lfo_targets[params:get(i .. "lfo_target")]
            if target_name == "none" or target_name == full_param or not conflicts[target_name] then
                local i_str = i .. ""
                params:set(i_str .. "lfo_target", new_target_idx)
                if source_lfo_idx then
                    local src_str = source_lfo_idx .. ""
                    params:set(i_str .. "lfo_shape", params:get(src_str .. "lfo_shape"))
                    params:set(i_str .. "lfo_freq", params:get(src_str .. "lfo_freq"))
                    lfo[i].phase = lfo[source_lfo_idx].phase
                else
                    params:set(i_str .. "lfo_shape", 1)
                    params:set(i_str .. "lfo_freq", random_float(0.1, 0.7))
                end
                params:set(i_str .. "lfo_depth", create_with_depth and 0.01 or 0)
                params:set(i_str .. "offset", offset)
                params:set(i_str .. "lfo", create_with_depth and 2 or 1)
                invalidate_lfo_cache()
                return i
            end
        end
    end
    return nil
end

local function adjust_lfo_offset(lfo_idx, delta)
    local current_offset = params:get(lfo_idx .. "offset")
    local current_depth = params:get(lfo_idx .. "lfo_depth")
    local offset_delta = delta * 0.02
    local max_offset = 1 - current_depth * 0.01
    local proposed_offset = util.clamp(current_offset + offset_delta, -max_offset, max_offset)
    params:set(lfo_idx .. "offset", proposed_offset)
    lfo[lfo_idx].offset = proposed_offset
end

local function adjust_lfo_depth(lfo_idx, delta)
    local current_depth = params:get(lfo_idx .. "lfo_depth")
    if current_depth == 0 and delta > 0 then
        local target_param = lfo.lfo_targets[params:get(lfo_idx .. "lfo_target")]
        local min_val, max_val = lfo.get_parameter_range(target_param)
        if min_val and max_val and max_val > min_val then
            local current_val = params:get(target_param)
            local normalized = (current_val - min_val) / (max_val - min_val)
            local initial_depth = 0.01
            local initial_offset = util.clamp(normalized * 2 - 1, -0.9999, 0.9999)
            lfo[lfo_idx].depth = initial_depth
            lfo[lfo_idx].offset = initial_offset
            params:set(lfo_idx .. "offset", initial_offset)
            params:set(lfo_idx .. "lfo_depth", initial_depth)
            params:set(lfo_idx .. "lfo", 2)
            invalidate_lfo_cache()
            lfos_turned_off[target_param] = nil
        end
        return
    end
    local proposed_depth = current_depth + delta
    if proposed_depth <= 0 then if current_depth > 0 then params:set(lfo_idx .. "lfo", 1) invalidate_lfo_cache() end return end
    local max_offset = 1 - proposed_depth * 0.01
    local current_offset = params:get(lfo_idx .. "offset")
    local new_offset = util.clamp(current_offset, -max_offset, max_offset)
    lfo[lfo_idx].depth = proposed_depth
    params:set(lfo_idx .. "lfo_depth", proposed_depth)
    if new_offset ~= current_offset then
        lfo[lfo_idx].offset = new_offset
        params:set(lfo_idx .. "offset", new_offset)
    end
end

function enc(n, d)
    if not installer:ready() then return end
    if presets.is_menu_open() then presets.menu_enc(n, d) return end
    local k1, k2, k3 = key_state[1], key_state[2], key_state[3]
    local should_auto_save = current_scene_mode == "on" and (morph_amount == 0 or morph_amount == 100)
    local is_morphing = current_scene_mode == "on" and morph_amount > 0 and morph_amount < 100
    local function mark_key_interaction()
        if k1 then key_trackers[1].had_interaction = true key_trackers[1].long_triggered = true end
        if k2 then key_trackers[2].had_interaction = true key_trackers[2].long_triggered = true end
        if k3 then key_trackers[3].had_interaction = true key_trackers[3].long_triggered = true end
        if k2 and k3 then key_trackers[23].had_interaction = true key_trackers[23].long_triggered = true end
    end
    local function finalize_change()
        if is_morphing then capture_to_temp_scene() end
        if should_auto_save then auto_save_to_scene() end
    end
    local function adjust_lfo_with_symmetry(track, param_name, lfo_idx, adjustment_fn, delta_modifier, only_existing, create_with_depth)
        adjustment_fn(lfo_idx, d)
        if params:get("symmetry") == 1 then
            local other_lfo = find_or_create_lfo_for_param(3 - track, param_name, only_existing, create_with_depth, lfo_idx)
            if other_lfo then adjustment_fn(other_lfo, delta_modifier and delta_modifier(d) or d) end
        end
    end
    if k2 and k3 and not k1 then
        local fx_map = {[1] = "reverb_mix", [2] = "delay_mix", [3] = "shimmer_mix1"}
        local fx_labels = {[1] = "reverb", [2] = "delay", [3] = "shimmer"}
        local fx = fx_map[n]
        if fx then
            mark_key_interaction()
            params:delta(fx, d)
            fx_popup.label = fx_labels[n]
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
            local mode_name = (current_mode == "lpf" or current_mode == "hpf") and current_filter_mode or current_mode
            param_name = param_modes[mode_name] and param_modes[mode_name].param or mode_name
        end
        mark_key_interaction()
        if n == 1 then
            local lfo_idx = find_or_create_lfo_for_param(voice, param_name, true, false)
            if lfo_idx then params:delta(lfo_idx .. "lfo_freq", d * 0.5)
                if params:get("symmetry") == 1 then
                    local other_lfo = find_or_create_lfo_for_param(3 - voice, param_name, true, false, lfo_idx)
                    if other_lfo then params:delta(other_lfo .. "lfo_freq", d * 0.5) end
                end
                finalize_change()
            end
        elseif n == 2 then
            local lfo_idx = find_or_create_lfo_for_param(voice, param_name, false, true)
            if lfo_idx then
                adjust_lfo_with_symmetry(voice, param_name, lfo_idx, adjust_lfo_depth, nil, false, true)
                finalize_change()
            end
        elseif n == 3 then
            local lfo_idx = find_or_create_lfo_for_param(voice, param_name, true, false)
            if lfo_idx then
                local pan_inv = param_name == "pan" and function(v) return -v end or nil
                adjust_lfo_with_symmetry(voice, param_name, lfo_idx, adjust_lfo_offset, pan_inv, true, false)
                finalize_change()
            end
        end
        return
    end
    if n == 1 then
        mark_key_interaction()
        if should_auto_save then auto_save_to_scene() end
        if k1 and current_scene_mode == "on" then
            params:set("morph_amount", util.clamp(morph_amount + (d * 3), 0, 100))
        else
            handle_volume_lfo(1, d, k1)
            if is_morphing then capture_to_temp_scene() end
        end
        return
    end
    if n == 2 or n == 3 then
        local track = n - 1
        mark_key_interaction()
        stop_metro_safe(randomize_metro[track]) randomize_metro[track] = nil
        if k1 then
            local p = track .. "volume"
            disable_lfos_for_param(p, true)
            if params:get("symmetry") == 1 then handle_lfo(p, true) end
            params:delta(p, 3 * d)
        else
            local mode = (current_mode == "lpf" or current_mode == "hpf") and current_filter_mode or current_mode
            local config = param_modes[mode]
            if config then handle_param_change(track, config, config.delta * d) end
        end
        finalize_change()
    end
end

local function set_key_tracking(n, state)
    local tracker = key_trackers[n]
    local is_init = state == "init"
    tracker.press_time = is_init and util.time() or nil
    tracker.had_interaction = false
    tracker.long_triggered = false
    if not is_init and (n == 2 or n == 3) and key_trackers[23] then
        key_trackers[23].press_time = nil
        key_trackers[23].had_interaction = false
        key_trackers[23].long_triggered = false
    end
end

function key(n, z)
    if not installer:ready() then installer:key(n, z) return end
    if presets.is_menu_open() then
        if n == 1 and z == 1 then presets.close_menu() return end
        if presets.menu_key(n, z, scene_data, update_pan_positioning, audio_active) then return end
    end
    local is_press = z == 1
    key_state[n] = is_press
    local both_keys_pressed = key_state[2] and key_state[3]
    if is_press then handle_key_press(n) else handle_key_release(n, both_keys_pressed) end
end

function handle_key_press(n)
    if n <= 3 then set_key_tracking(n, "init") end
    if key_state[2] and key_state[3] then
        if not key_trackers[23] then key_trackers[23] = {press_time = nil, had_interaction = false, long_triggered = false} end
        set_key_tracking(23, "init")
        key_trackers[2].had_interaction = true
        key_trackers[3].had_interaction = true
    end
    if (key_state[1] and (n == 2 or n == 3)) or (n == 1 and (key_state[2] or key_state[3])) then
        key_trackers[1].had_interaction = true
        key_trackers[1].long_triggered = true
    end
    if n ~= 1 and key_state[1] then handle_randomize_track(n) end
end

function handle_key_release(n, both_keys_pressed)
    local tracker = key_trackers[n]
    if (n == 2 or n == 3) and key_trackers[23] and key_trackers[23].press_time then
        local combo_tracker = key_trackers[23]
        if not combo_tracker.had_interaction then
            local duration = util.time() - combo_tracker.press_time
            if duration >= KEY_LONG_PRESS_THRESHOLD then
                lfo.assign_to_current_row(current_mode, current_filter_mode)
                invalidate_lfo_cache()
            else
                handle_parameter_lock()
            end
            combo_tracker.had_interaction = true
        end
    end
    if (n == 2 or n == 3) and tracker.press_time and not tracker.long_triggered and
       not tracker.had_interaction and not both_keys_pressed then
        if (util.time() - tracker.press_time) < KEY_LONG_PRESS_THRESHOLD then handle_mode_navigation(n) end
    end
    set_key_tracking(n)
    lfos_turned_off = {}
end

local function format_density(value) return string.format("%.1f Hz", value) end
local function format_pitch(value, track) if not track then return value > 0 and string.format("+%.0f", value) or string.format("%.0f", value) end local pitch_random_enabled = (params:get(track.."pitch_random_prob") or 0) ~= 0 local show_dots = pitch_random_enabled local suffix = show_dots and ".. st" or " st" return value > 0 and string.format("+%.0f%s", value, suffix) or string.format("%.0f%s", value, suffix) end
local function format_seek(value) return string.format("%.0f%%", value) end
local function format_speed(speed) if math.abs(speed) < 0.01 then return ".00x" elseif math.abs(speed) < 1 then if speed < -0.01 then return string.format("-.%02dx", math.floor(math.abs(speed) * 100)) else return string.format(".%02dx", math.floor(math.abs(speed) * 100)) end else return string.format("%.2fx", speed) end end
local function format_jitter(value) if value > 999 then return string.format("%.1f s", value / 1000) else return string.format("%.0f ms", value) end end
local function format_size(value) if value > 999 then return string.format("%.2f s", value / 1000) else return string.format("%.0f ms", value) end end

local LEVEL = {hi=15, dim=9, val=2}
local TRACK_X, VOL_X, PAN_X = {51, 92}, {0,126}, {52,93}
local BAR_W, Y = 30, {bottom=60, seek=63}
local UPPER = {jitter=true, size=true, density=true, spread=true, pitch=true}
local FORMAT = {
  hz=function(v) return format_density(v) end,
  st=function(v,t) return format_pitch(v,t) end,
  spread=function(v) return string.format("%.0f%%",v) end,
  jitter=function(v) return format_jitter(v) end,
  size=function(v) return format_size(v) end}
local ops = {r={}, r_n=0, p={}, p_n=0, t={}, t_n=0}
local level_buckets = {}
local function clear_ops()
  ops.r_n = 0; ops.p_n = 0; ops.t_n = 0
end
local function R(l,x,y,w,h)
  local n = ops.r_n + 1; ops.r_n = n
  local s = ops.r[n]
  if s then s[1]=l;s[2]=x;s[3]=y;s[4]=w;s[5]=h else ops.r[n]={l,x,y,w,h} end
end
local function P(l,x,y)
  local n = ops.p_n + 1; ops.p_n = n
  local s = ops.p[n]
  if s then s[1]=l;s[2]=x;s[3]=y else ops.p[n]={l,x,y} end
end
local function T(l,x,y,s,a)
  local n = ops.t_n + 1; ops.t_n = n
  local slot = ops.t[n]
  if slot then slot[1]=l;slot[2]=x;slot[3]=y;slot[4]=s;slot[5]=a else ops.t[n]={l,x,y,s,a} end
end
local LOCK_OFFSETS = {{-3,0},{-4,0},{-4,-1},{-4,-2}}
local function draw_lock(x,y)
  for _,o in ipairs(LOCK_OFFSETS) do P(LEVEL.dim, x+o[1], y+o[2]) end
end
local SIZE_LINK_OFFSETS = {1,3,5,7,9,11,13,15}
local function draw_size_link(x,y) 
  for _,offset in ipairs(SIZE_LINK_OFFSETS) do 
    local center = 8
    local distance = math.abs(offset - center)
    local level = math.floor(10 * (1 - distance / center))
    P(level, x-4, y+offset) 
  end 
end
local function get_or_create_bucket(l)
  if not level_buckets[l] then level_buckets[l] = {r={}, p={}, t={}, r_count=0, p_count=0, t_count=0} end
  return level_buckets[l]
end
local function flush()
  for _,bucket in pairs(level_buckets) do bucket.r_count, bucket.p_count, bucket.t_count = 0, 0, 0 end
  for i=1,ops.r_n do
    local o = ops.r[i]
    local bucket = get_or_create_bucket(o[1])
    local rc = bucket.r_count + 1; bucket.r_count = rc
    local s = bucket.r[rc]
    if s then s[1]=o[2];s[2]=o[3];s[3]=o[4];s[4]=o[5] else bucket.r[rc]={o[2],o[3],o[4],o[5]} end
  end
  for i=1,ops.p_n do
    local o = ops.p[i]
    local bucket = get_or_create_bucket(o[1])
    local pc = bucket.p_count + 1; bucket.p_count = pc
    local s = bucket.p[pc]
    if s then s[1]=o[2];s[2]=o[3] else bucket.p[pc]={o[2],o[3]} end
  end
  for i=1,ops.t_n do
    local o = ops.t[i]
    local bucket = get_or_create_bucket(o[1])
    local tc = bucket.t_count + 1; bucket.t_count = tc
    local s = bucket.t[tc]
    if s then s[1]=o[2];s[2]=o[3];s[3]=o[4];s[4]=o[5] else bucket.t[tc]={o[2],o[3],o[4],o[5]} end
  end
  for l=1,15 do
    local bucket = level_buckets[l]
    if bucket and (bucket.r_count > 0 or bucket.p_count > 0 or bucket.t_count > 0) then
      screen.level(l)
      if bucket.r_count > 0 then
        for i=1,bucket.r_count do
          local r = bucket.r[i]
          screen.rect(r[1], r[2], r[3], r[4])
        end
        screen.fill()
      end
      if bucket.p_count > 0 then
        for i=1,bucket.p_count do
          local p = bucket.p[i]
          screen.pixel(p[1], p[2])
        end
        screen.fill()
      end
      for i=1,bucket.t_count do
        local t = bucket.t[i]
        screen.move(t[1], t[2])
        if t[4] == "center" then screen.text_center(t[3])
        else screen.text(t[3])
        end
      end
    end
  end
end

function redraw()
  if not installer:ready() then installer:redraw() return end
  if presets.draw_menu() then return end
  if _G.preset_loading then screen.clear() screen.level(15) screen.move(64, 32) screen.text_center("Loading...") screen.update() return end
  screen.clear()
  screen.save()
  screen.translate(0, animation_y)
  clear_ops()
  local C = {
    vol  = {params:get("1volume"), params:get("2volume")},
    pan  = {params:get("1pan"),    params:get("2pan")},
    seek = {params:get("1seek"),   params:get("2seek")},
    spd  = {params:get("1speed"),  params:get("2speed")},
    cut  = {params:get("1cutoff"), params:get("2cutoff")},
    hpf  = {params:get("1hpf"),    params:get("2hpf")},
    size = {params:get("1size"),   params:get("2size")},
    live = {in_  = {params:get("1live_input"),  params:get("2live_input")}, dir_ = {params:get("1live_direct"), params:get("2live_direct")}},
    link = params:get("global_pitch_size_density_link") == 1,
    dry  = params:get("dry_mode") == 1,
    sym  = params:get("symmetry") == 1,
    evo  = params:get("evolution") == 1}
  local now = util.time()
  local cur_mode = current_mode
  local cur_filter = current_filter_mode
  for _,row in ipairs(param_rows) do
    local name = row.name
    local label_upper = row.label_upper
    local hi = cur_mode == row.mode
    local y = row.y
    if hi then 
      T(1, 7, y + 1, label_upper)
      T(LEVEL.hi, 6, y, label_upper)
    else
      T(LEVEL.hi, 6, y, row.label)
    end
    for t=1,2 do
      local x = TRACK_X[t]
      local param = t == 1 and row.param1 or row.param2
      if name == "size" and C.link then draw_size_link(x, y) end
      if is_param_locked(t, name) then draw_lock(x, y-1) end
      local is_lfo, _ = is_lfo_active_for_param(param)
      local val = params:get(param)
      local fmt = FORMAT[row.hz and "hz" or row.st and "st" or name]
      local txt = fmt and fmt(val, t) or params:string(param)
      T(flash_level(t, hi and LEVEL.hi or LEVEL.val), x, y, txt)
      if is_lfo then
        local a, b = lfo.get_parameter_range(param)
        R(LEVEL.dim+2, x, y + 1, util.linlin(a, b, 0, BAR_W, val), 1)
      end
    end
  end
  local function draw_seek_bar_viz(t, x)
    local loaded = audio_active[t] or C.live.in_[t] == 1 or C.live.dir_[t] == 1
    local mode = UPPER[cur_mode] and "seek" or cur_mode
    if mode == "speed" then
      R(1, x, Y.seek, BAR_W, 1)
      local speed = C.spd[t]
      local normalized_speed = util.clamp(speed / 2, -1, 1)
      local center_x = x + math.floor(BAR_W / 2)
      local position_offset = math.floor(normalized_speed * (BAR_W / 2))
      local position_x = center_x + position_offset
      if loaded then R(LEVEL.hi, position_x, Y.seek - 1, 1, 2) end
    else
      local animated_bar_w = math.floor(BAR_W * seek_bar_width)
      R(1, x, Y.seek, animated_bar_w, 1)
      if params:get(t .. "granular_gain") > 0 then
        local grains = grain_positions[t]
        if grains then
          local dur, keep, drawn = cached_buffer_durations[t], 0, 0
          for i=1,#grains do
            local g = grains[i]
            local age = now - g.t
            if age <= (g.size or 0.1) then
              keep = keep + 1
              grains[keep] = g
              if drawn < 25 then
                local grain_size_norm = (g.size or 0.1) / dur
                local grain_end = (g.pos or 0) + grain_size_norm
                local spd_fwd = C.spd[t] >= -0.01
                local segments = grain_end > 1 and {{g.pos or 0, 1.0}, {0, grain_end - 1.0}} or {{g.pos or 0, grain_end}}
                for _,seg in ipairs(segments) do
                  local pos = x + math.floor(seg[1] * BAR_W)
                  local w = math.max(1, math.floor((seg[2] - seg[1]) * BAR_W))
                  local l = spd_fwd and pos or (pos - w)
                  local r = spd_fwd and (pos + w - 1) or (pos - 1)
                  if r >= x and l <= x + BAR_W - 1 then
                    local dl, dr = math.max(l, x), math.min(r, x + BAR_W - 1)
                    local bw = dr - dl + 1
                    if bw > 0 then
                      R(math.ceil(1 + (LEVEL.hi - 1) * (1 - age / (g.size or 0.1))), dl, Y.seek, bw, 1)
                      drawn = drawn + 1
                    end
                  end
                end
              end
            end
          end
          for i=keep+1,#grains do grains[i] = nil end
        end
      else grain_positions[t] = {} end
      if loaded and C.live.dir_[t] ~= 1 then R(LEVEL.hi, x + math.floor(osc_positions[t] * animated_bar_w), Y.seek - 1, 1, 2) end
      if C.live.in_[t] == 1 then R(LEVEL.hi, x + math.floor(rec_positions[t] * BAR_W), Y.seek - 1, 2, 2) end
    end
  end
  local upper = UPPER[cur_mode]
  local mode = upper and "seek" or cur_mode
  local active = not upper
  local label = (mode == "lpf" or mode == "hpf") and (cur_filter .. ":       ") or (mode .. ":      ")
  local y_bot = Y.bottom
  if active then T(1, 7, y_bot + 2, label:upper()) end
  T(LEVEL.hi, 6, y_bot + 1, active and label:upper() or label)
  for t=1,2 do
    local x = TRACK_X[t]
    local vL = active and LEVEL.hi or LEVEL.val
    if mode == "seek" then
      if is_param_locked(t, "seek") then draw_lock(x, y_bot) end
      local txt = C.live.in_[t] == 1 and "live" or C.live.dir_[t] == 1 and "direct" or string.format("%.0f%%", osc_positions[t] * 100)
      T(flash_level(t, vL), x, y_bot + 1, txt)
    elseif mode == "speed" then
      if is_param_locked(t, "speed") then draw_lock(x, y_bot) end
      T(flash_level(t, LEVEL.hi), x, y_bot + 1, format_speed(C.spd[t]))
    elseif mode == "pan" then
      if is_param_locked(t, "pan") then draw_lock(x, y_bot) end
      local p = C.pan[t]
      T(flash_level(t, LEVEL.hi), x, y_bot + 1, math.abs(p) < 0.5 and "0%" or string.format("%.0f%%", p))
    else
      local v = cur_filter == "lpf" and C.cut[t] or C.hpf[t]
      if filter_lock_ratio then draw_lock(x, y_bot) end
      T(flash_level(t, LEVEL.hi), x, y_bot + 1, string.format("%.0f", v))
    end
    if (mode == "seek" or mode == "speed") then
      local audio_loaded = audio_active[t] or C.live.in_[t] == 1 or C.live.dir_[t] == 1
      if audio_loaded and C.live.dir_[t] ~= 1 then
        local s = C.spd[t]
        local icon = math.abs(s) < 0.01 and "⏸" or (s > 0 and "▶" or "◀")
        T(vL, t == 1 and 77 or 118, y_bot+1, icon)
      end
    end
    if mode == "seek" or mode == "speed" then draw_seek_bar_viz(t, x) end
  end
  for t=1,2 do
    local h = util.linlin(-70, 10, 0, 64, C.vol[t])
    R(LEVEL.dim-3, VOL_X[t], 64 - h + volume_bar_y[t], 2, h)
    local peak_amp = math.max(voice_peak_amplitudes[t].l, voice_peak_amplitudes[t].r)
    local peak_db = util.clamp(20 * math.log(peak_amp, 10), -70, 10)
    local peak_h = math.min(util.linlin(-70, 10, 0, 64, peak_db), h)
    if peak_h > 0 then R(LEVEL.hi-1, VOL_X[t], 64 - peak_h + volume_bar_y[t], 2, peak_h) end
    local pan_pos = util.linlin(-100, 100, PAN_X[t], PAN_X[t] + 25, C.pan[t])
    R(LEVEL.dim, pan_pos - 1 + pan_indicator_x[t], 1, 4, 1)
  end
  if cur_mode == "lpf" or mode == "hpf" then
    for t=1,2 do
      local x = TRACK_X[t]
      R(1, x, Y.seek, BAR_W, 1)
      local filter_val = cur_filter == "lpf" and C.cut[t] or C.hpf[t]
      local log_normalized = util.clamp(math.log(filter_val / 20) / math.log(20000 / 20), 0, 1)
      local bar_width = math.max(1, math.floor(log_normalized * BAR_W))
      R(LEVEL.hi, x, Y.seek, bar_width, 1)
    end
  end
  if C.dry then for x=7,15,4 do P(LEVEL.hi, x, 0) end end
  if C.sym then 
    for i=1,30 do
      local y = (i * 2) % 64
      if y ~= 0 then P(math.floor(10 * (1 - math.abs(y - 32) / 32)), 85, y + 2) end
    end
  end
  if C.evo then 
    local t = now * 4
    for i=0,2 do P(math.floor(8 + 7 * math.sin(t - i * 0.8)), (i * 2)+6, 63) end
  end
  if current_scene_mode == "on" then 
    R(1, 7, 1, 22, 1) 
    if morph_amount > 0 then 
      R(LEVEL.hi, 7, 1, util.linlin(0, 100, 0, 22, morph_amount), 1) 
    end
  else 
    font.draw_fx_status_bucketed(P) 
  end
  if showing_save_message then R(1, 40, 25, 48, 10) T(LEVEL.hi, 64, 33, "SAVING...", "center") end
  if fx_popup.time and (now - fx_popup.time) < FX_POPUP_DURATION then
    local pct = string.format("%.0f%%", fx_popup.value)
    local txt = fx_popup.label .. ": " .. pct
    local w = #txt * 5 + 8
    R(1, 64 - math.floor(w/2), 27, w, 10)
    T(LEVEL.hi, 64, 35, txt, "center")
  end
  flush()
  screen.restore()
  screen.update()
end

local osc_handlers = {
   ["/twins/buffer_loaded"] = function(args)
        local voice = args[1]
        presets.buffer_loaded(voice)
    end,
    ["/twins/buf_pos"] = function(args)
        local vid, pos = args[1] + 1, args[2]
        if audio_active[vid] or params:get(vid.."live_input") == 1 or params:get(vid.."live_direct") == 1 then
            osc_positions[vid] = pos
            params:set(vid.."seek", pos * 100, true)
        end
    end,
    ["/twins/rec_pos"] = function(args)
        local vid, pos = args[1] + 1, args[2]
        if params:get(vid.."live_input") == 1 then rec_positions[vid] = pos end
    end,
    ["/twins/grain_pos"] = function(args)
        local vid, pos, size = args[1] + 1, args[2], args[3]
        if audio_active[vid] then table.insert(grain_positions[vid], {pos = pos, size = size, t = util.time()}) end
    end,
    ["/twins/voice_peak"] = function(args)
        local voice, peakL, peakR = args[1] + 1, args[2], args[3]
        voice_peak_amplitudes[voice].l = math.abs(peakL)
        voice_peak_amplitudes[voice].r = math.abs(peakR)
    end,
    ["/twins/output_saved"] = function(args)
        local filepath = args[1]
        params:set("unload_all", 1)
        tracked_clock_run(function()
            clock.sleep(0.1)
            params:set("1granular_gain", 0) disable_lfos_for_param("1speed") disable_lfos_for_param("1pan") params:set("1speed", 1) params:set("1sample", filepath) params:set("1pan", 0) params:set("2pan", 0) params:set("reverb_mix", 0) params:set("delay_mix", 0) params:set("shimmer_mix1", 0) params:set("glitch_ratio", 0) params:set("glitch_mix", 100) params:set("tape_mix", 1) params:set("dimension_mix", 0) params:set("sine_drive_wet", 0) params:set("drive", 0) params:set("wobble_mix", 0) params:set("chew_depth", 0) params:set("lossdegrade_mix", 0) params:set("Width", 100)  params:set("rspeed", 0) params:set("haas", 1) params:set("monobass_mix", 1) params:set("bitcrush_mix", 0) params:set("1lock_speed", 2)
            for i = 1, 2 do params:set(i.."eq_low_gain", 0) params:set(i.."eq_mid_gain", 0) params:set(i.."eq_high_gain", 0) params:set(i.."cutoff", 20000) params:set(i.."hpf", 20) end
        end)
    end, 
    ["/twins/save_complete"] = function(args)
        showing_save_message = false
    end}

local function setup_osc() osc.event = function(path, args) local handler = osc_handlers[path] if handler then handler(args) end end end

function init()
    initial_reverb_onoff = params:get('reverb')
    params:set('reverb', 1)
    initial_monitor_level = params:get('monitor_level')
    params:set('monitor_level', -math.huge)
    if not installer:ready() then tracked_clock_run(function() while true do redraw() clock.sleep(1 / 10) end end) do return end end
    setup_ui_metro()
    setup_params()
    setup_osc()
    lfo.on_state_change = invalidate_lfo_cache
    font.init_fx_cache()
    init_longpress_checker()
end

function cleanup()
    cancel_all_clocks()
    stop_metro_safe(ui_metro)
    stop_metro_safe(longpress_metro)
    for i = 1, 2 do stop_metro_safe(randomize_metro[i]) end
    lfo.cleanup()
    lfo.on_state_change = nil
    randpara.cleanup()
    if initial_monitor_level then params:set('monitor_level', initial_monitor_level) end
    if initial_reverb_onoff then params:set('reverb', initial_reverb_onoff) end
    osc.event = nil
end