local MiniTest = require("mini.test")

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["ataraxy.context.buffer"] = nil
    end,
  },
})

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  local win = vim.api.nvim_get_current_win()
  return buf, win
end

-- get_context: mid-line split
T["mid-line split yields correct prefix and suffix"] = function()
  local buf, win = make_buf({ "line1", "foo bar", "line3" })
  vim.api.nvim_win_set_cursor(win, { 2, 3 })  -- after "foo"

  local buffer = require("ataraxy.context.buffer")
  local ctx = buffer.get_context(buf, win)

  MiniTest.expect.equality(ctx.prefix, "line1\nfoo")
  MiniTest.expect.equality(ctx.suffix, " bar\nline3")
end

-- get_context: cursor at start of blank line
T["cursor at start of blank line: prefix ends with newline, suffix starts with newline"] = function()
  local buf, win = make_buf({ "above", "", "below" })
  vim.api.nvim_win_set_cursor(win, { 2, 0 })  -- start of blank line

  local buffer = require("ataraxy.context.buffer")
  local ctx = buffer.get_context(buf, win)

  MiniTest.expect.equality(ctx.prefix, "above\n")
  MiniTest.expect.equality(ctx.suffix, "\nbelow")
end

-- get_context: cursor on last char of line (normal mode, col clamped to len-1)
T["cursor on last char of line: last char appears in suffix"] = function()
  local buf, win = make_buf({ "hello", "world" })
  vim.api.nvim_win_set_cursor(win, { 1, 4 })  -- ON 'o', the last char (0-indexed)

  local buffer = require("ataraxy.context.buffer")
  local ctx = buffer.get_context(buf, win)

  MiniTest.expect.equality(ctx.prefix, "hell")
  MiniTest.expect.equality(ctx.suffix, "o\nworld")
end

-- get_context: cursor after last char (insert mode, col = len)
T["cursor after last char in insert mode: suffix remainder starts with next line"] = function()
  local buf, win = make_buf({ "hello", "world" })
  vim.cmd("startinsert")
  vim.api.nvim_win_set_cursor(win, { 1, 5 })  -- after 'o', insert mode allows col=len

  local buffer = require("ataraxy.context.buffer")
  local ctx = buffer.get_context(buf, win)

  vim.cmd("stopinsert")

  MiniTest.expect.equality(ctx.prefix, "hello")
  MiniTest.expect.equality(ctx.suffix, "\nworld")
end

-- get_context: empty buffer
T["empty buffer returns empty prefix and suffix"] = function()
  local buf, win = make_buf({ "" })
  vim.api.nvim_win_set_cursor(win, { 1, 0 })

  local buffer = require("ataraxy.context.buffer")
  local ctx = buffer.get_context(buf, win)

  MiniTest.expect.equality(ctx.prefix, "")
  MiniTest.expect.equality(ctx.suffix, "")
end

-- get_context: single-line buffer, cursor mid-line
T["single-line buffer mid-cursor splits line correctly"] = function()
  local buf, win = make_buf({ "abcdef" })
  vim.api.nvim_win_set_cursor(win, { 1, 3 })  -- after "abc"

  local buffer = require("ataraxy.context.buffer")
  local ctx = buffer.get_context(buf, win)

  MiniTest.expect.equality(ctx.prefix, "abc")
  MiniTest.expect.equality(ctx.suffix, "def")
end

-- get_context: prefix + suffix spans entire buffer
T["prefix and suffix together span the full buffer"] = function()
  local buf, win = make_buf({ "aaa", "bbb", "ccc" })
  vim.api.nvim_win_set_cursor(win, { 2, 1 })  -- after "b" in "bbb"

  local buffer = require("ataraxy.context.buffer")
  local ctx = buffer.get_context(buf, win)

  -- Reconstructing should give the original buffer with a join point at the cursor
  local reconstructed = ctx.prefix .. ctx.suffix
  MiniTest.expect.equality(reconstructed, "aaa\nb" .. "bb\nccc")
end

-- build_fim_prompt: default tokens
T["build_fim_prompt uses default PRE/SUF/MID tokens"] = function()
  local buffer = require("ataraxy.context.buffer")
  local result = buffer.build_fim_prompt("prefix_text", "suffix_text")

  MiniTest.expect.equality(result, "<PRE>prefix_text<SUF>suffix_text<MID>")
end

-- build_fim_prompt: custom tokens
T["build_fim_prompt uses custom tokens when provided"] = function()
  local buffer = require("ataraxy.context.buffer")
  local tokens = { prefix = "[P]", suffix = "[S]", middle = "[M]" }
  local result = buffer.build_fim_prompt("AAA", "BBB", tokens)

  MiniTest.expect.equality(result, "[P]AAA[S]BBB[M]")
end

-- build_request_payload: shape
T["build_request_payload returns correct payload shape"] = function()
  local buffer = require("ataraxy.context.buffer")
  local cfg = { model = "test-model", api_key = "k" }
  local payload = buffer.build_request_payload("<PRE>p<SUF>s<MID>", cfg)

  MiniTest.expect.equality(payload.model, "test-model")
  MiniTest.expect.equality(payload.stream, true)
  MiniTest.expect.equality(type(payload.messages), "table")
  MiniTest.expect.equality(#payload.messages, 1)
  MiniTest.expect.equality(payload.messages[1].role, "user")
  MiniTest.expect.equality(payload.messages[1].content, "<PRE>p<SUF>s<MID>")
end

return T
