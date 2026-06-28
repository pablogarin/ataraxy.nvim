local MiniTest = require("mini.test")

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["ataraxy.completion.trigger"] = nil
    end,
    post_case = function()
      -- Ensure no timer leaks between tests
      local ok, trigger = pcall(require, "ataraxy.completion.trigger")
      if ok then trigger.cancel() end
      package.loaded["ataraxy.completion.trigger"] = nil
    end,
  },
})

-- arm: callback fires after delay
T["arm fires callback after the specified delay"] = function()
  local trigger = require("ataraxy.completion.trigger")
  local fired = false

  trigger.arm(50, function() fired = true end)

  vim.wait(500, function() return fired end, 10)
  MiniTest.expect.equality(fired, true)
end

-- reset: cancels previous arm and restarts; callback fires once
T["reset cancels previous timer and callback fires exactly once"] = function()
  local trigger = require("ataraxy.completion.trigger")
  local count = 0

  trigger.arm(80, function() count = count + 1 end)
  vim.wait(30, function() return false end, 10)   -- wait less than 80ms
  trigger.reset(80, function() count = count + 1 end)

  vim.wait(500, function() return count > 0 end, 10)
  -- Give extra time to confirm second callback does not fire
  vim.wait(150, function() return false end, 10)

  MiniTest.expect.equality(count, 1)
end

-- cancel: prevents callback from firing
T["cancel prevents the armed callback from firing"] = function()
  local trigger = require("ataraxy.completion.trigger")
  local fired = false

  trigger.arm(60, function() fired = true end)
  trigger.cancel()

  vim.wait(200, function() return fired end, 10)
  MiniTest.expect.equality(fired, false)
end

-- fire: invokes callback immediately, does not wait for delay
T["fire invokes callback immediately without waiting for delay"] = function()
  local trigger = require("ataraxy.completion.trigger")
  local fired = false

  trigger.arm(500, function() fired = true end)
  trigger.fire(function() fired = true end)

  -- Should be true immediately (fire is synchronous)
  MiniTest.expect.equality(fired, true)
end

-- fire: cancels any pending debounce timer
T["fire cancels the pending debounce timer"] = function()
  local trigger = require("ataraxy.completion.trigger")
  local arm_fired = false
  local fire_fired = false

  trigger.arm(60, function() arm_fired = true end)
  trigger.fire(function() fire_fired = true end)

  vim.wait(200, function() return false end, 10)
  MiniTest.expect.equality(fire_fired, true)
  MiniTest.expect.equality(arm_fired, false)
end

-- reset then cancel: no callback fires
T["reset followed by cancel produces no callback"] = function()
  local trigger = require("ataraxy.completion.trigger")
  local fired = false

  trigger.reset(60, function() fired = true end)
  trigger.cancel()

  vim.wait(200, function() return fired end, 10)
  MiniTest.expect.equality(fired, false)
end

return T
