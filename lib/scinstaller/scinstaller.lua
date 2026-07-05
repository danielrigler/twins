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
  self.update_state     = nil
  self.restarting       = false

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
  return self.satisfied and self.update_state == nil
end

function Installer:check_update()
  if not self.satisfied or self.update_state then return end
  local dir = norns.state.path
  local cmd = "cd '" .. dir .. "' 2>/dev/null && "
    .. "git rev-parse --git-dir >/dev/null 2>&1 || { echo NOGIT; exit 0; }; "
    .. "[ -n \"$(git status --porcelain -uno 2>/dev/null)\" ] && { echo DIRTY; exit 0; }; "
    .. "git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 || { echo NOUPSTREAM; exit 0; }; "
    .. "timeout 5 git fetch -q 2>/dev/null || { echo OFFLINE; exit 0; }; "
    .. "b=$(git rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0); "
    .. "a=$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0); "
    .. "echo \"STATUS $b $a\""
  norns.system_cmd(cmd, function(out)
    local b, a = string.match(out or "", "STATUS (%d+) (%d+)")
    if b and tonumber(b) > 0 and tonumber(a) == 0 then
      self.update_state = "offer"
    end
  end)
end

function Installer:update_pull()
  self.update_state = "pulling"
  local dir = norns.state.path
  local cmd = "cd '" .. dir .. "' 2>/dev/null || exit 0; "
    .. "h1=$(cat lib/*.sc 2>/dev/null | md5sum); "
    .. "if timeout 60 git pull --ff-only -q 2>&1; then "
    .. "h2=$(cat lib/*.sc 2>/dev/null | md5sum); "
    .. "if [ \"$h1\" = \"$h2\" ]; then echo PULLOK LUA; else echo PULLOK ENGINE; fi; "
    .. "fi"
  norns.system_cmd(cmd, function(out)
    local kind = string.match(out or "", "PULLOK (%u+)")
    if kind == "LUA" then
      self.update_state = nil
      norns.script.load(norns.state.script)
    elseif kind == "ENGINE" then
      self.update_state = "restart"
    else
      self.update_state = "failed"
    end
  end)
end

function Installer:finish_restart()
  if self.restarting then return end
  self.restarting = true
  self:redraw()
  os.execute("sudo systemd-run --no-block --collect bash -c '"
    .. "systemctl restart norns-jack.service; sleep 3; "
    .. "systemctl restart norns-sclang.service norns-crone.service norns-matron.service' >/dev/null 2>&1")
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
  if self.update_state then
    if z ~= 1 then return end
    if self.update_state == "offer" then
      if k == 2 then self.update_state = nil
      elseif k == 3 then self:update_pull() end
    elseif self.update_state == "restart" then
      if k == 3 then self:finish_restart() end
    elseif self.update_state == "failed" then
      if k == 3 then self.update_state = nil end
    end
    return
  end
  if self.satisfied or self.ready_to_restart or self.installing then return end
  if k == 3 and z == 1 then
    clock.run(function() self:install() end)
  end
end

function Installer:redraw()
  screen.clear()
  screen.blend_mode(0)
  screen.level(15)
  if self.update_state then
    if self.update_state == "offer" then
      screen.move(64, 26); screen.text_center("update available")
      screen.level(8)
      screen.move(64, 44); screen.text_center("K2 = later   K3 = update")
    elseif self.update_state == "pulling" then
      screen.move(64, 32); screen.text_center("updating...")
    elseif self.update_state == "restart" then
      if self.restarting then
        screen.move(64, 32); screen.text_center("restarting...")
      else
        screen.move(64, 26); screen.text_center("engine updated")
        screen.level(8)
        screen.move(64, 44); screen.text_center("K3 = restart")
      end
    else
      screen.move(64, 26); screen.text_center("update failed")
      screen.level(8)
      screen.move(64, 44); screen.text_center("K3 = continue")
    end
    screen.update()
    return
  end
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