local assert = require("luassert")
local prompt_mod = require("ataraxy.prompt")

local function make_buf(lines)
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  return b
end

-- extract_existing_imports ----------------------------------------------------

describe("ataraxy.prompt.extract_existing_imports", function()
  it("extracts python imports", function()
    local buf = make_buf({ "import os", "import sys", "from pathlib import Path", "", "x = 1" })
    local result = prompt_mod.extract_existing_imports(buf, "python")
    assert.truthy(result:find("import os"))
    assert.truthy(result:find("import sys"))
    assert.truthy(result:find("from pathlib import Path"))
    assert.falsy(result:find("x = 1"))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("extracts lua require statements", function()
    local buf = make_buf({ "local M = {}", "local api = require('api')", "local ui = require(\"ui\")", "", "M.x = 1" })
    local result = prompt_mod.extract_existing_imports(buf, "lua")
    assert.truthy(result:find("require"))
    assert.falsy(result:find("M.x"))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("extracts c includes", function()
    local buf = make_buf({ "#include <stdio.h>", "#include \"mylib.h\"", "", "int main() {}" })
    local result = prompt_mod.extract_existing_imports(buf, "c")
    assert.truthy(result:find("#include <stdio%.h>"))
    assert.truthy(result:find("#include"))
    assert.falsy(result:find("int main"))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns empty string when no imports present", function()
    local buf = make_buf({ "x = 1", "y = 2" })
    local result = prompt_mod.extract_existing_imports(buf, "python")
    assert.equals("", result)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns empty string for unknown filetype", function()
    local buf = make_buf({ "import os" })
    local result = prompt_mod.extract_existing_imports(buf, "unknownlang")
    assert.equals("", result)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("handles go grouped import blocks", function()
    local buf = make_buf({
      "package main",
      "",
      "import (",
      '\t"fmt"',
      '\t"os"',
      ")",
      "",
      "func main() {}",
    })
    local result = prompt_mod.extract_existing_imports(buf, "go")
    assert.truthy(result:find("import %("))
    assert.truthy(result:find('"fmt"'))
    assert.truthy(result:find('"os"'))
    assert.falsy(result:find("func main"))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

-- find_import_insert_row ------------------------------------------------------

describe("ataraxy.prompt.find_import_insert_row", function()
  it("returns row after last python import", function()
    local buf = make_buf({ "import os", "import sys", "", "x = 1" })
    local row = prompt_mod.find_import_insert_row(buf, "python")
    assert.equals(2, row)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns 0 when no imports exist", function()
    local buf = make_buf({ "x = 1", "y = 2" })
    local row = prompt_mod.find_import_insert_row(buf, "python")
    assert.equals(0, row)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns 0 for unknown filetype", function()
    local buf = make_buf({ "import os" })
    local row = prompt_mod.find_import_insert_row(buf, "unknownlang")
    assert.equals(0, row)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns row after closing paren of go import block", function()
    local buf = make_buf({
      "package main",  -- row 0
      "",              -- row 1
      "import (",      -- row 2
      '\t"fmt"',       -- row 3
      ")",             -- row 4
      "",              -- row 5
      "func main() {}",
    })
    local row = prompt_mod.find_import_insert_row(buf, "go")
    assert.equals(5, row)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

-- build_import_messages -------------------------------------------------------

describe("ataraxy.prompt.build_import_messages", function()
  it("includes language, existing imports and snippet", function()
    local msgs = prompt_mod.build_import_messages("python", "import os", "import sys\nx = sys.argv[0]")
    assert.equals(1, #msgs)
    local c = msgs[1].content
    assert.truthy(c:find("python"))
    assert.truthy(c:find("import os"))
    assert.truthy(c:find("import sys"))
    assert.truthy(c:find("sys%.argv"))
  end)

  it("omits existing-imports section when empty", function()
    local msgs = prompt_mod.build_import_messages("lua", "", "local x = require('x')")
    local c = msgs[1].content
    assert.falsy(c:find("Existing imports"))
    assert.truthy(c:find("lua"))
    assert.truthy(c:find("require"))
  end)
end)
