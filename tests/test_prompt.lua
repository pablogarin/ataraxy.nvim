local assert = require("luassert")

describe("ataraxy.prompt", function()
  local prompt_mod

  before_each(function()
    package.loaded["ataraxy.prompt"] = nil
    package.loaded["ataraxy.config"] = nil
    prompt_mod = require("ataraxy.prompt")
  end)

  describe("build_fim", function()
    it("returns prefix and suffix strings from buffer content", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "line one",
        "line two",
        "line three",
      })
      local prefix, suffix = prompt_mod.build_fim(bufnr, 1, 4)
      assert.truthy(prefix:find("line one"))
      assert.truthy(prefix:find("line"))
      assert.truthy(suffix ~= nil)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("handles cursor at start of buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello world" })
      local prefix, suffix = prompt_mod.build_fim(bufnr, 0, 0)
      assert.equals("", prefix)
      assert.truthy(suffix:find("hello world"))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("handles cursor at end of buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "only line" })
      local prefix, suffix = prompt_mod.build_fim(bufnr, 0, 9)
      assert.truthy(prefix:find("only line"))
      assert.equals("", suffix)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("build_fim_messages", function()
    it("returns a table with a single user message", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = 1" })
      local msgs = prompt_mod.build_fim_messages(bufnr, 0, 5)
      assert.equals(1, #msgs)
      assert.equals("user", msgs[1].role)
      assert.truthy(msgs[1].content:find("<PREFIX>"))
      assert.truthy(msgs[1].content:find("<SUFFIX>"))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("build_agent_messages", function()
    it("includes all context parts when provided", function()
      local msgs = prompt_mod.build_agent_messages(
        "file content here",
        "refactor this",
        "workspace context",
        "skill text"
      )
      assert.equals(1, #msgs)
      local c = msgs[1].content
      assert.truthy(c:find("Workspace Context"))
      assert.truthy(c:find("Active Skills"))
      assert.truthy(c:find("Active File"))
      assert.truthy(c:find("Task"))
      assert.truthy(c:find("refactor this"))
    end)

    it("omits missing context sections", function()
      local msgs = prompt_mod.build_agent_messages("file content", "do something", nil, nil)
      local c = msgs[1].content
      assert.falsy(c:find("Workspace Context"))
      assert.falsy(c:find("Active Skills"))
      assert.truthy(c:find("Active File"))
      assert.truthy(c:find("do something"))
    end)
  end)
end)
