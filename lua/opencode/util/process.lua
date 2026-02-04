---Process utilities for provider implementations.
local M = {}

local debug = require("opencode.util.debug")

---Get all descendant PIDs of a process (children, grandchildren, etc.)
---@param pid number The parent process ID
---@param max_depth? number Maximum recursion depth (default 3)
---@return number[] pids List of descendant PIDs
function M.get_descendants(pid, max_depth)
  max_depth = max_depth or 3
  debug.log("[PROCESS] get_descendants: starting from pid=" .. pid .. " max_depth=" .. max_depth, vim.log.levels.DEBUG)

  local function recurse(current_pid, depth)
    if depth > max_depth then
      debug.log("[PROCESS] get_descendants: max depth reached at " .. depth, vim.log.levels.DEBUG)
      return {}
    end

    local children = {}
    local cmd = "pgrep -P " .. current_pid .. " 2>/dev/null"
    local output = vim.fn.system(cmd)
    debug.log("[PROCESS] get_descendants: depth=" .. depth .. " pid=" .. current_pid .. " pgrep output='" .. vim.trim(output) .. "'", vim.log.levels.DEBUG)
    
    for child_pid in output:gmatch("%d+") do
      local child = tonumber(child_pid)
      table.insert(children, child)
      for _, descendant in ipairs(recurse(child, depth + 1)) do
        table.insert(children, descendant)
      end
    end
    return children
  end

  local descendants = recurse(pid, 1)
  debug.log("[PROCESS] get_descendants: found " .. #descendants .. " descendants: " .. vim.inspect(descendants), vim.log.levels.INFO)
  return descendants
end

---Find the TCP port a process is listening on.
---@param pid number The process ID
---@return number|nil port The listening port, or nil if not found
function M.get_listening_port(pid)
  local cmd = "lsof -w -iTCP -sTCP:LISTEN -P -n -a -p " .. pid .. " 2>/dev/null"
  local lsof_output = vim.fn.system(cmd)
  debug.log("[PROCESS] get_listening_port: pid=" .. pid .. " lsof output='" .. vim.trim(lsof_output):sub(1, 200) .. "'", vim.log.levels.DEBUG)
  
  for line in lsof_output:gmatch("[^\r\n]+") do
    local port = line:match(":(%d+)%s+%(LISTEN%)")
    if port then
      local port_num = tonumber(port)
      debug.log("[PROCESS] get_listening_port: pid=" .. pid .. " found port=" .. port_num, vim.log.levels.INFO)
      return port_num
    end
  end
  
  debug.log("[PROCESS] get_listening_port: pid=" .. pid .. " no port found", vim.log.levels.DEBUG)
  return nil
end

---Find the listening port of any descendant of a process.
---@param pid number The ancestor process ID
---@param max_depth? number Maximum recursion depth (default 3)
---@return number|nil port The listening port, or nil if not found
function M.get_descendant_listening_port(pid, max_depth)
  debug.log("[PROCESS] get_descendant_listening_port: starting search from pid=" .. pid, vim.log.levels.INFO)
  local descendants = M.get_descendants(pid, max_depth)
  
  for _, desc_pid in ipairs(descendants) do
    local port = M.get_listening_port(desc_pid)
    if port then
      debug.log("[PROCESS] get_descendant_listening_port: found port=" .. port .. " on descendant pid=" .. desc_pid, vim.log.levels.INFO)
      return port
    end
  end
  
  debug.log("[PROCESS] get_descendant_listening_port: no listening port found in any descendant", vim.log.levels.WARN)
  return nil
end

return M
