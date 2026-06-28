local M = {}

local _timer = nil

local function stop_timer()
  if _timer then
    _timer:stop()
    _timer:close()
    _timer = nil
  end
end

function M.arm(delay_ms, callback)
  stop_timer()
  _timer = vim.uv.new_timer()
  _timer:start(delay_ms, 0, function()
    stop_timer()
    vim.schedule(callback)
  end)
end

function M.reset(delay_ms, callback)
  M.arm(delay_ms, callback)
end

function M.cancel()
  stop_timer()
end

function M.fire(callback)
  stop_timer()
  callback()
end

return M
