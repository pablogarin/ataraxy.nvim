local MiniTest = require("mini.test")

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["ataraxy.context.symbols"] = nil
    end,
  },
})

-- extract_symbols: basic word extraction
T["extract_symbols returns identifiers from prefix"] = function()
  local symbols = require("ataraxy.context.symbols")
  local result = symbols.extract_symbols("local x = foo.bar(baz)")
  MiniTest.expect.equality(type(result), "table")
  -- should contain multi-char identifiers: foo.bar, baz (and possibly others)
  local found = {}
  for _, v in ipairs(result) do found[v] = true end
  MiniTest.expect.equality(found["foo.bar"], true)
  MiniTest.expect.equality(found["baz"], true)
end

-- extract_symbols: single-char identifiers are skipped
T["extract_symbols skips single-char identifiers"] = function()
  local symbols = require("ataraxy.context.symbols")
  local result = symbols.extract_symbols("a = bb + c")
  local found = {}
  for _, v in ipairs(result) do found[v] = true end
  MiniTest.expect.equality(found["a"], nil)
  MiniTest.expect.equality(found["c"], nil)
  MiniTest.expect.equality(found["bb"], true)
end

-- extract_symbols: empty prefix returns empty list
T["extract_symbols on empty prefix returns empty table"] = function()
  local symbols = require("ataraxy.context.symbols")
  local result = symbols.extract_symbols("")
  MiniTest.expect.equality(#result, 0)
end

-- extract_symbols: deduplicates
T["extract_symbols deduplicates repeated identifiers"] = function()
  local symbols = require("ataraxy.context.symbols")
  local result = symbols.extract_symbols("foo foo foo bar")
  local count = 0
  for _, v in ipairs(result) do
    if v == "foo" then count = count + 1 end
  end
  MiniTest.expect.equality(count, 1)
end

-- extract_symbols: most-recently-seen symbol is last
T["extract_symbols preserves order with most-recent last"] = function()
  local symbols = require("ataraxy.context.symbols")
  local result = symbols.extract_symbols("alpha beta gamma")
  MiniTest.expect.equality(result[#result], "gamma")
end

-- find_definition: symbol not found returns empty table
T["find_definition calls callback with empty table when symbol not found"] = function()
  local symbols = require("ataraxy.context.symbols")
  local done = false
  local received = nil

  symbols.find_definition("__nonexistent_symbol_xyz__", vim.fn.getcwd(), function(res)
    received = res
    done = true
  end)

  vim.wait(5000, function() return done end, 50)
  MiniTest.expect.equality(done, true)
  MiniTest.expect.equality(type(received), "table")
  MiniTest.expect.equality(#received, 0)
end

-- resolve: empty prefix calls back with empty string
T["resolve with empty prefix calls callback with empty string"] = function()
  local symbols = require("ataraxy.context.symbols")
  local done = false
  local received = nil

  symbols.resolve("", vim.fn.getcwd(), function(text)
    received = text
    done = true
  end)

  vim.wait(5000, function() return done end, 50)
  MiniTest.expect.equality(done, true)
  MiniTest.expect.equality(received, "")
end

-- resolve: symbol not in workspace calls back with empty string
T["resolve with unknown symbol calls callback with empty string"] = function()
  local symbols = require("ataraxy.context.symbols")
  local done = false
  local received = nil

  symbols.resolve("__totally_unknown_sym_abc123__", vim.fn.getcwd(), function(text)
    received = text
    done = true
  end)

  vim.wait(5000, function() return done end, 50)
  MiniTest.expect.equality(done, true)
  MiniTest.expect.equality(received, "")
end

return T
