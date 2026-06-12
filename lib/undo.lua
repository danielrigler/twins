local undo = {}
local MAX_DEPTH = 8
local NUM_LFOS  = 16
local undo_stack = {}
local redo_stack = {}
local lfo_ref = nil
local keys    = nil
local on_before_restore, on_after_restore, on_action
local capture_extra, restore_extra
local EXCLUDE = {
    reverb = true, reverb_eng_cut = true, reverb_eng_dry = true,
    monitor_level = true, input_level = true, input_level_l = true, input_level_r = true,
    output_level = true, headphone_level = true, screen_brightness = true,
    clock_source = true, clock_tempo = true, clock_crow_in_div = true,
    clock_crow_out_div = true, clock_link_quantum = true, clock_link_start_stop_sync = true,
    midi_out_clock = true, midi_in_clock = true,
    enc_sens_default = true, key_repeat_initial = true, key_repeat_period = true,
    morph_amount = true, scene_mode = true, lfo_pause = true,
    dry_mode = true, dry_mode2 = true,
}

local EXCLUDE_PATTERNS = {"^%d+sample$",}

local T_SEPARATOR, T_FILE, T_TRIGGER, T_GROUP, T_TEXT = 0, 4, 6, 7, 8

local lfo_slot_ids = nil
local capture_ids  = nil

local function is_excluded(id)
    if EXCLUDE[id] then return true end
    for i = 1, #EXCLUDE_PATTERNS do
        if id:match(EXCLUDE_PATTERNS[i]) then return true end
    end
    return false
end

local function capturable(p)
    local t = p.t
    if t == T_SEPARATOR or t == T_FILE or t == T_TRIGGER or t == T_GROUP or t == T_TEXT then
        return false
    end
    if p.behavior and p.behavior ~= "toggle" then return false end
    return true
end

local function build_capture_list()
    lfo_slot_ids = {}
    for i = 1, NUM_LFOS do
        lfo_slot_ids[keys.lfo[i]]    = true
        lfo_slot_ids[keys.target[i]] = true
        lfo_slot_ids[keys.shape[i]]  = true
        lfo_slot_ids[keys.freq[i]]   = true
        lfo_slot_ids[keys.depth[i]]  = true
        lfo_slot_ids[keys.offset[i]] = true
    end
    capture_ids = {}
    for _, p in ipairs(params.params) do
        local id = p.id
        if id and params.lookup[id] and not lfo_slot_ids[id]
           and not is_excluded(id) and capturable(p) then
            capture_ids[#capture_ids + 1] = id
        end
    end
end

local function capture()
    if not capture_ids then build_capture_list() end
    local snap = {params = {}, lfo = {}}
    local sp = snap.params
    for i = 1, #capture_ids do
        local id = capture_ids[i]
        sp[id] = params:get(id)
    end
    for i = 1, NUM_LFOS do
        snap.lfo[i] = {
            state  = params:get(keys.lfo[i]),
            target = params:get(keys.target[i]),
            shape  = params:get(keys.shape[i]),
            freq   = params:get(keys.freq[i]),
            depth  = params:get(keys.depth[i]),
            offset = params:get(keys.offset[i]),
        }
    end
    if capture_extra then
        local ok, extra = pcall(capture_extra)
        if ok then snap.extra = extra end
    end
    return snap
end

local function restore(snap)
    if on_before_restore then pcall(on_before_restore) end

    local was_paused = params:get("lfo_pause")
    params:set("lfo_pause", 1)

    for i = 1, NUM_LFOS do params:set(keys.lfo[i], 1) end

    for id, v in pairs(snap.params) do
        if params.lookup[id] then params:set(id, v) end
    end

    for i = 1, NUM_LFOS do
        local s = snap.lfo[i]
        params:set(keys.target[i], s.target)
        params:set(keys.shape[i],  s.shape)
        params:set(keys.freq[i],   s.freq)
        params:set(keys.depth[i],  s.depth)
        params:set(keys.offset[i], s.offset)
        params:set(keys.lfo[i],    s.state)
    end

    params:set("lfo_pause", was_paused)

    if restore_extra and snap.extra then pcall(restore_extra, snap.extra) end

    if lfo_ref and lfo_ref.invalidate_lfo_param_cache then
        lfo_ref.invalidate_lfo_param_cache()
    end
    if on_after_restore then pcall(on_after_restore) end
end

local function push(stack, snap)
    if #stack >= MAX_DEPTH then table.remove(stack, 1) end
    stack[#stack + 1] = snap
end

local function notify(msg)
    if on_action then pcall(on_action, msg) end
end

function undo.init(opts)
    lfo_ref           = opts.lfo
    keys              = lfo_ref.keys
    on_before_restore = opts.on_before_restore
    on_after_restore  = opts.on_after_restore
    on_action         = opts.on_action
    capture_extra     = opts.capture_extra
    restore_extra     = opts.restore_extra
    undo.clear()
end

function undo.rebuild_param_list()
    capture_ids = nil
end

function undo.checkpoint()
    if _G.preset_loading then return end
    if not keys then return end
    push(undo_stack, capture())
    for i = #redo_stack, 1, -1 do redo_stack[i] = nil end
end

function undo.undo()
    if #undo_stack == 0 then notify("NOTHING TO UNDO") return false end
    push(redo_stack, capture())
    restore(table.remove(undo_stack))
    notify(#undo_stack > 0 and ("UNDO (" .. #undo_stack .. " LEFT)") or "UNDO")
    return true
end

function undo.redo()
    if #redo_stack == 0 then notify("NOTHING TO REDO") return false end
    push(undo_stack, capture())
    restore(table.remove(redo_stack))
    notify("REDO")
    return true
end

function undo.clear()
    for i = #undo_stack, 1, -1 do undo_stack[i] = nil end
    for i = #redo_stack, 1, -1 do redo_stack[i] = nil end
end

function undo.depth()    return #undo_stack       end
function undo.can_undo() return #undo_stack > 0   end
function undo.can_redo() return #redo_stack > 0   end

return undo