local M = {}

local _accumulated = ""

function M.reset()
  _accumulated = ""
end

function M.get_accumulated()
  return _accumulated
end

function M.write(scratch_bufnr, token)
  _accumulated = _accumulated .. token
  local lines = vim.split(_accumulated, "\n", { plain = true })
  if vim.api.nvim_buf_is_valid(scratch_bufnr) then
    vim.api.nvim_buf_set_lines(scratch_bufnr, 0, -1, false, lines)
  end
end

return M
