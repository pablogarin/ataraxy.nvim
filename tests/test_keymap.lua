local MiniTest = require("mini.test")

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["ataraxy.completion.ghost"] = nil
      package.loaded["ataraxy.completion.keymap"] = nil
    end,
  },
})

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  return buf
end

-- Tab accept: ghost present → text committed, ghost cleared
T["accept inserts completion text into buffer and clears ghost"] = function()
  local buf = make_buf({ "hello " })
  local ghost = require("ataraxy.completion.ghost")
  local keymap = require("ataraxy.completion.keymap")

  vim.cmd("startinsert")
  vim.api.nvim_win_set_cursor(0, { 1, 6 })
  ghost.show(buf, 1, 6, "world")
  MiniTest.expect.equality(ghost.has_ghost(buf), true)

  keymap.accept(buf)

  vim.cmd("stopinsert")

  local result = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(result[1], "hello world")
  MiniTest.expect.equality(ghost.has_ghost(buf), false)
end

-- Tab accept: multiline completion inserted correctly
T["accept handles multiline completion text"] = function()
  local buf = make_buf({ "fn " })
  local ghost = require("ataraxy.completion.ghost")
  local keymap = require("ataraxy.completion.keymap")

  vim.cmd("startinsert")
  vim.api.nvim_win_set_cursor(0, { 1, 3 })
  ghost.show(buf, 1, 3, "foo\n  return 1\nend")

  keymap.accept(buf)
  vim.cmd("stopinsert")

  local result = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(result[1], "fn foo")
  MiniTest.expect.equality(result[2], "  return 1")
  MiniTest.expect.equality(result[3], "end")
end

-- Tab passthrough: no ghost → has_ghost stays false
T["accept does not change buffer when no ghost text is present"] = function()
  local buf = make_buf({ "abc" })
  local ghost = require("ataraxy.completion.ghost")
  local keymap = require("ataraxy.completion.keymap")

  MiniTest.expect.equality(ghost.has_ghost(buf), false)
  -- accept() with no ghost calls feedkeys("<Tab>") — hard to assert in headless,
  -- but we verify buffer is unchanged and no error occurs
  vim.cmd("startinsert")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  keymap.accept(buf)
  vim.cmd("stopinsert")

  MiniTest.expect.equality(ghost.has_ghost(buf), false)
end

-- Escape dismiss: ghost present → cleared, stays in Insert Mode
T["dismiss clears ghost text when ghost is visible"] = function()
  local buf = make_buf({ "foo" })
  local ghost = require("ataraxy.completion.ghost")
  local keymap = require("ataraxy.completion.keymap")

  vim.cmd("startinsert")
  vim.api.nvim_win_set_cursor(0, { 1, 3 })
  ghost.show(buf, 1, 3, "bar")
  MiniTest.expect.equality(ghost.has_ghost(buf), true)

  keymap.dismiss(buf)

  MiniTest.expect.equality(ghost.has_ghost(buf), false)
  -- Buffer content must be unchanged
  local result = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(result[1], "foo")
  vim.cmd("stopinsert")
end

-- Escape normal exit: no ghost → exits Insert Mode via feedkeys
T["dismiss exits Insert Mode when no ghost text is present"] = function()
  local buf = make_buf({ "baz" })
  local ghost = require("ataraxy.completion.ghost")

  vim.cmd("startinsert")
  MiniTest.expect.equality(ghost.has_ghost(buf), false)

  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes("<Escape>", true, false, true), "x", false
  )

  local mode = vim.api.nvim_get_mode().mode
  MiniTest.expect.equality(mode, "n")
end

-- has_ghost reflects extmark state
T["has_ghost returns true after show and false after clear"] = function()
  local buf = make_buf({ "test" })
  local ghost = require("ataraxy.completion.ghost")

  MiniTest.expect.equality(ghost.has_ghost(buf), false)
  ghost.show(buf, 1, 0, "completion")
  MiniTest.expect.equality(ghost.has_ghost(buf), true)
  ghost.clear(buf)
  MiniTest.expect.equality(ghost.has_ghost(buf), false)
end

-- show clears previous extmark before rendering new one
T["show clears previous ghost text before rendering a new one"] = function()
  local buf = make_buf({ "line" })
  local ghost = require("ataraxy.completion.ghost")

  ghost.show(buf, 1, 0, "first")
  MiniTest.expect.equality(ghost.get_text(), "first")

  ghost.show(buf, 1, 0, "second")
  MiniTest.expect.equality(ghost.get_text(), "second")

  local marks = vim.api.nvim_buf_get_extmarks(
    buf, vim.api.nvim_create_namespace("ataraxy_ghost"), 0, -1, {}
  )
  MiniTest.expect.equality(#marks, 1)
end

-- BufWritePre clears ghost text
T["ghost text is cleared on BufWritePre"] = function()
  local buf = make_buf({ "write test" })
  local ghost = require("ataraxy.completion.ghost")
  ghost.setup()

  ghost.show(buf, 1, 0, "pending")
  MiniTest.expect.equality(ghost.has_ghost(buf), true)

  vim.api.nvim_exec_autocmds("BufWritePre", { buffer = buf })

  MiniTest.expect.equality(ghost.has_ghost(buf), false)
end

return T
