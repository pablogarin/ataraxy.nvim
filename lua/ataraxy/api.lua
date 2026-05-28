local config = require("ataraxy.config")

local M = {}

local active_jobs = {}

local function build_request_body(messages, system_prompt, stream)
  local opts = config.options
  local body = {
    model = opts.model or config.defaults.model,
    temperature = opts.temperature or config.defaults.temperature,
    stream = stream ~= false,
    messages = messages,
  }
  if system_prompt then
    table.insert(body.messages, 1, { role = "system", content = system_prompt })
  end
  return vim.json.encode(body)
end

local function parse_sse_chunk(chunk, on_token)
  for line in chunk:gmatch("[^\n]+") do
    if line:match("^data: %[DONE%]") then
      return true
    end
    local data = line:match("^data: (.+)$")
    if data then
      local ok, decoded = pcall(vim.json.decode, data)
      if ok and decoded.choices and decoded.choices[1] then
        local delta = decoded.choices[1].delta
        if delta and delta.content then
          on_token(delta.content)
        end
      end
    end
  end
  return false
end

function M.stream(messages, system_prompt, on_token, on_done, on_error)
  local opts = config.options
  local api_key = opts.api_key or config.defaults.api_key
  local endpoint = (opts.api_endpoint or config.defaults.api_endpoint) .. "/v1/chat/completions"

  if api_key == "" then
    if on_error then on_error("No API key configured.") end
    return nil
  end

  local body = build_request_body(messages, system_prompt, true)
  local body_file = os.tmpname()
  local f = io.open(body_file, "w")
  f:write(body)
  f:close()

  local cmd = {
    "curl", "--silent", "--no-buffer", "--fail-with-body",
    "-X", "POST", endpoint,
    "-H", "Content-Type: application/json",
    "-H", "Authorization: Bearer " .. api_key,
    "--data-binary", "@" .. body_file,
  }

  local buffer = ""
  local job_id = tostring({}):match("0x(.+)")
  local job = vim.system(cmd, {
    stdout = function(err, chunk)
      if err then
        if on_error then
          vim.schedule(function() on_error(tostring(err)) end)
        end
        return
      end
      if chunk then
        buffer = buffer .. chunk
        local lines = {}
        for line in (buffer .. "\n"):gmatch("([^\n]*)\n") do
          table.insert(lines, line)
        end
        buffer = lines[#lines] or ""
        table.remove(lines, #lines)
        local done = false
        for _, line in ipairs(lines) do
          if line:match("^data: %[DONE%]") then
            done = true
            break
          end
          local data = line:match("^data: (.+)$")
          if data then
            local ok, decoded = pcall(vim.json.decode, data)
            if ok and decoded.choices and decoded.choices[1] then
              local delta = decoded.choices[1].delta
              if delta and delta.content then
                local token = delta.content
                vim.schedule(function() on_token(token) end)
              end
            end
          end
        end
        if done then
          vim.schedule(function()
            os.remove(body_file)
            active_jobs[job_id] = nil
            if on_done then on_done() end
          end)
        end
      end
    end,
  }, function(result)
    os.remove(body_file)
    active_jobs[job_id] = nil
    if result.code ~= 0 then
      if on_error then
        vim.schedule(function()
          on_error("curl exited with code " .. result.code .. ": " .. (result.stderr or ""))
        end)
      end
    else
      vim.schedule(function()
        if on_done then on_done() end
      end)
    end
  end)

  active_jobs[job_id] = job
  return job_id
end

function M.cancel(job_id)
  if job_id and active_jobs[job_id] then
    active_jobs[job_id]:kill(9)
    active_jobs[job_id] = nil
  end
end

function M.cancel_all()
  for id, job in pairs(active_jobs) do
    job:kill(9)
    active_jobs[id] = nil
  end
end

return M
