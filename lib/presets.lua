local presets = {}

presets.menu_open = false
presets.preset_list = {}
presets.selected_index = 1
presets.delete_confirmation = nil

local function table_to_string(tbl, indent)
    indent = indent or ""
    local result = "{\n"
    for k, v in pairs(tbl) do
        result = result .. indent .. "  [" .. (type(k) == "string" and "\"" .. k .. "\"" or k) .. "] = "
        if type(v) == "table" then
            result = result .. table_to_string(v, indent .. "  ") .. ",\n"
        elseif type(v) == "string" then
            result = result .. "\"" .. v:gsub("\\", "\\\\"):gsub("\"", "\\\"") .. "\",\n"
        elseif type(v) == "number" or type(v) == "boolean" then
            result = result .. tostring(v) .. ",\n"
        end
    end
    result = result .. indent .. "}"
    return result
end

local function string_to_table(str)
    local chunk = load("return " .. str)
    if chunk then return chunk() end
    return nil
end

local function get_all_params_state()
    local state = {}
    for param_id, param in pairs(params.params) do
        if param.id then
            state[param.id] = params:get(param.id)
        end
    end
    return state
end

local function restore_all_params(state)
    for param_id, value in pairs(state) do
        if params.lookup[param_id] then
            params:set(param_id, value, true)
        end
    end
end

function presets.save_complete_preset(preset_name, scene_data_ref, current_scene_mode_ref, initialize_scenes_fn)
    local function get_next_preset_number_for_time(time_prefix)
        local existing_presets = presets.list_presets()
        local highest_num = 0
        for _, preset in ipairs(existing_presets) do
            local preset_time, num = preset:match("^twins_(" .. time_prefix .. ")_(%d+)$")
            if preset_time and num then
                local num_val = tonumber(num)
                if num_val and num_val > highest_num then
                    highest_num = num_val
                end
            end
        end
        return highest_num + 1
    end
    if not preset_name or preset_name:match("^%d%d%d%d%d%d%d%d_%d%d%d%d%d%d$") then
        local time_prefix = os.date("%Y%m%d_%H%M")
        local next_num = get_next_preset_number_for_time(time_prefix)
        preset_name = string.format("twins_%s_%03d", time_prefix, next_num)
    else
        if not preset_name:match("^twins_") then
            preset_name = "twins_" .. preset_name
        end
    end
    local preset_data = {
        name = preset_name,
        timestamp = os.time(),
        version = 1,
        params = get_all_params_state(),
        morph = {} }
    for track = 1, 2 do
        preset_data.morph[track] = {}
        for scene = 1, 2 do
            preset_data.morph[track][scene] = scene_data_ref[track][scene] or {}
        end
    end
    util.make_dir(_path.data .. "twins")
    local file_path = _path.data .. "twins/" .. preset_name .. ".lua"
    local file = io.open(file_path, "w")
    if file then
        file:write("-- Twins Complete Preset\n")
        file:write("-- Name: " .. preset_name .. "\n")
        file:write("-- Saved: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
        file:write("-- Version: 1\n\n")
        file:write("return " .. table_to_string(preset_data))
        file:close()
        print("Preset saved: " .. preset_name)
        return true
    else
        print("Error: Could not save preset")
        return false
    end
end

function presets.load_complete_preset(preset_name, scene_data_ref, update_pan_positioning_fn, audio_active_ref)
    local file_path = _path.data .. "twins/" .. preset_name .. ".lua"
    if not util.file_exists(file_path) then print("Preset file not found: " .. preset_name) return false end
    local file = io.open(file_path, "r")
    if file then
        local content = file:read("*a")
        file:close()
        local return_start = content:find("return%s*{")
        if return_start then
            content = content:sub(return_start + 6)
        end
        local preset_data = string_to_table(content)
        if preset_data then
            if preset_data.params and preset_data.params.scene_mode then
                params:set("scene_mode", preset_data.params.scene_mode)
            end
            clock.run(function()
                clock.sleep(0.05)
                if preset_data.params then
                    local params_to_restore = {}
                    for param_id, value in pairs(preset_data.params) do
                        if param_id ~= "scene_mode" then
                            params_to_restore[param_id] = value
                        end
                    end
                    restore_all_params(params_to_restore)
                end
                if preset_data.morph then
                    for track = 1, 2 do
                        for scene = 1, 2 do
                            scene_data_ref[track][scene] = (preset_data.morph[track] and preset_data.morph[track][scene]) or {}
                        end
                    end
                end
                clock.sleep(0.05)
                for i = 1, 2 do
                    local sample_path = params:get(i .. "sample")
                    if sample_path and sample_path ~= "-" and sample_path ~= "" and sample_path ~= "none" then
                        engine.read(i, sample_path)
                        audio_active_ref[i] = true
                    end
                end
                update_pan_positioning_fn()
                if preset_data.params and preset_data.params.morph_amount then
                    local saved_morph = preset_data.params.morph_amount
                    local temp_morph = (saved_morph == 0) and 1 or 0
                    params:set("morph_amount", temp_morph)
                    clock.sleep(0.05)
                    params:set("morph_amount", saved_morph)
                end
                clock.sleep(0.05)
                redraw()
            end)
            print("Preset loaded: " .. preset_name)
            return true
        else
            print("Error: Could not parse preset")
            print("Debug: Content starts with: " .. content:sub(1, 100))
            return false
        end
    else
        print("Error: Could not read preset file")
        return false
    end
end

function presets.list_presets()
    local presets_list = {}
    local dir = _path.data .. "twins"
    util.make_dir(dir)
    local success, entries = pcall(function() return util.scandir(dir) end)
    if success and entries then
        local count = 0
        for _, entry in ipairs(entries) do
            if type(entry) == "string" and entry:match("%.lua$") and not entry:match("/$") then
                count = count + 1
                presets_list[count] = entry:gsub("%.lua$", "")
            end
        end
    end
    table.sort(presets_list, function(a, b)
        local date_a, time_a, num_a = a:match("^twins_(%d%d%d%d%d%d%d%d)_(%d%d%d%d)_(%d+)$")
        local date_b, time_b, num_b = b:match("^twins_(%d%d%d%d%d%d%d%d)_(%d%d%d%d)_(%d+)$")
        if date_a and date_b then
            if date_a ~= date_b then
                return date_a > date_b
            else
                if time_a ~= time_b then
                    return time_a > time_b
                else
                    return tonumber(num_a) > tonumber(num_b)
                end
            end
        elseif date_a then
            return true 
        elseif date_b then
            return false
        else
            return a > b
        end
    end)
    return presets_list
end

function presets.delete_preset(preset_name)
    local file_path = _path.data .. "twins/" .. preset_name .. ".lua"
    if util.file_exists(file_path) then
        os.remove(file_path)
        print("Preset deleted: " .. preset_name)
        return true
    else
        print("Preset not found: " .. preset_name)
        return false
    end
end

-- Menu functions
function presets.open_menu()
    presets.preset_list = presets.list_presets()
    if #presets.preset_list == 0 then
        print("No presets found")
        return false
    end
    presets.selected_index = 1
    presets.menu_open = true
    return true
end

function presets.close_menu()
    presets.menu_open = false
end

function presets.menu_enc(n, d)
    if not presets.menu_open then return end
    if n == 2 then
        presets.selected_index = util.clamp(presets.selected_index + d, 1, #presets.preset_list)
    elseif n == 3 then
        presets.selected_index = util.clamp(presets.selected_index + (d * 4), 1, #presets.preset_list)
    end
end

function presets.menu_key(n, z, scene_data_ref, update_pan_positioning_fn, audio_active_ref)
    if not presets.menu_open then return false end
    if presets.delete_confirmation and presets.delete_confirmation.active then
        if n == 3 and z == 1 then
            local preset_name = presets.delete_confirmation.preset_name
            local preset_index = presets.delete_confirmation.preset_index or 1
            presets.delete_preset(preset_name)
            presets.preset_list = presets.list_presets()
            presets.delete_confirmation = nil
            if #presets.preset_list == 0 then
                presets.menu_open = false
            else
                presets.selected_index = util.clamp(preset_index, 1, #presets.preset_list)
            end
            return true
        elseif (n == 2 or n == 1) and z == 1 then
            presets.delete_confirmation = nil
            return true
        end
        return false
    end
    if n == 3 and z == 1 then
        local preset_name = presets.preset_list[presets.selected_index]
        local success = presets.load_complete_preset(preset_name, scene_data_ref, update_pan_positioning_fn, audio_active_ref)
        presets.menu_open = false
        return success
    elseif n == 2 and z == 1 then
        if #presets.preset_list > 0 and presets.preset_list[presets.selected_index] then
            local preset_name = presets.preset_list[presets.selected_index]
            presets.delete_confirmation = {
                active = true,
                preset_name = preset_name,
                preset_index = presets.selected_index
            }
        end
        return true
    elseif n == 1 and z == 1 then
        presets.menu_open = false
        return true
    end
    return false
end

function presets.draw_menu()
    if not presets.menu_open then return false end
    if presets.delete_confirmation and presets.delete_confirmation.active then
        screen.clear()
        screen.level(15)
        screen.move(64, 20)
        screen.text_center("DELETE PRESET?")
        screen.level(8)
        screen.move(64, 30)
        if presets.delete_confirmation.preset_name then
            screen.text_center(presets.delete_confirmation.preset_name)
        else
            screen.text_center("Unknown Preset")
        end
        screen.level(4)
        screen.move(64, 45)
        screen.text_center("K2/K1: Cancel")
        
        screen.level(15)
        screen.move(64, 55)
        screen.text_center("K3: Confirm")
        screen.update()
        return true
    end
    screen.clear()
    screen.level(15)
    screen.move(64, 10)
    screen.text_center("SELECT PRESET")
    local visible_count = math.min(4, #presets.preset_list)
    local start_index = math.max(1, math.min(presets.selected_index - 2, #presets.preset_list - visible_count + 1))
    start_index = math.max(1, start_index)
    
    for i = 1, visible_count do
        local idx = start_index + i - 1
        if idx <= #presets.preset_list then
            local y_pos = 15 + (i * 8)
            screen.level(idx == presets.selected_index and 15 or 4)
            screen.move(2, y_pos)
            if idx == presets.selected_index then
                screen.text("> " .. presets.preset_list[idx])
            else
                screen.text("  " .. presets.preset_list[idx])
            end
        end
    end
    if #presets.preset_list > 5 then
        screen.level(2)
        if start_index > 1 then
            screen.move(122, 23)
            screen.text("↑")
        end
        if start_index + visible_count - 1 < #presets.preset_list then
            screen.move(122, 47)
            screen.text("↓")
        end
    end
    screen.level(1)
    screen.move(2, 58)
    screen.text("K1: Back")
    screen.move(50, 58)
    screen.text("K2: Del")
    screen.move(91, 58)
    screen.text("K3: Load")
    screen.update()
    return true
end

function presets.is_menu_open()
    return presets.menu_open
end

return presets