local MiniTest = require("mini.test")

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["ataraxy.api"] = nil
    end,
  },
})

-- parse_sse_line: valid data chunk
T["parse_sse_line extracts content token from valid SSE chunk"] = function()
  local api = require("ataraxy.api")
  local chunk = vim.fn.json_encode({
    choices = { { delta = { content = "hello" } } },
  })
  local result = api.parse_sse_line("data: " .. chunk)
  MiniTest.expect.equality(result, "hello")
end

-- parse_sse_line: [DONE] sentinel returns nil
T["parse_sse_line returns nil for [DONE] sentinel"] = function()
  local api = require("ataraxy.api")
  local result = api.parse_sse_line("data: [DONE]")
  MiniTest.expect.equality(result, nil)
end

-- parse_sse_line: non-data line returns nil
T["parse_sse_line returns nil for non-data lines"] = function()
  local api = require("ataraxy.api")
  MiniTest.expect.equality(api.parse_sse_line(""), nil)
  MiniTest.expect.equality(api.parse_sse_line(": keep-alive"), nil)
  MiniTest.expect.equality(api.parse_sse_line("event: message"), nil)
end

-- parse_sse_line: malformed JSON returns nil
T["parse_sse_line returns nil for malformed JSON"] = function()
  local api = require("ataraxy.api")
  local result = api.parse_sse_line("data: {not valid json")
  MiniTest.expect.equality(result, nil)
end

-- parse_sse_line: missing choices field returns nil
T["parse_sse_line returns nil when choices field is absent"] = function()
  local api = require("ataraxy.api")
  local chunk = vim.fn.json_encode({ id = "1", object = "chat.completion.chunk" })
  local result = api.parse_sse_line("data: " .. chunk)
  MiniTest.expect.equality(result, nil)
end

-- parse_sse_line: nil delta content returns nil (role-only delta)
T["parse_sse_line returns nil when delta has no content field"] = function()
  local api = require("ataraxy.api")
  local chunk = vim.fn.json_encode({
    choices = { { delta = { role = "assistant" } } },
  })
  local result = api.parse_sse_line("data: " .. chunk)
  MiniTest.expect.equality(result, nil)
end

-- is_active: false when no request running
T["is_active returns false when no request is active"] = function()
  local api = require("ataraxy.api")
  MiniTest.expect.equality(api.is_active(), false)
end

-- cancel: safe to call when no job is active
T["cancel is a no-op when no request is active"] = function()
  local api = require("ataraxy.api")
  -- Should not error
  api.cancel()
  MiniTest.expect.equality(api.is_active(), false)
end

-- Successful streaming via a mock curl (cat-based fixture)
T["request streams tokens from SSE fixture via mock curl"] = function()
  local api = require("ataraxy.api")

  -- Build a fixture file with pre-recorded SSE payloads
  local lines = {
    "data: " .. vim.fn.json_encode({ choices = { { delta = { content = "foo" } } } }),
    "data: " .. vim.fn.json_encode({ choices = { { delta = { content = " bar" } } } }),
    "data: [DONE]",
    "",
  }
  local fixture = vim.fn.tempname()
  vim.fn.writefile(lines, fixture)

  -- Monkey-patch vim.system to cat the fixture instead of running curl
  local orig_system = vim.system
  vim.system = function(cmd, opts, on_exit)
    local fake_cmd = { "cat", fixture }
    return orig_system(fake_cmd, opts, on_exit)
  end

  local tokens = {}
  local done = false
  local success = nil

  local cfg = { api_key = "k", base_url = "http://x", model = "m" }
  local payload = { model = "m", messages = {}, stream = true }

  api.request(cfg, payload, function(tok)
    tokens[#tokens + 1] = tok
  end, function(ok)
    success = ok
    done = true
  end)

  vim.wait(5000, function() return done end, 50)
  vim.system = orig_system
  vim.fn.delete(fixture)

  MiniTest.expect.equality(done, true)
  MiniTest.expect.equality(success, true)
  MiniTest.expect.equality(tokens[1], "foo")
  MiniTest.expect.equality(tokens[2], " bar")
  MiniTest.expect.equality(#tokens, 2)
end

-- cancel terminates an active request
T["cancel terminates an active request mid-stream"] = function()
  local api = require("ataraxy.api")

  -- Use a long-running command as the mock curl
  local orig_system = vim.system
  vim.system = function(_, opts, on_exit)
    return orig_system({ "sleep", "60" }, opts, on_exit)
  end

  local cfg = { api_key = "k", base_url = "http://x", model = "m" }
  local payload = { model = "m", messages = {}, stream = true }
  local done = false

  api.request(cfg, payload, function() end, function()
    done = true
  end)

  MiniTest.expect.equality(api.is_active(), true)
  api.cancel()
  MiniTest.expect.equality(api.is_active(), false)

  vim.system = orig_system

  -- on_done may fire asynchronously after kill; just verify is_active is false
  vim.wait(1000, function() return done end, 50)
end

-- non-zero exit code: on_done called with false
T["request calls on_done with false on non-zero curl exit"] = function()
  local api = require("ataraxy.api")

  local orig_system = vim.system
  vim.system = function(_, opts, on_exit)
    return orig_system({ "false" }, opts, on_exit)
  end

  local done = false
  local success = nil
  local cfg = { api_key = "k", base_url = "http://x", model = "m" }
  local payload = { model = "m", messages = {}, stream = true }

  api.request(cfg, payload, function() end, function(ok)
    success = ok
    done = true
  end)

  vim.wait(5000, function() return done end, 50)
  vim.system = orig_system

  MiniTest.expect.equality(done, true)
  MiniTest.expect.equality(success, false)
end

return T
