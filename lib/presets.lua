local presets = {}
local lfo = nil

presets.menu_open = false
presets.menu_mode = "load"
presets.selected_index = 1
presets.preset_list = {}
presets.delete_confirmation = nil
presets.overwrite_confirmation = nil
preset_loading = false

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

local function string_to_table(str)
    local chunk, err = load("return " .. str)
    if not chunk then
        print("Parse error: " .. (err or "unknown"))
        return nil
    end
    return chunk()
end

-- Cached params state collection
local function get_all_params_state()
    local state = {}
    for _, param in pairs(params.params) do
        if param.id then
            state[param.id] = params:get(param.id)
        end
    end
    return state
end

-- Collect LFO states
local function get_lfo_states()
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
    return lfo_states
end

-- Generate preset name
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
    
    -- Save to file
    util.make_dir(_path.data .. "twins")
    local file_path = _path.data .. "twins/" .. preset_name .. ".lua"
    local file = io.open(file_path, "w")
    
    if not file then
        print("Error: Could not save preset")
        return false
    end
    
    local header = string.format(
        "-- Twins Complete Preset\n-- Name: %s\n-- Saved: %s\n-- Version: 1\n\nreturn ",
        preset_name, os.date("%Y-%m-%d %H:%M:%S")
    )
    
    file:write(header .. table_to_string(preset_data))
    file:close()
    print("Preset saved: " .. preset_name)
    return true
end

-- Apply LFO states
local function apply_lfo_states(lfo_states)
    if not lfo_states then return end
    
    for slot, lfo_state in pairs(lfo_states) do
        params:set(slot.."lfo_target", lfo_state.target)
        params:set(slot.."lfo_shape", lfo_state.shape)
        params:set(slot.."lfo_freq", lfo_state.freq)
        params:set(slot.."lfo_depth", lfo_state.depth)
        params:set(slot.."offset", lfo_state.offset)
        params:set(slot.."lfo", 2)
    end
end

-- Apply scene data efficiently
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
        local sample_path = params:get(i .. "sample")
        if sample_path and sample_path ~= "-" and sample_path ~= "" and sample_path ~= "none" then
            engine.read(i, sample_path)
            audio_active_ref[i] = true
        end
    end
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
    if not return_start then
        print("Error: Invalid preset format")
        return false
    end
    
    local preset_data = string_to_table(content:sub(return_start + 6))
    if not preset_data then
        print("Error: Could not parse preset")
        return false
    end
    
    preset_loading = true
    
    -- Disable all LFOs first
    for i = 1, 16 do
        params:set(i.."lfo", 1)
    end
    
    -- Apply preset data
    apply_scene_data(preset_data, scene_data_ref)
    
    if preset_data.morph_amount then
        morph_amount = preset_data.morph_amount
        params:set("morph_amount", preset_data.morph_amount)
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
        -- Clear the flag after loading is complete
        preset_loading = false
        print("Preset loaded: " .. preset_name)
    end)
    
    redraw()
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
    
    -- Sort by timestamp (newest first)
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
    
    os.remove(file_path)
    print("Preset deleted: " .. preset_name)
    return true
end

function presets.open_menu()
    presets.preset_list = presets.list_presets()
    
    if #presets.preset_list == 0 then
        print("No presets found")
        return false
    end
    
    presets.selected_index = util.clamp(presets.selected_index, 1, #presets.preset_list)
    presets.menu_open = true
    presets.menu_mode = "load"
    return true
end

function presets.close_menu()
    presets.menu_open = false
    presets.delete_confirmation = nil
    presets.overwrite_confirmation = nil
    presets.menu_mode = "load"
end

function presets.menu_enc(n, d)
    if not presets.menu_open then return end
    
    if n == 2 then
        presets.selected_index = util.clamp(presets.selected_index + d, 1, #presets.preset_list)
    elseif n == 3 then
        presets.menu_mode = d > 0 and "overwrite" or "load"
    end
end

function presets.menu_key(n, z, scene_data_ref, update_pan_positioning_fn, audio_active_ref)
    if not presets.menu_open or z ~= 1 then return false end
    
    -- Handle delete confirmation
    if presets.delete_confirmation then
        if n == 3 then
            local preset_name = presets.delete_confirmation.preset_name
            local preset_index = presets.delete_confirmation.preset_index
            presets.delete_preset(preset_name)
            presets.preset_list = presets.list_presets()
            presets.delete_confirmation = nil
            
            if #presets.preset_list == 0 then
                presets.menu_open = false
            else
                presets.selected_index = util.clamp(preset_index, 1, #presets.preset_list)
            end
        else
            presets.delete_confirmation = nil
        end
        return true
    end
    
    -- Handle overwrite confirmation
    if presets.overwrite_confirmation then
        if n == 3 then
            local preset_name = presets.overwrite_confirmation.preset_name
            presets.save_complete_preset(preset_name, scene_data_ref, update_pan_positioning_fn, audio_active_ref)
            presets.overwrite_confirmation = nil
            presets.menu_open = false
        else
            presets.overwrite_confirmation = nil
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
            presets.overwrite_confirmation = {
                active = true,
                preset_name = preset_name
            }
            return true
        end
    elseif n == 2 then
        presets.delete_confirmation = {
            active = true,
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

-- Draw confirmation dialog
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
    
    -- Show delete confirmation
    if presets.delete_confirmation then
        draw_confirmation("DELETE PRESET?", presets.delete_confirmation.preset_name)
        return true
    end
    
    -- Show overwrite confirmation
    if presets.overwrite_confirmation then
        draw_confirmation("OVERWRITE PRESET?", presets.overwrite_confirmation.preset_name)
        return true
    end
    
    screen.clear()
    screen.level(15)
    screen.move(64, 6)
    screen.text_center("SELECT A PRESET")
    
    -- Calculate visible range
    local visible_count = math.min(5, #presets.preset_list)
    local start_index = math.max(1, math.min(presets.selected_index - 2, #presets.preset_list - visible_count + 1))
    
    -- Draw preset list
    for i = 1, visible_count do
        local idx = start_index + i - 1
        if idx <= #presets.preset_list then
            local is_selected = idx == presets.selected_index
            screen.level(is_selected and 15 or 4)
            screen.move(2, 11 + (i * 8))
            screen.text((is_selected and "> " or "  ") .. presets.preset_list[idx])
        end
    end
    
    -- Scroll indicators
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
    
    -- Bottom controls
    screen.level(1)
    screen.move(2, 64)
    screen.text("K1: Back")
    screen.move(50, 64)
    screen.text("K2: Del")
    
    -- Mode-dependent K3 label
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