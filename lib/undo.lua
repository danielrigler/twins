local undo = {}
local utils = include("lib/utils")
local MAX_DEPTH = 8
local NUM_LFOS  = 16
local undo_stack = {}
local redo_stack = {}
local lfo_ref = nil
local keys    = nil
local on_before_restore, on_after_restore, on_action
local capture_extra, restore_extra
local EXCLUDE = {
    morph_amount = true, scene_mode = true, lfo_pause = true,
    dry_mode = true, dry_mode2 = true,
}
for k in pairs(utils.system_param_exclude) do EXCLUDE[k] = true end

local EXCLUDE_PATTERNS = {"^%d+sample$",}

local lfo_slot_ids = nil
local capture_ids  = nil
local capture_objs = nil

local function is_excluded(id)
    if EXCLUDE[id] then return true end
    for i = 1, #EXCLUDE_PATTERNS do
        if id:match(EXCLUDE_PATTERNS[i]) then return true end
    end
    return false
end

local capturable = utils.capturable

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
    capture_objs = {}
    local n = 0
    for _, p in ipairs(params.params) do
        local id = p.id
        if id and params.lookup[id] and not lfo_slot_ids[id]
           and not is_excluded(id) and capturable(p) then
            n = n + 1
            capture_ids[n] = id
            capture_objs[n] = p
        end
    end
end

local snap_pool = {}
local POOL_MAX = MAX_DEPTH + 2

local function alloc_snap()
    local n = #snap_pool
    if n > 0 then
        local s = snap_pool[n]
        snap_pool[n] = nil
        return s
    end
    local s = {params = {}, lfo = {}}
    for i = 1, NUM_LFOS do s.lfo[i] = {} end
    return s
end

local function free_snap(s)
    if not s then return end
    s.extra = nil
    if #snap_pool < POOL_MAX then snap_pool[#snap_pool + 1] = s end
end

local function capture()
    if not capture_ids then build_capture_list() end
    local snap = alloc_snap()
    local sp = snap.params
    for i = 1, #capture_ids do
        sp[capture_ids[i]] = capture_objs[i]:get()
    end
    local sl = snap.lfo
    for i = 1, NUM_LFOS do
        utils.fill_lfo_slot(i, keys, sl[i])
    end
    snap.extra = nil
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
        utils.apply_lfo_slot(i, keys, snap.lfo[i])
    end
    params:set("lfo_pause", was_paused)
    if restore_extra and snap.extra then pcall(restore_extra, snap.extra) end
    if lfo_ref and lfo_ref.invalidate_lfo_param_cache then
        lfo_ref.invalidate_lfo_param_cache()
    end
    if on_after_restore then pcall(on_after_restore) end
end

local function push(stack, snap)
    if #stack >= MAX_DEPTH then free_snap(table.remove(stack, 1)) end
    stack[#stack + 1] = snap
end

local function clear_stack(s)
    for i = #s, 1, -1 do free_snap(s[i]) s[i] = nil end
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

function undo.checkpoint()
    if _G.preset_loading then return end
    if not keys then return end
    push(undo_stack, capture())
    clear_stack(redo_stack)
end

function undo.undo()
    if #undo_stack == 0 then notify("NOTHING TO UNDO") return false end
    push(redo_stack, capture())
    local snap = table.remove(undo_stack)
    restore(snap)
    free_snap(snap)
    notify(#undo_stack > 0 and ("UNDO (" .. #undo_stack .. " LEFT)") or "UNDO")
    return true
end

function undo.redo()
    if #redo_stack == 0 then notify("NOTHING TO REDO") return false end
    push(undo_stack, capture())
    local snap = table.remove(redo_stack)
    restore(snap)
    free_snap(snap)
    notify("REDO")
    return true
end

function undo.clear()
    clear_stack(undo_stack)
    clear_stack(redo_stack)
end

return undo
