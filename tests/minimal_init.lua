-- Reset the persistent bytecode cache so edited modules are never served stale.
if vim.loader then vim.loader.reset() end

-- Wipe any ataraxy modules the user's plugin config may have pre-loaded.
for k in pairs(package.loaded) do
  if k:match("^ataraxy") then package.loaded[k] = nil end
end

local plenary_path = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
if vim.fn.isdirectory(plenary_path) == 0 then
  plenary_path = vim.fn.stdpath("data") .. "/site/pack/packer/start/plenary.nvim"
end
vim.opt.rtp:prepend(plenary_path)
vim.opt.rtp:prepend(vim.fn.getcwd())
