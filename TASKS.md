# Project Implementation Checklist — ataraxy.nvim

---

## Epic 1: Configuration & Secret Manager

- [x] **T-001**: Scaffold `lua/ataraxy/init.lua` with `setup(opts)` entry point and module boilerplate - *Belongs to US-01*
- [x] **T-002**: Implement `lua/ataraxy/config.lua` — parse opts, validate types, store resolved config table - *Belongs to US-01*
- [x] **T-003**: Implement silent self-disable: if `api_key_env` resolves to nil or empty, set `enabled = false` and return without registering anything - *Belongs to US-01*
- [x] **T-004**: Write `tests/test_config.lua` — cover enabled path, disabled path, missing fields, and type validation - *Belongs to US-01*
- [x] **T-005**: Implement `os.getenv()` resolution for `api_key_env`, `base_url`, and `model_env` inside `config.lua` - *Belongs to US-02*
- [x] **T-006**: Add `.gitignore` entries (`.env`, `*.key`, `*.secret`) and configure `.luacheckrc` to whitelist `vim.*` and `MiniTest` globals - *Belongs to US-02*

---

## Epic 2: Inline Completion Engine

- [x] **T-007**: Implement `lua/ataraxy/context/buffer.lua` — split active buffer at cursor into `prefix` and `suffix` using `nvim_buf_get_lines()` and `nvim_win_get_cursor()` - *Belongs to US-03*
- [x] **T-008**: Implement FIM prompt formatter — assemble `prefix`, `suffix`, and middle boundary tokens into the final request payload - *Belongs to US-03*
- [x] **T-009**: Write `tests/test_buffer.lua` — cover mid-line split, start-of-line, end-of-line, empty buffer, and single-line buffer cases - *Belongs to US-03*
- [x] **T-010**: Implement `lua/ataraxy/context/symbols.lua` — async workspace grep via `vim.system()` to locate symbol definitions; no ctags or LSP - *Belongs to US-04*
- [x] **T-011**: Implement `lua/ataraxy/context/docstring.lua` — extract docstring block from a definition file, falling back to full function body if absent - *Belongs to US-04*
- [x] **T-012**: Enforce depth-1 cap in the symbol resolver — discovered definition files are never recursively searched for further imports - *Belongs to US-04*
- [x] **T-013**: Write `tests/test_symbols.lua` and `tests/test_docstring.lua` with mocked file contents covering docstring-present, docstring-absent, and symbol-not-found cases - *Belongs to US-04*
- [x] **T-014**: Implement `lua/ataraxy/api.lua` — launch `curl` subprocess via `vim.system()` with a streaming `stdout` callback; expose `request()` and `cancel()` functions - *Belongs to US-05*
- [x] **T-015**: Implement SSE parser in `api.lua` — extract `data:` lines, skip `[DONE]`, JSON-decode each chunk's `choices[1].delta.content` field - *Belongs to US-05*
- [x] **T-016**: Implement request cancellation in `api.lua` — store the active job handle and expose a `cancel()` function that terminates the subprocess immediately - *Belongs to US-05*
- [x] **T-017**: Write `tests/test_api.lua` — mock curl stdout with pre-recorded SSE payloads; cover successful stream, mid-stream cancel, and non-zero exit code scenarios - *Belongs to US-05*

---

## Epic 3: Ghost Text Renderer & Insert Mode UX

- [x] **T-018**: Implement `lua/ataraxy/completion/ghost.lua` — render completion as virtual text via `nvim_buf_set_extmark()` in a dedicated namespace; expose `show()` and `clear()` - *Belongs to US-06*
- [x] **T-019**: Ensure ghost text namespace is fully cleared before each new render and on `BufWritePre` - *Belongs to US-06*
- [x] **T-020**: Implement `lua/ataraxy/completion/trigger.lua` — debounce timer using `vim.uv.new_timer()`; expose `arm()`, `reset()`, and `fire()` - *Belongs to US-07*
- [x] **T-021**: Implement auto-trigger: attach `TextChangedI` autocommand that calls `trigger.reset()` on each keystroke - *Belongs to US-07*
- [x] **T-022**: Implement manual trigger: register a configurable Insert Mode keymap that calls `api.request()` directly, bypassing the debounce timer - *Belongs to US-07*
- [x] **T-023**: Implement keystroke-during-stream cancellation: `TextChangedI` handler must call `api.cancel()` before resetting the debounce timer if a request is active - *Belongs to US-07*
- [x] **T-024**: Write `tests/test_trigger.lua` — cover auto debounce fire, debounce reset, manual dispatch, and mid-stream cancellation - *Belongs to US-07*
- [x] **T-025**: Implement `lua/ataraxy/completion/keymap.lua` — Tab accept logic: if ghost text extmarks exist, commit completion to buffer and clear; else feed original `<Tab>` - *Belongs to US-08*
- [x] **T-026**: Implement Escape conditional in `keymap.lua` — if ghost text extmarks exist, clear them and stay in Insert Mode; else feed original `<Escape>` to return to Normal Mode - *Belongs to US-08*
- [x] **T-027**: Write `tests/test_keymap.lua` — cover Tab accept, Tab passthrough, Escape dismiss, and Escape normal-exit scenarios - *Belongs to US-08*
- [x] **T-028**: Register `InsertLeave` autocommand in `init.lua` that calls `ghost.clear()` and `api.cancel()` to clean up on any Insert Mode exit - *Belongs to US-09*

---

## Epic 4: Interactive Prompt Mode

- [x] **T-029**: Implement `lua/ataraxy/prompt/ui.lua` — floating scratch-buffer window centered on screen using `nvim_open_win()`; `<CR>` submits, `<Escape>` cancels - *Belongs to US-10*
- [x] **T-030**: Register configurable Normal Mode keybinding in `init.lua` to open the Prompt Mode floating widget - *Belongs to US-10*
- [x] **T-031**: Implement `lua/ataraxy/prompt/workspace.lua` — duplicate active buffer to a scratch buffer, open a vertical vimdiff split, call `diffthis` on both windows - *Belongs to US-11*
- [x] **T-032**: Implement `lua/ataraxy/prompt/stream.lua` — write each decoded SSE token to the scratch buffer via `nvim_buf_set_lines()` in the stdout callback - *Belongs to US-11*
- [x] **T-033**: Construct Prompt Mode system prompt in `prompt/ui.lua` — explicitly instruct the model to return only code, no prose, no markdown fences unless they are literal code - *Belongs to US-11*
- [x] **T-034**: Implement Accept keybinding (local to the scratch buffer window) — copy scratch buffer lines to original buffer and wipe scratch buffer - *Belongs to US-12*
- [x] **T-035**: Implement Reject keybinding (local to the scratch buffer window) — wipe scratch buffer and close split without touching the original buffer - *Belongs to US-12*
- [x] **T-036**: Implement Cancel keybinding (local to the scratch buffer window) — call `api.cancel()` to terminate the active curl subprocess; leave scratch buffer in partial state - *Belongs to US-12*
- [x] **T-037**: Write `tests/test_prompt.lua` — cover workspace initialization, stream writing, accept, reject, and cancel lifecycle scenarios with mocked API responses - *Belongs to US-12*

---

## Epic 5: Dev Infrastructure & Testing

- [x] **T-038**: Write `scripts/minimal_init.lua` — clone or download `mini.nvim` to a temp directory and prepend it to `runtimepath` before any test file loads - *Belongs to US-13*
- [x] **T-039**: Add a `Makefile` with `test` and `lint` targets wrapping the headless Neovim command and `luacheck lua/ tests/` respectively - *Belongs to US-13*
- [x] **T-040**: Configure `.luacheckrc` — whitelist `vim`, `MiniTest`, and standard test globals; set `max_line_length = 120`; enable strict unused variable warnings - *Belongs to US-13*
