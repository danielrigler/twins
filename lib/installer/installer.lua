local Installer = {}
Installer.__index = Installer

local EXTENSIONS_DIR = "/home/we/.local/share/SuperCollider/Extensions/supercollider-plugins"
local TMP_DIR        = "/tmp/norns-installer/ignore"
local SEARCH_FOLDERS = {
  "/usr/local/share/SuperCollider/Extensions",
  "/home/we/dust/code",
  "/home/we/.local/share/SuperCollider/Extensions",
}
local RESTART_CMD = "sudo systemctl restart norns-jack.service norns-crone.service norns-matron.service"

local function basename(path)
  return path:match("([^\\/]+)$") or path
end

local function list_files(dir)
  local delim = "!"
  local raw   = util.os_capture(string.format("find %s -type f -printf '%%p%s'", dir, delim))
  local files = {}
  for entry in raw:gmatch("([^" .. delim .. "]+)") do
    if #entry > 2 then files[#files + 1] = entry end
  end
  return files
end

local function trim(s)
  s = (s or ""):gsub("^%s+", "")
  s = s:gsub("%s+$", "")
  return s
end

local function git(self, args)
  return trim(util.os_capture("git -C '" .. self.path .. "' " .. args .. " 2>/dev/null"))
end

function Installer:new(args)
  local m = setmetatable({}, Installer)
  for k, v in pairs(args or {}) do m[k] = v end
  m.path = trim(m.path or norns.state.path):gsub("/$", "")
  m.update = { state = nil, behind = 0, message = nil }
  m:scan()
  return m
end

function Installer:scan()
  if self.zip == nil or self.zip == "" then
    print("[installer] NEED TO SPECIFY ZIP FILE")
  end
  self.requirements     = self.requirements or {}
  self.ready_to_restart = false
  self.installing       = false
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

function Installer:install_libs()
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

function Installer:is_git()
  return git(self, "rev-parse --is-inside-work-tree") == "true"
end

function Installer:is_dirty()
  return git(self, "status --porcelain --untracked-files=no") ~= ""
end

function Installer:count_behind()
  return tonumber(git(self, "rev-list --count HEAD..@{u}")) or 0
end

function Installer:pulled_engine_change()
  local names = util.os_capture("git -C '" .. self.path .. "' diff --name-only ORIG_HEAD..HEAD -- '*.sc' '*.scd' 2>/dev/null") or ""
  return trim(names) ~= ""
end

function Installer:check()
  if not self.satisfied then return end
  if not self:is_git() then return end
  self.update.state = "checking"
  norns.system_cmd("git -C '" .. self.path .. "' fetch --quiet 2>/dev/null; echo _done_", function()
    self.update.behind = self:count_behind()
    if self.update.behind <= 0 then
      self.update.state = nil
    elseif self:is_dirty() then
      print("[installer] " .. self.update.behind .. " update(s) available but working tree has local changes; skipping prompt.")
      self.update.state = nil
    else
      self.update.state = "update"
    end
  end)
end

function Installer:install_update()
  self.update.state = "installing"
  self.update.message = nil
  norns.system_cmd("git -C '" .. self.path .. "' pull --ff-only 2>&1", function()
    if self:count_behind() == 0 then
      if self:pulled_engine_change() then
        self.update.state = "restart"
      else
        self.update.state = "reloading"
        clock.run(function() clock.sleep(0.4); norns.rerun() end)
      end
    else
      self.update.message = "update failed"
      self.update.state = "error"
    end
  end)
end

function Installer:do_restart()
  self.update.state = "restarting"
  os.execute(RESTART_CMD)
end

function Installer:pending()
  local s = self.update.state
  return s == "update" or s == "installing" or s == "reloading"
      or s == "restart" or s == "restarting" or s == "error"
end

function Installer:key(k, z)
  if not self.satisfied then
    if self.ready_to_restart or self.installing then return end
    if k == 3 and z == 1 then clock.run(function() self:install_libs() end) end
    return
  end
  if z ~= 1 then return end
  local s = self.update.state
  if s == "update" then
    if k == 2 then self.update.state = nil
    elseif k == 3 then clock.run(function() self:install_update() end) end
  elseif s == "restart" then
    if k == 2 then self.update.state = nil
    elseif k == 3 then self:do_restart() end
  elseif s == "error" then
    if k == 2 or k == 3 then self.update.state = nil end
  end
end

function Installer:redraw()
  screen.clear()
  screen.blend_mode(0)
  screen.level(15)
  if not self.satisfied then
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
    return
  end
  local s = self.update.state
  if s == "update" then
    screen.move(64, 18); screen.text_center("twins update available")
    screen.move(64, 30); screen.text_center(self.update.behind .. " new commit" .. (self.update.behind == 1 and "" or "s"))
    screen.move(64, 46); screen.text_center("K2: skip   K3: install")
  elseif s == "installing" then
    screen.move(64, 28); screen.text_center("installing update...")
  elseif s == "reloading" then
    screen.move(64, 28); screen.text_center("updated - reloading...")
  elseif s == "restart" then
    screen.move(64, 16); screen.text_center("update installed.")
    screen.move(64, 28); screen.text_center("engine changed - restart needed")
    screen.move(64, 44); screen.text_center("K3: restart   K2: later")
  elseif s == "restarting" then
    screen.move(64, 28); screen.text_center("restarting...")
  elseif s == "error" then
    screen.move(64, 24); screen.text_center(self.update.message or "update error")
    screen.move(64, 40); screen.text_center("K2/K3: dismiss")
  end
  screen.update()
end

return Installer