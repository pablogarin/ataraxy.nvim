local config = require("ataraxy.config")

local M = {}

local function find_project_root()
  local markers = { ".git", ".ataraxy.md", "package.json", "Makefile", "pyproject.toml" }
  local path = vim.fn.expand("%:p:h")
  while path and path ~= "/" do
    for _, marker in ipairs(markers) do
      if vim.fn.filereadable(path .. "/" .. marker) == 1
        or vim.fn.isdirectory(path .. "/" .. marker) == 1
      then
        return path
      end
    end
    path = vim.fn.fnamemodify(path, ":h")
  end
  return vim.fn.getcwd()
end

function M.load_workspace_context()
  local opts = config.options.agent or config.defaults.agent
  local root = find_project_root()
  local ctx_path = root .. "/" .. opts.context_file

  if vim.fn.filereadable(ctx_path) == 0 then
    return ""
  end

  local lines = vim.fn.readfile(ctx_path)
  return table.concat(lines, "\n")
end

function M.load_active_file(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n")
end

function M.load_skills()
  local opts = config.options.agent or config.defaults.agent
  local root = find_project_root()
  local skills_path = root .. "/" .. opts.skills_dir

  if vim.fn.isdirectory(skills_path) == 0 then
    return ""
  end

  local files = vim.fn.glob(skills_path .. "/*.md", false, true)
  if #files == 0 then
    files = vim.fn.glob(skills_path .. "/*.txt", false, true)
  end

  local parts = {}
  for _, fpath in ipairs(files) do
    local lines = vim.fn.readfile(fpath)
    if lines and #lines > 0 then
      table.insert(parts, table.concat(lines, "\n"))
    end
  end

  return table.concat(parts, "\n\n---\n\n")
end

function M.reload_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("edit!")
  end)
  vim.notify("[ataraxy] Buffer reloaded.", vim.log.levels.INFO)
end

return M
