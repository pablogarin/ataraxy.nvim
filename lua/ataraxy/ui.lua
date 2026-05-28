local M = {}

local ns_id = vim.api.nvim_create_namespace("ataraxy_ghost")

local ghost_state = {
  bufnr = nil,
  text = "",
  row = nil,
  col = nil,
  mark_id = nil,
}

local function render_ghost(text, bufnr, row, col)
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  local lines = vim.split(text, "\n", { plain = true })
  local virt_lines = {}
  for i = 2, #lines do
    table.insert(virt_lines, { { lines[i], "Comment" } })
  end
  local mark_opts = {
    virt_text = { { lines[1], "Comment" } },
    virt_text_pos = "inline",
    hl_mode = "combine",
  }
  if #virt_lines > 0 then
    mark_opts.virt_lines = virt_lines
    mark_opts.virt_lines_above = false
  end
  ghost_state.mark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, row, col, mark_opts)
end

function M.ghost_clear(bufnr)
  bufnr = bufnr or ghost_state.bufnr or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  ghost_state.text = ""
  ghost_state.mark_id = nil
  ghost_state.row = nil
  ghost_state.col = nil
  ghost_state.bufnr = nil
end

function M.ghost_append(token, bufnr, row, col)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if ghost_state.bufnr and ghost_state.bufnr ~= bufnr then
    M.ghost_clear(ghost_state.bufnr)
  end
  ghost_state.bufnr = bufnr
  ghost_state.row = row
  ghost_state.col = col
  ghost_state.text = ghost_state.text .. token
  render_ghost(ghost_state.text, bufnr, row, col)
end

-- Replace the currently displayed ghost text in place. Used by echo stripping
-- to swap the raw streamed response for the sanitised version without touching
-- the buffer or resetting position state.
function M.ghost_set_text(text)
  local bufnr = ghost_state.bufnr
  local row = ghost_state.row
  local col = ghost_state.col
  if not bufnr or row == nil then return end

  ghost_state.text = text
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  if text == "" then
    ghost_state.bufnr = nil
    ghost_state.row = nil
    ghost_state.col = nil
    ghost_state.mark_id = nil
    return
  end

  render_ghost(text, bufnr, row, col)
end

function M.ghost_commit(bufnr, row, col)
  bufnr = bufnr or ghost_state.bufnr or vim.api.nvim_get_current_buf()
  local text = ghost_state.text
  if text == "" then return end

  M.ghost_clear(bufnr)

  local lines = vim.split(text, "\n", { plain = true })
  local current_line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local before = current_line:sub(1, col)
  local after = current_line:sub(col + 1)

  local new_lines = {}
  new_lines[1] = before .. lines[1]
  for i = 2, #lines do
    table.insert(new_lines, lines[i])
  end
  new_lines[#new_lines] = new_lines[#new_lines] .. after

  vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, new_lines)

  local end_row = row + #new_lines - 1
  local end_col = #new_lines[#new_lines] - #after
  vim.api.nvim_win_set_cursor(0, { end_row + 1, end_col })
end

function M.ghost_get_text()
  return ghost_state.text
end

function M.open_agent_input(on_submit, on_cancel)
  local width = math.floor(vim.o.columns * 0.6)
  local height = 8
  local row = math.floor((vim.o.lines - height) / 2)
  local col_pos = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col_pos,
    style = "minimal",
    border = "rounded",
    title = " AtaraxyPrompt  <C-s> / <C-CR> submit  <Esc> cancel ",
    title_pos = "center",
  })

  vim.wo[win].wrap = true

  local function do_submit()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local prompt = table.concat(lines, "\n"):match("^%s*(.-)%s*$")
    vim.api.nvim_win_close(win, true)
    if prompt ~= "" and on_submit then
      on_submit(prompt)
    end
  end

  vim.keymap.set({ "n", "i" }, "<C-s>", do_submit, { buffer = buf, silent = true, noremap = true })
  vim.keymap.set({ "n", "i" }, "<C-CR>", do_submit, { buffer = buf, silent = true, noremap = true })

  vim.keymap.set({ "n", "i" }, "<Esc>", function()
    vim.api.nvim_win_close(win, true)
    if on_cancel then on_cancel() end
  end, { buffer = buf, silent = true, noremap = true })

  vim.cmd("startinsert")
  return buf, win
end

function M.open_diff_view(source_bufnr)
  local scratch_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[scratch_buf].buftype = "nofile"
  vim.bo[scratch_buf].bufhidden = "hide"
  vim.bo[scratch_buf].swapfile = false

  local source_lines = vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false)
  vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, source_lines)

  local source_ft = vim.bo[source_bufnr].filetype
  vim.bo[scratch_buf].filetype = source_ft

  vim.cmd("vsplit")
  local scratch_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(scratch_win, scratch_buf)

  vim.cmd("diffthis")

  local orig_win = nil
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == source_bufnr then
      orig_win = w
      break
    end
  end

  if orig_win then
    vim.api.nvim_set_current_win(orig_win)
    vim.cmd("diffthis")
    vim.api.nvim_set_current_win(scratch_win)
  end

  return scratch_buf, scratch_win
end

function M.close_diff_view(scratch_buf, scratch_win)
  if scratch_win and vim.api.nvim_win_is_valid(scratch_win) then
    vim.api.nvim_win_close(scratch_win, true)
  end
  if scratch_buf and vim.api.nvim_buf_is_valid(scratch_buf) then
    vim.api.nvim_buf_delete(scratch_buf, { force = true })
  end
  vim.cmd("diffoff!")
end

function M.stream_to_buf(bufnr, token)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local last_line = vim.api.nvim_buf_get_lines(bufnr, line_count - 1, line_count, false)[1] or ""

  local parts = vim.split(token, "\n", { plain = true })
  local updated_last = last_line .. parts[1]

  local new_lines = { updated_last }
  for i = 2, #parts do
    table.insert(new_lines, parts[i])
  end

  vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count, false, new_lines)
end

function M.notify(msg, level)
  vim.notify("[ataraxy] " .. msg, level or vim.log.levels.INFO)
end

return M
