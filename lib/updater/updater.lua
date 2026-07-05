local Updater = {}
Updater.__index = Updater

local RESTART_CMD = "sudo systemctl restart norns-jack.service norns-crone.service norns-matron.service"

local function trim(s)
  s = (s or ""):gsub("^%s+", "")
  s = s:gsub("%s+$", "")
  return s
end

local function git(self, args)
  return trim(util.os_capture("git -C '" .. self.path .. "' " .. args .. " 2>/dev/null"))
end

function Updater:new(args)
  local m = setmetatable({}, Updater)
  m.path = trim((args and args.path) or norns.state.path):gsub("/$", "")
  m.state = nil
  m.message = nil
  m.behind = 0
  m.engine_changed = false
  return m
end

function Updater:is_git()
  return git(self, "rev-parse --is-inside-work-tree") == "true"
end

function Updater:is_dirty()
  return git(self, "status --porcelain --untracked-files=no") ~= ""
end

function Updater:count_behind()
  return tonumber(git(self, "rev-list --count HEAD..@{u}")) or 0
end

function Updater:scan_engine_change()
  local names = util.os_capture("git -C '" .. self.path .. "' diff --name-only HEAD..@{u} 2>/dev/null") or ""
  for line in names:gmatch("[^\r\n]+") do
    if line:match("%.sc$") then return true end
  end
  return false
end

function Updater:check()
  if not self:is_git() then return end
  self.state = "checking"
  norns.system_cmd("git -C '" .. self.path .. "' fetch --quiet 2>/dev/null; echo _done_", function()
    self.behind = self:count_behind()
    if self.behind <= 0 then
      self.state = nil
    elseif self:is_dirty() then
      print("[updater] " .. self.behind .. " update(s) available but working tree has local changes; skipping prompt.")
      self.state = nil
    else
      self.engine_changed = self:scan_engine_change()
      self.state = "update"
    end
  end)
end

function Updater:install()
  self.state = "installing"
  self.message = nil
  norns.system_cmd("git -C '" .. self.path .. "' pull --ff-only 2>&1", function()
    if self:count_behind() == 0 then
      self.state = self.engine_changed and "restart" or "reload"
    else
      self.message = "update failed"
      self.state = "error"
    end
  end)
end

function Updater:do_restart()
  self.state = "restarting"
  os.execute(RESTART_CMD)
end

function Updater:pending()
  local s = self.state
  return s == "update" or s == "installing" or s == "reload"
      or s == "restart" or s == "restarting" or s == "error"
end

function Updater:key(k, z)
  if z ~= 1 then return end
  local s = self.state
  if s == "update" then
    if k == 2 then self.state = nil
    elseif k == 3 then clock.run(function() self:install() end) end
  elseif s == "reload" then
    if k == 2 then self.state = nil
    elseif k == 3 then norns.rerun() end
  elseif s == "restart" then
    if k == 2 then self.state = nil
    elseif k == 3 then self:do_restart() end
  elseif s == "error" then
    if k == 2 or k == 3 then self.state = nil end
  end
end

function Updater:redraw()
  screen.clear()
  screen.blend_mode(0)
  screen.level(15)
  local s = self.state
  if s == "update" then
    screen.move(64, 18); screen.text_center("twins update available")
    screen.move(64, 30); screen.text_center(self.behind .. " new commit" .. (self.behind == 1 and "" or "s"))
    screen.move(64, 46); screen.text_center("K2: skip   K3: install")
  elseif s == "installing" then
    screen.move(64, 28); screen.text_center("installing update...")
  elseif s == "reload" then
    screen.move(64, 22); screen.text_center("update installed.")
    screen.move(64, 40); screen.text_center("K3: reload   K2: later")
  elseif s == "restart" then
    screen.move(64, 16); screen.text_center("update installed.")
    screen.move(64, 28); screen.text_center("engine changed - restart needed")
    screen.move(64, 44); screen.text_center("K3: restart   K2: later")
  elseif s == "restarting" then
    screen.move(64, 28); screen.text_center("restarting...")
  elseif s == "error" then
    screen.move(64, 24); screen.text_center(self.message or "update error")
    screen.move(64, 40); screen.text_center("K2/K3: dismiss")
  end
  screen.update()
end

return Updater
