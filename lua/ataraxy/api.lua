local M = {}

local _active_job = nil

-- Exported for unit testing.
function M.parse_sse_line(line)
  if not line:match("^data: ") then
    return nil
  end
  local data = line:sub(7)
  if data == "[DONE]" then
    return nil
  end
  local ok, decoded = pcall(vim.fn.json_decode, data)
  if not ok or type(decoded) ~= "table" then
    return nil
  end
  local choices = decoded.choices
  if type(choices) ~= "table" or not choices[1] then
    return nil
  end
  local delta = choices[1].delta
  if type(delta) ~= "table" then
    return nil
  end
  return delta.content
end

function M.request(cfg, payload, on_token, on_done)
  M.cancel()

  local body = vim.fn.json_encode(payload)
  local buf = ""

  _active_job = vim.system(
    {
      "curl", "--silent", "--no-buffer",
      "-X", "POST",
      "-H", "Content-Type: application/json",
      "-H", "Authorization: Bearer " .. cfg.api_key,
      "-d", body,
      cfg.base_url .. "/chat/completions",
    },
    {
      text = false,
      stdout = function(err, chunk)
        if err or not chunk then return end
        buf = buf .. chunk
        -- Collect complete lines in the fast callback; defer vim.fn calls.
        local pending = {}
        while true do
          local nl = buf:find("\n")
          if not nl then break end
          pending[#pending + 1] = buf:sub(1, nl - 1):gsub("\r$", "")
          buf = buf:sub(nl + 1)
        end
        if #pending > 0 then
          vim.schedule(function()
            for _, line in ipairs(pending) do
              local token = M.parse_sse_line(line)
              if token then on_token(token) end
            end
          end)
        end
      end,
    },
    function(out)
      _active_job = nil
      vim.schedule(function() on_done(out.code == 0) end)
    end
  )
end

function M.cancel()
  if _active_job then
    _active_job:kill(9)
    _active_job = nil
  end
end

function M.is_active()
  return _active_job ~= nil
end

return M
