# Product Requirements Document (PRD)
# ataraxy.nvim

## 1. Project Overview & Objective

- **Problem Statement:** Neovim lacks a native, lightweight copilot-style completion plugin that works without Node.js, LSP servers, or heavy runtime dependencies. Existing solutions (GitHub Copilot, codeium.nvim) either require external runtimes or couple tightly to the LSP/cmp ecosystem, making them fragile and hard to customize.
- **Target Audience:** Neovim power users (v0.10+) who want fast, unobtrusive AI-assisted coding via any OpenAI-compatible API — including local inference stacks like Ollama, DeepSeek, or Groq — without sacrificing editor responsiveness or introducing complex dependencies.
- **Core Value Proposition:** A single-file-installable Lua plugin that stays entirely off the main thread, renders ghost text inline while the user types, and provides a structured interactive refactoring interface — all configurable in minutes with zero vendor lock-in.

---

## 2. Technical Stack Configuration

- **Language:** Lua 5.1 (LuaJIT, as shipped with Neovim)
- **Runtime:** Neovim 0.10+
- **HTTP / Streaming:** Native host `curl` binary via `vim.system()` / `vim.loop`; Server-Sent Events (SSE) parsed line-by-line in a non-blocking stdout callback
- **API Compatibility:** OpenAI-compatible REST interface; `base_url` and `model` are fully configurable — no vendor defaults
- **Auth:** System environment variables only; no hardcoded secrets
- **Testing:** `mini.test` (via `mini.nvim`) + `scripts/minimal_init.lua` headless bootstrapper
- **Linting:** `luacheck`

---

## 3. Functional Requirements (MVP Scope)

### Feature 1: Configuration & Secret Manager

- **Description:** A `setup()` entry point that reads all runtime credentials and tuning parameters. If the required API key is absent from the environment at startup, the plugin disables itself silently — no messages, no notifications, no errors.
- **Requirement 1.1:** `setup(opts)` accepts: `base_url` (string), `api_key_env` (env var name), `model_env` (env var name), `trigger` (`"auto"` | `"manual"`), `debounce_ms` (integer, 500–1000).
- **Requirement 1.2:** At startup, resolve `api_key_env` via `os.getenv()`. If the result is `nil` or empty, set an internal `enabled = false` flag and return immediately. Do not register any keymaps or autocommands.
- **Requirement 1.3:** `base_url` and model name are resolved the same way — from env vars named by the user in `setup()`. There are no built-in fallback values.
- **Requirement 1.4:** No secrets, URLs, or model names may be stored in version control at any point.

---

### Feature 2: Inline Completion Engine (FIM Context Pipeline)

- **Description:** Builds the prompt sent to the API using Fill-In-the-Middle (FIM) formatting, enriched with just enough project context to minimise hallucinations without bloating the token window.
- **Requirement 2.1:** Split the active buffer at the cursor position into `prefix` (lines above + partial current line before cursor) and `suffix` (partial current line after cursor + lines below). Format the prompt with explicit FIM boundary tokens.
- **Requirement 2.2:** Include the full active buffer content in the context payload.
- **Requirement 2.3:** For symbols near the cursor, perform an asynchronous background search across the workspace to locate their definitions. Do not use static ctags.
- **Requirement 2.4:** If a located definition file contains a docstring or documentation header, extract **only that block** for context. If no docstring exists, include the full function/method body.
- **Requirement 2.5:** Dependency context resolution is capped at **depth 1**. The plugin must not traverse transitive imports or follow nested dependency graphs.

---

### Feature 3: Ghost Text Renderer & Insert Mode UX

- **Description:** Renders AI completions as Neovim virtual text (ghost text) visible only in Insert Mode, with tight key interception rules to keep the UX unobtrusive.
- **Requirement 3.1:** Ghost text is rendered exclusively using Neovim's virtual text / extmarks API. It must not modify the actual buffer content until explicitly accepted.
- **Requirement 3.2 (Auto mode):** After each keystroke, start a debounce timer of `debounce_ms`. If the user types again before the timer fires, reset it. When the timer fires, dispatch the async API call.
- **Requirement 3.3 (Manual mode):** When `trigger = "manual"`, no timer is started. A user-configured keybinding dispatches the API call explicitly.
- **Requirement 3.4 (Cancellation):** If a new keystroke arrives while a curl process is active, terminate that process immediately before starting a new debounce cycle.
- **Requirement 3.5 (Tab key):** In Insert Mode, if ghost text is currently visible, `<Tab>` accepts the entire completion and commits it to the buffer. If no ghost text is visible, `<Tab>` falls through to its default indentation behavior.
- **Requirement 3.6 (Escape key):** In Insert Mode, if ghost text is currently visible, `<Escape>` clears the ghost text and keeps the user in Insert Mode. If no ghost text is visible, `<Escape>` behaves normally and returns the user to Normal Mode.
- **Requirement 3.7 (Mode exit):** Any transition out of Insert Mode by means other than the mapped `<Escape>` (e.g. `<C-c>`, mouse click, `<C-[>`) must silently clear ghost text and any pending curl processes.

---

### Feature 4: Interactive Prompt Mode

- **Description:** A structured interface for submitting natural-language instructions to the model, with results streamed into a real-time vimdiff workspace for review before committing.
- **Requirement 4.1:** A user-configured keybinding opens a floating text input widget. The user types a natural-language instruction and submits.
- **Requirement 4.2:** The plugin constructs a system prompt that explicitly requests structural code output only — no prose explanations, no markdown fences unless they are part of the code itself.
- **Requirement 4.3:** The active file is duplicated into a scratch buffer. A vertical split is opened using Neovim's native vimdiff layout (`diffopt`, `foldmethod=diff`), with the original on the left and the scratch buffer on the right.
- **Requirement 4.4:** The streaming SSE response is written into the scratch buffer line-by-line as chunks arrive, so the diff updates in real time.
- **Requirement 4.5:** A cancellation keybinding terminates the active curl process immediately and leaves the scratch buffer in its partial state.
- **Requirement 4.6:** An Accept keybinding overwrites the original buffer with the scratch buffer contents, closes the split, and deletes the scratch buffer.
- **Requirement 4.7:** A Reject keybinding closes the split and deletes the scratch buffer without touching the original buffer.

---

## 4. Out of Scope & Constraints

The following are **explicitly excluded** from the MVP. Any agent or contributor must not implement these without a formal PRD amendment:

- Partial, word-level, or line-level ghost text acceptance workflows
- LSP server integration (`nvim-lsp`, `nvim-cmp`, `blink.cmp`, etc.)
- Multi-cursor or visual-selection-based completions
- Multi-turn chat or conversation history in Prompt Mode (one-shot only)
- Any feature not explicitly described in Section 3 above
- Bundled or vendored HTTP libraries — curl is the only networking mechanism
- Hardcoded API provider URLs, model names, or API keys of any kind
