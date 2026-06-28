local M = {}

function M.setup(opts)
  local config = require("ataraxy.config")
  local cfg = config.load(opts)
  if not cfg.enabled then
    return
  end

  local api     = require("ataraxy.api")
  local ghost   = require("ataraxy.completion.ghost")
  local trigger = require("ataraxy.completion.trigger")
  local keymap  = require("ataraxy.completion.keymap")

  ghost.setup()

  local function dispatch()
    local buf  = require("ataraxy.context.buffer")
    local ctx  = buf.get_context()
    local fim  = buf.build_fim_prompt(ctx.prefix, ctx.suffix)
    local payload = buf.build_request_payload(fim, cfg)
    local bufnr   = vim.api.nvim_get_current_buf()
    local cursor  = vim.api.nvim_win_get_cursor(0)
    local accumulated = ""
    api.request(cfg, payload, function(token)
      accumulated = accumulated .. token
      ghost.show(bufnr, cursor[1], cursor[2], accumulated)
    end, function() end)
  end

  local group = vim.api.nvim_create_augroup("Ataraxy", { clear = true })

  -- T-021/T-023: auto-trigger with cancellation on TextChangedI
  if cfg.trigger == "auto" then
    vim.api.nvim_create_autocmd("TextChangedI", {
      group = group,
      callback = function()
        if api.is_active() then
          api.cancel()
        end
        trigger.reset(cfg.debounce_ms, dispatch)
      end,
    })
  end

  -- T-022: manual trigger keymap
  if cfg.trigger == "manual" then
    local manual_key = opts.manual_key or "<M-\\>"
    vim.keymap.set("i", manual_key, function()
      dispatch()
    end, { silent = true, desc = "Ataraxy: trigger completion" })
  end

  -- T-028: InsertLeave cleanup
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    callback = function()
      ghost.clear(vim.api.nvim_get_current_buf())
      api.cancel()
    end,
  })

  keymap.setup()

  -- T-030: Normal Mode keybinding to open Prompt Mode
  local prompt_key = opts.prompt_key or "<leader>p"
  vim.keymap.set("n", prompt_key, function()
    local ui        = require("ataraxy.prompt.ui")
    local workspace = require("ataraxy.prompt.workspace")
    local stream    = require("ataraxy.prompt.stream")

    ui.open(function(instruction)
      local orig_bufnr = vim.api.nvim_get_current_buf()
      local state = workspace.init(orig_bufnr)
      stream.reset()

      local orig_lines = vim.api.nvim_buf_get_lines(orig_bufnr, 0, -1, false)
      local code_context = table.concat(orig_lines, "\n")

      local payload = {
        model = cfg.model,
        stream = true,
        messages = {
          { role = "system", content = ui.system_prompt() },
          { role = "user",   content = instruction .. "\n\n" .. code_context },
        },
      }

      workspace.setup_keymaps(state, opts)
      api.request(cfg, payload, function(token)
        stream.write(state.scratch_buf, token)
      end, function() end)
    end, nil)
  end, { silent = true, desc = "Ataraxy: open Prompt Mode" })
end

return M
