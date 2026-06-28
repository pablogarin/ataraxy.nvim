local M = {}

function M.init(orig_bufnr)
  orig_bufnr = orig_bufnr or vim.api.nvim_get_current_buf()
  local orig_lines = vim.api.nvim_buf_get_lines(orig_bufnr, 0, -1, false)
  local orig_win   = vim.api.nvim_get_current_win()

  local scratch_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype",   "nofile", { buf = scratch_buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe",   { buf = scratch_buf })
  vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, orig_lines)

  -- Open vertical split; scratch buffer goes in the new (right) window
  vim.cmd("vsplit")
  local scratch_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(scratch_win, scratch_buf)

  -- Enable diff on both windows
  vim.api.nvim_set_current_win(orig_win)
  vim.cmd("diffthis")
  vim.api.nvim_set_current_win(scratch_win)
  vim.cmd("diffthis")

  return {
    orig_buf   = orig_bufnr,
    scratch_buf = scratch_buf,
    orig_win   = orig_win,
    scratch_win = scratch_win,
  }
end

local function close_scratch(state)
  if vim.api.nvim_win_is_valid(state.scratch_win) then
    vim.api.nvim_win_close(state.scratch_win, true)
  end
  if vim.api.nvim_buf_is_valid(state.scratch_buf) then
    vim.api.nvim_buf_delete(state.scratch_buf, { force = true })
  end
  if vim.api.nvim_win_is_valid(state.orig_win) then
    vim.api.nvim_set_current_win(state.orig_win)
    vim.cmd("diffoff")
  end
end

-- T-034: copy scratch → original, then wipe scratch
function M.accept(state)
  local lines = vim.api.nvim_buf_get_lines(state.scratch_buf, 0, -1, false)
  close_scratch(state)
  if vim.api.nvim_buf_is_valid(state.orig_buf) then
    vim.api.nvim_buf_set_lines(state.orig_buf, 0, -1, false, lines)
  end
end

-- T-035: wipe scratch without touching original
function M.reject(state)
  close_scratch(state)
end

-- T-036: terminate stream, leave scratch in partial state
function M.cancel(state)
  local api = require("ataraxy.api")
  api.cancel()
  -- scratch buffer intentionally left open in partial state
  _ = state
end

function M.setup_keymaps(state, opts)
  opts = opts or {}
  local accept_key = opts.prompt_accept or "<C-y>"
  local reject_key = opts.prompt_reject or "<C-n>"
  local cancel_key = opts.prompt_cancel or "<C-x>"
  local buf = state.scratch_buf
  local km_opts = { silent = true, buffer = buf }

  vim.keymap.set("n", accept_key, function() M.accept(state) end, km_opts)
  vim.keymap.set("n", reject_key, function() M.reject(state) end, km_opts)
  vim.keymap.set("n", cancel_key, function() M.cancel(state) end, km_opts)
end

return M
