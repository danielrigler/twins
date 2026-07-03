local utils = {}

local running_metros = {}

function utils.metro_start(m)
    running_metros[m] = true
    m:start()
end

function utils.stop_metro_safe(m)
    if m and running_metros[m] then
        running_metros[m] = nil
        pcall(function() m:stop() end)
        m.event = nil
    end
end

function utils.deep_copy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do copy[k] = utils.deep_copy(v) end
    return copy
end

function utils.clear_table(t)
    for k in pairs(t) do t[k] = nil end
end

function utils.random_float(l, h)
    return l + math.random() * (h - l)
end

local _mirror_cache = {}
function utils.mirror_param_name(param)
    local m = _mirror_cache[param]
    if m then return m end
    m = param:gsub("^(%d)(.*)", function(n, rest)
        return tostring((tonumber(n) % 2) + 1) .. rest
    end)
    _mirror_cache[param] = m
    return m
end

function utils.is_locked(key)
    return params.lookup[key] ~= nil and params:get(key) == 2
end

function utils.is_param_locked(track, suffix)
    return utils.is_locked(track .. "lock_" .. suffix)
end

return utils
