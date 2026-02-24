local preset_names = {}

preset_names.__index = preset_names
preset_names.firstnames_path = _path.code.."twins/lib/firstnames.txt"
preset_names.secondnames_path = _path.code.."twins/lib/secondnames.txt"

local PREFIXES = { "Post-", "Anti-", "Proto-", "Neo-", "Meta-", "Turbo-", "Quasi-" }
local SUFFIXES = { "Mk2", "Deluxe", "Final", "v2", "Pro", "Lite", "II" }

local PREFIX_CHANCE = 0.1
local SUFFIX_CHANCE = 0.05

local function getRandNameFromFile(path)
    local all_lines = {}
    for line in io.lines(path) do all_lines[#all_lines + 1] = line end
    local s = all_lines[math.random(1, #all_lines)]
    return s:gsub('[%p%c%s]', '')
end

function preset_names.rnd(separator)
    separator = separator or " "
    local d = getRandNameFromFile(preset_names.firstnames_path)
    local t = getRandNameFromFile(preset_names.secondnames_path)
    local roll = math.random()
    if roll < PREFIX_CHANCE then
        if math.random() < 0.5 then
            d = PREFIXES[math.random(#PREFIXES)] .. d
        else
            t = PREFIXES[math.random(#PREFIXES)] .. t
        end
    elseif roll < PREFIX_CHANCE + SUFFIX_CHANCE then
        t = t .. separator .. SUFFIXES[math.random(#SUFFIXES)]
    end
    return d .. separator .. t
end

return preset_names