local midi_input = {}

local BASE_NOTE  = 60
local SNAP_REL   = 0.003
local floor      = math.floor
local clamp      = util.clamp

local m          = nil
local key_trigger = false
local para_mode  = false
local solo_mode  = 0

local held       = {}
local voice_note = { nil, nil }
local applied    = { 0, 0 }
local retrig_clock = { nil, nil }

local PITCH_KEY  = { "1pitch", "2pitch" }
local CC1_PARAM  = { nil, "morph_amount", "reverb_mix", "delay_mix" }

local on_voice_trigger = nil
local on_voice_release = nil
local voice_loaded     = function(_) return true end

local set_pitch = function(v, p)
    local k = PITCH_KEY[v]
    if params.lookup[k] then params:set(k, clamp(p, -48, 48)) end
end

local function push_ad()
    local a, d = params:get("midi_attack"), params:get("midi_decay")
    engine.key_ad(1, a, d)
    engine.key_ad(2, a, d)
end

local function held_index(note)
    for i = 1, #held do if held[i].note == note then return i end end
end

local function held_push(note, vel)
    local i = held_index(note)
    if i then table.remove(held, i) end
    held[#held + 1] = { note = note, vel = vel }
end

local function held_remove(note)
    local i = held_index(note)
    if i then table.remove(held, i) end
end

local function cancel_retrig(v)
    local c = retrig_clock[v]
    if c then clock.cancel(c); retrig_clock[v] = nil end
end

local function retrigger(v, amp)
    local a, d = params:get("midi_attack"), params:get("midi_decay")
    engine.key_ad(v, a, SNAP_REL)
    engine.key_gate(v, 0)
    cancel_retrig(v)
    retrig_clock[v] = clock.run(function()
        clock.sleep(SNAP_REL + 0.001)
        engine.key_ad(v, a, d)
        engine.vel_amp(v, amp)
        engine.key_gate(v, 1)
        retrig_clock[v] = nil
    end)
end

local function set_voice(v, e)
    if e == nil then
        if voice_note[v] then
            voice_note[v] = nil
            if on_voice_release then on_voice_release(v) end
            if key_trigger then
                cancel_retrig(v)
                push_ad()
                engine.key_gate(v, 0)
            end
        end
        return
    end
    if voice_note[v] == e.note then return end
    local was_sounding = voice_note[v] ~= nil
    local off = e.note - BASE_NOTE
    set_pitch(v, params:get(PITCH_KEY[v]) - applied[v] + off)
    applied[v] = off
    local amp = (params:get("midi_velocity") == 2) and clamp((e.vel or 127) / 127, 0, 1) or 1
    voice_note[v] = e.note
    if on_voice_trigger then on_voice_trigger(v) end
    if key_trigger then
        if not was_sounding then
            retrigger(v, amp)
        else
            cancel_retrig(v)
            engine.key_ad(v, params:get("midi_attack"), params:get("midi_decay"))
            engine.vel_amp(v, amp)
            engine.key_gate(v, 1)
        end
    else
        engine.vel_amp(v, amp)
    end
end

local function update_voices()
    local e = held[#held]
    set_voice(1, e); set_voice(2, e)
end

local rr = 2

local function voice_holding(note)
    if voice_note[1] == note then return 1 end
    if voice_note[2] == note then return 2 end
end

local function solo_loaded_voice()
    local l1, l2 = voice_loaded(1), voice_loaded(2)
    if l1 and not l2 then return 1 end
    if l2 and not l1 then return 2 end
    return nil
end

local function alloc_voice()
    local solo = solo_loaded_voice()
    if solo then rr = solo; return solo end
    local v1 = rr % 2 + 1
    if not voice_note[v1] then rr = v1; return v1 end
    rr = v1 % 2 + 1
    return rr
end

local function unsounded_held()
    for i = #held, 1, -1 do
        local n = held[i].note
        if voice_note[1] ~= n and voice_note[2] ~= n then return held[i] end
    end
end

local function para_note_on(note, vel)
    held_push(note, vel)
    set_voice(alloc_voice(), { note = note, vel = vel })
end

local function para_note_off(note)
    local v = voice_holding(note)
    held_remove(note)
    if v then
        local e = unsounded_held()
        set_voice(v, e)
        if e then rr = v end
    end
end

local function all_off()
    cancel_retrig(1); cancel_retrig(2)
    held = {}; voice_note = { nil, nil }
    applied = { 0, 0 }; rr = 2
    engine.key_gate(1, 0); engine.key_gate(2, 0)
end

local function midi_controls_voice(v)
    if solo_mode > 0 then return v == solo_mode end
    return true
end

local function set_voice_free(v)
    cancel_retrig(v)
    engine.key_hold(v, 1)
    engine.key_ad(v, params:get("midi_attack"), params:get("midi_decay"))
    engine.key_gate(v, 1)
end

local function set_voice_keyed(v)
    cancel_retrig(v)
    engine.key_hold(v, 0)
    engine.key_ad(v, params:get("midi_attack"), SNAP_REL)
    engine.key_gate(v, 0)
end

local function apply_voice_gate(v)
    if key_trigger and midi_controls_voice(v) then
        set_voice_keyed(v)
    else
        set_voice_free(v)
    end
end

local function apply_gate_state()
    key_trigger = (params:get("midi_gate") == 2)
    apply_voice_gate(1)
    apply_voice_gate(2)
end

local function handle(data)
    local d = midi.to_msg(data)
    if not d then return end
    local t = d.type
    if t == "note_on" and d.vel and d.vel > 0 then
        if solo_mode > 0 then
            held_push(d.note, d.vel)
            set_voice(solo_mode, held[#held])
        elseif para_mode then para_note_on(d.note, d.vel)
        else held_push(d.note, d.vel); update_voices() end
    elseif t == "note_off" or (t == "note_on" and d.vel == 0) then
        if solo_mode > 0 then
            held_remove(d.note)
            set_voice(solo_mode, held[#held] or nil)
        elseif para_mode then para_note_off(d.note)
        else held_remove(d.note); update_voices() end
    elseif t == "cc" and d.cc == 1 then
        local dest = CC1_PARAM[params:get("midi_cc1_dest")]
        if dest and params.lookup[dest] then
            params:set(dest, floor((d.val or 0) / 127 * 100 + 0.5))
        end
    end
end

function midi_input.set_gate_mode()
    apply_gate_state()
end

function midi_input.set_voice_mode()
    local mode = params.lookup["midi_voice_mode"] and params:get("midi_voice_mode") or 1
    para_mode = (mode == 2)
    solo_mode = (mode == 3) and 1 or (mode == 4) and 2 or 0
    rr = 2; voice_note = { nil, nil }
    if key_trigger then apply_gate_state() end
    if solo_mode > 0 then
        if held[#held] then set_voice(solo_mode, held[#held]) end
    elseif para_mode then
        local solo = solo_loaded_voice()
        if solo then
            if held[#held] then set_voice(solo, held[#held]) end
        else
            local n = #held
            if held[n]     then set_voice(alloc_voice(), held[n])     end
            if held[n - 1] then set_voice(alloc_voice(), held[n - 1]) end
        end
    else
        update_voices()
    end
    if key_trigger then
        for v = 1, 2 do
            if midi_controls_voice(v) and not voice_note[v] then
                cancel_retrig(v); engine.key_gate(v, 0)
            end
        end
    end
end

function midi_input.push_ad()
    push_ad()
end

function midi_input.add_params(opts)
    opts = opts or {}
    if opts.set_pitch then set_pitch = opts.set_pitch end
    if opts.on_voice_trigger then on_voice_trigger = opts.on_voice_trigger end
    if opts.on_voice_release then on_voice_release = opts.on_voice_release end
    if opts.voice_loaded then voice_loaded = opts.voice_loaded end
    m = midi.connect()
    m.event = handle
end

function midi_input.cleanup()
    if m then m.event = nil; m = nil end
    on_voice_trigger = nil
    on_voice_release = nil
    all_off()
    if engine and engine.key_hold then engine.key_hold(1, 1); engine.key_hold(2, 1) end
    if engine and engine.vel_amp  then engine.vel_amp(1, 1);  engine.vel_amp(2, 1)  end
    key_trigger = false
    para_mode   = false
    solo_mode   = 0
end

return midi_input