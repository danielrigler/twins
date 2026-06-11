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

function utils.random_float(l, h)
  return l + math.random() * (h - l)
end

return utils