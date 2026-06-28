local MiniTest = require("mini.test")

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["ataraxy.config"] = nil
    end,
  },
})

T["enabled when all credentials resolve"] = function()
  vim.fn.setenv("ATARAXY_T_KEY", "sk-test-key")
  vim.fn.setenv("ATARAXY_T_MODEL", "gpt-4o-mini")

  local config = require("ataraxy.config")
  local cfg = config.load({
    api_key_env = "ATARAXY_T_KEY",
    model_env = "ATARAXY_T_MODEL",
    base_url = "https://api.example.com/v1",
  })

  MiniTest.expect.equality(cfg.enabled, true)
  MiniTest.expect.equality(cfg.api_key, "sk-test-key")
  MiniTest.expect.equality(cfg.model, "gpt-4o-mini")
  MiniTest.expect.equality(cfg.base_url, "https://api.example.com/v1")

  vim.fn.setenv("ATARAXY_T_KEY", nil)
  vim.fn.setenv("ATARAXY_T_MODEL", nil)
end

T["is_enabled returns true when config is valid"] = function()
  vim.fn.setenv("ATARAXY_T_KEY2", "sk-test-key")
  vim.fn.setenv("ATARAXY_T_MODEL2", "gpt-4o-mini")

  local config = require("ataraxy.config")
  config.load({
    api_key_env = "ATARAXY_T_KEY2",
    model_env = "ATARAXY_T_MODEL2",
    base_url = "https://api.example.com/v1",
  })

  MiniTest.expect.equality(config.is_enabled(), true)

  vim.fn.setenv("ATARAXY_T_KEY2", nil)
  vim.fn.setenv("ATARAXY_T_MODEL2", nil)
end

T["get returns nil before load is called"] = function()
  local config = require("ataraxy.config")
  MiniTest.expect.equality(config.get(), nil)
  MiniTest.expect.equality(config.is_enabled(), false)
end

T["disabled when api_key_env resolves to nil"] = function()
  local config = require("ataraxy.config")
  local cfg = config.load({
    api_key_env = "ATARAXY_NONEXISTENT_KEY_9a3f",
    model_env = "ATARAXY_T_MODEL_SKIP",
    base_url = "https://api.example.com/v1",
  })

  MiniTest.expect.equality(cfg.enabled, false)
  MiniTest.expect.equality(config.is_enabled(), false)
end

T["disabled when api_key_env resolves to empty string"] = function()
  vim.fn.setenv("ATARAXY_T_EMPTY_KEY", "")

  local config = require("ataraxy.config")
  local cfg = config.load({
    api_key_env = "ATARAXY_T_EMPTY_KEY",
    model_env = "ATARAXY_T_MODEL_SKIP",
    base_url = "https://api.example.com/v1",
  })

  MiniTest.expect.equality(cfg.enabled, false)

  vim.fn.setenv("ATARAXY_T_EMPTY_KEY", nil)
end

T["disabled when base_url is absent"] = function()
  vim.fn.setenv("ATARAXY_T_KEY3", "sk-test-key")
  vim.fn.setenv("ATARAXY_T_MODEL3", "gpt-4o-mini")

  local config = require("ataraxy.config")
  local cfg = config.load({
    api_key_env = "ATARAXY_T_KEY3",
    model_env = "ATARAXY_T_MODEL3",
  })

  MiniTest.expect.equality(cfg.enabled, false)

  vim.fn.setenv("ATARAXY_T_KEY3", nil)
  vim.fn.setenv("ATARAXY_T_MODEL3", nil)
end

T["disabled when base_url is empty string"] = function()
  vim.fn.setenv("ATARAXY_T_KEY4", "sk-test-key")
  vim.fn.setenv("ATARAXY_T_MODEL4", "gpt-4o-mini")

  local config = require("ataraxy.config")
  local cfg = config.load({
    api_key_env = "ATARAXY_T_KEY4",
    model_env = "ATARAXY_T_MODEL4",
    base_url = "",
  })

  MiniTest.expect.equality(cfg.enabled, false)

  vim.fn.setenv("ATARAXY_T_KEY4", nil)
  vim.fn.setenv("ATARAXY_T_MODEL4", nil)
end

T["disabled when model_env resolves to nil"] = function()
  vim.fn.setenv("ATARAXY_T_KEY5", "sk-test-key")

  local config = require("ataraxy.config")
  local cfg = config.load({
    api_key_env = "ATARAXY_T_KEY5",
    model_env = "ATARAXY_NONEXISTENT_MODEL_9a3f",
    base_url = "https://api.example.com/v1",
  })

  MiniTest.expect.equality(cfg.enabled, false)

  vim.fn.setenv("ATARAXY_T_KEY5", nil)
end

T["defaults applied when trigger and debounce_ms are omitted"] = function()
  vim.fn.setenv("ATARAXY_T_KEY6", "sk-test-key")
  vim.fn.setenv("ATARAXY_T_MODEL6", "gpt-4o-mini")

  local config = require("ataraxy.config")
  local cfg = config.load({
    api_key_env = "ATARAXY_T_KEY6",
    model_env = "ATARAXY_T_MODEL6",
    base_url = "https://api.example.com/v1",
  })

  MiniTest.expect.equality(cfg.trigger, "auto")
  MiniTest.expect.equality(cfg.debounce_ms, 600)

  vim.fn.setenv("ATARAXY_T_KEY6", nil)
  vim.fn.setenv("ATARAXY_T_MODEL6", nil)
end

T["manual trigger and custom debounce_ms accepted"] = function()
  vim.fn.setenv("ATARAXY_T_KEY7", "sk-test-key")
  vim.fn.setenv("ATARAXY_T_MODEL7", "gpt-4o-mini")

  local config = require("ataraxy.config")
  local cfg = config.load({
    api_key_env = "ATARAXY_T_KEY7",
    model_env = "ATARAXY_T_MODEL7",
    base_url = "https://api.example.com/v1",
    trigger = "manual",
    debounce_ms = 800,
  })

  MiniTest.expect.equality(cfg.enabled, true)
  MiniTest.expect.equality(cfg.trigger, "manual")
  MiniTest.expect.equality(cfg.debounce_ms, 800)

  vim.fn.setenv("ATARAXY_T_KEY7", nil)
  vim.fn.setenv("ATARAXY_T_MODEL7", nil)
end

T["invalid trigger value disables plugin"] = function()
  vim.fn.setenv("ATARAXY_T_KEY8", "sk-test-key")
  vim.fn.setenv("ATARAXY_T_MODEL8", "gpt-4o-mini")

  local config = require("ataraxy.config")
  local cfg = config.load({
    api_key_env = "ATARAXY_T_KEY8",
    model_env = "ATARAXY_T_MODEL8",
    base_url = "https://api.example.com/v1",
    trigger = "invalid",
  })

  MiniTest.expect.equality(cfg.enabled, false)

  vim.fn.setenv("ATARAXY_T_KEY8", nil)
  vim.fn.setenv("ATARAXY_T_MODEL8", nil)
end

T["debounce_ms out of range disables plugin"] = function()
  vim.fn.setenv("ATARAXY_T_KEY9", "sk-test-key")
  vim.fn.setenv("ATARAXY_T_MODEL9", "gpt-4o-mini")

  local config = require("ataraxy.config")
  local cfg = config.load({
    api_key_env = "ATARAXY_T_KEY9",
    model_env = "ATARAXY_T_MODEL9",
    base_url = "https://api.example.com/v1",
    debounce_ms = 200,
  })

  MiniTest.expect.equality(cfg.enabled, false)

  vim.fn.setenv("ATARAXY_T_KEY9", nil)
  vim.fn.setenv("ATARAXY_T_MODEL9", nil)
end

return T
