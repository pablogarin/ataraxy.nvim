local assert = require("luassert")
local prompt_mod = require("ataraxy.prompt")

local function make_buf(lines, filetype)
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.bo[b].filetype = filetype or ""
  return b
end

-- ---------------------------------------------------------------------------
-- detect_docstring
-- ---------------------------------------------------------------------------
describe("ataraxy.prompt.detect_docstring", function()
  it("returns nil for plain code lines (python)", function()
    local buf = make_buf({ "x = 1", "y = 2" }, "python")
    assert.is_nil(prompt_mod.detect_docstring(buf, 0))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("detects Python triple-quote block when cursor is inside", function()
    local buf = make_buf({
      '"""',
      "Calculate the total price.",
      '"""',
    }, "python")
    local r = prompt_mod.detect_docstring(buf, 1)
    assert.is_not_nil(r)
    assert.equals(0, r.start_row)
    assert.equals(2, r.end_row)
    assert.is_false(r.empty)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("detects Python triple-quote block when cursor is on closing delimiter", function()
    local buf = make_buf({
      '"""',
      "Returns a sorted list.",
      '"""',
    }, "python")
    local r = prompt_mod.detect_docstring(buf, 2)
    assert.is_not_nil(r)
    assert.equals(0, r.start_row)
    assert.equals(2, r.end_row)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("marks empty Python docstring as empty", function()
    local buf = make_buf({ '"""', '"""' }, "python")
    local r = prompt_mod.detect_docstring(buf, 1)
    assert.is_not_nil(r)
    assert.is_true(r.empty)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns nil when cursor is below a closed Python docstring", function()
    local buf = make_buf({
      '"""',
      "Some doc.",
      '"""',
      "x = 1",
    }, "python")
    -- cursor on "x = 1" which is below the closed block
    assert.is_nil(prompt_mod.detect_docstring(buf, 3))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("detects JSDoc block when cursor is inside", function()
    local buf = make_buf({
      "/**",
      " * Adds two numbers.",
      " * @param {number} a",
      " */",
    }, "javascript")
    local r = prompt_mod.detect_docstring(buf, 1)
    assert.is_not_nil(r)
    assert.equals(0, r.start_row)
    assert.equals(3, r.end_row)
    assert.is_false(r.empty)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("detects JSDoc block when cursor is on closing */", function()
    local buf = make_buf({
      "/**",
      " * Multiplies two numbers.",
      " */",
    }, "typescript")
    local r = prompt_mod.detect_docstring(buf, 2)
    assert.is_not_nil(r)
    assert.equals(0, r.start_row)
    assert.equals(2, r.end_row)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("detects Lua --- block at cursor", function()
    local buf = make_buf({
      "--- Computes the factorial of n.",
      "--- @param n number",
    }, "lua")
    local r = prompt_mod.detect_docstring(buf, 0)
    assert.is_not_nil(r)
    assert.equals(0, r.start_row)
    assert.equals(1, r.end_row)
    assert.is_false(r.empty)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("detects // comment block for Go", function()
    local buf = make_buf({
      "// Add returns the sum of a and b.",
      "// It panics if overflow occurs.",
    }, "go")
    local r = prompt_mod.detect_docstring(buf, 1)
    assert.is_not_nil(r)
    assert.equals(0, r.start_row)
    assert.equals(1, r.end_row)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("marks empty Lua --- block as empty", function()
    local buf = make_buf({ "---" }, "lua")
    local r = prompt_mod.detect_docstring(buf, 0)
    assert.is_not_nil(r)
    assert.is_true(r.empty)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

-- ---------------------------------------------------------------------------
-- extract_func_name_from_text
-- ---------------------------------------------------------------------------
describe("ataraxy.prompt.extract_func_name_from_text", function()
  it("extracts Python function name", function()
    local name = prompt_mod.extract_func_name_from_text("def calculate_total(items):\n    pass", "python")
    assert.equals("calculate_total", name)
  end)

  it("extracts Lua function name (local function)", function()
    local name = prompt_mod.extract_func_name_from_text("local function greet(name)\n  return name\nend", "lua")
    assert.equals("greet", name)
  end)

  it("extracts Lua function name (module method)", function()
    local name = prompt_mod.extract_func_name_from_text("function M.render(buf)\nend", "lua")
    assert.equals("M.render", name)
  end)

  it("extracts JS function name", function()
    local name = prompt_mod.extract_func_name_from_text("function fetchData(url) {}", "javascript")
    assert.equals("fetchData", name)
  end)

  it("extracts Go function name", function()
    local name = prompt_mod.extract_func_name_from_text("func Add(a, b int) int {", "go")
    assert.equals("Add", name)
  end)

  it("extracts Rust function name", function()
    local name = prompt_mod.extract_func_name_from_text("fn compute_hash(data: &[u8]) -> u64 {", "rust")
    assert.equals("compute_hash", name)
  end)

  it("returns nil when no recognizable function signature", function()
    local name = prompt_mod.extract_func_name_from_text("x = 1 + 2", "python")
    assert.is_nil(name)
  end)
end)

-- ---------------------------------------------------------------------------
-- find_func_in_buffer
-- ---------------------------------------------------------------------------
describe("ataraxy.prompt.find_func_in_buffer", function()
  it("finds a Python function and returns correct start/end rows", function()
    local buf = make_buf({
      "x = 1",
      "def add(a, b):",
      "    return a + b",
      "",
      "y = 2",
    }, "python")
    local r = prompt_mod.find_func_in_buffer(buf, "add", "python")
    assert.is_not_nil(r)
    assert.equals(1, r.start_row)
    assert.equals(2, r.end_row)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("finds a Lua function and returns correct start/end rows", function()
    local buf = make_buf({
      "local M = {}",
      "function M.greet(name)",
      "  return 'hello ' .. name",
      "end",
      "return M",
    }, "lua")
    local r = prompt_mod.find_func_in_buffer(buf, "M.greet", "lua")
    assert.is_not_nil(r)
    assert.equals(1, r.start_row)
    assert.equals(3, r.end_row)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns nil when function does not exist", function()
    local buf = make_buf({ "x = 1", "y = 2" }, "python")
    assert.is_nil(prompt_mod.find_func_in_buffer(buf, "missing_func", "python"))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns nil for empty func_name", function()
    local buf = make_buf({ "def foo(): pass" }, "python")
    assert.is_nil(prompt_mod.find_func_in_buffer(buf, "", "python"))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

-- ---------------------------------------------------------------------------
-- build_docstring_messages
-- ---------------------------------------------------------------------------
describe("ataraxy.prompt.build_docstring_messages", function()
  it("returns a single user message with all four sections", function()
    local msgs = prompt_mod.build_docstring_messages(
      "python", "PREFIX\n", '"""\nDoc text.\n"""', "\nSUFFIX"
    )
    assert.equals(1, #msgs)
    assert.equals("user", msgs[1].role)
    local c = msgs[1].content
    assert.truthy(c:match("Language: python"))
    assert.truthy(c:match("PREFIX"))
    assert.truthy(c:match("Doc text%."))
    assert.truthy(c:match("SUFFIX"))
  end)
end)
