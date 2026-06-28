# AGENTS.md — Operational Context & Guidelines
# ataraxy.nvim

## 1. Project Overview & Tech Stack

- **Context:** ataraxy.nvim is a minimalist Neovim plugin (v0.10+) that provides copilot-style inline ghost-text completions and an interactive refactoring interface, powered by any OpenAI-compatible API. It is written entirely in Lua with no external runtime dependencies beyond the host `curl` binary.
- **Core Architecture:**
  - Language: Lua 5.1 (LuaJIT as shipped with Neovim)
  - Runtime target: Neovim 0.10+
  - HTTP & Streaming: `curl` via `vim.system()` / `vim.loop`; SSE parsed line-by-line
  - Completion strategy: Fill-In-the-Middle (FIM) prompt formatting
  - UI: Neovim virtual text (extmarks) for ghost text; native vimdiff for Prompt Mode
  - Testing: `mini.test` (part of `mini.nvim`)
  - Linting: `luacheck`
- **Source layout:**
  ```
  lua/ataraxy/
    init.lua          ← plugin entry point, setup()
    config.lua        ← env var resolution, enabled flag, options
    api.lua           ← curl wrapper, SSE parser, request lifecycle
    context/
      buffer.lua      ← prefix/suffix/FIM construction
      symbols.lua     ← async workspace symbol search
      docstring.lua   ← docstring / function body extraction
    completion/
      trigger.lua     ← debounce timer, keystroke handling, cancellation
      ghost.lua       ← virtual text / extmark renderer
      keymap.lua      ← Tab / Escape interception
    prompt/
      ui.lua          ← floating input widget
      workspace.lua   ← scratch buffer, vimdiff split lifecycle
      stream.lua      ← SSE → scratch buffer writer
  tests/
    test_*.lua        ← mini.test test files
  scripts/
    minimal_init.lua  ← headless Neovim bootstrapper for tests
  ```

---

## 2. Build, Development, & Operational Commands

- **Run full test suite:**
  ```sh
  nvim --headless -u scripts/minimal_init.lua -c "lua MiniTest.run()"
  ```
- **Run a single test file:**
  ```sh
  nvim --headless -u scripts/minimal_init.lua -c "lua MiniTest.run('tests/test_NAME.lua')"
  ```
- **Lint:**
  ```sh
  luacheck lua/ tests/
  ```
- **Bootstrap dev deps:** `scripts/minimal_init.lua` automatically downloads `mini.nvim` into a temp directory at test runtime — no manual install step required.
- **No build step:** ataraxy.nvim is a pure Lua plugin. There is nothing to compile or bundle.

---

## 3. Testing Guidelines & Architecture

- **Framework:** `mini.test` — all test files use `MiniTest.new_set()` and `MiniTest.expect.*` assertions.
- **Test files:** `tests/test_*.lua` — one file per module or logical subsystem.
- **Bootstrapper:** `scripts/minimal_init.lua` downloads `mini.nvim` to a temp path and adds it to `runtimepath` before any test file is loaded.
- **Neovim APIs in tests:** All tests that exercise `vim.api`, `vim.fn`, `vim.loop`, or buffer state must run inside a headless Neovim instance via the bootstrapper — never in a plain Lua interpreter.
- **HTTP in tests:** Never make real HTTP requests. Mock the `curl` subprocess or the `api.lua` module boundary so tests are deterministic and offline.
- **Coverage target:** Minimum 80% statement coverage for any new module introduced.
- **CI gate:** Tests and lint must both pass before any commit is considered mergeable.

---

## 4. Code Style, Conventions, & Patterns

- **No globals:** Every module returns a plain Lua table. Nothing is written to the global `_G` namespace.
- **Naming:** `snake_case` for all variables, functions, and file names. Module table keys follow the same convention.
- **No external runtime deps:** The only permitted runtime dependency is the host `curl` binary. Do not `require` any third-party Lua library that is not part of Neovim's standard runtime.
- **Async discipline:** All I/O (HTTP, file reads for symbol resolution) must use `vim.system()` callbacks or `vim.loop` handles. Never call blocking I/O on the main thread.
- **Module pattern:** Each file in `lua/ataraxy/` is a self-contained module. `init.lua` wires them together; individual modules must not `require` `init.lua`.
- **Error handling:** Surface errors only at system boundaries (e.g. malformed SSE frames, unexpected curl exit codes). Internal logic should use `assert()` for invariants. Do not show `vim.notify` messages to the user for normal operating conditions.
- **Secrets:** Never log, print, or expose the resolved API key value anywhere in the codebase — not in error messages, debug output, or comments.

---

## 5. Git & Commit Workflow

- **Commit message format:** [Conventional Commits](https://www.conventionalcommits.org/)
  - `feat:` — new capability
  - `fix:` — bug correction
  - `refactor:` — structural change with no behaviour change
  - `test:` — test additions or corrections
  - `chore:` — tooling, CI, docs, linting config
- **Pre-commit gates:** `luacheck lua/ tests/` must exit 0. The full test suite must pass. Do not bypass these with `--no-verify`.
- **Branch strategy:** Feature branches off `main`; squash-merge or rebase before merging.
- **PR prerequisites:** Green lint + green tests. PR description must reference the PRD requirement(s) being implemented.

---

## 6. Strict Development Boundaries & Constraints

These are hard constraints. Do not violate them without a formal PRD amendment:

- **NEVER** make synchronous HTTP calls. All `curl` invocations must go through `vim.system()` or `vim.loop` async handles.
- **NEVER** hardcode an API key, base URL, or model name anywhere in the source tree — not even in comments as examples.
- **NEVER** store secrets in version control. `.gitignore` must cover `.env` and any credential file.
- **NEVER** add `nvim-lsp`, `nvim-cmp`, `blink.cmp`, `telescope.nvim`, `plenary.nvim`, or any other Neovim plugin as a runtime dependency.
- **NEVER** implement partial, word-level, or line-level ghost text acceptance. Completions are all-or-nothing (full block via `<Tab>`).
- **NEVER** implement multi-turn chat, conversation history, or session state in Prompt Mode. Each submission is a standalone, one-shot request.
- **NEVER** traverse import or dependency graphs deeper than depth 1. Context resolution stops at the immediate symbol definition.
- **NEVER** emit `vim.notify`, `print()`, or any user-visible message when the API key env var is absent. The plugin must self-disable silently.
- **NEVER** modify the original buffer during a Prompt Mode session until the user explicitly accepts the diff.
