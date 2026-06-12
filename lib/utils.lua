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

function utils.random_float(l, h)
  return l + math.random() * (h - l)
end

return utils