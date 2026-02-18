---@class opencode.lsp.Opts
---
---Whether to enable the `opencode` LSP.
---@field enabled boolean
---
---Filetypes to attach to.
---`nil` means all filetypes.
---@field filetypes? string[]

---@type table<vim.lsp.protocol.Method, fun(params: table, callback:fun(err: lsp.ResponseError?, result: any))>
local handlers = {}
local ms = vim.lsp.protocol.Methods

---@param params lsp.InitializeParams
---@param callback fun(err?: lsp.ResponseError, result: lsp.InitializeResult)
handlers[ms.initialize] = function(params, callback)
  callback(nil, {
    capabilities = {
      codeActionProvider = true,
      executeCommandProvider = {
        commands = { "opencode.fix" },
      },
    },
    serverInfo = {
      name = "opencode",
    },
  })
end

---@param params lsp.CodeActionParams
---@param callback fun(err?: lsp.ResponseError, result: lsp.CodeAction[])
handlers[ms.textDocument_codeAction] = function(params, callback)
  local diagnostics = vim.diagnostic.get(0, { lnum = params.range.start.line })
  ---@type lsp.CodeAction[]
  local fix_commands = vim.tbl_map(function(diagnostic)
    return {
      title = "Ask opencode to fix: " .. diagnostic.message,
      command = {
        command = "opencode.fix",
        arguments = { diagnostic },
      },
    }
  end, diagnostics or {})

  callback(nil, fix_commands)
end

---@param params lsp.ExecuteCommandParams
---@param callback fun(err?: lsp.ResponseError, result: any)
handlers[ms.workspace_executeCommand] = function(params, callback)
  if params.command == "opencode.fix" then
    local diagnostic = params.arguments[1]
    ---@cast diagnostic vim.Diagnostic
    local filepath = require("opencode.context").format({ buf = diagnostic.bufnr })
    local prompt = "Fix diagnostic: " .. filepath .. require("opencode.context").format_diagnostic(diagnostic)

    require("opencode")
      .prompt(prompt, { submit = true })
      :next(function()
        callback(nil, nil) -- Indicate success
      end)
      :catch(function(err)
        callback({ code = -32000, message = "Failed to fix: " .. err })
      end)
  else
    callback({ code = -32601, message = "Unknown command: " .. params.command })
  end
end

---An in-process LSP that interacts with `opencode`.
--- - Code actions: ask `opencode` to fix diagnostics under the cursor.
---
---@type vim.lsp.Config
return {
  name = "opencode",
  filetypes = require("opencode.config").opts.lsp.filetypes,
  cmd = function(dispatchers, config)
    return {
      request = function(method, params, callback)
        if handlers[method] then
          handlers[method](params, callback)
        end
      end,
      notify = function() end,
      is_closing = function()
        -- FIX: Stopping/disabling the LSP has no effect...
        -- Not sure if we're supposed to do something?
        -- This loop successfully removes us, but idk where to put it to respond to `vim.lsp.enable false`
        -- `is_closing` gets called, but not `terminate`.
        -- for _, client in ipairs(vim.lsp.get_clients()) do
        --   if client.name == "opencode" then
        --     for bufnr, _ in pairs(client.attached_buffers) do
        --       vim.lsp.buf_detach_client(bufnr, client.id)
        --     end
        --   end
        -- end
        return false
      end,
      terminate = function() end,
    }
  end,
}
