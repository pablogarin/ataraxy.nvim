local M = {}

local PREFIX_LINES = 2000
local SUFFIX_LINES = 500

local IMPORT_PATTERNS = {
  python     = { "^%s*import%s+", "^%s*from%s+%S+%s+import%s+" },
  javascript = { "^%s*import%s+", "^%s*const%s+.+=.+require%s*%(", "^%s*var%s+.+=.+require%s*%(", "^%s*let%s+.+=.+require%s*%(" },
  typescript = { "^%s*import%s+", "^%s*const%s+.+=.+require%s*%(", "^%s*var%s+.+=.+require%s*%(", "^%s*let%s+.+=.+require%s*%(" },
  go         = { "^import%s+", "^import%s*%(" },
  rust       = { "^%s*use%s+%S+%s*;" },
  lua        = { "^%s*local%s+%S+%s*=%s*require%s*%(", "^%s*require%s*%(" },
  c          = { "^%s*#include%s*[<\"]" },
  cpp        = { "^%s*#include%s*[<\"]", "^%s*using%s+namespace%s+" },
}

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

-- Strip any prefix echo from a completion response.
-- LLMs sometimes repeat the partial line at the cursor or nearby buffer lines.
function M.strip_echo(response, prefix, bufnr, row)
  if response == "" then return response end

  local tail = prefix:match("([^\n]*)$") or ""
  if tail ~= "" and response:sub(1, #tail) == tail then
    response = response:sub(#tail + 1)
    response = response:match("^\n(.*)") or response
  end

  if response == "" then return response end

  local win_start = math.max(0, row - 5)
  local win_end = math.min(vim.api.nvim_buf_line_count(bufnr), row + 6)
  local window_lines = vim.api.nvim_buf_get_lines(bufnr, win_start, win_end, false)
  local window_set = {}
  for _, l in ipairs(window_lines) do
    window_set[l] = true
  end

  local lines = vim.split(response, "\n", { plain = true })
  local start_idx = 1
  while start_idx <= #lines and window_set[lines[start_idx]] do
    start_idx = start_idx + 1
  end

  if start_idx > #lines then return "" end
  return table.concat(lines, "\n", start_idx)
end

-- Returns a newline-joined string of all import lines found in the first 100
-- lines of the buffer for the given filetype.
function M.extract_existing_imports(bufnr, filetype)
  local patterns = IMPORT_PATTERNS[filetype] or {}
  local scan_end = math.min(vim.api.nvim_buf_line_count(bufnr), 100)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, scan_end, false)
  local result = {}
  local in_go_block = false

  for _, line in ipairs(lines) do
    if filetype == "go" then
      if line:match("^import%s*%(") then
        in_go_block = true
        table.insert(result, line)
      elseif in_go_block then
        table.insert(result, line)
        if line:match("^%)") then in_go_block = false end
      elseif line:match("^import%s+") then
        table.insert(result, line)
      end
    else
      for _, pat in ipairs(patterns) do
        if line:match(pat) then
          table.insert(result, line)
          break
        end
      end
    end
  end

  return table.concat(result, "\n")
end

-- Returns the 0-indexed buffer row at which new import lines should be
-- inserted (i.e. the row *after* the last existing import block).
function M.find_import_insert_row(bufnr, filetype)
  local patterns = IMPORT_PATTERNS[filetype] or {}
  local scan_end = math.min(vim.api.nvim_buf_line_count(bufnr), 100)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, scan_end, false)
  local last_row = -1
  local in_go_block = false

  for i, line in ipairs(lines) do
    local row = i - 1
    if filetype == "go" then
      if line:match("^import%s*%(") then
        in_go_block = true
        last_row = row
      elseif in_go_block then
        last_row = row
        if line:match("^%)") then in_go_block = false end
      elseif line:match("^import%s+") then
        last_row = row
      end
    else
      for _, pat in ipairs(patterns) do
        if line:match(pat) then
          last_row = row
          break
        end
      end
    end
  end

  return last_row + 1
end

-- Builds the messages for the secondary auto-import resolution request.
function M.build_import_messages(filetype, existing_imports, snippet)
  local parts = { "Language: " .. filetype }
  if existing_imports ~= "" then
    table.insert(parts, "Existing imports:\n" .. existing_imports)
  end
  table.insert(parts, "Snippet:\n" .. snippet)
  return {
    { role = "user", content = table.concat(parts, "\n\n") },
  }
end

return M
