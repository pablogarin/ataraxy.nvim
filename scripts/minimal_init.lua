local data_path = vim.fn.stdpath("data")
local mini_path = data_path .. "/ataraxy-test-deps/mini.nvim"

if not vim.loop.fs_stat(mini_path) then
  vim.fn.mkdir(vim.fn.fnamemodify(mini_path, ":h"), "p")
  local out = vim.fn.system({
    "git", "clone", "--filter=blob:none", "--depth=1",
    "https://github.com/echasnovski/mini.nvim", mini_path,
  })
  if vim.v.shell_error ~= 0 then
    io.write("ERROR: failed to clone mini.nvim:\n" .. tostring(out) .. "\n")
    vim.cmd("1cq")
    return
  end
end

vim.opt.rtp:prepend(mini_path)
vim.opt.rtp:prepend(vim.fn.getcwd())

local ok, mini_test = pcall(require, "mini.test")
if not ok then
  io.write("ERROR: could not load mini.test: " .. tostring(mini_test) .. "\n")
  vim.cmd("1cq")
  return
end

mini_test.setup({
  execute = {
    reporter = mini_test.gen_reporter.stdout({ group_depth = 2 }),
  },
})
