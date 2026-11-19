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
local USER_EXT = "/home/we/.local/share/SuperCollider/Extensions"
local BUNDLE_DIR = USER_EXT .. "/twins"

local function basename(path) return path:match("([^\\/]+)$") or path end
local ELF_ARCH = {["1:40"] = "armv7l", ["2:183"] = "aarch64", ["2:62"] = "x86_64"}

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
  m.requirements = m.requirements or {}
  m.bundled_ok = {}
  if m.bundled then
    local b = {}
    for v in (util.os_capture("od -An -tu1 -N20 \"$(command -v scsynth)\" 2>/dev/null", true) or ""):gmatch("%d+") do b[#b + 1] = v end
    local arch = #b >= 20 and ELF_ARCH[b[5] .. ":" .. b[19]]
    for req, dir in pairs(m.bundled) do
      local base = m.path .. "/" .. dir .. "/"
      local sc, so = base .. req .. ".sc.in", arch and (base .. arch .. "/" .. req .. ".so.in")
      if arch and util.file_exists(sc) and util.file_exists(so) and not util.file_exists(_path.data .. "twins/skip_" .. req .. "_" .. arch) then
        m.bundled_ok[req] = { sc = sc, so = so, skip = _path.data .. "twins/skip_" .. req .. "_" .. arch }
        m.requirements[#m.requirements + 1] = req
      end
    end
  end
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

function Installer:missing()
  local missing, detail = probe(self.requirements)
  local gone = {}
  for _, req in ipairs(missing) do gone[req] = true end
  for req, b in pairs(self.bundled_ok) do
    if not gone[req] then
      local same = util.os_capture(string.format("cmp -s '%s' '%s/%s.sc' && cmp -s '%s' '%s/%s.so' && echo ok", b.sc, BUNDLE_DIR, req, b.so, BUNDLE_DIR, req))
      if trim(same) ~= "ok" then missing[#missing + 1] = req end
    end
  end
  return missing, detail
end

function Installer:scan()
  if self.zip == nil or self.zip == "" then print("[installer] NEED TO SPECIFY ZIP FILE") end
  self.requirements     = self.requirements or {}
  self.ready_to_restart = false
  self.installing       = false
  self.satisfied        = false
  self.install_error    = nil
  local missing, detail = self:missing()
  for _, req in ipairs(missing) do
    print(string.format("[installer] missing %s (class file: %s, server plugin: %s)",
      req, detail[req] and detail[req].sc and "yes" or "NO", detail[req] and detail[req].so and "yes" or "NO"))
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
  local names, cmds, copy = {}, {}, {}
  for _, req in ipairs(self.missing_requirements) do
    local b = self.bundled_ok[req]
    if b then
      copy[#copy + 1] = string.format("if python3 -c 'import ctypes,sys; ctypes.CDLL(sys.argv[1])' '%s' >/dev/null 2>&1; then find '%s' \\( -name '%s.sc' -o -name '%s.so' -o -name '%s_scsynth.so' \\) -type f -delete; cp '%s' '%s/%s.sc'; cp '%s' '%s/%s.so'; else echo SKIP:%s; fi",
        b.so, USER_EXT, req, req, req, b.sc, BUNDLE_DIR, req, b.so, BUNDLE_DIR, req, req)
    else
      for _, h in ipairs({ halves(req) }) do
        names[#names + 1] = string.format("-name '%s'", h[1])
      end
    end
  end
  if #names > 0 then
    print(string.format("[installer] downloading %s", self.zip))
    self.message_progress = "Downloading..."
    cmds = {
      string.format("rm -rf %s", TMP_DIR),
      string.format("mkdir -p %s '%s'", TMP_DIR, EXTENSIONS_DIR),
      string.format("wget -q -O %s/bundle.zip '%s'", TMP_DIR, self.zip),
      string.format("cd %s", TMP_DIR),
      "unzip -o -q bundle.zip",
      string.format("find . \\( %s \\) -type f -exec cp {} '%s/' ';'", table.concat(names, " -o "), EXTENSIONS_DIR),
      "cd /tmp",
      "rm -rf norns-installer",
    }
  end
  if #copy > 0 then
    cmds[#cmds + 1] = string.format("mkdir -p '%s'", BUNDLE_DIR)
    for _, c in ipairs(copy) do cmds[#cmds + 1] = c end
  end
  norns.system_cmd(table.concat(cmds, " && ") .. " 2>&1; echo _done_", function(out)
    for req in tostring(out):gmatch("SKIP:(%w+)") do
      local b = self.bundled_ok[req]
      if b then
        util.make_dir(_path.data .. "twins")
        local f = io.open(b.skip, "w")
        if f then f:write("1") f:close() end
        print("[installer] " .. req .. " can't load on this system; using built-in grains")
        self.bundled_ok[req] = nil
        for i = #self.requirements, 1, -1 do if self.requirements[i] == req then table.remove(self.requirements, i) end end
      end
    end
    local still_missing = self:missing()
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

local MSG = {
  nogit = {"Not Installed via Git", "Reinstall from maiden"},
  offline = {"Can't Reach Server", "Check WiFi and try again"},
  current = {"Twins is Up to Date", "Nothing new to install"},
  edited = {"Update Skipped", "Local files were modified"},
  failed = {"Update Failed", "Check WiFi and try again"}
}

function Installer:check(manual)
  if not self.satisfied then return end
  local u, s = self.update, self.update.state
  if s == "checking" then if manual then u.state = "searching" end return end
  if s and s ~= "info" and s ~= "update" then return end
  u.state = manual and "searching" or "checking"
  local g = "nice -n 19 git -C '" .. self.path .. "' "
  norns.system_cmd("if " .. g .. "rev-parse --is-inside-work-tree >/dev/null 2>&1; then timeout -k 5 20 " .. g .. "fetch --quiet 2>/dev/null; echo F$?; echo B$(" .. g .. "rev-list --count HEAD..@{u} 2>/dev/null); echo D$(" .. g .. "status --porcelain --untracked-files=no 2>/dev/null | wc -l); fi; echo _done_", function(out)
    out = out or ""
    local f = out:match("F(%d+)")
    u.behind = tonumber(out:match("B(%d+)")) or 0
    local msg = not f and MSG.nogit or f ~= "0" and MSG.offline
      or u.behind <= 0 and MSG.current
      or (tonumber(out:match("D(%d+)")) or 0) > 0 and MSG.edited
    if not msg then u.state = "update" return end
    print("[installer] " .. msg[1] .. ": " .. msg[2])
    u.state, u.message = u.state == "searching" and "info" or nil, msg
  end)
end

function Installer:install_update()
  self.update.state = "installing"
  self.update.message = nil
  norns.system_cmd("git -C '" .. self.path .. "' pull --ff-only 2>&1", function()
    if (tonumber(git(self, "rev-list --count HEAD..@{u}")) or 0) == 0 then
      if git(self, "diff --name-only ORIG_HEAD..HEAD -- '*.sc' '*.scd'") ~= "" then
        self.update.state = "restart"
      else
        self.update.state = "reloading"
        clock.run(function() clock.sleep(0.4) norns.rerun() end)
      end
    else
      self.update.message = MSG.failed
      self.update.state = "info"
    end
  end)
end

function Installer:do_restart()
  self.update.state = "restarting"
  os.execute(RESTART_CMD)
end

local PENDING = {update = true, installing = true, reloading = true, searching = true, restart = true, restarting = true, info = true}

function Installer:pending()
  return PENDING[self.update.state] == true
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
  elseif s == "info" then
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
  elseif s == "searching" then
    screen.move(64, 28); screen.text_center("Checking for Updates...")
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
  elseif s == "info" then
    local m = self.update.message or MSG.failed
    screen.move(64, 18); screen.text_center(m[1])
    screen.level(1)
    screen.move(64, 30); screen.text_center(m[2])
    screen.level(15)
    screen.move(64, 46); screen.text_center("K2/K3: Dismiss")
  end
  screen.update()
end

return Installer