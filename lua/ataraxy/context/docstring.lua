local M = {}

local function split_lines(content)
  local lines = {}
  for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
  end
  return lines
end

-- Pure extraction from file content string. Exported for testing.
function M.extract_from_content(content, lineno)
  local lines = split_lines(content)
  if lineno < 1 or lineno > #lines then
    return ""
  end

  -- Search upward from the line before the definition for --- doc comments
  local doc_lines = {}
  local i = lineno - 1
  while i >= 1 do
    local line = lines[i]
    if line:match("^%s*%-%-%%-") then
      table.insert(doc_lines, 1, line)
      i = i - 1
    elseif line:match("^%s*$") and i == lineno - 1 then
      -- allow one blank line between doc block and definition
      i = i - 1
    else
      break
    end
  end

  if #doc_lines > 0 then
    return table.concat(doc_lines, "\n")
  end

  -- No docstring: extract function body by tracking block depth
  local body = {}
  local depth = 0
  for j = lineno, #lines do
    local line = lines[j]
    body[#body + 1] = line
    for _ in line:gmatch("%f[%a]function%f[%A]") do depth = depth + 1 end
    for _ in line:gmatch("%f[%a]if%f[%A]") do depth = depth + 1 end
    for _ in line:gmatch("%f[%a]for%f[%A]") do depth = depth + 1 end
    for _ in line:gmatch("%f[%a]while%f[%A]") do depth = depth + 1 end
    for _ in line:gmatch("%f[%a]do%f[%A]") do depth = depth + 1 end
    for _ in line:gmatch("%f[%a]end%f[%A]") do depth = depth - 1 end
    if depth <= 0 and j > lineno then
      break
    end
  end
  return table.concat(body, "\n")
end

function M.extract(filepath, lineno, callback)
  vim.system({ "cat", filepath }, { text = true }, function(out)
    if out.code ~= 0 or not out.stdout then
      vim.schedule(function() callback("") end)
      return
    end
    local result = M.extract_from_content(out.stdout, lineno)
    vim.schedule(function() callback(result) end)
  end)
end

return M
