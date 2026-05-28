local assert = require("luassert")

describe("ataraxy.agent.skills", function()
  local skills

  before_each(function()
    package.loaded["ataraxy.agent.skills"] = nil
    skills = require("ataraxy.agent.skills")
  end)

  it("get_system_prompt returns base prompt when no skill given", function()
    local p = skills.get_system_prompt()
    assert.truthy(p:find("elite software engineering agent"))
  end)

  it("get_system_prompt appends template for known skill", function()
    local p = skills.get_system_prompt("refactor")
    assert.truthy(p:find("Refactor"))
    assert.truthy(p:find("elite software engineering agent"))
  end)

  it("get_system_prompt returns base prompt for unknown skill", function()
    local p = skills.get_system_prompt("nonexistent_skill")
    assert.truthy(p:find("elite software engineering agent"))
    assert.falsy(p:find("Refactor"))
  end)

  it("all template keys are present", function()
    for _, key in ipairs({ "refactor", "document", "test", "fix" }) do
      assert.truthy(skills.templates[key], "missing template: " .. key)
    end
  end)
end)
