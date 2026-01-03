local presets = {}
local lfo = nil

presets.menu_open = false
presets.menu_mode = "load"
presets.selected_index = 1
presets.preset_list = {}
presets.confirmation = nil
_G.preset_loading = false

function presets.set_lfo_reference(lfo_module)
    lfo = lfo_module
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

local function get_lfo_states()
    local lfo_states = {}
    for i = 1, 16 do
        local lfo_param = i.."lfo"
        if params.lookup[lfo_param] and params:get(lfo_param) == 2 then
            local target_param = i.."lfo_target"
            local shape_param = i.."lfo_shape"
            local freq_param = i.."lfo_freq"
            local depth_param = i.."lfo_depth"
            local offset_param = i.."offset"

            if params.lookup[target_param] and params.lookup[shape_param] and 
               params.lookup[freq_param] and params.lookup[depth_param] and 
               params.lookup[offset_param] then
                lfo_states[i] = {
                    slot = i,
                    enabled = true,
                    target = params:get(target_param),
                    shape = params:get(shape_param),
                    freq = params:get(freq_param),
                    depth = params:get(depth_param),
                    offset = params:get(offset_param)
                }
            end
        end
    end
    return lfo_states
end

local function generate_preset_name(preset_name)
    if not preset_name or preset_name == "" then
        local time_prefix = os.date("%Y%m%d_%H%M")
        local existing_presets = presets.list_presets()
        local highest_num = 0
        
        for _, preset in ipairs(existing_presets) do
            local num = preset:match("^twins_%d+_%d+_(%d+)$")
            if num then
                highest_num = math.max(highest_num, tonumber(num))
            end
        end
        
        return string.format("twins_%s_%03d", time_prefix, highest_num + 1)
    end
    
    return preset_name:match("^twins_") and preset_name or "twins_" .. preset_name
end

function presets.save_complete_preset(preset_name, scene_data_ref, update_pan_positioning_fn, audio_active_ref)
    local success, err = pcall(function()
        preset_name = generate_preset_name(preset_name)
        
        local preset_data = {
            name = preset_name,
            timestamp = os.time(),
            version = 1,
            params = get_all_params_state(),
            lfo_states = get_lfo_states(),
            morph = {
                [1] = { scene_data_ref[1][1] or {}, scene_data_ref[1][2] or {} },
                [2] = { scene_data_ref[2][1] or {}, scene_data_ref[2][2] or {} }
            },
            morph_amount = params:get("morph_amount") or 0
        }
        
        util.make_dir(_path.data .. "twins")
        local file_path = _path.data .. "twins/" .. preset_name .. ".lua"
        local file = io.open(file_path, "w")
        
        if not file then
            error("Could not open file for writing")
        end
        
        local header = string.format(
            "-- Twins Complete Preset\n-- Name: %s\n-- Saved: %s\n-- Version: 1\n\nreturn ",
            preset_name, os.date("%Y-%m-%d %H:%M:%S")
        )
        
        file:write(header .. table_to_string(preset_data))
        file:close()
        print("Preset saved: " .. preset_name)
    end)
    
    if success then
        return true
    else
        print("Error saving preset: " .. (err or "unknown"))
        return false
    end
end

local function apply_lfo_states(lfo_states)
    if not lfo_states then return end
    
    for slot, lfo_state in pairs(lfo_states) do
        local target_param = slot.."lfo_target"
        local shape_param = slot.."lfo_shape"
        local freq_param = slot.."lfo_freq"
        local depth_param = slot.."lfo_depth"
        local offset_param = slot.."offset"
        local lfo_param = slot.."lfo"
        
        if params.lookup[target_param] and params.lookup[shape_param] and 
           params.lookup[freq_param] and params.lookup[depth_param] and 
           params.lookup[offset_param] and params.lookup[lfo_param] then
            params:set(target_param, lfo_state.target)
            params:set(shape_param, lfo_state.shape)
            params:set(freq_param, lfo_state.freq)
            params:set(depth_param, lfo_state.depth)
            params:set(offset_param, lfo_state.offset)
            params:set(lfo_param, 2)
        end
    end
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

local function load_audio_samples(audio_active_ref)
    for i = 1, 2 do
        local sample_param = i .. "sample"
        if params.lookup[sample_param] then
            local sample_path = params:get(sample_param)
            if sample_path and sample_path ~= "-" and sample_path ~= "" and sample_path ~= "none" then
                engine.read(i, sample_path)
                audio_active_ref[i] = true
            end
        end
    end
end

function presets.load_complete_preset(preset_name, scene_data_ref, update_pan_positioning_fn, audio_active_ref)
    local file_path = _path.data .. "twins/" .. preset_name .. ".lua"
    
    if not util.file_exists(file_path) then
        print("Preset file not found: " .. preset_name)
        return false
    end
    
    local chunk, err = loadfile(file_path)
    if not chunk then
        print("Error loading preset: " .. (err or "unknown"))
        return false
    end
    
    local success, preset_data = pcall(chunk)
    if not success or not preset_data then
        print("Error parsing preset: " .. (preset_data or "unknown"))
        return false
    end
    
    if preset_data.version and preset_data.version > 1 then
        print("Warning: Preset saved with newer version")
    end
    
    _G.preset_loading = true
    
    if params.lookup["unload_all"] then
        params:set("unload_all", 1)
    end
    
    for i = 1, 16 do
        local lfo_param = i.."lfo"
        if params.lookup[lfo_param] then
            params:set(lfo_param, 1)
        end
    end
    
    apply_scene_data(preset_data, scene_data_ref)
    
    if preset_data.morph_amount then
        morph_amount = preset_data.morph_amount
        if params.lookup["morph_amount"] then
            params:set("morph_amount", preset_data.morph_amount)
        end
    end
    
    if preset_data.params then
        for param_id, value in pairs(preset_data.params) do
            if params.lookup[param_id] and param_id ~= "morph_amount" then
                params:set(param_id, value)
            end
        end
    end
    
    apply_lfo_states(preset_data.lfo_states)
    load_audio_samples(audio_active_ref)
    update_pan_positioning_fn()
    
    clock.run(function()
        clock.sleep(0.1)
        _G.preset_loading = false
        redraw()
        print("Preset loaded: " .. preset_name)
    end)

    return true
end

function presets.list_presets()
    local presets_list = {}
    local dir = _path.data .. "twins"
    util.make_dir(dir)
    
    local success, entries = pcall(util.scandir, dir)
    if not (success and entries) then
        return presets_list
    end
    
    for _, entry in ipairs(entries) do
        if type(entry) == "string" and entry:match("%.lua$") then
            presets_list[#presets_list + 1] = entry:gsub("%.lua$", "")
        end
    end
    
    table.sort(presets_list, function(a, b)
        local a_date, a_time, a_num = a:match("^twins_(%d+)_(%d+)_(%d+)$")
        local b_date, b_time, b_num = b:match("^twins_(%d+)_(%d+)_(%d+)$")
        
        if a_date and b_date then
            if a_date ~= b_date then return a_date > b_date end
            if a_time ~= b_time then return a_time > b_time end
            return tonumber(a_num) > tonumber(b_num)
        end
        
        return a_date and true or (not b_date and a > b)
    end)
    
    return presets_list
end

function presets.delete_preset(preset_name)
    local file_path = _path.data .. "twins/" .. preset_name .. ".lua"
    
    if not util.file_exists(file_path) then
        print("Preset not found: " .. preset_name)
        return false
    end
    
    local success, err = pcall(os.remove, file_path)
    if success then
        print("Preset deleted: " .. preset_name)
        return true
    else
        print("Error deleting preset: " .. (err or "unknown"))
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

function presets.menu_enc(n, d)
    if not presets.menu_open then return end
    
    if n == 2 then
        presets.selected_index = util.clamp(presets.selected_index + d, 1, #presets.preset_list)
    elseif n == 1 or n == 3 then
        presets.menu_mode = d > 0 and "overwrite" or "load"
    end
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
            elseif presets.confirmation.type == "overwrite" then
                local preset_name = presets.confirmation.preset_name
                presets.save_complete_preset(preset_name, scene_data_ref, update_pan_positioning_fn, audio_active_ref)
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
        else
            presets.confirmation = {
                type = "overwrite",
                preset_name = preset_name
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

local function draw_confirmation(title, preset_name)
    screen.clear()
    screen.level(15)
    screen.move(64, 20)
    screen.text_center(title)
    screen.level(8)
    screen.move(64, 30)
    screen.text_center(preset_name or "Unknown Preset")
    screen.level(4)
    screen.move(64, 45)
    screen.text_center("K2/K1: Cancel")
    screen.level(15)
    screen.move(64, 55)
    screen.text_center("K3: Confirm")
    screen.update()
end

function presets.draw_menu()
    if not presets.menu_open then return false end
    
    if presets.confirmation then
        local title = presets.confirmation.type == "delete" and "DELETE PRESET?" or "OVERWRITE PRESET?"
        draw_confirmation(title, presets.confirmation.preset_name)
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
            screen.level(is_selected and 15 or 4)
            screen.move(2, 11 + (i * 8))
            screen.text((is_selected and "> " or "  ") .. presets.preset_list[idx])
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
    
    if presets.menu_mode == "overwrite" then
        screen.level(15)
        screen.move(91, 64)
        screen.text("K3: Save")
    else
        screen.level(1)
        screen.move(91, 64)
        screen.text("K3: Load")
    end
    
    screen.update()
    return true
end

function presets.is_menu_open()
    return presets.menu_open
end

return presets