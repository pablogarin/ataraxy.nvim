local assert = require("luassert")

describe("ataraxy.config", function()
  local config

  before_each(function()
    package.loaded["ataraxy.config"] = nil
    config = require("ataraxy.config")
  end)

  it("has correct defaults", function()
    assert.equals("gpt-4o-mini", config.defaults.model)
    assert.equals(300, config.defaults.debounce_ms)
    assert.equals(0.0, config.defaults.temperature)
    assert.equals(".ataraxy.md", config.defaults.agent.context_file)
  end)

  it("setup merges user options", function()
    config.setup({ model = "gpt-4o", debounce_ms = 150 })
    assert.equals("gpt-4o", config.options.model)
    assert.equals(150, config.options.debounce_ms)
    assert.equals(0.0, config.options.temperature)
  end)

  it("get returns merged option", function()
    config.setup({ model = "gpt-4-turbo" })
    assert.equals("gpt-4-turbo", config.get("model"))
  end)

  it("get falls back to defaults for unset keys", function()
    config.setup({})
    assert.equals(300, config.get("debounce_ms"))
  end)

  it("deep merges agent sub-table", function()
    config.setup({ agent = { skills_dir = "custom/skills" } })
    assert.equals("custom/skills", config.options.agent.skills_dir)
    assert.equals(".ataraxy.md", config.options.agent.context_file)
  end)
end)
