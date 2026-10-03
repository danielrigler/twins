local Installer = {}
Installer.__index = Installer

local EXTENSIONS_DIR = "/home/we/.local/share/SuperCollider/Extensions/supercollider-plugins"
local TMP_DIR        = "/tmp/norns-installer/ignore"
local SEARCH_FOLDERS = {
  "/usr/local/share/SuperCollider/Extensions",
  "/home/we/.local/share/SuperCollider/Extensions",
  "/home/we/dust/code",
}
local RESTART_CMD = "sudo systemctl restart norns-jack.service norns-crone.service norns-matron.service"

local function basename(path) return path:match("([^\\/]+)$") or path end

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

local function halves(req)
  return { string.format("%s.sc", req), "sc" },
         { string.format("%s.so", req), "so" },
         { string.format("%s_scsynth.so", req), "so" }
end

local function probe(requirements)
  local found, order = {}, {}
  for _, req in ipairs(requirements) do
    if found[req] == nil then
      found[req] = { sc = false, so = false }
      order[#order + 1] = req
    end
  end
  if #order == 0 then return {}, found end
  local clauses, wanted = {}, {}
  for _, req in ipairs(order) do
    for _, h in ipairs({ halves(req) }) do
      clauses[#clauses + 1] = string.format("-name '%s'", h[1])
      wanted[h[1]] = { req = req, half = h[2] }
    end
  end
  local cmd = string.format("find %s -name .git -prune -o \\( %s \\) -not -path '*ignore*' -type f -printf '%%p!' 2>/dev/null",
    table.concat(SEARCH_FOLDERS, " "), table.concat(clauses, " -o "))
  local raw = util.os_capture(cmd, true) or ""
  for entry in raw:gmatch("([^!]+)") do
    local w = wanted[basename(entry)]
    if w then found[w.req][w.half] = true end
  end
  local missing = {}
  for _, req in ipairs(order) do
    local rec = found[req]
    if not (rec.sc and rec.so) then missing[#missing + 1] = req end
  end
  return missing, found
end

function Installer:scan()
  if self.zip == nil or self.zip == "" then print("[installer] NEED TO SPECIFY ZIP FILE") end
  self.requirements     = self.requirements or {}
  self.ready_to_restart = false
  self.installing       = false
  self.satisfied        = false
  self.install_error    = nil
  local missing, detail = probe(self.requirements)
  for _, req in ipairs(missing) do
    print(string.format("[installer] missing %s (class file: %s, server plugin: %s)",
      req, detail[req].sc and "yes" or "NO", detail[req].so and "yes" or "NO"))
  end
  self.missing_requirements = missing
  self.satisfied = (#missing == 0)
  if self.satisfied then print("[installer] all libraries installed.") end
  self.message_needed = table.concat(self.missing_requirements, ",")
  return self.satisfied
end

function Installer:ready()
  return self.satisfied
end

function Installer:install_libs()
  if self.installing then return end
  self.installing    = true
  self.install_error = nil
  print(string.format("[installer] downloading %s", self.zip))
  self.message_progress = "Downloading..."
  local names = {}
  for _, req in ipairs(self.missing_requirements) do
    for _, h in ipairs({ halves(req) }) do
      names[#names + 1] = string.format("-name '%s'", h[1])
    end
  end
  local cmd = table.concat({
    string.format("rm -rf %s", TMP_DIR),
    string.format("mkdir -p %s '%s'", TMP_DIR, EXTENSIONS_DIR),
    string.format("wget -q -O %s/bundle.zip '%s'", TMP_DIR, self.zip),
    string.format("cd %s", TMP_DIR),
    "unzip -o -q bundle.zip",
    string.format("find . \\( %s \\) -type f -exec cp {} '%s/' ';'",
      table.concat(names, " -o "), EXTENSIONS_DIR),
    "cd /tmp",
    "rm -rf norns-installer",
  }, " && ")
  norns.system_cmd(cmd .. " 2>&1; echo _done_", function(out)
    local still_missing = probe(self.requirements)
    self.installing = false
    self.message_progress = nil
    if #still_missing == 0 then
      print("[installer] install complete; restart needed to load the engine.")
      self.ready_to_restart = true
    else
      self.install_error = "could not install " .. table.concat(still_missing, ",")
      print("[installer] " .. self.install_error)
      print("[installer] shell output: " .. tostring(out))
    end
  end)
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
  self.update.state = "checking"
  local g = "nice -n 19 git -C '" .. self.path .. "' "
  norns.system_cmd("if " .. g .. "rev-parse --is-inside-work-tree >/dev/null 2>&1; then timeout -k 5 20 " .. g .. "fetch --quiet 2>/dev/null; echo B$(" .. g .. "rev-list --count HEAD..@{u} 2>/dev/null); echo D$(" .. g .. "status --porcelain --untracked-files=no 2>/dev/null | wc -l); fi; echo _done_", function(out)
    out = out or ""
    self.update.behind = tonumber(out:match("B(%d+)")) or 0
    if self.update.behind <= 0 then
      self.update.state = nil
    elseif (tonumber(out:match("D(%d+)")) or 0) > 0 then
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
    if self.installing then return end
    if self.ready_to_restart then
      if k == 3 and z == 1 then self:do_restart() end
      return
    end
    if k == 3 and z == 1 then
      self.install_error = nil
      self:install_libs()
    end
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
      if self.update.state == "restarting" then
        screen.move(64, 28); screen.text_center("Restarting...")
      else
        screen.move(64, 22); screen.text_center("Libraries Installed.")
        screen.level(1);
        screen.move(64, 34); screen.text_center("Restart to Load the Engine")
         screen.level(15);
        screen.move(64, 46); screen.text_center("K3: Restart")
      end
    elseif self.installing then
      screen.move(64, 22); screen.text_center("Installing:")
      screen.move(64, 32); screen.text_center(self.message_needed)
      if self.message_progress then
        screen.move(64, 42); screen.text_center(self.message_progress)
      end
    elseif self.install_error then
      screen.move(64, 20); screen.text_center("Install Failed")
      screen.level(1);
      screen.move(64, 32); screen.text_center(self.install_error)
      screen.move(64, 40); screen.text_center("see maiden for details")
      screen.level(15);
      screen.move(64, 52); screen.text_center("K3: Retry")
    else
      screen.move(64, 22); screen.text_center("Missing SuperCollider Libraries:")
      screen.level(1);
      screen.move(64, 32); screen.text_center(self.message_needed)
      screen.level(15);
      screen.move(64, 42); screen.text_center("K3: Install")
    end
    screen.update()
    return
  end
  local s = self.update.state
  if s == "update" then
    screen.move(64, 18); screen.text_center("Twins Update Available")
    screen.level(1);
    screen.move(64, 30); screen.text_center(self.update.behind .. " new commit" .. (self.update.behind == 1 and "" or "s"))
    screen.level(15);
    screen.move(64, 46); screen.text_center("K2: Skip   K3: Install")
  elseif s == "installing" then
    screen.move(64, 28); screen.text_center("Installing Update...")
  elseif s == "reloading" then
    screen.move(64, 28); screen.text_center("Updated - Reloading...")
  elseif s == "restart" then
    screen.move(64, 16); screen.text_center("Update Installed.")
    screen.level(1);
    screen.move(64, 28); screen.text_center("New Engine - Restart Needed")
    screen.level(15);
    screen.move(64, 44); screen.text_center("K2: Later   K3: Restart")
  elseif s == "restarting" then
    screen.move(64, 28); screen.text_center("Restarting...")
  elseif s == "error" then
    screen.move(64, 24); screen.text_center(self.update.message or "Update Error")
    screen.move(64, 40); screen.text_center("K2/K3: Dismiss")
  end
  screen.update()
end

return Installer