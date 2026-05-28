# ataraxy.nvim

A lightweight Neovim (v0.10+) inline code completion and conversational coding agent plugin, written in pure Lua with zero external dependencies.

As you type, ataraxy streams ghost-text completions directly into your buffer using Fill-in-the-Middle (FIM) prompting. When you need deeper assistance, `:AtaraxyPrompt` opens an interactive agent that applies changes in a live diff view — letting you review, edit, accept, or discard the generation before touching your source file.

---

## Requirements

- Neovim >= 0.10
- `curl` available on `$PATH`
- An OpenAI-compatible API key

---

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "pablogarin/ataraxy.nvim",
  event = "InsertEnter",
  opts = {
    api_key = os.getenv("ATARAXY_API_KEY"),
  },
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "pablogarin/ataraxy.nvim",
  config = function()
    require("ataraxy").setup({
      api_key = os.getenv("ATARAXY_API_KEY"),
    })
  end,
}
```

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'pablogarin/ataraxy.nvim'
```

```lua
-- In your init.lua
require("ataraxy").setup({})
```

---

## Quick Start

Set your API key in the environment before launching Neovim:

```sh
export ATARAXY_API_KEY="sk-..."
```

ataraxy also reads `OPENAI_API_KEY` as a fallback. No key needs to be hardcoded in your config.

---

## Configuration

Call `setup()` once during Neovim initialization. All fields are optional — the defaults shown below apply when omitted.

```lua
require("ataraxy").setup({
  -- API credentials
  api_key      = os.getenv("ATARAXY_API_KEY"),   -- falls back to OPENAI_API_KEY
  api_endpoint = "https://api.openai.com",        -- any OpenAI-compatible endpoint
  model        = "gpt-4o-mini",
  temperature  = 0.0,

  -- Typing delay before a completion request is sent (milliseconds)
  debounce_ms  = 300,

  -- Override the system prompt sent with every completion request
  system_prompt = "...",

  -- Keymaps applied per-buffer in Insert mode (see Keymaps section)
  keymaps = {
    accept  = "<Tab>",   -- commit ghost text into the buffer
    reject  = "<Esc>",   -- dismiss ghost text, no change
    trigger = nil,       -- manually trigger a completion (disabled by default)
  },

  -- Coding agent settings
  agent = {
    context_file = ".ataraxy.md",    -- workspace context file (looked up from project root)
    skills_dir   = "ataraxy/skills", -- directory of Markdown/text skill templates
  },
})
```

### OpenAI-Compatible Endpoints

Point `api_endpoint` at any server that implements the `/v1/chat/completions` SSE interface:

```lua
require("ataraxy").setup({
  api_endpoint = "http://localhost:11434",  -- Ollama
  model        = "codellama",
  api_key      = "ollama",
})
```

---

## Keymaps

Keymaps are registered buffer-locally in Insert mode the first time each normal file buffer is entered. They do not pollute your global keymap table.

### Default bindings

| Key       | Action                                              |
|-----------|-----------------------------------------------------|
| `<Tab>`   | Accept ghost-text — commits the suggestion and moves the cursor to the end of the inserted text |
| `<Esc>`   | Reject ghost-text — clears the suggestion, then falls through to normal `<Esc>` behavior |

### Customizing keymaps

Pass a `keymaps` table to `setup()`:

```lua
require("ataraxy").setup({
  keymaps = {
    accept  = "<C-y>",     -- accept with Ctrl-y
    reject  = "<C-e>",     -- reject with Ctrl-e
    trigger = "<C-Space>", -- manually fire a completion
  },
})
```

Setting a key to `false` or `nil` disables that binding entirely:

```lua
require("ataraxy").setup({
  keymaps = {
    accept  = "<C-y>",
    reject  = false,   -- no reject key; any cursor movement clears ghost text
    trigger = nil,
  },
})
```

### Manual trigger

By default completions fire automatically after `debounce_ms` of inactivity. To disable automatic firing and trigger on demand instead:

```lua
require("ataraxy").setup({
  debounce_ms = 99999,           -- effectively disables auto-complete
  keymaps = {
    trigger = "<C-Space>",
  },
})
```

---

## Commands

| Command             | Description |
|---------------------|-------------|
| `:AtaraxyPrompt`    | Open the interactive agent input. Sends the active file, your prompt, `.ataraxy.md` workspace context, and any skills to the LLM. The result streams into a scratch buffer shown in a vertical diff split. |
| `:AtaraxyAccept`    | Apply the diff — overwrites the source file with the scratch buffer contents and closes the diff view. Only available during an active agent session. |
| `:AtaraxyCancel`    | Discard the generation — closes the diff view and scratch buffer without modifying the source file. Only available during an active agent session. |
| `:AtaraxyRedo`      | Cancel the current inline completion and immediately retry it using the cached buffer context. |
| `:AtaraxyReadfile`  | Force-reload the current buffer from disk into the plugin session context. |

---

## Workspace Context (`.ataraxy.md`)

Place a `.ataraxy.md` file at your project root. Its contents are prepended to every `:AtaraxyPrompt` request, giving the model persistent awareness of your project's conventions, architecture, and constraints.

```markdown
# Project Context

- Language: TypeScript, Node 20
- Style: functional, no classes
- All API handlers must validate input with Zod before processing
- Database: PostgreSQL via Drizzle ORM — never use raw SQL strings
```

ataraxy searches for `.ataraxy.md` by walking up from the current file's directory, stopping at the first `.git` root it finds.

---

## Skills

Skills are Markdown or plain-text files placed in the `agent.skills_dir` directory (default: `ataraxy/skills/` relative to the project root). All files in that directory are concatenated and injected into the agent's system prompt on every `:AtaraxyPrompt` call.

```
project/
└── ataraxy/
    └── skills/
        ├── testing.md        # "Always use vitest, never jest"
        └── api-design.md     # "Follow REST conventions strictly"
```

Built-in skill templates (`refactor`, `document`, `test`, `fix`) are also available programmatically:

```lua
local skills = require("ataraxy.agent.skills")
print(skills.get_system_prompt("refactor"))
```

---

## How Inline Completion Works

1. You type in Insert mode. After `debounce_ms` of inactivity, ataraxy captures up to 2000 lines above and 500 lines below the cursor as FIM context.
2. A non-blocking `curl` request streams the response via Server-Sent Events.
3. Each token is rendered as ephemeral ghost text in a dedicated extmark namespace (`Comment` highlight group) — your buffer is not modified.
4. Press `<Tab>` to commit the text at the cursor position. Any cursor movement or mode change cancels the suggestion and kills the network request.

---

## Agent Diff Workflow

1. Run `:AtaraxyPrompt` and enter your instruction.
2. ataraxy duplicates the active buffer into a scratch buffer (`buftype=nofile`) and opens it in a vertical split with `diffthis` applied to both sides.
3. The LLM response streams token-by-token into the scratch buffer. You can freely edit it during or after streaming.
4. Run `:AtaraxyAccept` to apply or `:AtaraxyCancel` to discard. The original file is never touched until you explicitly accept.

---

## Development

```sh
# Run the test suite (requires plenary.nvim on the runtimepath)
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/"

# Lint
luacheck lua/
```

---

## License

MIT
