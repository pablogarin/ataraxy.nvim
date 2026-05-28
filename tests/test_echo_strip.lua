local assert = require("luassert")
local prompt_mod = require("ataraxy.prompt")

local function make_buf(lines)
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  return b
end

describe("ataraxy.prompt.strip_echo", function()
  it("returns response unchanged when no echo detected", function()
    local buf = make_buf({ "local x = 1", "" })
    local result = prompt_mod.strip_echo("local y = 2\n", "local x = 1\n", buf, 1)
    assert.equals("local y = 2\n", result)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("strips tail of prefix echoed at start of response", function()
    local buf = make_buf({ "local x = foo" })
    local result = prompt_mod.strip_echo("local x = foo.bar()\n", "local x = foo", buf, 0)
    assert.equals(".bar()\n", result)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("strips leading lines that exist verbatim in buffer window", function()
    local buf = make_buf({ "import os", "import sys", "" })
    local result = prompt_mod.strip_echo(
      "import os\nimport sys\nx = 1\n",
      "import os\nimport sys\n",
      buf, 2
    )
    assert.equals("x = 1\n", result)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns empty string when response is entirely echoed context", function()
    local buf = make_buf({ "def foo():" })
    local result = prompt_mod.strip_echo("def foo():", "def foo():", buf, 0)
    assert.equals("", result)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns empty string unchanged when given empty response", function()
    local buf = make_buf({ "x = 1" })
    local result = prompt_mod.strip_echo("", "x = 1", buf, 0)
    assert.equals("", result)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("does not strip lines outside the +-5 window", function()
    local lines = {}
    for i = 1, 20 do lines[i] = "line_" .. i end
    local buf = make_buf(lines)
    -- cursor is at row 15 (0-indexed); "line_1" is outside the +-5 window
    local result = prompt_mod.strip_echo("line_1\nnew_code\n", "", buf, 15)
    assert.equals("line_1\nnew_code\n", result)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
