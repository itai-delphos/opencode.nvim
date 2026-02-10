---Provide `opencode` in a [`tmux`](https://github.com/tmux/tmux) pane in the current window.
---@class opencode.provider.Tmux : opencode.Provider
---
---@field opts opencode.provider.tmux.Opts
---
---The `tmux` pane ID where `opencode` is running (internal use only).
---@field pane_id? string
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
  local ok = self.health()
  if ok ~= true then
    error(ok, 0)
  end

  if self.pane_id then
    -- Confirm it still exists
    if vim.fn.system("tmux list-panes -t " .. self.pane_id):match("can't find pane") then
      self.pane_id = nil
    end
  end

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
  local pane_id = self:get_pane_id()
  if not pane_id then
    -- Create new pane
    local detach_flag = self.opts.focus and "" or "-d"
    self.pane_id = vim.trim(vim.fn.system(
      string.format("tmux split-window %s -P -F '#{pane_id}' %s '%s'", detach_flag, self.opts.options or "", self.cmd)
    ))
    local disable_passthrough = self.opts.allow_passthrough ~= true -- default true (disable passthrough)
    if disable_passthrough and self.pane_id and self.pane_id ~= "" then
      vim.fn.system(string.format("tmux set-option -t %s -p allow-passthrough off", self.pane_id))
    end
  end
end

---Get the PID of the shell running in a `tmux` pane.
---@param pane_id string
---@return string|nil
local function get_pane_pid(pane_id)
  local pid = vim.fn.system(string.format("tmux display-message -t '%s' -p '#{pane_pid}'", pane_id))
  pid = vim.trim(pid)
  return (pid ~= "" and pid) or nil
end

---Get all child process IDs in the same process group.
---@param parent_pid string
---@return string[]
local function get_process_group_pids(parent_pid)
  local ps_output = vim.fn.system("ps -o pid= -g $(ps -o pgid= -p " .. parent_pid .. " | tr -d ' ') 2>/dev/null")

  local pids = {}
  if ps_output and ps_output ~= "" then
    for pid in ps_output:gmatch("%d+") do
      pid = vim.trim(pid)
      if pid ~= parent_pid then
        table.insert(pids, pid)
      end
    end
  end

  return pids
end

---Check if a process is still running.
---@param pid string
---@return boolean
local function is_process_running(pid)
  local result = vim.fn.system("ps -p " .. pid .. " -o pid= 2>/dev/null")
  return result and vim.trim(result) ~= ""
end

---Kill a list of processes, trying graceful termination first.
---@param pids string[]
local function kill_processes(pids)
  if #pids == 0 then
    return
  end

  for _, pid in ipairs(pids) do
    vim.fn.system("kill -TERM " .. pid .. " 2>/dev/null")
  end

  vim.wait(200)

  for _, pid in ipairs(pids) do
    if is_process_running(pid) then
      vim.fn.system("kill -KILL " .. pid .. " 2>/dev/null")
    end
  end
end

---Kill the `opencode` pane.
function Tmux:stop()
  local pane_id = self:get_pane_id()
  if not pane_id then
    return
  end

  local pane_pid = get_pane_pid(pane_id)
  if pane_pid then
    kill_processes(get_process_group_pids(pane_pid))
  end

  vim.fn.system("tmux kill-pane -t " .. pane_id)
  self.pane_id = nil
end

return Tmux
