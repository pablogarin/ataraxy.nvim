local M = {}

local NS = vim.api.nvim_create_namespace("ataraxy_ghost")

local _state = {
  bufnr = nil,
  text = nil,
}

function M.show(bufnr, row, col, text)
  if not text or text == "" then return end
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  M.clear(bufnr)

  local lines = {}
  for part in (text .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = part
  end

  -- First line: virtual text appended at cursor column on the current row
  local virt_text = { { lines[1], "Comment" } }

  -- Additional lines: rendered as virt_lines below the cursor row
  local virt_lines = nil
  if #lines > 1 then
    virt_lines = {}
    for i = 2, #lines do
      virt_lines[#virt_lines + 1] = { { lines[i], "Comment" } }
    end
  end

  local opts = {
    virt_text = virt_text,
    virt_text_pos = "overlay",
    hl_mode = "combine",
  }
  if virt_lines then
    opts.virt_lines = virt_lines
  end

  vim.api.nvim_buf_set_extmark(bufnr, NS, row - 1, col, opts)

  _state.bufnr = bufnr
  _state.text = text
end

function M.clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  if _state.bufnr == bufnr then
    _state.bufnr = nil
    _state.text = nil
  end
end

function M.has_ghost(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, NS, 0, -1, { limit = 1 })
  return #marks > 0
end

function M.get_text()
  return _state.text
end

function M.setup()
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = vim.api.nvim_create_augroup("AtaraxyClearOnWrite", { clear = true }),
    callback = function(ev)
      M.clear(ev.buf)
    end,
  })
end

return M
