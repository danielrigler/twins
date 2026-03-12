local presets = {}
local NameSizer = include("lib/preset_names")

presets.menu_open      = false
presets.menu_mode      = "load"
presets.selected_index = 1
presets.preset_list    = {}
presets.confirmation   = nil
presets.k2_mode        = "delete"

_G.preset_loading = false

local PRESETS_DIR         = "twins"
local PRESET_VERSION      = 1
local RENAME_CHARSET      = " abcdefghijklmnopqrstuvwxyz_0123456789"
local RENAME_CHARSET_LEN  = #RENAME_CHARSET
local RENAME_COMMIT_DELAY = 1.0
local RENAME_MAX_LEN      = 23
local MENU_MODES          = {"load", "rename", "save"}

local loading_clock = nil
local rename_clock  = nil
local LFO_KEYS      = {}
for i = 1, 16 do LFO_KEYS[i] = i .. "lfo" end

local PARAM_MATCHERS = {
    "^%d+lock$",
    "sample_[se][tn][ad]r?t?$",
    "volume$",
}
local PARAM_DELAYS = { 0.02, 0.03, 0.03, 0.03, 0, 0.03 }

local function format_number(n) return n >= 100 and tostring(n) or string.format("%02d", n) end
local function fmt_name(n, w)   return format_number(n) .. " " .. w end

local function cancel_clock(c)
    if c then pcall(clock.cancel, c) end
    return nil
end
local function cancel_rename_clock()  rename_clock  = cancel_clock(rename_clock)  end
local function cancel_loading_clock() loading_clock = cancel_clock(loading_clock) end

local function pad_text(text, len)
    return #text < len and text .. string.rep(" ", len - #text) or text:sub(1, len)
end

local function str_set_char(str, pos, ch) return str:sub(1, pos-1) .. ch .. str:sub(pos+1) end
local function is_word_start(text, pos)   return pos <= 1 or text:sub(pos-1, pos-1) == " "  end

local function auto_case(ch, text, pos)
    if ch == " " then return " " end
    return is_word_start(text, pos) and ch:upper() or ch:lower()
end

local function char_to_charset_idx(c)
    if not c or c == "" then return 2 end
    if c == " " then return 1 end
    return RENAME_CHARSET:find(c:lower(), 1, true) or 2
end

local function cycle_mode(current, delta)
    for i, m in ipairs(MENU_MODES) do
        if m == current then return MENU_MODES[util.clamp(i + delta, 1, #MENU_MODES)] end
    end
    return "load"
end

local function parse_preset_name(name)
    local n, word = name:match("^(%d+) (.+)$")
    return tonumber(n), word
end

local function is_valid_sample(p)
    if not p or p == "-" or p == "" or p == "none" then return false end
    if p == _path.tape or p == (_path.tape .. "live!") then return false end
    return util.file_exists(p)
end

function presets.list_presets()
    local dir  = _path.data .. PRESETS_DIR
    util.make_dir(dir)
    local list   = {}
    local mtimes = {}
    local f = io.popen('stat -c "%n %Y" "' .. dir .. '"/*.lua 2>/dev/null')
    if f then
        for line in f:lines() do
            local name, t = line:match('([^/]+)%.lua (%d+)$')
            if name then
                list[#list+1]  = name
                mtimes[name]   = tonumber(t)
            end
        end
        f:close()
    end
    table.sort(list, function(a, b)
        local na = parse_preset_name(a) or 0
        local nb = parse_preset_name(b) or 0
        if na ~= nb then return na > nb end
        return (mtimes[a] or 0) > (mtimes[b] or 0)
    end)
    return list
end

local SYSTEM_PARAMS_EXCLUDE = {
    reverb=true, reverb_eng_cut=true, reverb_eng_dry=true,
    monitor_level=true, input_level=true, input_level_l=true, input_level_r=true,
    output_level=true, headphone_level=true, screen_brightness=true,
    clock_source=true, clock_tempo=true, clock_crow_in_div=true,
    clock_crow_out_div=true, clock_link_quantum=true, clock_link_start_stop_sync=true,
    midi_out_clock=true, midi_in_clock=true,
    enc_sens_default=true, key_repeat_initial=true, key_repeat_period=true,
}

local function params_snapshot()
    local state = {}
    for id in pairs(params.lookup) do if not SYSTEM_PARAMS_EXCLUDE[id] then state[id] = params:get(id) end end
    return state
end

local function serialize(tbl, indent)
    indent    = indent or ""
    local sub = indent .. "  "
    local out = { "{\n" }
    for k, v in pairs(tbl) do
        local ks = type(k) == "string" and string.format("%q", k) or tostring(k)
        local vs = type(v) == "table"  and serialize(v, sub)
               or (type(v) == "string" and string.format("%q", v) or tostring(v))
        out[#out+1] = string.format("%s  [%s] = %s,\n", indent, ks, vs)
    end
    out[#out+1] = indent .. "}"
    return table.concat(out)
end

local function get_mtime(path)
    local f = io.popen('stat -c "%Y" "' .. path .. '" 2>/dev/null')
    if not f then return 0 end
    local t = f:read("*n"); f:close(); return t or 0
end

function presets.save_complete_preset(name, scene_data, active_mode, active_filter_mode)
    local ok, err = pcall(function()
        if not name or name == "" then
            local existing = presets.list_presets()
            local max_n = 0
            for i = 1, #existing do
                local n = parse_preset_name(existing[i])
                if n and n > max_n then max_n = n end
            end
            name = format_number(max_n + 1) .. " " .. NameSizer.rnd(" ")
        end
        local params_state = params_snapshot()
        local morph_amount = params:get("morph_amount") or 0
        local data = {
            name = name,
            timestamp = os.time(),
            version = PRESET_VERSION,
            params = params_state,
            morph = {{scene_data[1][1] or {}, scene_data[1][2] or {}},
                     {scene_data[2][1] or {}, scene_data[2][2] or {}}},
            morph_amount = morph_amount,
            active_mode = active_mode,
            active_filter_mode = active_filter_mode,
        }
        local presets_path = _path.data .. PRESETS_DIR
        util.make_dir(presets_path)
        local path = presets_path .. "/" .. name .. ".lua"
        local file, open_err = io.open(path, "w")
        if not file then error("Cannot write: " .. path .. " (" .. tostring(open_err) .. ")") end
        local header = string.format("-- Twins Preset\n-- Name: %s\n-- Saved: %s\n-- Version: %d\n\nreturn ", name, os.date("%Y-%m-%d %H:%M:%S"), PRESET_VERSION)
        file:write(header, serialize(data))
        file:close()
        print("✓ Saved: " .. name)
    end)
    if not ok then print("✗ Save error: " .. (err or "unknown")) end
    return ok
end

function presets.delete_preset(name)
    local path = _path.data .. PRESETS_DIR .. "/" .. name .. ".lua"
    if not util.file_exists(path) then print("✗ Not found: " .. name); return false end
    local ok, err = pcall(os.remove, path)
    if ok then print("✓ Deleted: " .. name) else print("✗ Delete error: " .. (err or "?")) end
    return ok
end

local function apply_params_ordered(p)
    local buckets = { {}, {}, {}, {}, {}, {} }
    for id, value in pairs(p) do
        if params.lookup[id] and not id:match("^%d+sample$")
                and not id:match("^%d+volume$") and not id:match("^%d+granular_gain$") then
            local placed = false
            for i = 1, 3 do
                if id:match(PARAM_MATCHERS[i]) then
                    buckets[i][#buckets[i]+1] = { id=id, value=value }
                    placed = true; break
                end
            end
            if not placed then
                if id == "allow_volume_lfos" then
                    buckets[4][#buckets[4]+1] = { id=id, value=value }
                elseif id:match("^%d+lfo$") then
                    buckets[5][#buckets[5]+1] = { id=id, value=value }
                else
                    buckets[6][#buckets[6]+1] = { id=id, value=value }
                end
            end
        end
    end
    for i, bucket in ipairs(buckets) do
        for _, item in ipairs(bucket) do params:set(item.id, item.value) end
        if PARAM_DELAYS[i] > 0 then clock.sleep(PARAM_DELAYS[i]) end
    end
end

function presets.load_complete_preset(name, scene_data, update_pan, audio_active, on_loaded)
    local path = _path.data .. PRESETS_DIR .. "/" .. name .. ".lua"
    if not util.file_exists(path) then print("✗ Not found: " .. name); return false end
    local chunk, err = loadfile(path)
    if not chunk then print("✗ Load error: " .. (err or "?")); return false end
    local ok, data = pcall(chunk)
    if not ok or not data then print("✗ Parse error: " .. (data or "?")); return false end
    if data.version and data.version > PRESET_VERSION then print("⚠ Newer preset version") end
    local saved_output_level
    if params.lookup["output_level"] then
        saved_output_level = params:get("output_level")
        params:set("output_level", -math.huge)
    end
    for i = 1, 2 do if params.lookup[i .. "volume"] then params:set(i .. "volume", -70) end end
    _G.preset_loading = true
    cancel_loading_clock()
    loading_clock = clock.run(function()
        if params.lookup["unload_all"] then params:set("unload_all", 1); clock.sleep(0.1) end
        for _, k in ipairs(LFO_KEYS) do if params.lookup[k] then params:set(k, 1) end end
        local src = data.morph or data.scene_data
        if src then
            for track = 1, 2 do for scene = 1, 2 do
                scene_data[track][scene] = (src[track] and src[track][scene]) or {}
            end end
        end
        if data.morph_amount then
            morph_amount = data.morph_amount
            if params.lookup["morph_amount"] then params:set("morph_amount", data.morph_amount) end
        end
        if data.params then
            for i = 1, 2 do
                local sp = i .. "sample"
                if params.lookup[sp] and is_valid_sample(data.params[sp]) then
                    params:set(sp, data.params[sp])
                end
            end
        end
        for i = 1, 2 do
            local sp = i .. "sample"
            if params.lookup[sp] then audio_active[i] = is_valid_sample(params:get(sp)) end
        end
        update_pan()
        _G.preset_loading = false
        if data.params then apply_params_ordered(data.params) end
        for i = 1, 2 do
            for _, suffix in ipairs({"volume", "granular_gain"}) do
                local p = i .. suffix
                if params.lookup[p] then
                    local saved = data.params and data.params[p]
                    params:set(p, saved ~= nil and saved or params:get(p))
                end
            end
        end
        clock.sleep(0.1)
        if saved_output_level ~= nil and params.lookup["output_level"] then
            params:set("output_level", saved_output_level)
        end
        redraw()
        print("✓ Loaded: " .. name)
        loading_clock = nil
        if on_loaded then on_loaded(data.active_mode, data.active_filter_mode) end
    end)
    return true
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
    presets.menu_open      = false
    presets.confirmation   = nil
    presets.menu_mode      = "load"
    presets.k2_mode        = "delete"
    presets.preset_list    = {}
end

function presets.is_menu_open() return presets.menu_open end

local function available_numbers(current_name)
    local current_n = parse_preset_name(current_name)
    local used, max_n = {}, 0
    for _, name in ipairs(presets.preset_list) do
        local n = parse_preset_name(name)
        if n and n ~= current_n then used[n] = true; if n > max_n then max_n = n end end
    end
    local avail = {}
    for i = 1, max_n + 1 do if not used[i] then avail[#avail+1] = i end end
    return #avail > 0 and avail or {1}
end

local function commit_pending(conf)
    if not conf.pending_char then return end
    if conf.manual_cursor > #conf.manual_text then conf.manual_text = pad_text(conf.manual_text, conf.manual_cursor) end
    conf.manual_text  = str_set_char(conf.manual_text, conf.manual_cursor, conf.pending_char)
    conf.pending_char = nil
end

local function update_suggested(conf)
    local trimmed = conf.manual_text:match("^(.-)%s*$") or conf.manual_text
    conf.suggested_name = fmt_name(conf.suggested_number, trimmed)
end

local function start_commit_clock(conf)
    cancel_rename_clock()
    rename_clock = clock.run(function()
        clock.sleep(RENAME_COMMIT_DELAY)
        rename_clock = nil
        if presets.confirmation ~= conf or conf.rename_mode ~= "manual" then return end
        commit_pending(conf)
        local trimmed_len = #(conf.manual_text:match("^(.-)%s*$") or conf.manual_text)
        local max_cursor  = math.min(trimmed_len + 2, RENAME_MAX_LEN)
        if conf.manual_cursor < max_cursor then
            conf.manual_cursor = conf.manual_cursor + 1
            if conf.manual_cursor > #conf.manual_text then conf.manual_text = conf.manual_text .. " " end
            conf.manual_char_idx = char_to_charset_idx(conf.manual_text:sub(conf.manual_cursor, conf.manual_cursor))
        end
        update_suggested(conf)
        redraw()
    end)
end

local function open_rename(preset_name)
    local n, word = parse_preset_name(preset_name)
    n, word = n or 1, word or preset_name
    local avail, avail_idx = available_numbers(preset_name), 1
    for i, v in ipairs(avail) do if v == n then avail_idx = i; break end end
    return {
        type              = "rename",
        rename_mode       = "random",
        preset_name       = preset_name,
        suggested_number  = avail[avail_idx],
        suggested_word    = word,
        available_numbers = avail,
        avail_index       = avail_idx,
        suggested_name    = fmt_name(avail[avail_idx], word),
        manual_text       = word,
        manual_cursor     = 1,
        manual_char_idx   = char_to_charset_idx(word:sub(1, 1)),
        erase_acc         = 0,
        pending_char      = nil,
    }
end

local function swap_preset_numbers(idx_a, idx_b)
    local name_a, name_b = presets.preset_list[idx_a], presets.preset_list[idx_b]
    if not name_a or not name_b then return nil end
    local na, wa = parse_preset_name(name_a)
    local nb, wb = parse_preset_name(name_b)
    if not (na and nb and wa and wb) then return nil end
    local dir   = _path.data .. PRESETS_DIR .. "/"
    local new_a = fmt_name(nb, wa)
    os.rename(dir .. name_a .. ".lua", dir .. new_a .. ".lua")
    os.rename(dir .. name_b .. ".lua", dir .. fmt_name(na, wb) .. ".lua")
    return new_a
end

local function draw_rename_manual(conf)
    screen.clear()
    screen.level(15); screen.move(64,  9); screen.text_center("RENAME")
    screen.level(3);  screen.move(64, 17); screen.text_center("manual mode")
    local num_str = format_number(conf.suggested_number) .. " "
    local text    = conf.manual_cursor > #conf.manual_text and pad_text(conf.manual_text, conf.manual_cursor) or conf.manual_text
    local before  = text:sub(1, conf.manual_cursor - 1)
    local cur_ch  = conf.pending_char or text:sub(conf.manual_cursor, conf.manual_cursor)
    if cur_ch == "" then cur_ch = " " end
    local after   = text:sub(conf.manual_cursor + 1):match("^(.-)%s*$") or text:sub(conf.manual_cursor + 1)
    local pad        = 1
    local pipe_w     = screen.text_extents("|")
    local num_w      = screen.text_extents(num_str:match("^(.-)%s*$") or num_str)
    local before_w   = screen.text_extents(before .. "|") - pipe_w
    local cur_ch_w   = screen.text_extents(cur_ch)
    local rect_w     = math.max(cur_ch_w, 4) + pad * 2
    local full_name  = text:match("^(.-)%s*$") or text
    local name_w     = screen.text_extents(full_name)
    local total_w    = num_w + 4 + name_w + pad * 2
    local start_x    = math.floor(64 - total_w / 2)
    local before_x   = start_x + num_w + 4
    local cur_x      = before_x + before_w
    local y          = 30
    screen.level(4);  screen.move(start_x,     y); screen.text(num_str)
    screen.level(15); screen.move(before_x,    y); screen.text(before)
    screen.level(15); screen.rect(cur_x, y-6, rect_w, 8); screen.fill()
    screen.level(0);  screen.move(cur_x + pad, y); screen.text(cur_ch)
    screen.level(15); screen.move(cur_x + rect_w, y); screen.text(after)
    screen.level(2); screen.move(64, 44); screen.text_center("E1: del   E2: pos   E3: char")
    screen.level(3); screen.move(2,   64); screen.text("[K1]: Exit")
    screen.move(68,  64); screen.text_center("K2: Mode")
    screen.move(126, 64); screen.text_right("K3: OK")
    screen.update()
end

local function draw_rename_random(conf)
    screen.clear()
    screen.level(15); screen.move(64,  9); screen.text_center("RENAME")
    screen.level(3);  screen.move(64, 17); screen.text_center("random mode")
    screen.level(15); screen.move(64, 30); screen.text_center(conf.suggested_name)
    screen.level(2);  screen.move(64, 44); screen.text_center("E2: number   E3: name")
    screen.level(3);  screen.move(2,   64); screen.text("[K1]: Exit")
    screen.move(68, 64); screen.text_center("K2: Mode")
    screen.move(126, 64); screen.text_right("K3: OK")
    screen.update()
end

local function draw_confirm(title, name)
    screen.clear()
    screen.level(15); screen.move(64, 12); screen.text_center(title)
    screen.level(8);  screen.move(64, 26); screen.text_center(name or "Unknown Preset")
    screen.level(4);  screen.move(64, 64); screen.text_center("K2: Cancel   K3: Confirm")
    screen.update()
end

function presets.draw_menu()
    if not presets.menu_open then return false end
    local conf = presets.confirmation
    if conf then
        if conf.type == "rename" then
            if conf.rename_mode == "manual" then draw_rename_manual(conf)
            else draw_rename_random(conf) end
        elseif conf.type == "delete" then draw_confirm("DELETE PRESET?",    conf.preset_name)
        elseif conf.type == "save"   then draw_confirm("OVERWRITE PRESET?", conf.preset_name)
        end
        return true
    end
    screen.clear()
    screen.level(15); screen.move(64, 6); screen.text_center("PRESET BROWSER")
    local count     = math.min(5, #presets.preset_list)
    local start_idx = math.max(1, math.min(presets.selected_index - 2, #presets.preset_list - count + 1))
    for i = 1, count do
        local idx = start_idx + i - 1
        if idx <= #presets.preset_list then
            local sel  = idx == presets.selected_index
            local y    = 11 + (i * 8)
            local name = presets.preset_list[idx]:gsub("twins_", "")
            local n, word = name:match("^(%d+) (.+)$")
            screen.level(sel and 15 or 1)
            screen.move(2, y)
            screen.text(sel and (presets.k2_mode == "move" and "▶" or ">") or "")
            if n then
                screen.move(18, y); screen.level(sel and 15 or 1); screen.text_right(n)
                screen.move(22, y); screen.level(sel and 15 or 4); screen.text(word)
            else
                screen.move(22, y); screen.text(name)
            end
        end
    end
    if #presets.preset_list > count then
        screen.level(2)
        if start_idx > 1                               then screen.move(122, 19); screen.text("↑") end
        if start_idx + count - 1 < #presets.preset_list then screen.move(122, 51); screen.text("↓") end
    end
    local bright = { load=1, save=15, rename=8 }
    local labels  = { load="Load", rename="Edit", save="Save" }
    screen.level(1); screen.move(2,  64); screen.text("[K1]: Exit")
    screen.level(1); screen.move(50, 64); screen.text("K2: Del")
    screen.level(bright[presets.menu_mode] or 1)
    screen.move(91, 64); screen.text("K3: " .. (labels[presets.menu_mode] or "Load"))
    screen.update()
    return true
end

function presets.menu_enc(n, d)
    if not presets.menu_open then return end
    local conf = presets.confirmation
    if conf and conf.type == "rename" then
        if conf.rename_mode == "manual" then

            if n == 1 then
                conf.erase_acc = (conf.erase_acc or 0) + math.abs(d)
                if conf.erase_acc < 3 then return end
                conf.erase_acc = 0; conf.pending_char = nil; cancel_rename_clock()
                local t = conf.manual_text
                if d < 0 then
                    if conf.manual_cursor > 1 then
                        conf.manual_text   = t:sub(1, conf.manual_cursor-2) .. t:sub(conf.manual_cursor)
                        conf.manual_cursor = conf.manual_cursor - 1
                    end
                else
                    if conf.manual_cursor <= #t then
                        conf.manual_text = t:sub(1, conf.manual_cursor-1) .. t:sub(conf.manual_cursor+1)
                        if #conf.manual_text == 0 then
                            conf.manual_cursor = 1
                        else
                            conf.manual_cursor = math.min(conf.manual_cursor, #conf.manual_text)
                        end
                    end
                end
                conf.manual_char_idx = char_to_charset_idx(conf.manual_text:sub(conf.manual_cursor, conf.manual_cursor))
                update_suggested(conf); redraw()
            elseif n == 2 then
                cancel_rename_clock(); commit_pending(conf)
                local trimmed_len = #(conf.manual_text:match("^(.-)%s*$") or conf.manual_text)
                local new_cursor  = util.clamp(conf.manual_cursor + d, 1, math.min(trimmed_len + 2, RENAME_MAX_LEN))
                if new_cursor ~= conf.manual_cursor then
                    if new_cursor > #conf.manual_text then conf.manual_text = conf.manual_text .. string.rep(" ", new_cursor - #conf.manual_text) end
                    conf.manual_cursor   = new_cursor
                    conf.manual_char_idx = char_to_charset_idx(conf.manual_text:sub(conf.manual_cursor, conf.manual_cursor))
                    update_suggested(conf)
                    if conf.manual_text:sub(conf.manual_cursor, conf.manual_cursor) == " " then conf.pending_char = " "; start_commit_clock(conf) end
                    redraw()
                end
            elseif n == 3 then
                local trimmed_len = #(conf.manual_text:match("^(.-)%s*$") or conf.manual_text)
                local is_new  = conf.manual_cursor > trimmed_len
                local prev_ch = conf.manual_cursor > 1 and conf.manual_text:sub(conf.manual_cursor-1, conf.manual_cursor-1) or ""
                local step    = d > 0 and 1 or -1
                local new_idx, tries = conf.manual_char_idx, 0
                repeat
                    new_idx = util.clamp(new_idx + step, 1, RENAME_CHARSET_LEN)
                    tries   = tries + 1
                    local c = RENAME_CHARSET:sub(new_idx, new_idx)
                    if not (c == " " and (conf.manual_cursor == 1 or prev_ch == " ")) then break end
                until tries > RENAME_CHARSET_LEN or new_idx <= 1 or new_idx >= RENAME_CHARSET_LEN
                conf.manual_char_idx = new_idx
                local new_char = auto_case(RENAME_CHARSET:sub(new_idx, new_idx), conf.manual_text, conf.manual_cursor)
                if is_new then
                    conf.pending_char = new_char; start_commit_clock(conf)
                else
                    cancel_rename_clock(); conf.pending_char = nil
                    if conf.manual_cursor > #conf.manual_text then conf.manual_text = pad_text(conf.manual_text, conf.manual_cursor) end
                    conf.manual_text = str_set_char(conf.manual_text, conf.manual_cursor, new_char)
                    update_suggested(conf)
                end
                redraw()
            end
        else
            if n == 2 then
                conf.avail_index      = util.clamp(conf.avail_index + d, 1, #conf.available_numbers)
                conf.suggested_number = conf.available_numbers[conf.avail_index]
                conf.suggested_name   = fmt_name(conf.suggested_number, conf.suggested_word)
                redraw()
            elseif n == 3 then
                conf.suggested_word = NameSizer.rnd(" ")
                conf.suggested_name = fmt_name(conf.suggested_number, conf.suggested_word)
                redraw()
            end
        end
        return
    end
    if n == 1 then
        presets.k2_mode = d > 0 and "move" or "delete"
    elseif n == 2 then
        if presets.k2_mode == "move" then
            local neighbor = presets.selected_index + (d > 0 and 1 or -1)
            if neighbor >= 1 and neighbor <= #presets.preset_list then
                local moved = swap_preset_numbers(presets.selected_index, neighbor)
                presets.preset_list = presets.list_presets()
                if moved then
                    for i, name in ipairs(presets.preset_list) do
                        if name == moved then presets.selected_index = i; break end
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

function presets.menu_key(n, z, scene_data, update_pan, audio_active, active_mode, active_filter_mode, on_loaded)
    if not presets.menu_open or z ~= 1 then return false end
    local conf = presets.confirmation
    if conf then
        if n == 1 then cancel_rename_clock(); presets.close_menu(); return true end
        if n == 2 then
            if conf.type == "rename" then
                cancel_rename_clock()
                if conf.rename_mode == "random" then
                    local _, word = parse_preset_name(conf.preset_name)
                    word = word or conf.preset_name
                    conf.rename_mode     = "manual"
                    conf.manual_text     = word
                    conf.manual_cursor   = 1
                    conf.manual_char_idx = char_to_charset_idx(word:sub(1, 1))
                    conf.erase_acc       = 0
                    conf.pending_char    = nil
                else
                    conf.rename_mode    = "random"
                    local trimmed       = conf.manual_text:match("^(.-)%s*$") or conf.manual_text
                    conf.suggested_word = trimmed
                    conf.suggested_name = fmt_name(conf.suggested_number, trimmed)
                end
                redraw()
            else
                presets.confirmation = nil
            end
            return true
        end
        if n == 3 then
            if conf.type == "delete" then
                presets.delete_preset(conf.preset_name)
                presets.preset_list  = presets.list_presets()
                presets.confirmation = nil
                if #presets.preset_list == 0 then
                    presets.menu_open = false
                else
                    presets.selected_index = util.clamp(conf.preset_index, 1, #presets.preset_list)
                end
            elseif conf.type == "save" then
                local path  = _path.data .. PRESETS_DIR .. "/" .. conf.preset_name .. ".lua"
                local mtime = get_mtime(path)
                presets.save_complete_preset(conf.preset_name, scene_data, active_mode, active_filter_mode)
                if mtime > 0 then os.execute('touch -m -d @' .. mtime .. ' "' .. path .. '"') end
                presets.confirmation = nil
                presets.menu_open    = false
            elseif conf.type == "rename" then
                cancel_rename_clock()
                local new_name = (conf.suggested_name or conf.preset_name):match("^(.-)%s*$") or conf.preset_name
                if new_name ~= conf.preset_name then
                    local dir = _path.data .. PRESETS_DIR .. "/"
                    os.rename(dir .. conf.preset_name .. ".lua", dir .. new_name .. ".lua")
                end
                presets.confirmation   = nil
                presets.menu_mode      = "load"
                presets.preset_list    = presets.list_presets()
                presets.selected_index = 1
                for i, name in ipairs(presets.preset_list) do
                    if name == new_name then presets.selected_index = i; break end
                end
            end
            return true
        end
        return true
    end
    local name = presets.preset_list[presets.selected_index]
    if n == 3 then
        if presets.menu_mode == "load" then
            presets.load_complete_preset(name, scene_data, update_pan, audio_active, on_loaded)
            presets.menu_open = false
        elseif presets.menu_mode == "save" then
            presets.confirmation = { type = "save", preset_name = name }
        else
            presets.confirmation = open_rename(name)
        end
        return true
    elseif n == 2 then
        presets.confirmation = { type = "delete", preset_name = name, preset_index = presets.selected_index }
        return true
    elseif n == 1 then
        presets.close_menu(); return true
    end
    return false
end

return presets