local Installer = {}
Installer.__index = Installer

local EXTENSIONS_DIR = "/home/we/.local/share/SuperCollider/Extensions/supercollider-plugins"
local TMP_DIR        = "/tmp/norns-installer/ignore"
local SEARCH_FOLDERS = {
  "/usr/local/share/SuperCollider/Extensions",
  "/home/we/dust/code",
  "/home/we/.local/share/SuperCollider/Extensions",
}

local function basename(path)
  return path:match("([^\\/]+)$") or path
end

local function list_files(dir)
  local delim   = "!"
  local raw     = util.os_capture(string.format("find %s -type f -printf '%%p%s'", dir, delim))
  local files   = {}
  for entry in raw:gmatch("([^" .. delim .. "]+)") do
    if #entry > 2 then files[#files + 1] = entry end
  end
  return files
end

function Installer:new(args)
  local m = setmetatable({}, Installer)
  for k, v in pairs(args or {}) do m[k] = v end
  m:init()
  return m
end

function Installer:init()
  if self.zip == nil or self.zip == "" then
    print("[installer] NEED TO SPECIFY ZIP FILE")
  end
  self.requirements     = self.requirements or {}
  self.ready_to_restart = false
  self.satisfied        = false

  local found = {}
  for _, req in ipairs(self.requirements) do found[req] = false end

  for _, folder in ipairs(SEARCH_FOLDERS) do
    for _, file in ipairs(list_files(folder)) do
      if not file:find("ignore") then
        local name = basename(file)
        for req, already in pairs(found) do
          if not already and name:find(req, 1, true) then
            found[req] = true
          end
        end
      end
    end
  end

  self.missing_requirements = {}
  for req, ok in pairs(found) do
    if not ok then
      print(string.format("[installer] missing %s", req))
      self.missing_requirements[#self.missing_requirements + 1] = req
    end
  end

  self.satisfied = (#self.missing_requirements == 0)
  if self.satisfied then print("[installer] all libraries installed.") end
  self.message_needed = table.concat(self.missing_requirements, ",")
  return self.satisfied
end

function Installer:ready()
  return self.satisfied
end

function Installer:install()
  self.installing = true

  os.execute("mkdir -p " .. TMP_DIR)
  os.execute("mkdir -p " .. EXTENSIONS_DIR)

  print(string.format("[installer] downloading %s", self.zip))
  self.message_progress = "downloading..."
  os.execute(string.format("wget -q -O %s/bundle.zip %s", TMP_DIR, self.zip))

  print(string.format("[installer] unzipping %s", self.zip))
  self.message_progress = "unzipping..."
  os.execute(string.format("cd %s && unzip -o -q bundle.zip", TMP_DIR))

  for _, file in ipairs(list_files(TMP_DIR)) do
    local name = basename(file)
    for _, req in ipairs(self.missing_requirements) do
      if name:find(req, 1, true) then
        print("copying " .. name .. " to Extensions...")
        self.message_progress = "copying " .. name .. "..."
        os.execute(string.format("cp %s %s/", file, EXTENSIONS_DIR))
      end
    end
  end

  os.execute("cd /tmp/ && rm -rf norns-installer")
  self.ready_to_restart = true
  self.installing       = false
end

function Installer:key(k, z)
  if self.satisfied or self.ready_to_restart or self.installing then return end
  if k == 3 and z == 1 then
    clock.run(function() self:install() end)
  end
end

function Installer:redraw()
  screen.clear()
  screen.blend_mode(0)
  screen.level(15)
  if self.ready_to_restart then
    screen.move(64, 22); screen.text_center("ready.")
    screen.move(64, 32); screen.text_center("do SYSTEM -> RESTART")
    screen.move(64, 42); screen.text_center("then reload this script.")
  elseif self.installing then
    screen.move(64, 22); screen.text_center("installing:")
    screen.move(64, 32); screen.text_center(self.message_needed)
    if self.message_progress then
      screen.move(64, 42); screen.text_center(self.message_progress)
    end
  else
    screen.move(64, 22); screen.text_center("missing SuperCollider libraries:")
    screen.move(64, 32); screen.text_center(self.message_needed)
    screen.move(64, 42); screen.text_center("press K3 to install.")
  end
  screen.update()
end

return Installer
