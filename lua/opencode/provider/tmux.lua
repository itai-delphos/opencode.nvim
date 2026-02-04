---Provide `opencode` in a [`tmux`](https://github.com/tmux/tmux) pane in the current window.
---@class opencode.provider.Tmux : opencode.Provider
---
---@field opts opencode.provider.tmux.Opts
---
---The `tmux` pane ID where `opencode` is running (internal use only).
---@field pane_id? string
---
---Cached port of the `opencode` server (internal use only).
---@field port? number
local Tmux = {}
Tmux.__index = Tmux
Tmux.name = "tmux"

---@class opencode.provider.tmux.Opts
---
---`tmux` options for creating the pane.
---@field options? string
---
---Focus the opencode pane when created. Default: `false`
---@field focus? boolean
--
---Allow `allow-passthrough` on the opencode pane.
-- When enabled, opencode.nvim will use your configured tmux `allow-passthrough` option on its pane.
-- This allows opencode to use OSC escape sequences, but may leak escape codes to the buffer
-- (e.g., "=31337;OK" appearing in your buffer).
--
-- Limitations of having allow-passthrough disabled in the opencode pane:
-- - can't display images
-- - can't use special (terminal specific; non-system) clipboards
-- - may have issues setting window properties like the title from the pane
--
-- If you enable this, consider also enabling `focus` to auto-focus the pane on creation,
-- which can help avoid OSC code leakage while opencode is sending escape sequences on startup.
--
-- Default: `false` (allow-passthrough is disabled to prevent OSC code leakage)
---@field allow_passthrough? boolean

---@param opts? opencode.provider.tmux.Opts
---@return opencode.provider.Tmux
function Tmux.new(opts)
  local self = setmetatable({}, Tmux)
  self.opts = opts or {}
  self.pane_id = nil
  self.port = nil
  return self
end

---Check if we're running in a `tmux` session.
function Tmux.health()
  if vim.fn.executable("tmux") ~= 1 then
    return "`tmux` executable not found in `$PATH`.", {
      "Install `tmux` and ensure it's in your `$PATH`.",
    }
  end

  if not vim.env.TMUX then
    return "Not running in a `tmux` session.", {
      "Launch Neovim in a `tmux` session.",
    }
  end

  return true
end

---Get the `tmux` pane ID where we started `opencode`, if it still exists.
---Ideally we'd find existing panes by title or command, but `tmux` doesn't make that straightforward.
---@return string|nil pane_id
function Tmux:get_pane_id()
  local debug = require("opencode.util.debug")
  local ok = self.health()
  if ok ~= true then
    error(ok, 0)
  end

  if self.pane_id then
    -- Confirm it still exists
    local check_cmd = "tmux list-panes -t " .. self.pane_id
    local check_result = vim.fn.system(check_cmd)
    debug.log("[TMUX] get_pane_id: checking pane=" .. self.pane_id .. " result=" .. vim.trim(check_result):sub(1, 50), vim.log.levels.DEBUG)
    if check_result:match("can't find pane") then
      debug.log("[TMUX] get_pane_id: pane not found, clearing", vim.log.levels.WARN)
      self.pane_id = nil
    end
  else
    debug.log("[TMUX] get_pane_id: no pane_id stored", vim.log.levels.DEBUG)
  end

  debug.log("[TMUX] get_pane_id: returning pane_id=" .. tostring(self.pane_id), vim.log.levels.INFO)
  return self.pane_id
end

---Create or kill the `opencode` pane.
function Tmux:toggle()
  local pane_id = self:get_pane_id()
  if pane_id then
    self:stop()
  else
    self:start()
  end
end

---Start `opencode` in pane.
function Tmux:start()
  local debug = require("opencode.util.debug")
  local pane_id = self:get_pane_id()
  if not pane_id then
    -- Create new pane
    local detach_flag = self.opts.focus and "" or "-d"
    local cmd = string.format("tmux split-window %s -P -F '#{pane_id}' %s '%s'", detach_flag, self.opts.options or "", self.cmd)
    debug.log("[TMUX] start: creating pane with cmd: " .. cmd, vim.log.levels.INFO)
    
    local output = vim.fn.system(cmd)
    debug.log("[TMUX] start: raw output='" .. output .. "' length=" .. #output, vim.log.levels.INFO)
    
    self.pane_id = vim.trim(output)
    debug.log("[TMUX] start: trimmed pane_id='" .. self.pane_id .. "' length=" .. #self.pane_id, vim.log.levels.INFO)
    
    local disable_passthrough = self.opts.allow_passthrough ~= true -- default true (disable passthrough)
    if disable_passthrough and self.pane_id and self.pane_id ~= "" then
      vim.fn.system(string.format("tmux set-option -t %s -p allow-passthrough off", self.pane_id))
      debug.log("[TMUX] start: disabled passthrough for pane " .. self.pane_id, vim.log.levels.DEBUG)
    end
  else
    debug.log("[TMUX] start: pane already exists: " .. pane_id, vim.log.levels.INFO)
  end
end

---Kill the `opencode` pane.
function Tmux:stop()
  local pane_id = self:get_pane_id()
  if pane_id then
    vim.fn.system("tmux kill-pane -t " .. pane_id)
    self.pane_id = nil
    self.port = nil
  end
end

---Get the PID of the shell process running in the opencode pane.
---@return number|nil pid
function Tmux:get_pane_process_pid()
  local debug = require("opencode.util.debug")
  local pane_id = self:get_pane_id()
  if not pane_id then
    debug.log("[TMUX] get_pane_process_pid: no pane_id", vim.log.levels.WARN)
    return nil
  end

  -- Use display-message to get the PID of the specific pane
  local cmd = "tmux display-message -p -t " .. pane_id .. " '#{pane_pid}'"
  local output = vim.fn.system(cmd)
  local trimmed = vim.trim(output)
  local pid = tonumber(trimmed)
  debug.log("[TMUX] get_pane_process_pid: cmd=" .. cmd .. " output='" .. trimmed .. "' pid=" .. tostring(pid), vim.log.levels.INFO)
  return pid
end

---Get the port of the opencode server started in this pane.
---Traces from pane PID through descendants to find the listening port.
---Caches the result for subsequent calls.
---@return number|nil port
function Tmux:get_port()
  local debug = require("opencode.util.debug")
  -- Return cached port if pane still exists
  if self.port and self:get_pane_id() then
    debug.log("[TMUX] get_port: returning cached port=" .. self.port, vim.log.levels.INFO)
    return self.port
  end

  local pane_pid = self:get_pane_process_pid()
  if not pane_pid then
    debug.log("[TMUX] get_port: no pane_pid, returning nil", vim.log.levels.WARN)
    return nil
  end

  debug.log("[TMUX] get_port: searching for listening port in descendants of pid=" .. pane_pid, vim.log.levels.INFO)
  local process = require("opencode.util.process")
  self.port = process.get_descendant_listening_port(pane_pid, 3)
  debug.log("[TMUX] get_port: found port=" .. tostring(self.port), vim.log.levels.INFO)
  return self.port
end

return Tmux
