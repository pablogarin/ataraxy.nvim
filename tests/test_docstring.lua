local MiniTest = require("mini.test")

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["ataraxy.context.docstring"] = nil
    end,
  },
})

-- extract_from_content: docstring present
T["extract_from_content returns doc block when present above definition"] = function()
  local docstring = require("ataraxy.context.docstring")
  local content = table.concat({
    "local M = {}",
    "",
    "--- Computes the sum of two numbers.",
    "--- @param a number",
    "--- @param b number",
    "function M.add(a, b)",
    "  return a + b",
    "end",
    "",
    "return M",
  }, "\n")

  local result = docstring.extract_from_content(content, 6)
  MiniTest.expect.equality(result, "--- Computes the sum of two numbers.\n--- @param a number\n--- @param b number")
end

-- extract_from_content: no docstring falls back to function body
T["extract_from_content returns function body when no docstring present"] = function()
  local docstring = require("ataraxy.context.docstring")
  local content = table.concat({
    "local M = {}",
    "",
    "function M.multiply(a, b)",
    "  return a * b",
    "end",
    "",
    "return M",
  }, "\n")

  local result = docstring.extract_from_content(content, 3)
  MiniTest.expect.equality(result, "function M.multiply(a, b)\n  return a * b\nend")
end

-- extract_from_content: nested function body extracted correctly
T["extract_from_content handles nested blocks in function body"] = function()
  local docstring = require("ataraxy.context.docstring")
  local content = table.concat({
    "function outer(x)",
    "  if x > 0 then",
    "    return x",
    "  end",
    "end",
    "local y = 1",
  }, "\n")

  local result = docstring.extract_from_content(content, 1)
  MiniTest.expect.equality(result, "function outer(x)\n  if x > 0 then\n    return x\n  end\nend")
end

-- extract_from_content: lineno out of range returns empty string
T["extract_from_content returns empty string for out-of-range lineno"] = function()
  local docstring = require("ataraxy.context.docstring")
  local result = docstring.extract_from_content("line one\nline two", 99)
  MiniTest.expect.equality(result, "")
end

-- extract_from_content: docstring with blank line separator
T["extract_from_content tolerates one blank line between docstring and definition"] = function()
  local docstring = require("ataraxy.context.docstring")
  local content = table.concat({
    "--- My function docs.",
    "",
    "function my_fn()",
    "  return 1",
    "end",
  }, "\n")

  local result = docstring.extract_from_content(content, 3)
  MiniTest.expect.equality(result, "--- My function docs.")
end

-- extract: async reads a real temp file
T["extract reads a real file and returns docstring asynchronously"] = function()
  local docstring = require("ataraxy.context.docstring")

  local tmpfile = vim.fn.tempname() .. ".lua"
  local lines = {
    "--- Does something useful.",
    "function do_thing()",
    "  return true",
    "end",
  }
  vim.fn.writefile(lines, tmpfile)

  local done = false
  local received = nil

  docstring.extract(tmpfile, 2, function(text)
    received = text
    done = true
  end)

  vim.wait(5000, function() return done end, 50)
  vim.fn.delete(tmpfile)

  MiniTest.expect.equality(done, true)
  MiniTest.expect.equality(received, "--- Does something useful.")
end

-- extract: missing file returns empty string
T["extract returns empty string when file does not exist"] = function()
  local docstring = require("ataraxy.context.docstring")

  local done = false
  local received = nil

  docstring.extract("/nonexistent/path/file.lua", 1, function(text)
    received = text
    done = true
  end)

  vim.wait(5000, function() return done end, 50)
  MiniTest.expect.equality(done, true)
  MiniTest.expect.equality(received, "")
end

return T
