local MiniTest = require("mini.test")

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["ataraxy.prompt.ui"]        = nil
      package.loaded["ataraxy.prompt.workspace"]  = nil
      package.loaded["ataraxy.prompt.stream"]     = nil
      package.loaded["ataraxy.api"]               = nil
    end,
  },
})

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  return buf
end

-- workspace.init seeds scratch buffer with original content
T["workspace init seeds scratch buffer with original buffer content"] = function()
  local orig = make_buf({ "line one", "line two", "line three" })
  local workspace = require("ataraxy.prompt.workspace")

  local state = workspace.init(orig)

  local scratch_lines = vim.api.nvim_buf_get_lines(state.scratch_buf, 0, -1, false)
  MiniTest.expect.equality(scratch_lines[1], "line one")
  MiniTest.expect.equality(scratch_lines[2], "line two")
  MiniTest.expect.equality(scratch_lines[3], "line three")

  -- Cleanup
  workspace.reject(state)
end

-- workspace.init opens a second window (the split)
T["workspace init creates a second window for the diff split"] = function()
  local orig = make_buf({ "hello" })
  local workspace = require("ataraxy.prompt.workspace")
  local win_count_before = #vim.api.nvim_list_wins()

  local state = workspace.init(orig)
  local win_count_after = #vim.api.nvim_list_wins()

  MiniTest.expect.equality(win_count_after, win_count_before + 1)

  workspace.reject(state)
end

-- workspace.accept copies scratch lines into original buffer
T["workspace accept overwrites original buffer with scratch content"] = function()
  local orig = make_buf({ "old line" })
  local workspace = require("ataraxy.prompt.workspace")

  local state = workspace.init(orig)
  vim.api.nvim_buf_set_lines(state.scratch_buf, 0, -1, false, { "new line", "added" })

  workspace.accept(state)

  local result = vim.api.nvim_buf_get_lines(orig, 0, -1, false)
  MiniTest.expect.equality(result[1], "new line")
  MiniTest.expect.equality(result[2], "added")
end

-- workspace.accept closes the split window
T["workspace accept closes the scratch window"] = function()
  local orig = make_buf({ "text" })
  local workspace = require("ataraxy.prompt.workspace")

  local state = workspace.init(orig)
  local scratch_win = state.scratch_win

  workspace.accept(state)

  MiniTest.expect.equality(vim.api.nvim_win_is_valid(scratch_win), false)
end

-- workspace.reject leaves original buffer unchanged
T["workspace reject leaves original buffer content unchanged"] = function()
  local orig = make_buf({ "original" })
  local workspace = require("ataraxy.prompt.workspace")

  local state = workspace.init(orig)
  vim.api.nvim_buf_set_lines(state.scratch_buf, 0, -1, false, { "modified" })

  workspace.reject(state)

  local result = vim.api.nvim_buf_get_lines(orig, 0, -1, false)
  MiniTest.expect.equality(result[1], "original")
end

-- workspace.reject wipes the scratch buffer
T["workspace reject deletes the scratch buffer"] = function()
  local orig = make_buf({ "text" })
  local workspace = require("ataraxy.prompt.workspace")

  local state = workspace.init(orig)
  local scratch_buf = state.scratch_buf

  workspace.reject(state)

  MiniTest.expect.equality(vim.api.nvim_buf_is_valid(scratch_buf), false)
end

-- workspace.cancel calls api.cancel
T["workspace cancel calls api.cancel"] = function()
  local orig = make_buf({ "text" })
  local workspace = require("ataraxy.prompt.workspace")
  local api = require("ataraxy.api")

  local cancel_called = false
  local saved = { cancel = api.cancel }
  api.cancel = function() cancel_called = true end

  local state = workspace.init(orig)
  workspace.cancel(state)

  api.cancel = saved.cancel
  workspace.reject(state)

  MiniTest.expect.equality(cancel_called, true)
end

-- workspace.cancel leaves scratch buffer open in partial state
T["workspace cancel leaves scratch buffer open"] = function()
  local orig = make_buf({ "text" })
  local workspace = require("ataraxy.prompt.workspace")
  local api = require("ataraxy.api")

  local saved = { cancel = api.cancel }
  api.cancel = function() end

  local state = workspace.init(orig)
  workspace.cancel(state)

  api.cancel = saved.cancel

  MiniTest.expect.equality(vim.api.nvim_buf_is_valid(state.scratch_buf), true)
  workspace.reject(state)
end

-- stream.write accumulates tokens and updates scratch buffer
T["stream write accumulates tokens and writes lines to scratch buffer"] = function()
  local stream = require("ataraxy.prompt.stream")
  local buf = make_buf({})
  stream.reset()

  stream.write(buf, "function foo()")
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(lines[1], "function foo()")

  stream.write(buf, "\n  return 1\nend")
  lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(lines[1], "function foo()")
  MiniTest.expect.equality(lines[2], "  return 1")
  MiniTest.expect.equality(lines[3], "end")
end

-- stream.reset clears accumulator
T["stream reset clears the accumulated text"] = function()
  local stream = require("ataraxy.prompt.stream")
  local buf = make_buf({})

  stream.write(buf, "some text")
  MiniTest.expect.equality(stream.get_accumulated(), "some text")

  stream.reset()
  MiniTest.expect.equality(stream.get_accumulated(), "")
end

-- stream.write with invalid buffer does not error
T["stream write is a no-op when scratch buffer is invalid"] = function()
  local stream = require("ataraxy.prompt.stream")
  stream.reset()

  local ok = pcall(stream.write, 99999, "token")
  MiniTest.expect.equality(ok, true)
end

-- ui.system_prompt returns a non-empty string
T["ui system_prompt returns a non-empty instruction string"] = function()
  local ui = require("ataraxy.prompt.ui")
  local prompt = ui.system_prompt()

  MiniTest.expect.equality(type(prompt), "string")
  MiniTest.expect.equality(prompt ~= "", true)
end

-- ui.submit calls on_submit with trimmed instruction
T["ui submit calls on_submit with the trimmed instruction text"] = function()
  local ui = require("ataraxy.prompt.ui")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "  refactor this  " })
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor", row = 0, col = 0, width = 40, height = 1,
  })

  local received = nil
  ui.submit(buf, win, function(instr) received = instr end, nil)

  MiniTest.expect.equality(received, "refactor this")
end

-- ui.submit calls on_cancel when instruction is empty
T["ui submit calls on_cancel when the buffer is empty"] = function()
  local ui = require("ataraxy.prompt.ui")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor", row = 0, col = 0, width = 40, height = 1,
  })

  local cancelled = false
  ui.submit(buf, win, function() end, function() cancelled = true end)

  MiniTest.expect.equality(cancelled, true)
end

return T
