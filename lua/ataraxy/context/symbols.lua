local M = {}

function M.extract_symbols(prefix)
  local seen = {}
  local ordered = {}
  for word in prefix:gmatch("[%a_][%w_%.]*") do
    if #word > 1 and not seen[word] then
      seen[word] = true
      ordered[#ordered + 1] = word
    end
  end
  return ordered
end

function M.find_definition(symbol, cwd, callback)
  local pattern = "function[[:space:]].*" .. symbol
  vim.system(
    { "grep", "-rn", "--include=*.lua", "-E", "-m", "5", pattern, cwd },
    { text = true },
    function(out)
      if out.code ~= 0 or not out.stdout or out.stdout == "" then
        callback({})
        return
      end
      local results = {}
      for line in out.stdout:gmatch("[^\n]+") do
        local file, lineno, match = line:match("^([^:]+):(%d+):(.*)")
        if file then
          results[#results + 1] = { file = file, line = tonumber(lineno), match = match }
        end
      end
      callback(results)
    end
  )
end

-- Depth-1 cap: only symbols extracted from the original prefix are searched.
-- Definitions found in result files are never recursively searched for imports.
function M.resolve(prefix, cwd, callback)
  local symbols = M.extract_symbols(prefix)
  if #symbols == 0 then
    callback("")
    return
  end

  local symbol = symbols[#symbols]
  M.find_definition(symbol, cwd, function(results)
    if #results == 0 then
      callback("")
      return
    end
    local docstring = require("ataraxy.context.docstring")
    docstring.extract(results[1].file, results[1].line, function(text)
      callback(text)
    end)
  end)
end

return M
