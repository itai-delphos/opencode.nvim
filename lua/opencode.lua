---`opencode.nvim` public API.
local M = {}

-- Initialize debug logging
require("opencode.util.debug").init()

M.ask = require("opencode.ui.ask").ask
M.select = require("opencode.ui.select").select
M.select_session = require("opencode.ui.select_session").select_session

M.prompt = require("opencode.api.prompt").prompt
M.operator = require("opencode.api.operator").operator
M.command = require("opencode.api.command").command

M.toggle = require("opencode.provider").toggle
M.start = require("opencode.provider").start
M.stop = require("opencode.provider").stop

M.statusline = require("opencode.status").statusline

-- Debug utilities
M.debug = {
  open_log = require("opencode.util.debug").open_log,
  get_log_path = require("opencode.util.debug").get_log_path,
  test_pid_tracking = function()
    local debug = require("opencode.util.debug")
    debug.log("=== Starting PID tracking test ===", vim.log.levels.INFO)
    
    local provider = require("opencode.config").provider
    if not provider then
      debug.log("[TEST] No provider configured", vim.log.levels.ERROR)
      return
    end
    
    debug.log("[TEST] Provider: " .. tostring(provider.name), vim.log.levels.INFO)
    
    if provider.get_pane_id then
      local pane_id = provider:get_pane_id()
      debug.log("[TEST] Pane ID: " .. tostring(pane_id), vim.log.levels.INFO)
    end
    
    if provider.get_pane_process_pid then
      local pid = provider:get_pane_process_pid()
      debug.log("[TEST] Pane PID: " .. tostring(pid), vim.log.levels.INFO)
    end
    
    if provider.get_port then
      local port = provider:get_port()
      debug.log("[TEST] Port: " .. tostring(port), vim.log.levels.INFO)
    end
    
    debug.log("=== Test complete ===", vim.log.levels.INFO)
    debug.log("View full log with: :lua require('opencode').debug.open_log()", vim.log.levels.INFO)
  end,
}

return M
