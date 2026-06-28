local M = {}

local function feedkeys(keys)
  local esc = vim.api.nvim_replace_termcodes(keys, true, false, true)
  vim.api.nvim_feedkeys(esc, "n", false)
end

-- Exported so tests can invoke acceptance logic directly.
function M.accept(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ghost = require("ataraxy.completion.ghost")

  if not ghost.has_ghost(bufnr) then
    feedkeys("<Tab>")
    return
  end

  local text = ghost.get_text()
  if not text then
    feedkeys("<Tab>")
    return
  end

  local lines = {}
  for part in (text .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = part
  end

  ghost.clear(bufnr)

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1  -- 0-indexed
  local col = cursor[2]      -- 0-indexed byte

  vim.api.nvim_buf_set_text(bufnr, row, col, row, col, lines)

  local last_row = row + #lines - 1
  local last_col = #lines == 1 and col + #lines[1] or #lines[#lines]
  vim.api.nvim_win_set_cursor(0, { last_row + 1, last_col })
end

-- Exported so tests can invoke dismiss logic directly.
function M.dismiss(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ghost = require("ataraxy.completion.ghost")

  if ghost.has_ghost(bufnr) then
    ghost.clear(bufnr)
    -- Stay in Insert Mode; do not feed Escape
  else
    feedkeys("<Escape>")
  end
end

function M.setup(bufnr)
  bufnr = bufnr or 0
  local opts = { silent = true, buffer = bufnr }
  local resolved = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr

  vim.keymap.set("i", "<Tab>", function()
    M.accept(resolved)
  end, opts)

  vim.keymap.set("i", "<Escape>", function()
    M.dismiss(resolved)
  end, opts)
end

return M
