local config = require("ataraxy.config")
local prompt_mod = require("ataraxy.prompt")
local api = require("ataraxy.api")
local ui = require("ataraxy.ui")
local context = require("ataraxy.agent.context")
local skills = require("ataraxy.agent.skills")

local M = {}

local state = {
  debounce_timer = nil,
  active_job_id = nil,
  last_fim_bufnr = nil,
  last_fim_row = nil,
  last_fim_col = nil,

  diff_active = false,
  diff_source_bufnr = nil,
  diff_scratch_bufnr = nil,
  diff_scratch_win = nil,
  diff_job_id = nil,
}

local function cancel_active_completion()
  if state.active_job_id then
    api.cancel(state.active_job_id)
    state.active_job_id = nil
  end
  if state.debounce_timer then
    state.debounce_timer:stop()
    state.debounce_timer:close()
    state.debounce_timer = nil
  end
  ui.ghost_clear()
end

local function trigger_completion(bufnr, row, col)
  cancel_active_completion()

  state.last_fim_bufnr = bufnr
  state.last_fim_row = row
  state.last_fim_col = col

  local messages = prompt_mod.build_fim_messages(bufnr, row, col)
  local system_prompt = config.get("system_prompt")

  local accumulated = ""
  state.active_job_id = api.stream(
    messages,
    system_prompt,
    function(token)
      accumulated = accumulated .. token
      ui.ghost_append(token, bufnr, row, col)
    end,
    function()
      state.active_job_id = nil
    end,
    function(err)
      state.active_job_id = nil
      ui.ghost_clear(bufnr)
      ui.notify("Completion error: " .. err, vim.log.levels.ERROR)
    end
  )
end

local function debounced_completion(bufnr, row, col)
  if state.debounce_timer then
    state.debounce_timer:stop()
    state.debounce_timer:close()
    state.debounce_timer = nil
  end

  local debounce_ms = config.get("debounce_ms") or 300
  state.debounce_timer = vim.uv.new_timer()
  state.debounce_timer:start(debounce_ms, 0, vim.schedule_wrap(function()
    if state.debounce_timer then
      state.debounce_timer:close()
      state.debounce_timer = nil
    end
    local mode = vim.api.nvim_get_mode().mode
    if mode == "i" then
      trigger_completion(bufnr, row, col)
    end
  end))
end

local function setup_buffer_autocmds(bufnr)
  local group = vim.api.nvim_create_augroup("AtaraxyBuf" .. bufnr, { clear = true })

  vim.api.nvim_create_autocmd("TextChangedI", {
    group = group,
    buffer = bufnr,
    callback = function()
      if ui.ghost_get_text() ~= "" then
        cancel_active_completion()
        return
      end
      local cursor = vim.api.nvim_win_get_cursor(0)
      debounced_completion(bufnr, cursor[1] - 1, cursor[2])
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorMovedI", "InsertLeave", "BufLeave" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      cancel_active_completion()
    end,
  })

  config.set_keymaps(
    bufnr,
    function()
      local ghost = ui.ghost_get_text()
      if ghost == "" then
        return vim.api.nvim_feedkeys(
          vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "n", false
        )
      end
      local cursor = vim.api.nvim_win_get_cursor(0)
      ui.ghost_commit(bufnr, cursor[1] - 1, cursor[2])
      cancel_active_completion()
    end,
    function()
      cancel_active_completion()
      return vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false
      )
    end,
    config.get("keymaps") and config.get("keymaps").trigger and function()
      local cursor = vim.api.nvim_win_get_cursor(0)
      trigger_completion(bufnr, cursor[1] - 1, cursor[2])
    end or nil
  )
end

local function cmd_prompt()
  if state.diff_active then
    ui.notify("Agent session already active. Use :AtaraxyAccept or :AtaraxyCancel first.", vim.log.levels.WARN)
    return
  end

  local source_bufnr = vim.api.nvim_get_current_buf()

  ui.open_agent_input(function(user_prompt)
    local file_content = context.load_active_file(source_bufnr)
    local workspace_ctx = context.load_workspace_context()
    local skills_text = context.load_skills()
    local system_prompt = skills.get_system_prompt()

    local messages = prompt_mod.build_agent_messages(file_content, user_prompt, workspace_ctx, skills_text)

    local scratch_buf, scratch_win = ui.open_diff_view(source_bufnr)
    vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, {})

    state.diff_active = true
    state.diff_source_bufnr = source_bufnr
    state.diff_scratch_bufnr = scratch_buf
    state.diff_scratch_win = scratch_win

    state.diff_job_id = api.stream(
      messages,
      system_prompt,
      function(token)
        if vim.api.nvim_buf_is_valid(scratch_buf) then
          ui.stream_to_buf(scratch_buf, token)
        end
      end,
      function()
        state.diff_job_id = nil
        ui.notify("Generation complete. Use :AtaraxyAccept or :AtaraxyCancel.")
      end,
      function(err)
        state.diff_job_id = nil
        ui.notify("Agent error: " .. err, vim.log.levels.ERROR)
      end
    )
  end, nil)
end

local function cmd_redo()
  if not state.last_fim_bufnr then
    ui.notify("No previous completion to redo.", vim.log.levels.WARN)
    return
  end
  cancel_active_completion()
  trigger_completion(state.last_fim_bufnr, state.last_fim_row, state.last_fim_col)
end

local function cmd_readfile()
  context.reload_buffer()
end

local function cmd_accept()
  if not state.diff_active then
    ui.notify("No active agent session.", vim.log.levels.WARN)
    return
  end

  if state.diff_job_id then
    api.cancel(state.diff_job_id)
    state.diff_job_id = nil
  end

  local scratch_lines = vim.api.nvim_buf_get_lines(state.diff_scratch_bufnr, 0, -1, false)
  vim.api.nvim_buf_set_lines(state.diff_source_bufnr, 0, -1, false, scratch_lines)

  ui.close_diff_view(state.diff_scratch_bufnr, state.diff_scratch_win)

  state.diff_active = false
  state.diff_source_bufnr = nil
  state.diff_scratch_bufnr = nil
  state.diff_scratch_win = nil

  ui.notify("Changes accepted.")
end

local function cmd_cancel()
  if not state.diff_active then
    ui.notify("No active agent session.", vim.log.levels.WARN)
    return
  end

  if state.diff_job_id then
    api.cancel(state.diff_job_id)
    state.diff_job_id = nil
  end

  ui.close_diff_view(state.diff_scratch_bufnr, state.diff_scratch_win)

  state.diff_active = false
  state.diff_source_bufnr = nil
  state.diff_scratch_bufnr = nil
  state.diff_scratch_win = nil

  ui.notify("Generation cancelled.")
end

function M.setup(user_opts)
  config.setup(user_opts)

  local group = vim.api.nvim_create_augroup("Ataraxy", { clear = true })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      local bufnr = ev.buf
      local bt = vim.bo[bufnr].buftype
      if bt == "" or bt == "acwrite" then
        setup_buffer_autocmds(bufnr)
      end
    end,
  })

  vim.api.nvim_create_user_command("AtaraxyPrompt", cmd_prompt, { nargs = 0 })
  vim.api.nvim_create_user_command("AtaraxyRedo", cmd_redo, { nargs = 0 })
  vim.api.nvim_create_user_command("AtaraxyReadfile", cmd_readfile, { nargs = 0 })
  vim.api.nvim_create_user_command("AtaraxyAccept", cmd_accept, { nargs = 0 })
  vim.api.nvim_create_user_command("AtaraxyCancel", cmd_cancel, { nargs = 0 })
end

return M
