# User Stories — ataraxy.nvim

---

## Epic 1: Configuration & Secret Manager

---

### US-01: Plugin Setup & Silent Disable

**Epic/Feature:** Configuration & Secret Manager

**User Story:**
As a Neovim user,
I want to call `require("ataraxy").setup(opts)` to initialize the plugin,
So that it activates correctly when a valid API key is present and silently does nothing when it is not.

**Acceptance Criteria (Gherkin/BDD Style):**
- **Scenario:** API key is present in the environment
  - **Given** the env var named by `api_key_env` resolves to a non-empty string
  - **When** `setup(opts)` is called
  - **Then** the plugin sets `enabled = true` and registers all keymaps and autocommands

- **Scenario:** API key is absent from the environment
  - **Given** the env var named by `api_key_env` resolves to nil or an empty string
  - **When** `setup(opts)` is called
  - **Then** the plugin sets `enabled = false`, registers nothing, and produces zero output (no notify, no print, no error)

- **Scenario:** `setup()` is never called
  - **Given** the plugin is loaded but `setup()` is not invoked
  - **When** the user opens a buffer
  - **Then** no keymaps or autocommands are active

**Technical Notes / Constraints:**
- `setup(opts)` accepts: `base_url` (string), `api_key_env` (string), `model_env` (string), `trigger` (`"auto"` | `"manual"`), `debounce_ms` (integer, 500–1000)
- Resolution of env vars via `os.getenv()` only
- No defaults for any credential or URL field

**Associated Tasks:**
- Links to: `T-001`, `T-002`, `T-003`, `T-004`

**Definition of Done (DoD):**
- [ ] Code builds locally without errors or warnings.
- [ ] All automated tests (unit/integration) pass; minimum 80% test coverage achieved for new code.
- [ ] Code is peer-reviewed and adheres to project styling guidelines.
- [ ] Documentation (inline code, API endpoints, or README) is updated.
- [ ] Feature is verified to meet all specified Acceptance Criteria in the staging/dev environment.

---

### US-02: Environment-based Credential Resolution

**Epic/Feature:** Configuration & Secret Manager

**User Story:**
As a security-conscious developer,
I want all secrets — API key, base URL, and model name — sourced exclusively from environment variables,
So that no sensitive data is ever hardcoded or accidentally committed to version control.

**Acceptance Criteria (Gherkin/BDD Style):**
- **Scenario:** All env vars are set
  - **Given** `api_key_env`, `base_url`, and `model_env` all resolve to non-empty strings
  - **When** `setup(opts)` is called
  - **Then** the resolved values are stored in the internal config table and used for all subsequent API calls

- **Scenario:** A credential env var is unset
  - **Given** one or more of the env vars resolves to nil
  - **When** `setup(opts)` is called
  - **Then** the plugin self-disables (per US-01) and no partial credentials are stored

- **Scenario:** `.env` or credential file exists in the repo
  - **Given** a `.env` file or similar secret file exists in the project root
  - **When** a `git status` or `git add` is attempted
  - **Then** the file is excluded by `.gitignore` and never staged

**Technical Notes / Constraints:**
- `os.getenv()` is the only permitted resolution mechanism
- `.gitignore` must cover `.env`, `*.key`, `*.secret`
- `luacheck` configured via `.luacheckrc` to suppress false positives on `vim.*` globals

**Associated Tasks:**
- Links to: `T-005`, `T-006`

**Definition of Done (DoD):**
- [ ] Code builds locally without errors or warnings.
- [ ] All automated tests (unit/integration) pass; minimum 80% test coverage achieved for new code.
- [ ] Code is peer-reviewed and adheres to project styling guidelines.
- [ ] Documentation (inline code, API endpoints, or README) is updated.
- [ ] Feature is verified to meet all specified Acceptance Criteria in the staging/dev environment.

---

## Epic 2: Inline Completion Engine

---

### US-03: FIM Prompt Construction

**Epic/Feature:** Inline Completion Engine (FIM Context Pipeline)

**User Story:**
As a developer actively writing code in Neovim,
I want the plugin to build a Fill-In-the-Middle prompt from my buffer split at the cursor,
So that the AI model receives accurate prefix and suffix boundaries for precise, context-aware completions.

**Acceptance Criteria (Gherkin/BDD Style):**
- **Scenario:** Cursor is mid-line
  - **Given** the cursor is positioned partway through a line in an active buffer
  - **When** the FIM context builder runs
  - **Then** prefix = all lines above + partial line up to cursor column; suffix = remainder of line + all lines below; both are separated by FIM boundary tokens

- **Scenario:** Cursor is at the start of a blank line
  - **Given** the cursor is on an empty line
  - **When** the FIM context builder runs
  - **Then** prefix ends with a newline and suffix begins with a newline; the FIM middle token is empty

- **Scenario:** Full buffer content is included
  - **Given** any cursor position
  - **When** the context payload is assembled
  - **Then** the combined prefix + suffix spans the entire buffer without omission

**Technical Notes / Constraints:**
- FIM boundary tokens must be configurable or follow `<PRE>`, `<SUF>`, `<MID>` conventions compatible with common OpenAI FIM endpoints
- Buffer content is read via `vim.api.nvim_buf_get_lines()`
- Cursor position via `vim.api.nvim_win_get_cursor()`

**Associated Tasks:**
- Links to: `T-007`, `T-008`, `T-009`

**Definition of Done (DoD):**
- [ ] Code builds locally without errors or warnings.
- [ ] All automated tests (unit/integration) pass; minimum 80% test coverage achieved for new code.
- [ ] Code is peer-reviewed and adheres to project styling guidelines.
- [ ] Documentation (inline code, API endpoints, or README) is updated.
- [ ] Feature is verified to meet all specified Acceptance Criteria in the staging/dev environment.

---

### US-04: Async Symbol & Context Resolution

**Epic/Feature:** Inline Completion Engine (FIM Context Pipeline)

**User Story:**
As a developer working in a multi-file project,
I want the plugin to asynchronously find definitions of symbols near my cursor and include their docstrings (or bodies) in the prompt,
So that completions are informed by real project context without freezing my editor.

**Acceptance Criteria (Gherkin/BDD Style):**
- **Scenario:** Symbol has a docstring in its definition file
  - **Given** a symbol near the cursor is found in another file that contains a docstring above the definition
  - **When** context resolution runs
  - **Then** only the docstring block is extracted and appended to the prompt; the full function body is excluded

- **Scenario:** Symbol definition has no docstring
  - **Given** a symbol near the cursor is found in a file with no docstring
  - **When** context resolution runs
  - **Then** the full function or method body is extracted and appended to the prompt

- **Scenario:** Symbol is not found in the workspace
  - **Given** the symbol near the cursor has no resolvable definition in the workspace
  - **When** context resolution runs
  - **Then** no additional context is appended and the completion proceeds with buffer content only

- **Scenario:** Transitive import encountered
  - **Given** a discovered definition file itself imports another module
  - **When** context resolution runs
  - **Then** the resolver does not follow that import; depth is capped at 1

**Technical Notes / Constraints:**
- Symbol search must use `vim.system()` (e.g. ripgrep or grep) — no ctags, no LSP
- All file I/O in this module is async; never block the main thread
- Depth cap is a hard constraint from the PRD

**Associated Tasks:**
- Links to: `T-010`, `T-011`, `T-012`, `T-013`

**Definition of Done (DoD):**
- [ ] Code builds locally without errors or warnings.
- [ ] All automated tests (unit/integration) pass; minimum 80% test coverage achieved for new code.
- [ ] Code is peer-reviewed and adheres to project styling guidelines.
- [ ] Documentation (inline code, API endpoints, or README) is updated.
- [ ] Feature is verified to meet all specified Acceptance Criteria in the staging/dev environment.

---

### US-05: Async API Client & SSE Streaming

**Epic/Feature:** Inline Completion Engine (FIM Context Pipeline)

**User Story:**
As a developer using the plugin,
I want all API communication to happen over an async curl subprocess that streams tokens as they arrive,
So that my editor never blocks and completions appear progressively.

**Acceptance Criteria (Gherkin/BDD Style):**
- **Scenario:** Successful streaming response
  - **Given** a well-formed request is dispatched to the configured base_url
  - **When** the server responds with an SSE stream
  - **Then** each `data:` chunk is parsed and its content token extracted incrementally via a stdout callback

- **Scenario:** Request is cancelled mid-stream
  - **Given** an active curl process is streaming a response
  - **When** a cancellation signal is received
  - **Then** the subprocess is terminated immediately and no further chunks are processed

- **Scenario:** curl exits with a non-zero code
  - **Given** the API endpoint is unreachable or returns an HTTP error
  - **When** curl exits
  - **Then** the error is logged internally (not surfaced to the user) and the ghost text state remains cleared

**Technical Notes / Constraints:**
- Use `vim.system()` with `stdout` callback for streaming
- SSE format: parse lines starting with `data: `; skip `data: [DONE]`
- JSON decode each chunk's `choices[1].delta.content` field

**Associated Tasks:**
- Links to: `T-014`, `T-015`, `T-016`, `T-017`

**Definition of Done (DoD):**
- [ ] Code builds locally without errors or warnings.
- [ ] All automated tests (unit/integration) pass; minimum 80% test coverage achieved for new code.
- [ ] Code is peer-reviewed and adheres to project styling guidelines.
- [ ] Documentation (inline code, API endpoints, or README) is updated.
- [ ] Feature is verified to meet all specified Acceptance Criteria in the staging/dev environment.

---

## Epic 3: Ghost Text Renderer & Insert Mode UX

---

### US-06: Ghost Text Rendering

**Epic/Feature:** Ghost Text Renderer & Insert Mode UX

**User Story:**
As a developer in Insert Mode,
I want AI completions to appear as non-intrusive ghost text overlaid on my buffer,
So that I can preview suggestions without any modification to my actual code.

**Acceptance Criteria (Gherkin/BDD Style):**
- **Scenario:** Completion is received
  - **Given** the API returns a completion string
  - **When** the ghost text renderer fires
  - **Then** the completion is displayed as virtual text at the cursor position using Neovim's extmarks API; the buffer content is unchanged

- **Scenario:** New completion arrives while ghost text is visible
  - **Given** ghost text from a previous completion is currently displayed
  - **When** a new completion is ready to render
  - **Then** the existing ghost text namespace is cleared before the new text is applied

- **Scenario:** Buffer is written while ghost text is visible
  - **Given** ghost text is currently displayed
  - **When** the user saves the buffer (`:w`)
  - **Then** ghost text is cleared; the saved file contains no virtual text artifacts

**Technical Notes / Constraints:**
- Use `vim.api.nvim_buf_set_extmark()` with `virt_text` option
- All ghost text must be placed in a dedicated, named extmark namespace
- Ghost text must never appear in Normal Mode or any mode other than Insert

**Associated Tasks:**
- Links to: `T-018`, `T-019`

**Definition of Done (DoD):**
- [ ] Code builds locally without errors or warnings.
- [ ] All automated tests (unit/integration) pass; minimum 80% test coverage achieved for new code.
- [ ] Code is peer-reviewed and adheres to project styling guidelines.
- [ ] Documentation (inline code, API endpoints, or README) is updated.
- [ ] Feature is verified to meet all specified Acceptance Criteria in the staging/dev environment.

---

### US-07: Debounced Auto-trigger & Manual Trigger

**Epic/Feature:** Ghost Text Renderer & Insert Mode UX

**User Story:**
As a developer, I want completion requests to trigger automatically after I pause typing (auto mode) or only on demand (manual mode),
So that I can tune suggestion frequency to match my working style without flooding the API.

**Acceptance Criteria (Gherkin/BDD Style):**
- **Scenario:** Auto mode — user pauses typing
  - **Given** `trigger = "auto"` and `debounce_ms = 600`
  - **When** the user stops typing for 600ms
  - **Then** a completion request is dispatched

- **Scenario:** Auto mode — user types again before timer fires
  - **Given** a debounce timer is running
  - **When** the user types another character before the timer expires
  - **Then** the timer is reset and no request is sent

- **Scenario:** Auto mode — user types while curl is running
  - **Given** a curl subprocess is actively streaming
  - **When** the user types a character
  - **Then** the subprocess is terminated immediately and a new debounce cycle begins

- **Scenario:** Manual mode — explicit trigger
  - **Given** `trigger = "manual"`
  - **When** the user presses the configured manual trigger keybinding
  - **Then** a completion request is dispatched immediately

- **Scenario:** Manual mode — no auto-trigger
  - **Given** `trigger = "manual"`
  - **When** the user types any character
  - **Then** no timer is started and no automatic request is dispatched

**Technical Notes / Constraints:**
- Timer implemented via `vim.loop.new_timer()` (or `vim.uv.new_timer()` on Neovim 0.10+)
- Auto-trigger attaches to `TextChangedI` autocommand
- Manual trigger registered as an Insert Mode keymap

**Associated Tasks:**
- Links to: `T-020`, `T-021`, `T-022`, `T-023`, `T-024`

**Definition of Done (DoD):**
- [ ] Code builds locally without errors or warnings.
- [ ] All automated tests (unit/integration) pass; minimum 80% test coverage achieved for new code.
- [ ] Code is peer-reviewed and adheres to project styling guidelines.
- [ ] Documentation (inline code, API endpoints, or README) is updated.
- [ ] Feature is verified to meet all specified Acceptance Criteria in the staging/dev environment.

---

### US-08: Tab / Escape Key Interception

**Epic/Feature:** Ghost Text Renderer & Insert Mode UX

**User Story:**
As a developer reviewing a ghost text suggestion,
I want Tab to accept it in full and Escape to dismiss it without exiting Insert Mode,
So that I can act on suggestions with minimal keystrokes.

**Acceptance Criteria (Gherkin/BDD Style):**
- **Scenario:** Tab with ghost text visible
  - **Given** ghost text is currently displayed
  - **When** the user presses `<Tab>` in Insert Mode
  - **Then** the full completion is committed to the buffer at the cursor position and ghost text is cleared

- **Scenario:** Tab with no ghost text
  - **Given** no ghost text is visible
  - **When** the user presses `<Tab>` in Insert Mode
  - **Then** normal indentation behavior is preserved (the keypress falls through)

- **Scenario:** Escape with ghost text visible
  - **Given** ghost text is currently displayed
  - **When** the user presses `<Escape>` in Insert Mode
  - **Then** ghost text is cleared and the user remains in Insert Mode

- **Scenario:** Escape with no ghost text
  - **Given** no ghost text is visible
  - **When** the user presses `<Escape>` in Insert Mode
  - **Then** Neovim returns the user to Normal Mode as expected

**Technical Notes / Constraints:**
- Both keymaps are buffer-local Insert Mode maps (`vim.keymap.set("i", ...)`)
- Tab fallthrough uses `vim.api.nvim_feedkeys()` with the original Tab keycode
- Escape conditional implemented by checking the ghost text extmark namespace for existing marks

**Associated Tasks:**
- Links to: `T-025`, `T-026`, `T-027`

**Definition of Done (DoD):**
- [ ] Code builds locally without errors or warnings.
- [ ] All automated tests (unit/integration) pass; minimum 80% test coverage achieved for new code.
- [ ] Code is peer-reviewed and adheres to project styling guidelines.
- [ ] Documentation (inline code, API endpoints, or README) is updated.
- [ ] Feature is verified to meet all specified Acceptance Criteria in the staging/dev environment.

---

### US-09: Mode Exit Cleanup

**Epic/Feature:** Ghost Text Renderer & Insert Mode UX

**User Story:**
As a developer leaving Insert Mode by any means,
I want ghost text and pending API processes to be silently cleared,
So that stale suggestions never linger in my buffer after I switch modes.

**Acceptance Criteria (Gherkin/BDD Style):**
- **Scenario:** User exits Insert Mode via Ctrl-C
  - **Given** ghost text is visible and a curl process may be active
  - **When** the user presses `<C-c>` to exit Insert Mode
  - **Then** ghost text is cleared and any active curl subprocess is terminated

- **Scenario:** User exits Insert Mode via mouse click
  - **Given** ghost text is visible
  - **When** the user clicks outside Insert Mode
  - **Then** ghost text is cleared

- **Scenario:** No ghost text on mode exit
  - **Given** no ghost text is visible when Insert Mode exits
  - **When** the mode changes
  - **Then** no visible effect; the cleanup is a no-op

**Technical Notes / Constraints:**
- Implemented via `InsertLeave` autocommand (and optionally `ModeChanged`)
- Must call the same ghost text clear function used by the Escape handler
- Must call the same curl cancellation function used by the trigger module

**Associated Tasks:**
- Links to: `T-028`

**Definition of Done (DoD):**
- [ ] Code builds locally without errors or warnings.
- [ ] All automated tests (unit/integration) pass; minimum 80% test coverage achieved for new code.
- [ ] Code is peer-reviewed and adheres to project styling guidelines.
- [ ] Documentation (inline code, API endpoints, or README) is updated.
- [ ] Feature is verified to meet all specified Acceptance Criteria in the staging/dev environment.

---

## Epic 4: Interactive Prompt Mode

---

### US-10: Prompt Mode Input Widget

**Epic/Feature:** Interactive Prompt Mode

**User Story:**
As a developer who wants to refactor or generate code,
I want to open a floating text input widget with a keybinding and type a natural-language instruction,
So that I can initiate a structured code change without leaving Neovim.

**Acceptance Criteria (Gherkin/BDD Style):**
- **Scenario:** User opens Prompt Mode
  - **Given** the plugin is enabled
  - **When** the user presses the configured Prompt Mode keybinding
  - **Then** a floating window appears centered on the screen with an empty text field and a visible border

- **Scenario:** User submits an instruction
  - **Given** the floating widget is open and the user has typed an instruction
  - **When** the user presses `<CR>`
  - **Then** the widget closes and the Prompt Mode pipeline begins (per US-11)

- **Scenario:** User cancels the widget
  - **Given** the floating widget is open
  - **When** the user presses `<Escape>`
  - **Then** the widget closes and no API call is made

**Technical Notes / Constraints:**
- Floating window via `vim.api.nvim_open_win()` with `relative = "editor"`, centered
- Input buffer is a scratch buffer (`buftype = "nofile"`)
- Keybinding registered in Normal Mode only; configurable by the user in `setup(opts)`

**Associated Tasks:**
- Links to: `T-029`, `T-030`

**Definition of Done (DoD):**
- [ ] Code builds locally without errors or warnings.
- [ ] All automated tests (unit/integration) pass; minimum 80% test coverage achieved for new code.
- [ ] Code is peer-reviewed and adheres to project styling guidelines.
- [ ] Documentation (inline code, API endpoints, or README) is updated.
- [ ] Feature is verified to meet all specified Acceptance Criteria in the staging/dev environment.

---

### US-11: Real-time Vimdiff Workspace

**Epic/Feature:** Interactive Prompt Mode

**User Story:**
As a developer reviewing an AI-generated refactor,
I want the model's output to stream into a scratch buffer shown as a vimdiff alongside my original file,
So that I can observe incoming changes in real time before deciding to accept or reject them.

**Acceptance Criteria (Gherkin/BDD Style):**
- **Scenario:** Prompt Mode pipeline starts
  - **Given** the user has submitted an instruction
  - **When** the pipeline initializes
  - **Then** the active file is duplicated into a scratch buffer, a vertical split opens with the original on the left and the scratch on the right, and vimdiff is enabled on both windows

- **Scenario:** SSE tokens arrive
  - **Given** the vimdiff workspace is open
  - **When** SSE chunks arrive from the API
  - **Then** each chunk is appended to the scratch buffer line-by-line and the diff highlighting updates live

- **Scenario:** System prompt construction
  - **Given** any user instruction
  - **When** the API request is built
  - **Then** the system prompt explicitly instructs the model to return only code with no prose explanations and no markdown fences (unless they are literal code)

**Technical Notes / Constraints:**
- Scratch buffer: `buftype = "nofile"`, `bufhidden = "wipe"`, unnamed
- `vim.cmd("diffthis")` called on both windows after the split
- Stream writer targets the scratch buffer using `vim.api.nvim_buf_set_lines()` in the stdout callback

**Associated Tasks:**
- Links to: `T-031`, `T-032`, `T-033`

**Definition of Done (DoD):**
- [ ] Code builds locally without errors or warnings.
- [ ] All automated tests (unit/integration) pass; minimum 80% test coverage achieved for new code.
- [ ] Code is peer-reviewed and adheres to project styling guidelines.
- [ ] Documentation (inline code, API endpoints, or README) is updated.
- [ ] Feature is verified to meet all specified Acceptance Criteria in the staging/dev environment.

---

### US-12: Accept / Reject / Cancel Controls

**Epic/Feature:** Interactive Prompt Mode

**User Story:**
As a developer reviewing a Prompt Mode diff,
I want keybindings to accept the changes, reject them, or cancel the stream mid-generation,
So that I have full, explicit control over whether AI output is applied to my file.

**Acceptance Criteria (Gherkin/BDD Style):**
- **Scenario:** User accepts the diff
  - **Given** the vimdiff workspace is open (stream complete or cancelled)
  - **When** the user presses the Accept keybinding
  - **Then** the original buffer is overwritten with the scratch buffer's content, the split is closed, and the scratch buffer is wiped

- **Scenario:** User rejects the diff
  - **Given** the vimdiff workspace is open
  - **When** the user presses the Reject keybinding
  - **Then** the split is closed and the scratch buffer is wiped; the original buffer is untouched

- **Scenario:** User cancels mid-stream
  - **Given** the vimdiff workspace is open and the curl subprocess is actively streaming
  - **When** the user presses the Cancel keybinding
  - **Then** the subprocess is terminated immediately; the scratch buffer retains its partial state; Accept and Reject remain available

**Technical Notes / Constraints:**
- All three keybindings are local to the scratch buffer window
- Accept uses `vim.api.nvim_buf_get_lines()` on scratch + `vim.api.nvim_buf_set_lines()` on original
- Scratch buffer wiped with `vim.api.nvim_buf_delete(bufnr, { force = true })`

**Associated Tasks:**
- Links to: `T-034`, `T-035`, `T-036`, `T-037`

**Definition of Done (DoD):**
- [ ] Code builds locally without errors or warnings.
- [ ] All automated tests (unit/integration) pass; minimum 80% test coverage achieved for new code.
- [ ] Code is peer-reviewed and adheres to project styling guidelines.
- [ ] Documentation (inline code, API endpoints, or README) is updated.
- [ ] Feature is verified to meet all specified Acceptance Criteria in the staging/dev environment.

---

## Epic 5: Dev Infrastructure & Testing

---

### US-13: Test Scaffolding & CI Setup

**Epic/Feature:** Dev Infrastructure

**User Story:**
As a contributor to ataraxy.nvim,
I want a working mini.test suite with a headless Neovim bootstrapper and a lint config,
So that I can verify plugin behavior automatically and enforce code quality in a single command.

**Acceptance Criteria (Gherkin/BDD Style):**
- **Scenario:** Running the test suite from a clean checkout
  - **Given** only Neovim and curl are installed on the machine
  - **When** the test command is run
  - **Then** `scripts/minimal_init.lua` downloads mini.nvim to a temp dir, all test files are discovered and executed, and results are printed to stdout

- **Scenario:** Running luacheck
  - **Given** the `.luacheckrc` is present
  - **When** `luacheck lua/ tests/` is run
  - **Then** no errors or warnings are reported for valid plugin code; `vim.*` globals are whitelisted

- **Scenario:** A test file exercises a Neovim API
  - **Given** a test that calls `vim.api.nvim_buf_set_lines()`
  - **When** it runs via the headless bootstrapper
  - **Then** it executes without error inside the Neovim runtime

**Technical Notes / Constraints:**
- `scripts/minimal_init.lua` must not require internet access after initial mini.nvim download
- A `Makefile` or shell script wraps the headless Neovim command so contributors don't need to memorize it
- `.luacheckrc` must whitelist: `vim`, `MiniTest`, `describe`, `it`, `before_each`, `after_each`

**Associated Tasks:**
- Links to: `T-038`, `T-039`, `T-040`

**Definition of Done (DoD):**
- [ ] Code builds locally without errors or warnings.
- [ ] All automated tests (unit/integration) pass; minimum 80% test coverage achieved for new code.
- [ ] Code is peer-reviewed and adheres to project styling guidelines.
- [ ] Documentation (inline code, API endpoints, or README) is updated.
- [ ] Feature is verified to meet all specified Acceptance Criteria in the staging/dev environment.
