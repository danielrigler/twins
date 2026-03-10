local utils = {}

function utils.stop_metro_safe(m)
  if m then
    pcall(function() m:stop() end)
    if m then m.event = nil end
  end
end

function utils.random_float(l, h)
  return l + math.random() * (h - l)
end

return utils
