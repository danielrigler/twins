local presets = {}
local NameSizer = include("lib/preset_names")

presets.menu_open = false
presets.menu_mode = "load"
presets.selected_index = 1
presets.preset_list = {}
presets.confirmation = nil

_G.preset_loading = false
local buffer_loading = {pending = {}, complete = {}}
local loading_clock = nil
local PRESETS_DIR = "twins"
local BUFFER_TIMEOUT = 15
local PRESET_VERSION = 1
local _LFO_KEYS = {}
for _i = 1, 16 do _LFO_KEYS[_i] = _i .. "lfo" end

local function is_valid_sample_path(p)
    if not p then return false end
    if p == "-" or p == "" or p == "none" then return false end
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
        if util.time() - start_time > timeout then
            print("⚠ Buffer loading timeout")
            return false
        end
        clock.sleep(0.1)
    end
    return true
end

local function table_to_string(tbl, indent)
    indent = indent or ""
    local items = {}
    for k, v in pairs(tbl) do
        local key_str = type(k) == "string" and string.format("%q", k) or tostring(k)
        local value_str
        if type(v) == "table" then
            value_str = table_to_string(v, indent .. "  ")
        elseif type(v) == "string" then
            value_str = string.format("%q", v)
        else
            value_str = tostring(v)
        end
        items[#items + 1] = string.format("%s  [%s] = %s", indent, key_str, value_str)
    end
    return string.format("{\n%s\n%s}", table.concat(items, ",\n"), indent)
end

local function get_all_params_state()
    local state = {}
    for _, param in pairs(params.params) do
        if param.id then
            state[param.id] = params:get(param.id)
        end
    end
    return state
end

local function get_file_mtime(path)
    local f = io.popen('stat -c "%Y" "' .. path .. '" 2>/dev/null')
    if not f then return 0 end
    local result = f:read("*n")
    f:close()
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

local function format_preset_number(n)
    if n >= 100 then
        return tostring(n)
    else
        return string.format("%02d", n)
    end
end

local function parse_preset_name(name)
    local n, word = name:match("^(%d+) (.+)$")
    return tonumber(n), word
end

local function build_available_numbers(current_preset_name)
    local current_n = parse_preset_name(current_preset_name)
    local used = {}
    local max_n = 0
    local dir = _path.data .. PRESETS_DIR
    local f = io.popen('ls "' .. dir .. '"/*.lua 2>/dev/null')
    if f then
        for line in f:lines() do
            local n = tonumber(line:match("/(%d+) "))
            if n and n ~= current_n then
                used[n] = true
                if n > max_n then max_n = n end
            end
        end
        f:close()
    end
    local available = {}
    for i = 1, max_n + 1 do
        if not used[i] then
            available[#available + 1] = i
        end
    end
    if #available == 0 then available[1] = 1 end
    return available
end

local function generate_preset_name(preset_name)
    if preset_name and preset_name ~= "" then
        return preset_name
    end
    local n = next_preset_number()
    local word = NameSizer.rnd(" ")
    return format_preset_number(n) .. " " .. word
end

function presets.save_complete_preset(preset_name, scene_data_ref, update_pan_positioning_fn, audio_active_ref)
    local success, err = pcall(function()
        preset_name = generate_preset_name(preset_name)
        local preset_data = {
            name = preset_name,
            timestamp = os.time(),
            version = PRESET_VERSION,
            params = get_all_params_state(),
            morph = {
                [1] = { scene_data_ref[1][1] or {}, scene_data_ref[1][2] or {} },
                [2] = { scene_data_ref[2][1] or {}, scene_data_ref[2][2] or {} }
            },
            morph_amount = params:get("morph_amount") or 0
        }
        util.make_dir(_path.data .. PRESETS_DIR)
        local file_path = _path.data .. PRESETS_DIR .. "/" .. preset_name .. ".lua"
        local file = io.open(file_path, "w")
        if not file then
            error("Could not open file for writing")
        end
        local header = string.format(
            "-- Twins Preset\n-- Name: %s\n-- Saved: %s\n-- Version: %d\n\nreturn ",
            preset_name, os.date("%Y-%m-%d %H:%M:%S"), PRESET_VERSION
        )
        file:write(header .. table_to_string(preset_data))
        file:close()
        print("✓ Preset saved: " .. preset_name)
    end)
    if not success then
        print("✗ Error saving preset: " .. (err or "unknown"))
    end
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
    { fn = function(id) return id:match("^%d+lock$")                               end, bucket = 1 },
    { fn = function(id) return id:match("sample_start$") or id:match("sample_end$") end, bucket = 2 },
    { fn = function(id) return id:match("volume$")                                  end, bucket = 3 },
    { fn = function(id) return id == "allow_volume_lfos"                            end, bucket = 4 },
    { fn = function(id) return id:match("^%d+lfo$")                                end, bucket = 5 },
    { fn = function(id) return not id:match("sample$")                             end, bucket = 6 },
}

local function categorize_params(preset_params)
    local buckets = { {}, {}, {}, {}, {}, {} }
    for param_id, value in pairs(preset_params) do
        if params.lookup[param_id] then
            for _, m in ipairs(_PARAM_MATCHERS) do
                if m.fn(param_id) then
                    buckets[m.bucket][#buckets[m.bucket] + 1] = { id = param_id, value = value }
                    break
                end
            end
        end
    end
    return buckets[1], buckets[2], buckets[3], buckets[5], buckets[4], buckets[6]
end

local function apply_params(lock_params, audio_params, volume_params, lfo_enable_params, allow_volume_lfo_params, other_params)
    for _, p in ipairs(lock_params)             do params:set(p.id, p.value) end
    clock.sleep(0.02)
    for _, p in ipairs(audio_params)            do params:set(p.id, p.value) end
    clock.sleep(0.03)
    for _, p in ipairs(volume_params)           do params:set(p.id, p.value) end
    clock.sleep(0.03)
    for _, p in ipairs(allow_volume_lfo_params) do params:set(p.id, p.value) end
    clock.sleep(0.03)
    for _, p in ipairs(other_params)            do params:set(p.id, p.value) end
    clock.sleep(0.03)
    for _, p in ipairs(lfo_enable_params)       do params:set(p.id, p.value) end
end

local function refresh_voice_params()
    for i = 1, 2 do
        local vol_param = i .. "volume"
        if params.lookup[vol_param] then params:set(vol_param, params:get(vol_param)) end
        local gain_param = i .. "granular_gain"
        if params.lookup[gain_param] then params:set(gain_param, params:get(gain_param)) end
    end
end

function presets.load_complete_preset(preset_name, scene_data_ref, update_pan_positioning_fn, audio_active_ref)
    local file_path = _path.data .. PRESETS_DIR .. "/" .. preset_name .. ".lua"
    if not util.file_exists(file_path) then
        print("✗ Preset file not found: " .. preset_name)
        return false
    end
    local chunk, err = loadfile(file_path)
    if not chunk then
        print("✗ Error loading preset: " .. (err or "unknown"))
        return false
    end
    local success, preset_data = pcall(chunk)
    if not success or not preset_data then
        print("✗ Error parsing preset: " .. (preset_data or "unknown"))
        return false
    end
    if preset_data.version and preset_data.version > PRESET_VERSION then
        print("⚠ Preset saved with newer version")
    end
    for i = 1, 2 do
        local vol_param = i .. "volume"
        if params.lookup[vol_param] then
            params:set(vol_param, -70)
        end
    end
    _G.preset_loading = true
    cancel_loading_clock()
    loading_clock = clock.run(function()
        if params.lookup["unload_all"] then
            params:set("unload_all", 1)
            clock.sleep(0.05)
        end
        for i = 1, 16 do
            if params.lookup[_LFO_KEYS[i]] then
                params:set(_LFO_KEYS[i], 1)
            end
        end
        apply_scene_data(preset_data, scene_data_ref)
        if preset_data.morph_amount then
            morph_amount = preset_data.morph_amount
            if params.lookup["morph_amount"] then
                params:set("morph_amount", preset_data.morph_amount)
            end
        end
        buffer_loading.pending = {}
        buffer_loading.complete = {}
        local sample_count = 0
        for i = 1, 2 do
            local sample_param = i .. "sample"
            if params.lookup[sample_param] and preset_data.params and preset_data.params[sample_param] then
                if is_valid_sample_path(preset_data.params[sample_param]) then
                    buffer_loading.pending[i] = true
                    buffer_loading.complete[i] = false
                    sample_count = sample_count + 1
                end
            end
        end
        if preset_data.params and sample_count > 0 then
            print("⏳ Loading " .. sample_count .. " sample" .. (sample_count > 1 and "s" or "") .. "...")
            for param_id, value in pairs(preset_data.params) do
                if param_id:match("sample$") and params.lookup[param_id] then
                    params:set(param_id, value)
                end
            end
        end
        clock.sleep(0.05)
        if sample_count > 0 then
            local ok = wait_for_buffers(BUFFER_TIMEOUT)
            print(ok and "✓ All buffers loaded" or "⚠ Timeout - some samples may not be ready")
        end
        for i = 1, 2 do
            local sample_param = i .. "sample"
            if params.lookup[sample_param] then
                audio_active_ref[i] = is_valid_sample_path(params:get(sample_param))
            end
        end
        _G.preset_loading = false
        if preset_data.params then
            local lock_params, audio_params, volume_params, lfo_enable_params, allow_volume_lfo_params, other_params = categorize_params(preset_data.params)
            apply_params(lock_params, audio_params, volume_params, lfo_enable_params, allow_volume_lfo_params, other_params)
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
    local presets_list = {}
    local dir = _path.data .. PRESETS_DIR
    util.make_dir(dir)
    local success, entries = pcall(util.scandir, dir)
    if not (success and entries) then return presets_list end
    for _, entry in ipairs(entries) do
        if type(entry) == "string" and entry:match("%.lua$") then
            presets_list[#presets_list + 1] = entry:gsub("%.lua$", "")
        end
    end
    local mtimes = get_all_mtimes(dir)
    table.sort(presets_list, function(a, b)
        local na = parse_preset_name(a)
        local nb = parse_preset_name(b)
        na = na or 0
        nb = nb or 0
        if na ~= nb then return na > nb end
        return (mtimes[a] or 0) > (mtimes[b] or 0)
    end)
    return presets_list
end

function presets.delete_preset(preset_name)
    local file_path = _path.data .. PRESETS_DIR .. "/" .. preset_name .. ".lua"
    if not util.file_exists(file_path) then
        print("✗ Preset not found: " .. preset_name)
        return false
    end
    local success, err = pcall(os.remove, file_path)
    if success then
        print("✓ Preset deleted: " .. preset_name)
        return true
    else
        print("✗ Error deleting preset: " .. (err or "unknown"))
        return false
    end
end

function presets.open_menu()
    local list = presets.list_presets()
    if #list == 0 then
        print("No presets found")
        return false
    end
    presets.preset_list = list
    presets.selected_index = util.clamp(presets.selected_index, 1, #list)
    presets.menu_open = true
    presets.menu_mode = "load"
    return true
end

function presets.close_menu()
    presets.menu_open = false
    presets.confirmation = nil
    presets.menu_mode = "load"
    presets.preset_list = {}
end

local MENU_MODES = {"load", "rename", "save"}
local _MODE_INDEX = {}
for i, m in ipairs(MENU_MODES) do _MODE_INDEX[m] = i end

local function cycle_mode(current, delta)
    local i = _MODE_INDEX[current]
    if not i then return "load" end
    return MENU_MODES[math.max(1, math.min(#MENU_MODES, i + delta))]
end

function presets.menu_enc(n, d)
    if not presets.menu_open then return end
    if presets.confirmation and presets.confirmation.type == "rename" then
        local conf = presets.confirmation
        if n == 2 then
            conf.avail_index = util.clamp(conf.avail_index + d, 1, #conf.available_numbers)
            conf.suggested_number = conf.available_numbers[conf.avail_index]
            conf.suggested_name = format_preset_number(conf.suggested_number) .. " " .. conf.suggested_word
            redraw()
        elseif n == 3 then
            conf.suggested_word = NameSizer.rnd(" ")
            conf.suggested_name = format_preset_number(conf.suggested_number) .. " " .. conf.suggested_word
            redraw()
        end
        return
    end
    if n == 2 then
        presets.selected_index = util.clamp(presets.selected_index + d, 1, #presets.preset_list)
    elseif n == 1 or n == 3 then
        presets.menu_mode = cycle_mode(presets.menu_mode, d > 0 and 1 or -1)
    end
    redraw()
end

function presets.menu_key(n, z, scene_data_ref, update_pan_positioning_fn, audio_active_ref)
    if not presets.menu_open or z ~= 1 then return false end
    if presets.confirmation then
        if n == 3 then
            if presets.confirmation.type == "delete" then
                local preset_name = presets.confirmation.preset_name
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
                local new_name = presets.confirmation.suggested_name or presets.confirmation.preset_name
                if new_name ~= presets.confirmation.preset_name then
                    local old_path = _path.data .. PRESETS_DIR .. "/" .. presets.confirmation.preset_name .. ".lua"
                    local new_path = _path.data .. PRESETS_DIR .. "/" .. new_name .. ".lua"
                    os.rename(old_path, new_path)
                end
                presets.confirmation = nil
                presets.menu_open = false
            end
        else
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
            presets.confirmation = {
                type = "save",
                preset_name = preset_name
            }
            return true
        else
            local current_n, current_word = parse_preset_name(preset_name)
            current_n    = current_n    or 1
            current_word = current_word or preset_name
            local avail  = build_available_numbers(preset_name)
            local avail_index = 1
            for i, v in ipairs(avail) do
                if v == current_n then avail_index = i; break end
            end
            local suggested_number = avail[avail_index]
            presets.confirmation = {
                type             = "rename",
                preset_name      = preset_name,
                suggested_number = suggested_number,
                suggested_word   = current_word,
                available_numbers = avail,
                avail_index      = avail_index,
                suggested_name   = format_preset_number(suggested_number) .. " " .. current_word
            }
            return true
        end
    elseif n == 2 then
        presets.confirmation = {
            type = "delete",
            preset_name = preset_name,
            preset_index = presets.selected_index
        }
        return true
    elseif n == 1 then
        presets.close_menu()
        return true
    end
    return false
end

local function draw_confirmation(title, preset_name, suggested_name)
    screen.clear()
    screen.level(15)
    screen.move(64, 12)
    screen.text_center(title)
    if suggested_name then
        screen.level(4)
        screen.move(64, 24)
        screen.text_center("renaming to:")
        screen.level(15)
        screen.move(64, 34)
        screen.text_center(suggested_name)
        screen.level(2)
        screen.move(64, 44)
        screen.text_center("E2: number   E3: name")
    else
        screen.level(8)
        screen.move(64, 26)
        screen.text_center(preset_name or "Unknown Preset")
    end
    screen.level(4)
    screen.move(64, 55)
    screen.text_center("K1/K2: Cancel   K3: Confirm")
    screen.update()
end

function presets.draw_menu()
    if not presets.menu_open then return false end
    if presets.confirmation then
        local title
        if presets.confirmation.type == "delete" then title = "DELETE PRESET?"
        elseif presets.confirmation.type == "save" then title = "OVERWRITE PRESET?"
        else title = "RENAME PRESET" end
        draw_confirmation(title, presets.confirmation.preset_name, presets.confirmation.suggested_name)
        return true
    end
    screen.clear()
    screen.level(15)
    screen.move(64, 6)
    screen.text_center("PRESET BROWSER")
    local visible_count = math.min(5, #presets.preset_list)
    local start_index = math.max(1, math.min(presets.selected_index - 2, #presets.preset_list - visible_count + 1))
    for i = 1, visible_count do
        local idx = start_index + i - 1
        if idx <= #presets.preset_list then
            local is_selected = idx == presets.selected_index
            screen.level(is_selected and 15 or 1)
            local y = 11 + (i * 8)
            local name = presets.preset_list[idx]:gsub("twins_", "")
            local n, word = name:match("^(%d+) (.+)$")
            screen.move(2, y)
            screen.text(is_selected and ">" or "")
            if n then
                screen.move(18, y)
                screen.level(is_selected and 15 or 1)
                screen.text_right(n)
                screen.move(22, y)
                screen.level(is_selected and 15 or 4)
                screen.text(word)
            else
                screen.move(22, y)
                screen.text(name)
            end
        end
    end
    if #presets.preset_list > visible_count then
        screen.level(2)
        if start_index > 1 then
            screen.move(122, 19)
            screen.text("↑")
        end
        if start_index + visible_count - 1 < #presets.preset_list then
            screen.move(122, 51)
            screen.text("↓")
        end
    end
    screen.level(1)
    screen.move(2, 64)
    screen.text("K1: Back")
    screen.move(50, 64)
    screen.text("K2: Del")
    local mode_labels = {load = "Load", rename = "Name", save = "Save"}
    local mode_bright = {load = 1, save = 15, rename = 8}
    screen.level(mode_bright[presets.menu_mode] or 1)
    screen.move(91, 64)
    screen.text("K3: " .. (mode_labels[presets.menu_mode] or "Load"))
    screen.update()
    return true
end

function presets.is_menu_open()
    return presets.menu_open
end

function presets.cleanup()
    cancel_loading_clock()
    _G.preset_loading = false
end

return presets