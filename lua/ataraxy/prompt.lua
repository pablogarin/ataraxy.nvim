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

-- Strip prefix and suffix echo from a completion response.
-- LLMs frequently repeat text already present in <PREFIX> or <SUFFIX>.
function M.strip_echo(response, prefix, bufnr, row, suffix)
  if response == "" then return response end

  -- Strip prefix tail echo from the start.
  local tail = prefix:match("([^\n]*)$") or ""
  if tail ~= "" and response:sub(1, #tail) == tail then
    response = response:sub(#tail + 1)
    response = response:match("^\n(.*)") or response
  end

  if response == "" then return response end

  -- Discard leading lines already present verbatim in the ±5-line buffer window.
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
  response = table.concat(lines, "\n", start_idx)

  -- Strip suffix_head echo from the end.
  -- suffix_head is the text on the cursor line after the cursor column.
  -- If the LLM echoed it at the tail of the response, remove it so that
  -- ghost_commit does not double-insert it when it appends the buffer's
  -- trailing content.
  if suffix and suffix ~= "" then
    local suffix_head = suffix:match("^([^\n]*)")
    if suffix_head and suffix_head ~= "" then
      local r = response:match("^(.-)\n*$") or response
      if #suffix_head > 0 and r:sub(-#suffix_head) == suffix_head then
        r = r:sub(1, -(#suffix_head + 1))
        response = r:match("^(.-)\n*$") or r
      end
    end
  end

  return response
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

-- Internal: Python triple-quoted docstring block containing cursor_row.
-- Scans backward collecting all standalone-delimiter rows; an odd count means
-- cursor is inside the block, an even count where the nearest row equals
-- cursor_row means cursor is on the closing delimiter.
local function find_python_docstring(lines, cursor_row)
  for _, delim in ipairs({ '"""', "'''" }) do
    local delim_rows = {}
    for r = cursor_row, math.max(0, cursor_row - 100), -1 do
      local stripped = (lines[r + 1] or ""):match("^%s*(.*)") or ""
      if stripped:sub(1, #delim) == delim then
        local after = stripped:sub(#delim + 1)
        if not after:find(delim, 1, true) then
          table.insert(delim_rows, r)
        end
      end
    end

    local open_row = nil
    if #delim_rows % 2 == 1 then
      open_row = delim_rows[#delim_rows]
    elseif #delim_rows >= 2 and delim_rows[1] == cursor_row then
      if (#delim_rows - 1) % 2 == 1 then
        open_row = delim_rows[#delim_rows]
      end
    end

    if open_row then
      local close_row = nil
      for r = open_row + 1, math.min(#lines - 1, open_row + 300) do
        if (lines[r + 1] or ""):find(delim, 1, true) then
          close_row = r
          break
        end
      end
      if close_row and cursor_row >= open_row and cursor_row <= close_row then
        local doc_lines = {}
        for r = open_row, close_row do
          table.insert(doc_lines, lines[r + 1] or "")
        end
        return { text = table.concat(doc_lines, "\n"), start_row = open_row, end_row = close_row }
      end
    end
  end
  return nil
end

-- Internal: JSDoc block (/** ... */) containing cursor_row.
local function find_jsdoc_block(lines, cursor_row)
  local open_row = nil
  for r = cursor_row, math.max(0, cursor_row - 100), -1 do
    local line = lines[r + 1] or ""
    if line:match("/%*%*") then open_row = r; break end
    if r < cursor_row and line:match("%*/") then break end
  end
  if not open_row then return nil end
  local close_row = nil
  for r = open_row, math.min(#lines - 1, open_row + 200) do
    if (lines[r + 1] or ""):match("%*/") then close_row = r; break end
  end
  if not (close_row and cursor_row >= open_row and cursor_row <= close_row) then
    return nil
  end
  local doc_lines = {}
  for r = open_row, close_row do
    table.insert(doc_lines, lines[r + 1] or "")
  end
  return { text = table.concat(doc_lines, "\n"), start_row = open_row, end_row = close_row }
end

-- Internal: contiguous line-comment block (Lua ---, or // for other langs).
local function find_line_comment_block(lines, cursor_row, pattern)
  if not (lines[cursor_row + 1] or ""):match(pattern) then return nil end
  local start_row = cursor_row
  for r = cursor_row - 1, math.max(0, cursor_row - 100), -1 do
    if (lines[r + 1] or ""):match(pattern) then start_row = r else break end
  end
  local end_row = cursor_row
  for r = cursor_row + 1, math.min(#lines - 1, cursor_row + 100) do
    if (lines[r + 1] or ""):match(pattern) then end_row = r else break end
  end
  local doc_lines = {}
  for r = start_row, end_row do
    table.insert(doc_lines, lines[r + 1] or "")
  end
  return { text = table.concat(doc_lines, "\n"), start_row = start_row, end_row = end_row }
end

-- Internal: find the last row (0-indexed) of a function starting at start_row.
local function find_func_end(lines, start_row, filetype)
  local total = #lines
  if filetype == "python" then
    local base_indent = #((lines[start_row + 1] or ""):match("^(%s*)") or "")
    local last_body = start_row
    for r = start_row + 1, total - 1 do
      local line = lines[r + 1] or ""
      if line:match("%S") then
        local indent = #(line:match("^(%s*)") or "")
        if indent <= base_indent then return last_body end
        last_body = r
      end
    end
    return last_body
  elseif filetype == "lua" then
    local depth = 0
    for r = start_row, total - 1 do
      local line = lines[r + 1] or ""
      for _ in line:gmatch("%f[%w]function%f[%W]") do depth = depth + 1 end
      for _ in line:gmatch("%f[%w]end%f[%W]") do
        depth = depth - 1
        if depth <= 0 then return r end
      end
    end
    return total - 1
  else
    local depth = 0
    for r = start_row, total - 1 do
      local line = lines[r + 1] or ""
      for _ in line:gmatch("{") do depth = depth + 1 end
      for _ in line:gmatch("}") do
        depth = depth - 1
        if depth == 0 then return r end
      end
    end
    return total - 1
  end
end

-- Returns {text, start_row, end_row, empty} if cursor is inside/on a docstring block, else nil.
-- `empty` is true when the body has no meaningful content (caller should suppress completion).
function M.detect_docstring(bufnr, row)
  local filetype = vim.bo[bufnr].filetype
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local result
  if filetype == "python" then
    result = find_python_docstring(lines, row)
  elseif filetype == "javascript" or filetype == "typescript"
      or filetype == "javascriptreact" or filetype == "typescriptreact" then
    result = find_jsdoc_block(lines, row)
  elseif filetype == "lua" then
    result = find_line_comment_block(lines, row, "^%s*%-%-%-")
  else
    result = find_line_comment_block(lines, row, "^%s*//")
  end

  if not result then return nil end

  -- Determine if the docstring body has meaningful content.
  local has_content = false
  for _, raw in ipairs(vim.split(result.text, "\n", { plain = true })) do
    local line = raw:match("^%s*(.-)%s*$") or ""
    local body
    if filetype == "python" then
      if line ~= '"""' and line ~= "'''" then body = line end
    elseif filetype == "javascript" or filetype == "typescript"
        or filetype == "javascriptreact" or filetype == "typescriptreact" then
      if line ~= "/**" and line ~= "*/" then
        body = line:match("^%*%s?(.+)") or (line ~= "*" and line or "")
      end
    elseif filetype == "lua" then
      body = line:match("^%-%-%-(.+)")
    else
      body = line:match("^//(.+)")
    end
    if body and body:match("%S") then
      has_content = true
      break
    end
  end
  result.empty = not has_content
  return result
end

-- Extracts the function/method name from the first meaningful line of ghost text.
function M.extract_func_name_from_text(text, filetype)
  local first = (text:match("^%s*([^\n]+)") or ""):match("^%s*(.-)%s*$")
  if filetype == "python" then
    return first:match("def%s+([%w_]+)%s*%(")
  elseif filetype == "javascript" or filetype == "typescript"
      or filetype == "javascriptreact" or filetype == "typescriptreact" then
    return first:match("^%s*async%s+function%s+([%w_]+)%s*%(")
        or first:match("^%s*function%s+([%w_]+)%s*%(")
        or first:match("^%s*([%w_]+)%s*[:=]%s*%(?%s*async%s+function")
        or first:match("^%s*export%s+[%w_]+%s+function%s+([%w_]+)%s*%(")
  elseif filetype == "lua" then
    return first:match("local%s+function%s+([%w_]+)%s*%(")
        or first:match("function%s+([%w_%.]+)%s*%(")
        or first:match("^%s*([%w_]+)%s*=%s*function")
  elseif filetype == "go" then
    return first:match("func%s+%b()%s+([%w_]+)%s*%(")
        or first:match("func%s+([%w_]+)%s*%(")
  elseif filetype == "rust" then
    return first:match("fn%s+([%w_]+)%s*%(")
  else
    return first:match("[%s%*]([%w_]+)%s*%(") or first:match("^([%w_]+)%s*%(")
  end
end

-- Finds an existing function by name and returns {start_row, end_row} (0-indexed) or nil.
function M.find_func_in_buffer(bufnr, func_name, filetype)
  if not func_name or func_name == "" then return nil end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local esc = vim.pesc(func_name)

  local patterns
  if filetype == "python" then
    patterns = { "def%s+" .. esc .. "%s*%(" }
  elseif filetype == "javascript" or filetype == "typescript"
      or filetype == "javascriptreact" or filetype == "typescriptreact" then
    patterns = {
      "function%s+" .. esc .. "%s*%(",
      "async%s+function%s+" .. esc .. "%s*%(",
      esc .. "%s*=%s*function",
      esc .. "%s*[:=]%s*%(.*%)%s*[={]",
    }
  elseif filetype == "lua" then
    patterns = {
      "function%s+" .. esc .. "%s*%(",
      "local%s+function%s+" .. esc .. "%s*%(",
      esc .. "%s*=%s*function",
    }
  elseif filetype == "go" then
    patterns = { "func%s+%b()%s+" .. esc .. "%s*%(", "func%s+" .. esc .. "%s*%(" }
  elseif filetype == "rust" then
    patterns = { "fn%s+" .. esc .. "%s*%(", "pub%s+fn%s+" .. esc .. "%s*%(" }
  else
    patterns = { "[%s%*]" .. esc .. "%s*%(", "^" .. esc .. "%s*%(" }
  end

  for i, line in ipairs(lines) do
    for _, pat in ipairs(patterns) do
      if line:match(pat) then
        local start_row = i - 1
        return { start_row = start_row, end_row = find_func_end(lines, start_row, filetype) }
      end
    end
  end
  return nil
end

-- Builds the messages for the secondary suffix-safety check.
-- The model responds with "replace" or "keep".
function M.build_suffix_check_messages(filetype, ghost_text, suffix)
  return {
    {
      role = "user",
      content = string.format(
        "Language: %s\nReplacement: %s\nTrailing suffix: %s",
        filetype, ghost_text, suffix
      ),
    },
  }
end

-- Builds the messages for docstring-driven function generation.
function M.build_docstring_messages(filetype, prefix, docstring_text, suffix)
  return {
    {
      role = "user",
      content = string.format(
        "Language: %s\n\nFile context (prefix):\n%s\n\nDocstring:\n%s\n\nFile context (suffix):\n%s",
        filetype, prefix, docstring_text, suffix
      ),
    },
  }
end

return M
