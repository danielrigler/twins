local NameSizer = {}

NameSizer.__index = NameSizer
NameSizer.descriptor_path = _path.code.."namesizer/lib/descriptors.txt"
NameSizer.things_path = _path.code.."namesizer/lib/things.txt"

local function getRandNameFromFile(path)
    local f = io.open(path, "r")
    f:close()
    local all_lines = {}
    for line in io.lines(path) do table.insert(all_lines, line) end
    local s = all_lines[math.random(1, #all_lines)]
    return s:gsub('[%p%c%s]', '')
end

function NameSizer.rnd(separator)
    separator = separator or " "
    local d = getRandNameFromFile(NameSizer.descriptor_path)
    local t = getRandNameFromFile(NameSizer.things_path);
    return d..separator..t
end

return NameSizer