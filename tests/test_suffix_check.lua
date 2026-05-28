local assert = require("luassert")
local prompt_mod = require("ataraxy.prompt")
local ui = require("ataraxy.ui")

local function make_buf(lines, filetype)
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.bo[b].filetype = filetype or ""
  return b
end

-- ---------------------------------------------------------------------------
-- build_suffix_check_messages
-- ---------------------------------------------------------------------------
describe("ataraxy.prompt.build_suffix_check_messages", function()
  it("returns a single user message with language, replacement, and suffix", function()
    local msgs = prompt_mod.build_suffix_check_messages("python", "x = foo(", ")")
    assert.equals(1, #msgs)
    assert.equals("user", msgs[1].role)
    local c = msgs[1].content
    assert.truthy(c:match("Language: python"))
    assert.truthy(c:match("Replacement: x = foo%("))
    assert.truthy(c:match("Trailing suffix: %)"))
  end)

  it("includes all three fields for JS", function()
    local msgs = prompt_mod.build_suffix_check_messages(
      "javascript", "const fn = () =>", "{ return 1 }"
    )
    local c = msgs[1].content
    assert.truthy(c:match("Language: javascript"))
    assert.truthy(c:match("Replacement:"))
    assert.truthy(c:match("Trailing suffix:"))
  end)
end)

-- ---------------------------------------------------------------------------
-- ghost_commit with drop_suffix
-- ---------------------------------------------------------------------------
describe("ataraxy.ui.ghost_commit drop_suffix", function()
  local function set_ghost(text, bufnr, row, col)
    -- Simulate ghost text by calling ghost_append directly
    ui.ghost_append(text, bufnr, row, col)
  end

  it("keeps suffix by default when drop_suffix is false", function()
    local buf = make_buf({ "foo(bar)" }, "python")
    -- cursor is at col 4 (after "foo("), suffix is "bar)"
    set_ghost("baz, ", buf, 0, 4)
    ui.ghost_commit(buf, 0, 4, false)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("foo(baz, bar)", lines[1])
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("drops suffix when drop_suffix is true", function()
    local buf = make_buf({ "foo(bar)" }, "python")
    set_ghost("baz)", buf, 0, 4)
    ui.ghost_commit(buf, 0, 4, true)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("foo(baz)", lines[1])
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("positions cursor at end of inserted text when dropping suffix", function()
    local buf = make_buf({ "x = old_value + extra" }, "python")
    vim.api.nvim_win_set_buf(0, buf)
    -- cursor at col 4 (after "x = "), suffix is "old_value + extra"
    set_ghost("new_value", buf, 0, 4)
    ui.ghost_commit(buf, 0, 4, true)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("x = new_value", lines[1])
    local cursor = vim.api.nvim_win_get_cursor(0)
    assert.equals(1, cursor[1])
    -- In normal mode (headless tests) the cursor clamps to #line-1 = 12.
    -- In insert mode (real usage) it would be 13 (past-end position).
    assert.truthy(cursor[2] >= 12)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("keeps suffix when drop_suffix is nil (backward compat)", function()
    local buf = make_buf({ "a = b + c" }, "python")
    set_ghost("x", buf, 0, 4)
    ui.ghost_commit(buf, 0, 4, nil)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("a = xb + c", lines[1])
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("handles multiline ghost text with drop_suffix", function()
    local buf = make_buf({ "def foo(obsolete_arg):" }, "python")
    vim.api.nvim_win_set_buf(0, buf)
    -- cursor at col 8 (after "def foo("), suffix is "obsolete_arg):"
    set_ghost("a, b):\n    return a + b", buf, 0, 8)
    ui.ghost_commit(buf, 0, 8, true)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("def foo(a, b):", lines[1])
    assert.equals("    return a + b", lines[2])
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
