local M = {}

local _config = nil

local function resolve(env_name)
  if type(env_name) ~= "string" or env_name == "" then
    return nil
  end
  local val = os.getenv(env_name)
  if not val or val == "" then
    return nil
  end
  return val
end

function M.load(opts)
  opts = opts or {}
  _config = { enabled = false }

  local api_key = resolve(opts.api_key_env)
  if not api_key then
    return _config
  end

  if type(opts.base_url) ~= "string" or opts.base_url == "" then
    return _config
  end

  local model = resolve(opts.model_env)
  if not model then
    return _config
  end

  local trigger = opts.trigger
  if trigger == nil then
    trigger = "auto"
  elseif trigger ~= "auto" and trigger ~= "manual" then
    return _config
  end

  local debounce_ms = opts.debounce_ms
  if debounce_ms == nil then
    debounce_ms = 600
  elseif type(debounce_ms) ~= "number" or debounce_ms < 500 or debounce_ms > 1000 then
    return _config
  end

  _config = {
    enabled = true,
    api_key = api_key,
    base_url = opts.base_url,
    model = model,
    trigger = trigger,
    debounce_ms = debounce_ms,
  }
  return _config
end

function M.get()
  return _config
end

function M.is_enabled()
  return _config ~= nil and _config.enabled == true
end

return M
