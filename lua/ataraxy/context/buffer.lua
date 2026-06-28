local M = {}

function M.get_context(bufnr, win)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  win = win or vim.api.nvim_get_current_win()

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines == 0 then
    return { prefix = "", suffix = "" }
  end

  local cursor = vim.api.nvim_win_get_cursor(win)
  local row = cursor[1]  -- 1-indexed
  local col = cursor[2]  -- 0-indexed byte offset

  local current_line = lines[row] or ""

  local prefix_parts = {}
  for i = 1, row - 1 do
    prefix_parts[#prefix_parts + 1] = lines[i]
  end
  prefix_parts[#prefix_parts + 1] = current_line:sub(1, col)

  local suffix_parts = {}
  suffix_parts[#suffix_parts + 1] = current_line:sub(col + 1)
  for i = row + 1, #lines do
    suffix_parts[#suffix_parts + 1] = lines[i]
  end

  return {
    prefix = table.concat(prefix_parts, "\n"),
    suffix = table.concat(suffix_parts, "\n"),
  }
end

local DEFAULT_TOKENS = { prefix = "<PRE>", suffix = "<SUF>", middle = "<MID>" }

function M.build_fim_prompt(prefix, suffix, tokens)
  tokens = tokens or DEFAULT_TOKENS
  return tokens.prefix .. prefix .. tokens.suffix .. suffix .. tokens.middle
end

function M.build_request_payload(fim_prompt, cfg)
  return {
    model = cfg.model,
    messages = { { role = "user", content = fim_prompt } },
    stream = true,
  }
end

return M
