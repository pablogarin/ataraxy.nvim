local M = {}

local PREFIX_LINES = 2000
local SUFFIX_LINES = 500

function M.build_fim(bufnr, row, col)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  row = row or vim.api.nvim_win_get_cursor(0)[1] - 1
  col = col or vim.api.nvim_win_get_cursor(0)[2]

  local total_lines = vim.api.nvim_buf_line_count(bufnr)

  local prefix_start = math.max(0, row - PREFIX_LINES)
  local prefix_lines = vim.api.nvim_buf_get_lines(bufnr, prefix_start, row, false)
  local current_line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  table.insert(prefix_lines, current_line:sub(1, col))

  local suffix_end = math.min(total_lines, row + 1 + SUFFIX_LINES)
  local suffix_lines = vim.api.nvim_buf_get_lines(bufnr, row + 1, suffix_end, false)
  local suffix_tail = current_line:sub(col + 1)
  table.insert(suffix_lines, 1, suffix_tail)

  local prefix = table.concat(prefix_lines, "\n")
  local suffix = table.concat(suffix_lines, "\n")

  return prefix, suffix
end

function M.build_fim_messages(bufnr, row, col)
  local prefix, suffix = M.build_fim(bufnr, row, col)
  local filetype = vim.bo[bufnr or vim.api.nvim_get_current_buf()].filetype or ""

  local user_content = string.format(
    "Language: %s\n\n<PREFIX>\n%s\n</PREFIX>\n\n<SUFFIX>\n%s\n</SUFFIX>",
    filetype, prefix, suffix
  )

  return {
    { role = "user", content = user_content },
  }
end

function M.build_agent_messages(file_content, user_prompt, context_md, skills_text)
  local parts = {}

  if context_md and context_md ~= "" then
    table.insert(parts, "# Workspace Context\n" .. context_md)
  end

  if skills_text and skills_text ~= "" then
    table.insert(parts, "# Active Skills\n" .. skills_text)
  end

  if file_content and file_content ~= "" then
    table.insert(parts, "# Active File\n```\n" .. file_content .. "\n```")
  end

  table.insert(parts, "# Task\n" .. user_prompt)

  return {
    { role = "user", content = table.concat(parts, "\n\n") },
  }
end

return M
