local presets = {}
local lfo = nil

function presets.set_lfo_reference(lfo_module)
    lfo = lfo_module
end

-- Optimized table serialization
local function table_to_string(tbl, indent)
    indent = indent or ""
    local result = {"{"}
    local items = {}
    
    for k, v in pairs(tbl) do
        local key_str = type(k) == "string" and ("%q"):format(k) or tostring(k)
        local value_str
        
        if type(v) == "table" then
            value_str = table_to_string(v, indent .. "  ")
        elseif type(v) == "string" then
            value_str = ("%q"):format(v:gsub("\\", "\\\\"):gsub("\"", "\\\""))
        else
            value_str = tostring(v)
        end
        
        items[#items + 1] = indent .. "  [" .. key_str .. "] = " .. value_str
    end
    
    result[#result + 1] = table.concat(items, ",\n")
    result[#result + 1] = indent .. "}"
    
    return table.concat(result, "\n")
end

local function string_to_table(str)
    local chunk = load("return " .. str)
    return chunk and chunk() or nil
end

local function get_all_params_state()
    local state = {}
    for _, param in pairs(params.params) do
        if param.id then
            state[param.id] = params:get(param.id)
        end
    end
    state.scene_mode = params:get("scene_mode")
    return state
end

function presets.save_complete_preset(preset_name, scene_data_ref, update_pan_positioning_fn, audio_active_ref)
    if not preset_name or preset_name:match("^%d%d%d%d%d%d%d%d_%d%d%d%d%d%d$") then
        local time_prefix = os.date("%Y%m%d_%H%M")
        local existing_presets = presets.list_presets()
        local highest_num = 0
        
        for _, preset in ipairs(existing_presets) do
            local _, _, num = preset:match("^twins_(%d%d%d%d%d%d%d%d)_(%d%d%d%d)_(%d+)$")
            local num_val = tonumber(num)
            if num_val and num_val > highest_num then
                highest_num = num_val
            end
        end
        
        preset_name = ("twins_%s_%03d"):format(time_prefix, highest_num + 1)
    elseif not preset_name:match("^twins_") then
        preset_name = "twins_" .. preset_name
    end
    
    -- Collect LFO states
    local lfo_states = {}
    for i = 1, 16 do
        if params:get(i.."lfo") == 2 then
            lfo_states[i] = {
                slot = i,
                enabled = true,
                target = params:get(i.."lfo_target"),
                shape = params:get(i.."lfo_shape"),
                freq = params:get(i.."lfo_freq"),
                depth = params:get(i.."lfo_depth"),
                offset = params:get(i.."offset")
            }
        end
    end
    
    -- Build preset data
    local preset_data = {
        name = preset_name,
        timestamp = os.time(),
        version = 1,
        params = get_all_params_state(),
        lfo_states = lfo_states,
        morph = {
            [1] = { scene_data_ref[1][1] or {}, scene_data_ref[1][2] or {} },
            [2] = { scene_data_ref[2][1] or {}, scene_data_ref[2][2] or {} }
        },
        morph_amount = params:get("morph_amount") or 0  -- ADD THIS LINE
    }
    
    -- Save to file
    util.make_dir(_path.data .. "twins")
    local file_path = _path.data .. "twins/" .. preset_name .. ".lua"
    local file = io.open(file_path, "w")
    
    if file then
        file:write(("-- Twins Complete Preset\n-- Name: %s\n-- Saved: %s\n-- Version: 1\n\nreturn %s"):format(
            preset_name, os.date("%Y-%m-%d %H:%M:%S"), table_to_string(preset_data)))
        file:close()
        print("Preset saved: " .. preset_name)
        return true
    end
    
    print("Error: Could not save preset")
    return false
end


function presets.load_complete_preset(preset_name, scene_data_ref, update_pan_positioning_fn, audio_active_ref)
    local file_path = _path.data .. "twins/" .. preset_name .. ".lua"
    if not util.file_exists(file_path) then
        print("Preset file not found: " .. preset_name)
        return false
    end
    
    local file = io.open(file_path, "r")
    if not file then
        print("Error: Could not read preset file")
        return false
    end
    
    local content = file:read("*a")
    file:close()
    
    local return_start = content:find("return%s*{")
    local preset_data = string_to_table(return_start and content:sub(return_start + 6) or content)
    
    if not preset_data then
        print("Error: Could not parse preset")
        return false
    end
    
        -- First, completely disable ALL LFO slots
        for i = 1, 16 do
            params:set(i.."lfo", 1)
        end

        -- Restore scene data FIRST (this is crucial for morph)
        if preset_data.morph then
            for track = 1, 2 do
                for scene = 1, 2 do
                    scene_data_ref[track][scene] = preset_data.morph[track] and 
                    preset_data.morph[track][scene] or {}
                end
            end
        end

        -- Set regular parameters
        if preset_data.params then
            for param_id, value in pairs(preset_data.params) do
                if not param_id:match("^%d+lfo") and param_id ~= "scene_mode" and 
                   param_id ~= "lfo_pause" and params.lookup[param_id] then
                    params:set(param_id, value)
                end
            end
            -- restore scene_mode
            if preset_data.params.scene_mode then
                params:set("scene_mode", preset_data.params.scene_mode)
            end
        end

        -- Restore LFO states
        if preset_data.lfo_states then
            for slot, lfo_state in pairs(preset_data.lfo_states) do
                params:set(slot.."lfo_target", lfo_state.target)
                params:set(slot.."lfo_shape", lfo_state.shape)
                params:set(slot.."lfo_freq", lfo_state.freq)
                params:set(slot.."lfo_depth", lfo_state.depth)
                params:set(slot.."offset", lfo_state.offset)
                params:set(slot.."lfo", 2)
            end
        end

        -- Load samples
        for i = 1, 2 do
            local sample_path = params:get(i .. "sample")
            if sample_path and sample_path ~= "-" and sample_path ~= "" and sample_path ~= "none" then
                engine.read(i, sample_path)
                audio_active_ref[i] = true
            end
        end
        
        update_pan_positioning_fn()
        
        -- Handle morph amount
        if preset_data.params and preset_data.params.morph_amount then
            params:set("morph_amount", preset_data.params.morph_amount)
            local apply_morph = _G.apply_morph
            if apply_morph then
                apply_morph()
            end
        end
     
        redraw()
    
    return true
end

-- Optimized preset listing with better sorting
function presets.list_presets()
    local presets_list = {}
    local dir = _path.data .. "twins"
    util.make_dir(dir)
    
    local success, entries = pcall(util.scandir, dir)
    if success and entries then
        for _, entry in ipairs(entries) do
            if type(entry) == "string" and entry:match("%.lua$") and not entry:match("/$") then
                presets_list[#presets_list + 1] = entry:gsub("%.lua$", "")
            end
        end
    end
    
    table.sort(presets_list, function(a, b)
        local a_date, a_time, a_num = a:match("^twins_(%d%d%d%d%d%d%d%d)_(%d%d%d%d)_(%d+)$")
        local b_date, b_time, b_num = b:match("^twins_(%d%d%d%d%d%d%d%d)_(%d%d%d%d)_(%d+)$")
        
        if a_date and b_date then
            if a_date ~= b_date then return a_date > b_date end
            if a_time ~= b_time then return a_time > b_time end
            return tonumber(a_num) > tonumber(b_num)
        end
        
        return a_date and not b_date or (not a_date and not b_date and a > b)
    end)
    
    return presets_list
end

function presets.delete_preset(preset_name)
    local file_path = _path.data .. "twins/" .. preset_name .. ".lua"
    if util.file_exists(file_path) then
        os.remove(file_path)
        print("Preset deleted: " .. preset_name)
        return true
    end
    
    print("Preset not found: " .. preset_name)
    return false
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
    presets.delete_confirmation = nil
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
    if not presets.menu_open or z ~= 1 then return false end
    
    if presets.delete_confirmation then
        if n == 3 then
            local preset_name = presets.delete_confirmation.preset_name
            presets.delete_preset(preset_name)
            presets.preset_list = presets.list_presets()
            presets.delete_confirmation = nil
            if #presets.preset_list == 0 then
                presets.menu_open = false
            else
                presets.selected_index = util.clamp(presets.delete_confirmation.preset_index or 1, 1, #presets.preset_list)
            end
        else
            presets.delete_confirmation = nil
        end
        return true
    end
    
    if n == 3 then
        local preset_name = presets.preset_list[presets.selected_index]
        local success = presets.load_complete_preset(preset_name, scene_data_ref, update_pan_positioning_fn, audio_active_ref)
        presets.menu_open = false
        return success
    elseif n == 2 then
        if presets.preset_list[presets.selected_index] then
            presets.delete_confirmation = {
                active = true,
                preset_name = presets.preset_list[presets.selected_index],
                preset_index = presets.selected_index
            }
        end
        return true
    elseif n == 1 then
        presets.menu_open = false
        return true
    end
    
    return false
end

function presets.draw_menu()
    if not presets.menu_open then return false end
    
    if presets.delete_confirmation then
        screen.clear()
        screen.level(15)
        screen.move(64, 20)
        screen.text_center("DELETE PRESET?")
        screen.level(8)
        screen.move(64, 30)
        screen.text_center(presets.delete_confirmation.preset_name or "Unknown Preset")
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
    
    for i = 1, visible_count do
        local idx = start_index + i - 1
        if idx <= #presets.preset_list then
            local level = idx == presets.selected_index and 15 or 4
            screen.level(level)
            screen.move(2, 15 + (i * 8))
            screen.text((idx == presets.selected_index and "> " or "  ") .. presets.preset_list[idx])
        end
    end
    
    -- Scroll indicators
    if #presets.preset_list > 4 then
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