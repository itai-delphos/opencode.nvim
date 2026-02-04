---Debug utilities for opencode
local M = {}

-- Log file path
local log_file = vim.fn.stdpath("cache") .. "/opencode-debug.log"

---Check if debug logging is enabled
---@return boolean
local function is_enabled()
  local ok, config = pcall(require, "opencode.config")
  return ok and config.opts.debug == true
end

---Initialize debug logging (clear old log)
function M.init()
  if not is_enabled() then
    return
  end
  
  local f = io.open(log_file, "w")
  if f then
    f:write("=== OpenCode Debug Log ===\n")
    f:write("Started at: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
    f:close()
  end
end

---Log a debug message to both notify and file
---@param msg string The message to log
---@param level? number Vim log level (default: INFO)
function M.log(msg, level)
  if not is_enabled() then
    return
  end
  
  level = level or vim.log.levels.INFO
  
  -- Show in Neovim
  vim.notify(msg, level)
  
  -- Write to file
  local f = io.open(log_file, "a")
  if f then
    local timestamp = os.date("%H:%M:%S")
    local level_name = ({"TRACE", "DEBUG", "INFO", "WARN", "ERROR"})[level] or "INFO"
    f:write(string.format("[%s] [%s] %s\n", timestamp, level_name, msg))
    f:close()
  end
end

---Get the log file path
---@return string path
function M.get_log_path()
  return log_file
end

---Open the log file in a split
function M.open_log()
  vim.cmd("split " .. log_file)
end

return M
