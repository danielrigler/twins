local presets = {}
local NameSizer = include("lib/preset_names")

presets.menu_open = false
presets.menu_mode = "load"
presets.selected_index = 1
presets.preset_list = {}
presets.confirmation = nil
presets.k2_mode = "delete"

_G.preset_loading = false
local buffer_loading = {pending = {}, complete = {}}
local loading_clock = nil
local PRESETS_DIR = "twins"
local BUFFER_TIMEOUT = 15
local PRESET_VERSION = 1
local _LFO_KEYS = {}
for _i = 1, 16 do _LFO_KEYS[_i] = _i .. "lfo" end

local RENAME_CHARSET = " abcdefghijklmnopqrstuvwxyz0123456789"
local RENAME_CHARSET_LEN = #RENAME_CHARSET
local RENAME_COMMIT_DELAY = 1.0
local RENAME_MAX_LEN = 18
local rename_commit_clock = nil

local function char_to_charset_idx(c)
    if not c or c == "" then return 2 end
    if c == " " then return 1 end
    return RENAME_CHARSET:find(c:lower(), 1, true) or 2
end

local function is_word_start(text, pos) return pos <= 1 or text:sub(pos-1, pos-1) == " " end

local function auto_case(ch, text, pos)
    if ch == " " then return " " end
    return is_word_start(text, pos) and ch:upper() or ch:lower()
end

local function cancel_rename_clock()
    if rename_commit_clock then
        pcall(function() clock.cancel(rename_commit_clock) end)
        rename_commit_clock = nil
    end
end

local function is_valid_sample_path(p)
    if not p or p == "-" or p == "" or p == "none" then return false end
    if p == _path.tape or p == (_path.tape .. "live!") then return false end
    return util.file_exists(p)
end

local function cancel_loading_clock()
    if loading_clock then
        pcall(function() if coroutine.status(loading_clock) ~= "dead" then clock.cancel(loading_clock) end end)
        loading_clock = nil
    end
end

function presets.buffer_loaded(voice)
    buffer_loading.complete[voice] = true
    buffer_loading.pending[voice] = false
    print("Buffer " .. voice .. " loaded")
end

local function all_buffers_loaded()
    for voice, pending in pairs(buffer_loading.pending) do
        if pending and not buffer_loading.complete[voice] then return false end
    end
    return true
end

local function wait_for_buffers(timeout)
    timeout = timeout or BUFFER_TIMEOUT
    local start_time = util.time()
    while not all_buffers_loaded() do
        if util.time() - start_time > timeout then print("⚠ Buffer loading timeout"); return false end
        clock.sleep(0.1)
    end
    return true
end

local function table_to_string(tbl, indent)
    indent = indent or ""
    local items = {}
    for k, v in pairs(tbl) do
        local ks = type(k) == "string" and string.format("%q", k) or tostring(k)
        local vs = type(v) == "table" and table_to_string(v, indent .. "  ")
               or (type(v) == "string" and string.format("%q", v) or tostring(v))
        items[#items+1] = string.format("%s  [%s] = %s", indent, ks, vs)
    end
    return string.format("{\n%s\n%s}", table.concat(items, ",\n"), indent)
end

local function get_all_params_state()
    local state = {}
    for _, param in pairs(params.params) do
        if param.id then state[param.id] = params:get(param.id) end
    end
    return state
end

local function get_file_mtime(path)
    local f = io.popen('stat -c "%Y" "' .. path .. '" 2>/dev/null')
    if not f then return 0 end
    local result = f:read("*n"); f:close()
    return result or 0
end

local function get_all_mtimes(dir)
    local mtimes = {}
    local f = io.popen('stat -c "%n %Y" "' .. dir .. '"/*.lua 2>/dev/null')
    if not f then return mtimes end
    for line in f:lines() do
        local name, t = line:match('([^/]+)%.lua (%d+)$')
        if name and t then mtimes[name] = tonumber(t) end
    end
    f:close()
    return mtimes
end

local function next_preset_number()
    local max_n = 0
    local f = io.popen('ls "' .. _path.data .. PRESETS_DIR .. '"/*.lua 2>/dev/null')
    if f then
        for line in f:lines() do
            local n = tonumber(line:match("/(%d+) "))
            if n and n > max_n then max_n = n end
        end
        f:close()
    end
    return max_n + 1
end

local function format_preset_number(n) return n >= 100 and tostring(n) or string.format("%02d", n) end

local function parse_preset_name(name)
    local n, word = name:match("^(%d+) (.+)$")
    return tonumber(n), word
end

local function build_available_numbers(current_preset_name)
    local current_n = parse_preset_name(current_preset_name)
    local used, max_n = {}, 0
    local f = io.popen('ls "' .. _path.data .. PRESETS_DIR .. '"/*.lua 2>/dev/null')
    if f then
        for line in f:lines() do
            local n = tonumber(line:match("/(%d+) "))
            if n and n ~= current_n then used[n] = true; if n > max_n then max_n = n end end
        end
        f:close()
    end
    local available = {}
    for i = 1, max_n + 1 do if not used[i] then available[#available+1] = i end end
    if #available == 0 then available[1] = 1 end
    return available
end

local function generate_preset_name(preset_name)
    if preset_name and preset_name ~= "" then return preset_name end
    return format_preset_number(next_preset_number()) .. " " .. NameSizer.rnd(" ")
end

function presets.save_complete_preset(preset_name, scene_data_ref, update_pan_positioning_fn, audio_active_ref)
    local success, err = pcall(function()
        preset_name = generate_preset_name(preset_name)
        local preset_data = {
            name = preset_name, timestamp = os.time(), version = PRESET_VERSION,
            params = get_all_params_state(),
            morph = {
                [1] = {scene_data_ref[1][1] or {}, scene_data_ref[1][2] or {}},
                [2] = {scene_data_ref[2][1] or {}, scene_data_ref[2][2] or {}}
            },
            morph_amount = params:get("morph_amount") or 0
        }
        util.make_dir(_path.data .. PRESETS_DIR)
        local file_path = _path.data .. PRESETS_DIR .. "/" .. preset_name .. ".lua"
        local file = io.open(file_path, "w")
        if not file then error("Could not open file for writing") end
        file:write(string.format(
            "-- Twins Preset\n-- Name: %s\n-- Saved: %s\n-- Version: %d\n\nreturn ",
            preset_name, os.date("%Y-%m-%d %H:%M:%S"), PRESET_VERSION
        ) .. table_to_string(preset_data))
        file:close()
        print("✓ Preset saved: " .. preset_name)
    end)
    if not success then print("✗ Error saving preset: " .. (err or "unknown")) end
    return success
end

local function apply_scene_data(preset_data, scene_data_ref)
    local source = preset_data.morph or preset_data.scene_data
    if not source then return end
    for track = 1, 2 do
        for scene = 1, 2 do
            scene_data_ref[track][scene] = (source[track] and source[track][scene]) or {}
        end
    end
end

local _PARAM_MATCHERS = {
    {fn = function(id) return id:match("^%d+lock$") end,                              bucket = 1},
    {fn = function(id) return id:match("sample_start$") or id:match("sample_end$") end, bucket = 2},
    {fn = function(id) return id:match("volume$") end,                                bucket = 3},
    {fn = function(id) return id == "allow_volume_lfos" end,                          bucket = 4},
    {fn = function(id) return id:match("^%d+lfo$") end,                              bucket = 5},
    {fn = function(id) return not id:match("sample$") end,                            bucket = 6},
}

local function categorize_params(preset_params)
    local buckets = {{}, {}, {}, {}, {}, {}}
    for param_id, value in pairs(preset_params) do
        if params.lookup[param_id] then
            for _, m in ipairs(_PARAM_MATCHERS) do
                if m.fn(param_id) then
                    local b = buckets[m.bucket]
                    b[#b+1] = {id = param_id, value = value}
                    break
                end
            end
        end
    end
    return buckets[1], buckets[2], buckets[3], buckets[5], buckets[4], buckets[6]
end

local function apply_params(lock_params, audio_params, volume_params, lfo_enable_params, allow_volume_lfo_params, other_params)
    for _, p in ipairs(lock_params)             do params:set(p.id, p.value) end; clock.sleep(0.02)
    for _, p in ipairs(audio_params)            do params:set(p.id, p.value) end; clock.sleep(0.03)
    for _, p in ipairs(volume_params)           do params:set(p.id, p.value) end; clock.sleep(0.03)
    for _, p in ipairs(allow_volume_lfo_params) do params:set(p.id, p.value) end; clock.sleep(0.03)
    for _, p in ipairs(other_params)            do params:set(p.id, p.value) end; clock.sleep(0.03)
    for _, p in ipairs(lfo_enable_params)       do params:set(p.id, p.value) end
end

local function refresh_voice_params()
    for i = 1, 2 do
        for _, suffix in ipairs({"volume", "granular_gain"}) do
            local p = i .. suffix
            if params.lookup[p] then params:set(p, params:get(p)) end
        end
    end
end

function presets.load_complete_preset(preset_name, scene_data_ref, update_pan_positioning_fn, audio_active_ref)
    local file_path = _path.data .. PRESETS_DIR .. "/" .. preset_name .. ".lua"
    if not util.file_exists(file_path) then print("✗ Preset file not found: " .. preset_name); return false end
    local chunk, err = loadfile(file_path)
    if not chunk then print("✗ Error loading preset: " .. (err or "unknown")); return false end
    local success, preset_data = pcall(chunk)
    if not success or not preset_data then print("✗ Error parsing preset: " .. (preset_data or "unknown")); return false end
    if preset_data.version and preset_data.version > PRESET_VERSION then print("⚠ Preset saved with newer version") end
    for i = 1, 2 do
        local vp = i .. "volume"
        if params.lookup[vp] then params:set(vp, -70) end
    end
    _G.preset_loading = true
    cancel_loading_clock()
    loading_clock = clock.run(function()
        if params.lookup["unload_all"] then params:set("unload_all", 1); clock.sleep(0.05) end
        for i = 1, 16 do if params.lookup[_LFO_KEYS[i]] then params:set(_LFO_KEYS[i], 1) end end
        apply_scene_data(preset_data, scene_data_ref)
        if preset_data.morph_amount then
            morph_amount = preset_data.morph_amount
            if params.lookup["morph_amount"] then params:set("morph_amount", preset_data.morph_amount) end
        end
        buffer_loading.pending = {}
        buffer_loading.complete = {}
        local sample_count = 0
        for i = 1, 2 do
            local sp = i .. "sample"
            if params.lookup[sp] and preset_data.params and preset_data.params[sp] then
                if is_valid_sample_path(preset_data.params[sp]) then
                    buffer_loading.pending[i] = true
                    buffer_loading.complete[i] = false
                    sample_count = sample_count + 1
                end
            end
        end
        if preset_data.params and sample_count > 0 then
            print("⏳ Loading " .. sample_count .. " sample" .. (sample_count > 1 and "s" or "") .. "...")
            for param_id, value in pairs(preset_data.params) do
                if param_id:match("sample$") and params.lookup[param_id] then params:set(param_id, value) end
            end
        end
        clock.sleep(0.05)
        if sample_count > 0 then
            local ok = wait_for_buffers(BUFFER_TIMEOUT)
            print(ok and "✓ All buffers loaded" or "⚠ Timeout - some samples may not be ready")
        end
        for i = 1, 2 do
            local sp = i .. "sample"
            if params.lookup[sp] then audio_active_ref[i] = is_valid_sample_path(params:get(sp)) end
        end
        _G.preset_loading = false
        if preset_data.params then
            apply_params(categorize_params(preset_data.params))
        end
        update_pan_positioning_fn()
        refresh_voice_params()
        clock.sleep(0.1)
        redraw()
        print("✓ Preset loaded: " .. preset_name)
        loading_clock = nil
    end)
    return true
end

function presets.list_presets()
    local list = {}
    local dir = _path.data .. PRESETS_DIR
    util.make_dir(dir)
    local success, entries = pcall(util.scandir, dir)
    if not (success and entries) then return list end
    for _, entry in ipairs(entries) do
        if type(entry) == "string" and entry:match("%.lua$") then
            list[#list+1] = entry:gsub("%.lua$", "")
        end
    end
    local mtimes = get_all_mtimes(dir)
    table.sort(list, function(a, b)
        local na = parse_preset_name(a) or 0
        local nb = parse_preset_name(b) or 0
        if na ~= nb then return na > nb end
        return (mtimes[a] or 0) > (mtimes[b] or 0)
    end)
    return list
end

function presets.delete_preset(preset_name)
    local file_path = _path.data .. PRESETS_DIR .. "/" .. preset_name .. ".lua"
    if not util.file_exists(file_path) then print("✗ Preset not found: " .. preset_name); return false end
    local success, err = pcall(os.remove, file_path)
    if success then print("✓ Preset deleted: " .. preset_name); return true end
    print("✗ Error deleting preset: " .. (err or "unknown"))
    return false
end

function presets.open_menu()
    local list = presets.list_presets()
    if #list == 0 then print("No presets found"); return false end
    cancel_rename_clock()
    presets.preset_list    = list
    presets.selected_index = util.clamp(presets.selected_index, 1, #list)
    presets.menu_open      = true
    presets.menu_mode      = "load"
    presets.k2_mode        = "delete"
    presets.confirmation   = nil
    return true
end

function presets.close_menu()
    cancel_rename_clock()
    presets.menu_open    = false
    presets.confirmation = nil
    presets.menu_mode    = "load"
    presets.k2_mode      = "delete"
    presets.preset_list  = {}
end

local function move_preset_swap(idx_a, idx_b)
    local name_a, name_b = presets.preset_list[idx_a], presets.preset_list[idx_b]
    if not name_a or not name_b then return nil end
    local na, wa = parse_preset_name(name_a)
    local nb, wb = parse_preset_name(name_b)
    if not na or not nb or not wa or not wb then return nil end
    local dir = _path.data .. PRESETS_DIR .. "/"
    local new_a = format_preset_number(nb) .. " " .. wa
    os.rename(dir .. name_a .. ".lua", dir .. new_a .. ".lua")
    os.rename(dir .. name_b .. ".lua", dir .. format_preset_number(na) .. " " .. wb .. ".lua")
    return new_a
end

local MENU_MODES = {"load", "rename", "save"}
local _MODE_INDEX = {}
for i, m in ipairs(MENU_MODES) do _MODE_INDEX[m] = i end

local function cycle_mode(current, delta)
    local i = _MODE_INDEX[current]
    if not i then return "load" end
    return MENU_MODES[math.max(1, math.min(#MENU_MODES, i + delta))]
end

local function pad_text(text, len)
    return #text < len and text .. string.rep(" ", len - #text) or text:sub(1, len)
end

local function str_set_char(str, pos, ch) return str:sub(1, pos-1) .. ch .. str:sub(pos+1) end

local function start_commit_clock()
    cancel_rename_clock()
    rename_commit_clock = clock.run(function()
        clock.sleep(RENAME_COMMIT_DELAY)
        rename_commit_clock = nil
        local conf = presets.confirmation
        if not (conf and conf.type == "rename" and conf.rename_mode == "manual") then return end
        if conf.pending_char then
            if conf.manual_cursor > #conf.manual_text then
                conf.manual_text = conf.manual_text .. string.rep(" ", conf.manual_cursor - #conf.manual_text)
            end
            conf.manual_text = str_set_char(conf.manual_text, conf.manual_cursor, conf.pending_char)
            conf.pending_char = nil
        end
        local trimmed_len = #(conf.manual_text:match("^(.-)%s*$") or conf.manual_text)
        local max_cursor  = math.min(trimmed_len + 2, RENAME_MAX_LEN)
        if conf.manual_cursor < max_cursor then
            conf.manual_cursor = conf.manual_cursor + 1
            if conf.manual_cursor > #conf.manual_text then conf.manual_text = conf.manual_text .. " " end
            conf.manual_char_idx = char_to_charset_idx(conf.manual_text:sub(conf.manual_cursor, conf.manual_cursor))
        end
        local trimmed = conf.manual_text:match("^(.-)%s*$") or conf.manual_text
        conf.suggested_name = format_preset_number(conf.suggested_number) .. " " .. trimmed
        redraw()
    end)
end

function presets.menu_enc(n, d)
    if not presets.menu_open then return end

    if presets.confirmation and presets.confirmation.type == "rename" then
        local conf = presets.confirmation

        if conf.rename_mode == "manual" then
            if n == 1 then
                conf.erase_acc = (conf.erase_acc or 0) + math.abs(d)
                if conf.erase_acc < 3 then return end
                conf.erase_acc = 0
                conf.pending_char = nil
                cancel_rename_clock()
                local t = conf.manual_text
                if d < 0 then
                    if conf.manual_cursor > 1 then
                        conf.manual_text   = t:sub(1, conf.manual_cursor-2) .. t:sub(conf.manual_cursor)
                        conf.manual_cursor = conf.manual_cursor - 1
                        if #conf.manual_text == 0 then conf.manual_text = "A"; conf.manual_cursor = 1 end
                    end
                else
                    if conf.manual_cursor <= #t then
                        conf.manual_text = t:sub(1, conf.manual_cursor-1) .. t:sub(conf.manual_cursor+1)
                        if #conf.manual_text == 0 then
                            conf.manual_text = "A"; conf.manual_cursor = 1
                        else
                            conf.manual_cursor = math.min(conf.manual_cursor, #conf.manual_text)
                        end
                    end
                end
                conf.manual_char_idx = char_to_charset_idx(conf.manual_text:sub(conf.manual_cursor, conf.manual_cursor))
                local trimmed = conf.manual_text:match("^(.-)%s*$") or conf.manual_text
                conf.suggested_name = format_preset_number(conf.suggested_number) .. " " .. trimmed
                redraw()

            elseif n == 2 then
                cancel_rename_clock()
                conf.pending_char = nil
                local trimmed_len = #(conf.manual_text:match("^(.-)%s*$") or conf.manual_text)
                local new_cursor  = util.clamp(conf.manual_cursor + d, 1, math.min(trimmed_len + 2, RENAME_MAX_LEN))
                if new_cursor ~= conf.manual_cursor then
                    if new_cursor > #conf.manual_text then
                        conf.manual_text = conf.manual_text .. string.rep(" ", new_cursor - #conf.manual_text)
                    end
                    conf.manual_cursor   = new_cursor
                    conf.manual_char_idx = char_to_charset_idx(conf.manual_text:sub(conf.manual_cursor, conf.manual_cursor))
                    local trimmed = conf.manual_text:match("^(.-)%s*$") or conf.manual_text
                    conf.suggested_name = format_preset_number(conf.suggested_number) .. " " .. trimmed
                    if conf.manual_text:sub(conf.manual_cursor, conf.manual_cursor) == " " then
                        conf.pending_char = " "; start_commit_clock()
                    end
                    redraw()
                end

            elseif n == 3 then
                local trimmed_len = #(conf.manual_text:match("^(.-)%s*$") or conf.manual_text)
                local is_new  = conf.manual_cursor > trimmed_len
                local prev_ch = conf.manual_cursor > 1 and conf.manual_text:sub(conf.manual_cursor-1, conf.manual_cursor-1) or ""
                local new_idx, tries = conf.manual_char_idx, 0
                repeat
                    new_idx = ((new_idx - 1 + d) % RENAME_CHARSET_LEN) + 1
                    tries = tries + 1
                    local candidate = RENAME_CHARSET:sub(new_idx, new_idx)
                    if not (candidate == " " and (conf.manual_cursor == 1 or prev_ch == " ")) then break end
                until tries > RENAME_CHARSET_LEN
                conf.manual_char_idx = new_idx
                local new_char = auto_case(RENAME_CHARSET:sub(new_idx, new_idx), conf.manual_text, conf.manual_cursor)
                if is_new then
                    conf.pending_char = new_char; start_commit_clock()
                else
                    cancel_rename_clock()
                    conf.pending_char = nil
                    if conf.manual_cursor > #conf.manual_text then
                        conf.manual_text = pad_text(conf.manual_text, conf.manual_cursor)
                    end
                    conf.manual_text = str_set_char(conf.manual_text, conf.manual_cursor, new_char)
                    local trimmed = conf.manual_text:match("^(.-)%s*$") or conf.manual_text
                    conf.suggested_name = format_preset_number(conf.suggested_number) .. " " .. trimmed
                end
                redraw()
            end
        else
            if n == 2 then
                conf.avail_index      = util.clamp(conf.avail_index + d, 1, #conf.available_numbers)
                conf.suggested_number = conf.available_numbers[conf.avail_index]
                conf.suggested_name   = format_preset_number(conf.suggested_number) .. " " .. conf.suggested_word
                redraw()
            elseif n == 3 then
                conf.suggested_word = NameSizer.rnd(" ")
                conf.suggested_name = format_preset_number(conf.suggested_number) .. " " .. conf.suggested_word
                redraw()
            end
        end
        return
    end

    if n == 1 then
        presets.k2_mode = (d > 0) and "move" or "delete"
    elseif n == 2 then
        if presets.k2_mode == "move" then
            local neighbor = presets.selected_index + (d > 0 and 1 or -1)
            if neighbor >= 1 and neighbor <= #presets.preset_list then
                local moved_name = move_preset_swap(presets.selected_index, neighbor)
                presets.preset_list = presets.list_presets()
                if moved_name then
                    for i, name in ipairs(presets.preset_list) do
                        if name == moved_name then presets.selected_index = i; break end
                    end
                end
            end
        else
            presets.selected_index = util.clamp(presets.selected_index + d, 1, #presets.preset_list)
        end
    elseif n == 3 then
        presets.menu_mode = cycle_mode(presets.menu_mode, d > 0 and 1 or -1)
    end
    redraw()
end

function presets.menu_key(n, z, scene_data_ref, update_pan_positioning_fn, audio_active_ref)
    if not presets.menu_open or z ~= 1 then return false end

    if presets.confirmation then
        if n == 1 then cancel_rename_clock(); presets.close_menu(); return true end

        if presets.confirmation.type == "rename" and n == 2 then
            cancel_rename_clock()
            local conf = presets.confirmation
            if conf.rename_mode == "random" then
                local _, saved_word = parse_preset_name(conf.preset_name)
                saved_word = saved_word or conf.preset_name
                conf.rename_mode     = "manual"
                conf.manual_text     = saved_word
                conf.manual_cursor   = 1
                conf.manual_char_idx = char_to_charset_idx(saved_word:sub(1, 1))
                conf.erase_acc       = 0
                conf.pending_char    = nil
            else
                conf.rename_mode    = "random"
                local trimmed       = conf.manual_text:match("^(.-)%s*$") or conf.manual_text
                conf.suggested_word = trimmed
                conf.suggested_name = format_preset_number(conf.suggested_number) .. " " .. trimmed
            end
            redraw(); return true
        end

        if n == 3 then
            if presets.confirmation.type == "delete" then
                local preset_name  = presets.confirmation.preset_name
                local preset_index = presets.confirmation.preset_index
                presets.delete_preset(preset_name)
                presets.preset_list = presets.list_presets()
                presets.confirmation = nil
                if #presets.preset_list == 0 then
                    presets.menu_open = false
                else
                    presets.selected_index = util.clamp(preset_index, 1, #presets.preset_list)
                end
            elseif presets.confirmation.type == "save" then
                local file_path = _path.data .. PRESETS_DIR .. "/" .. presets.confirmation.preset_name .. ".lua"
                local mtime = get_file_mtime(file_path)
                presets.save_complete_preset(presets.confirmation.preset_name, scene_data_ref, update_pan_positioning_fn, audio_active_ref)
                if mtime and mtime > 0 then
                    os.execute('touch -m -d @' .. mtime .. ' "' .. file_path .. '"')
                end
                presets.confirmation = nil
                presets.menu_open = false
            elseif presets.confirmation.type == "rename" then
                cancel_rename_clock()
                local new_name = presets.confirmation.suggested_name or presets.confirmation.preset_name
                new_name = new_name:match("^(.-)%s*$") or new_name
                if new_name ~= presets.confirmation.preset_name then
                    local dir = _path.data .. PRESETS_DIR .. "/"
                    os.rename(dir .. presets.confirmation.preset_name .. ".lua", dir .. new_name .. ".lua")
                end
                presets.confirmation = nil
                presets.preset_list  = presets.list_presets()
                presets.selected_index = 1
                for i, name in ipairs(presets.preset_list) do
                    if name == new_name then presets.selected_index = i; break end
                end
            end
        else
            cancel_rename_clock()
            if presets.confirmation.type == "rename" then presets.confirmation.pending_char = nil end
            presets.confirmation = nil
        end
        return true
    end

    local preset_name = presets.preset_list[presets.selected_index]
    if n == 3 then
        if presets.menu_mode == "load" then
            local success = presets.load_complete_preset(preset_name, scene_data_ref, update_pan_positioning_fn, audio_active_ref)
            presets.menu_open = false
            return success
        elseif presets.menu_mode == "save" then
            presets.confirmation = {type = "save", preset_name = preset_name}
            return true
        else
            local current_n, current_word = parse_preset_name(preset_name)
            current_n    = current_n    or 1
            current_word = current_word or preset_name
            local avail  = build_available_numbers(preset_name)
            local avail_index = 1
            for i, v in ipairs(avail) do if v == current_n then avail_index = i; break end end
            local suggested_number = avail[avail_index]
            presets.confirmation = {
                type              = "rename",
                rename_mode       = "random",
                preset_name       = preset_name,
                suggested_number  = suggested_number,
                suggested_word    = current_word,
                available_numbers = avail,
                avail_index       = avail_index,
                suggested_name    = format_preset_number(suggested_number) .. " " .. current_word,
                manual_text       = current_word,
                manual_cursor     = 1,
                manual_char_idx   = char_to_charset_idx(current_word:sub(1, 1)),
                erase_acc         = 0,
                pending_char      = nil,
            }
            return true
        end
    elseif n == 2 then
        presets.confirmation = {type = "delete", preset_name = preset_name, preset_index = presets.selected_index}
        return true
    elseif n == 1 then
        presets.close_menu(); return true
    end
    return false
end

local function draw_rename_manual(conf)
    screen.clear()
    screen.level(15); screen.move(64, 9);  screen.text_center("RENAME")
    screen.level(3);  screen.move(64, 17); screen.text_center("manual mode")

    local num_str  = format_preset_number(conf.suggested_number) .. " "
    local text     = conf.manual_text
    local cursor   = conf.manual_cursor
    if cursor > #text then text = pad_text(text, cursor) end
    local before   = text:sub(1, cursor-1)
    local cur_char = conf.pending_char or text:sub(cursor, cursor)
    if cur_char == "" then cur_char = " " end
    local after    = (text:sub(cursor+1):match("^(.-)%s*$") or text:sub(cursor+1))

    local pad       = 1
    local sentinel  = "|"
    local sentinel_w  = screen.text_extents(sentinel)
    local num_w       = screen.text_extents(num_str:match("^(.-)%s*$") or num_str)
    local before_w    = screen.text_extents(before .. sentinel) - sentinel_w
    local rect_w      = math.max(screen.text_extents(cur_char), 4) + pad * 2
    local full_name   = text:match("^(.-)%s*$") or text
    local total_w     = num_w + 4 + screen.text_extents(full_name) + pad * 2
    local start_x     = math.floor(64 - total_w / 2)
    local before_x    = start_x + num_w + 4
    local cur_x       = before_x + before_w
    local y_name      = 30

    screen.level(4);  screen.move(start_x,  y_name); screen.text(num_str)
    screen.level(15); screen.move(before_x, y_name); screen.text(before)
    screen.level(15); screen.rect(cur_x, y_name-6, rect_w, 8); screen.fill()
    screen.level(0);  screen.move(cur_x + pad, y_name); screen.text(cur_char)
    screen.level(15); screen.move(cur_x + rect_w, y_name); screen.text(after)

    screen.level(2); screen.move(64, 44); screen.text_center("E1: del   E2: pos   E3: char")
    screen.level(3); screen.move(2,   64); screen.text("[K1]: Exit")
    screen.move(68, 64); screen.text_center("K2: Mode")
    screen.move(126, 64); screen.text_right("K3: OK")
    screen.update()
end

local function draw_confirmation(title, preset_name, suggested_name)
    screen.clear()
    if suggested_name then
        screen.level(15); screen.move(64, 9);  screen.text_center("RENAME")
        screen.level(3);  screen.move(64, 17); screen.text_center("random mode")
        screen.level(15); screen.move(64, 30); screen.text_center(suggested_name)
        screen.level(2);  screen.move(64, 44); screen.text_center("E2: number   E3: name")
        screen.level(3); screen.move(2,   64); screen.text("[K1]: Exit")
        screen.move(68, 64); screen.text_center("K2: Mode")
        screen.move(126, 64); screen.text_right("K3: OK")
    else
        screen.level(15); screen.move(64, 12); screen.text_center(title)
        screen.level(8);  screen.move(64, 26); screen.text_center(preset_name or "Unknown Preset")
        screen.level(4);  screen.move(64, 64); screen.text_center("K2: Cancel   K3: Confirm")
    end
    screen.update()
end

function presets.draw_menu()
    if not presets.menu_open then return false end
    if presets.confirmation then
        if presets.confirmation.type == "rename" and presets.confirmation.rename_mode == "manual" then
            draw_rename_manual(presets.confirmation)
        else
            local titles = {delete = "DELETE PRESET?", save = "OVERWRITE PRESET?", rename = "RENAME PRESET"}
            draw_confirmation(titles[presets.confirmation.type] or "RENAME PRESET",
                presets.confirmation.preset_name, presets.confirmation.suggested_name)
        end
        return true
    end
    screen.clear()
    screen.level(15); screen.move(64, 6); screen.text_center("PRESET BROWSER")
    local visible_count = math.min(5, #presets.preset_list)
    local start_index   = math.max(1, math.min(presets.selected_index - 2, #presets.preset_list - visible_count + 1))
    for i = 1, visible_count do
        local idx = start_index + i - 1
        if idx <= #presets.preset_list then
            local is_selected = idx == presets.selected_index
            local y    = 11 + (i * 8)
            local name = presets.preset_list[idx]:gsub("twins_", "")
            local n, word = name:match("^(%d+) (.+)$")
            screen.level(is_selected and 15 or 1)
            screen.move(2, y)
            screen.text(is_selected and (presets.k2_mode == "move" and "▶" or ">") or "")
            if n then
                screen.move(18, y); screen.level(is_selected and 15 or 1); screen.text_right(n)
                screen.move(22, y); screen.level(is_selected and 15 or 4); screen.text(word)
            else
                screen.move(22, y); screen.text(name)
            end
        end
    end
    if #presets.preset_list > visible_count then
        screen.level(2)
        if start_index > 1 then screen.move(122, 19); screen.text("↑") end
        if start_index + visible_count - 1 < #presets.preset_list then screen.move(122, 51); screen.text("↓") end
    end
    local mode_bright = {load = 1, save = 15, rename = 8}
    local mode_labels = {load = "Load", rename = "Edit", save = "Save"}
    screen.level(1); screen.move(2,  64); screen.text("[K1]: Exit")
    screen.level(1); screen.move(50, 64); screen.text("K2: Del")
    screen.level(mode_bright[presets.menu_mode] or 1)
    screen.move(91, 64); screen.text("K3: " .. (mode_labels[presets.menu_mode] or "Load"))
    screen.update()
    return true
end

function presets.is_menu_open() return presets.menu_open end

function presets.cleanup()
    cancel_loading_clock()
    cancel_rename_clock()
    _G.preset_loading = false
end

return presets