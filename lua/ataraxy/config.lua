local M = {}

M.defaults = {
  api_key = os.getenv("ATARAXY_API_KEY") or os.getenv("OPENAI_API_KEY") or "",
  api_endpoint = "https://api.openai.com",
  model = "gpt-4o-mini",
  temperature = 0.0,
  system_prompt = "You are an elite, low-latency code autocompletion engine. Provide the exact text that belongs between <PREFIX> and <SUFFIX>.\nRules:\n- Analyze <PREFIX> for unclosed loops, blocks, or brackets; generate closing structures.\n- If variables in <PREFIX> are iterable structures (lists, arrays), prioritize loop iterations.\n- If cursor is below a docstring, synthesize the functional execution block matching the text intent.\n- Output raw code only. Do NOT wrap in markdown backticks (```). Do NOT provide commentary.",
  debounce_ms = 300,
  keymaps = {
    accept = "<Tab>",
    reject = "<Esc>",
    trigger = nil,
  },
  agent = {
    context_file = ".ataraxy.md",
    skills_dir = "ataraxy/skills",
  },
}

M.options = {}

local keymap_handlers = {}

function M.setup(user_opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, user_opts or {})
  if M.options.api_key == "" then
    vim.notify("[ataraxy] No API key found. Set ATARAXY_API_KEY or OPENAI_API_KEY.", vim.log.levels.WARN)
  end
end

function M.set_keymaps(buf, on_accept, on_reject, on_trigger)
  local opts = M.options.keymaps or M.defaults.keymaps
  buf = buf or 0

  if on_accept and opts.accept then
    vim.keymap.set("i", opts.accept, on_accept, { buffer = buf, silent = true, noremap = true })
    keymap_handlers[buf] = keymap_handlers[buf] or {}
    keymap_handlers[buf].accept = opts.accept
  end

  if on_reject and opts.reject then
    vim.keymap.set("i", opts.reject, on_reject, { buffer = buf, silent = true, noremap = true })
    keymap_handlers[buf] = keymap_handlers[buf] or {}
    keymap_handlers[buf].reject = opts.reject
  end

  if on_trigger and opts.trigger then
    vim.keymap.set("i", opts.trigger, on_trigger, { buffer = buf, silent = true, noremap = true })
    keymap_handlers[buf] = keymap_handlers[buf] or {}
    keymap_handlers[buf].trigger = opts.trigger
  end
end

function M.clear_keymaps(buf)
  buf = buf or 0
  local handlers = keymap_handlers[buf]
  if not handlers then return end
  local opts = M.options.keymaps or M.defaults.keymaps
  pcall(vim.keymap.del, "i", opts.accept, { buffer = buf })
  pcall(vim.keymap.del, "i", opts.reject, { buffer = buf })
  if opts.trigger then
    pcall(vim.keymap.del, "i", opts.trigger, { buffer = buf })
  end
  keymap_handlers[buf] = nil
end

function M.get(key)
  local val = M.options[key]
  if val == nil then val = M.defaults[key] end
  return val
end

return M
