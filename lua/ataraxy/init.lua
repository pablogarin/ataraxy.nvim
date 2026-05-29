local config = require("ataraxy.config")
local prompt_mod = require("ataraxy.prompt")
local api = require("ataraxy.api")
local ui = require("ataraxy.ui")
local context = require("ataraxy.agent.context")
local skills = require("ataraxy.agent.skills")

local M = {}

local AUTO_IMPORT_SYSTEM_PROMPT = "You are a dependency resolver. Given a code snippet and its language, output ONLY the import statements required for any undefined symbols in the snippet. One statement per line. No explanations, no markdown fences, no blank lines. If no imports are needed, output nothing."

local DOCSTRING_SYSTEM_PROMPT = "You are an elite code synthesis engine. Given a docstring and its surrounding file context, output ONLY the complete function implementation that fulfills the docstring contract. Do NOT repeat the docstring. Do NOT wrap in markdown backticks. Do NOT add commentary."

local state = {
  debounce_timer = nil,
  completion_gen = 0,
  active_job_id = nil,
  last_fim_bufnr = nil,
  last_fim_row = nil,
  last_fim_col = nil,

  diff_active = false,
  diff_source_bufnr = nil,
  diff_scratch_bufnr = nil,
  diff_scratch_win = nil,
  diff_job_id = nil,

  docstring_mode = false,
  docstring_info = nil,
}

local function cancel_active_completion()
  -- Bump the generation so any vim.schedule_wrap callbacks already queued from
  -- a fired timer see a stale gen and abort instead of firing a completion.
  state.completion_gen = state.completion_gen + 1
  if state.active_job_id then
    api.cancel(state.active_job_id)
    state.active_job_id = nil
  end
  if state.debounce_timer then
    state.debounce_timer:stop()
    state.debounce_timer:close()
    state.debounce_timer = nil
  end
  state.docstring_mode = false
  state.docstring_info = nil
  ui.ghost_clear()
end

local function resolve_imports(bufnr, committed_text)
  local filetype = vim.bo[bufnr].filetype
  if filetype == "" then return end

  local existing = prompt_mod.extract_existing_imports(bufnr, filetype)
  local messages = prompt_mod.build_import_messages(filetype, existing, committed_text)

  local response = ""
  api.stream(
    messages,
    AUTO_IMPORT_SYSTEM_PROMPT,
    function(token) response = response .. token end,
    function()
      if response:match("^%s*$") then return end

      local existing_set = {}
      for line in existing:gmatch("[^\n]+") do
        existing_set[line:match("^%s*(.-)%s*$")] = true
      end

      local new_imports = {}
      for line in response:gmatch("[^\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" and not existing_set[trimmed] then
          table.insert(new_imports, trimmed)
          existing_set[trimmed] = true
        end
      end

      if #new_imports == 0 then return end

      local insert_row = prompt_mod.find_import_insert_row(bufnr, filetype)
      -- Suppress TextChangedI so import insertion does not re-trigger the
      -- debounce timer and schedule a phantom completion ~300 ms later.
      local saved_ei = vim.o.eventignore
      vim.o.eventignore = saved_ei ~= "" and (saved_ei .. ",TextChangedI,TextChanged")
          or "TextChangedI,TextChanged"
      vim.api.nvim_buf_set_lines(bufnr, insert_row, insert_row, false, new_imports)
      vim.o.eventignore = saved_ei
    end,
    function(err)
      ui.notify("Auto-import error: " .. err, vim.log.levels.WARN)
    end
  )
end

local function trigger_completion(bufnr, row, col)
  cancel_active_completion()

  state.last_fim_bufnr = bufnr
  state.last_fim_row = row
  state.last_fim_col = col

  local docstring_info = prompt_mod.detect_docstring(bufnr, row)

  if docstring_info then
    if docstring_info.empty then return end
    state.docstring_mode = true
    state.docstring_info = docstring_info
  else
    state.docstring_mode = false
    state.docstring_info = nil
  end

  local filetype = vim.bo[bufnr].filetype
  local prefix, suffix = prompt_mod.build_fim(bufnr, row, col)
  local messages, system_prompt

  if state.docstring_mode then
    messages = prompt_mod.build_docstring_messages(filetype, prefix, docstring_info.text, suffix)
    system_prompt = DOCSTRING_SYSTEM_PROMPT
  else
    messages = prompt_mod.build_fim_messages(bufnr, row, col)
    system_prompt = config.get("system_prompt")
  end

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

      if not state.docstring_mode then
        local stripped = prompt_mod.strip_echo(accumulated, prefix, bufnr, row, suffix)
        if stripped ~= accumulated then
          ui.ghost_set_text(stripped)
        end
      end
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

  state.completion_gen = state.completion_gen + 1
  local gen = state.completion_gen

  local debounce_ms = config.get("debounce_ms") or 300
  state.debounce_timer = vim.uv.new_timer()
  state.debounce_timer:start(debounce_ms, 0, vim.schedule_wrap(function()
    -- If a newer debounce or a cancellation has incremented the generation
    -- since this timer was created, this callback is stale — discard it.
    -- This guards against vim.schedule_wrap callbacks that were already queued
    -- when the timer fired but arrive after a subsequent cancel_active_completion
    -- or debounced_completion call; without the check, both the stale and the
    -- fresh callback would call trigger_completion, causing double completions.
    if gen ~= state.completion_gen then return end
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

      if state.docstring_mode and state.docstring_info then
        local filetype = vim.bo[bufnr].filetype
        local func_name = prompt_mod.extract_func_name_from_text(ghost, filetype)
        local existing = func_name and prompt_mod.find_func_in_buffer(bufnr, func_name, filetype)

        if existing then
          if state.diff_active then
            ui.notify("Agent session already active. Use :AtaraxyAccept or :AtaraxyCancel first.", vim.log.levels.WARN)
            return
          end

          cancel_active_completion()

          local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
          local ghost_lines = vim.split(ghost, "\n", { plain = true })

          local new_lines = {}
          for i = 1, existing.start_row do
            table.insert(new_lines, all_lines[i])
          end
          for _, l in ipairs(ghost_lines) do
            table.insert(new_lines, l)
          end
          for i = existing.end_row + 2, #all_lines do
            table.insert(new_lines, all_lines[i])
          end

          local scratch_buf, scratch_win = ui.open_diff_view(bufnr)
          vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, new_lines)

          state.diff_active = true
          state.diff_source_bufnr = bufnr
          state.diff_scratch_bufnr = scratch_buf
          state.diff_scratch_win = scratch_win

          ui.notify("Function already exists. Review diff and use :AtaraxyAccept or :AtaraxyCancel.")
          return
        end
      end

      -- Trailing chars after the cursor are always preserved (complete-in-place
      -- semantics): strip_echo already removed any suffix_head the model echoed,
      -- so ghost text contains only what belongs between cursor and the next char.
      ui.ghost_commit(bufnr, cursor[1] - 1, cursor[2])
      cancel_active_completion()
      resolve_imports(bufnr, ghost)
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
