local M = {}

local SYSTEM_PROMPT =
  "You are a code assistant. Return ONLY the modified code with no prose explanation, " ..
  "no introductory text, and no markdown code fences unless they are part of the code " ..
  "itself. Output the complete file content, ready to be written directly to disk."

function M.system_prompt()
  return SYSTEM_PROMPT
end

local function close_win(win, buf)
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

-- Extracted handler: read instruction from buf, close, dispatch callbacks.
-- Exported so tests can invoke submit logic directly.
function M.submit(buf, win, on_submit, on_cancel)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local instruction = table.concat(lines, "\n"):match("^%s*(.-)%s*$")
  close_win(win, buf)
  if instruction and instruction ~= "" then
    on_submit(instruction)
  elseif on_cancel then
    on_cancel()
  end
end

function M.open(on_submit, on_cancel)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })

  local width  = math.max(40, math.floor(vim.o.columns * 0.6))
  local height = 3
  local row    = math.floor((vim.o.lines - height) / 2)
  local col    = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative  = "editor",
    row       = row,
    col       = col,
    width     = width,
    height    = height,
    style     = "minimal",
    border    = "rounded",
    title     = " Prompt Mode ",
    title_pos = "center",
  })

  vim.cmd("startinsert")

  vim.keymap.set("i", "<CR>", function()
    M.submit(buf, win, on_submit, on_cancel)
  end, { buffer = buf, silent = true })

  vim.keymap.set("i", "<Escape>", function()
    close_win(win, buf)
    if on_cancel then on_cancel() end
  end, { buffer = buf, silent = true })

  return { buf = buf, win = win }
end

return M
