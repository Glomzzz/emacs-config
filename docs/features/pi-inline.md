# Inline Pi Editing

Editing a file in place with the Pi CLI from Emacs.

## Inline Pi File Editing

`pkgs/pi-inline.el` is a standalone local package, wired in by
`modules/feat/editing/pi.el`.  It requires Emacs 29.1+ and a recent `pi` CLI
with RPC `agent_settled` support.  Log in/configure a model with Pi normally
before using it; the package reuses Pi's credentials and offers Pi's current
model as the default choice.  There is no additional Emacs package to bootstrap.

1. Visit a local file and press **`C-c C-a`** (`M-x pi-inline/start`).
   Type instructions in the highlighted field; surrounding source stays
   visible.  Point provides context, **not an edit boundary**: Pi can edit
   anywhere in this file, change other files, or run commands as needed.
2. **`C-c C-k`** cancels a draft, restoring source text, modification state,
   read-only state, and undo history.  Only the field is editable while
   drafting.  Normal saving is blocked and auto-save-file writing is suspended
   so temporary instructions never become source content.
3. **`C-c C-c`** removes the field and **saves the source automatically**,
   using its normal save hooks, then opens **`Pi model:` in the minibuffer**.
   Choose a `provider/model-id` with normal completion; annotations show model
   names.  **RET** accepts Pi's current model (or the first available model
   when no current model is available).  Pi must acknowledge the selected model
   before the instructions are sent.  **`C-g`** while loading/choosing models
   closes the startup worker and restores the editable instructions, without
   sending a prompt; the source remains saved.  Discovery/switch errors do the
   same rather than silently using a different model.  New visiting files are
   created too; save failures reopen instructions without starting a worker.
   A virtual **`agent working… — click to see process (M-.)`** block then shows
   progress without changing file contents.  The source is editable again.
4. Click the block or press **`M-.` at its marker** to open the matching live
   `*Pi Inline Session*` buffer.  It shows thinking, responses, tool activity,
   diagnostics, and the session path.  This is an Emacs RPC view, not Pi's TUI.
   Extension dialogs show a **Respond to Pi** button: click it or use TAB/RET
   to choose, confirm, or enter text.  Nothing is automatically approved or
   declined.  `C-g` dismisses a dialog.  `q` buries the session view.
5. Pi makes its edits **directly on disk**.  After it settles, changed local
   visiting buffers reload only if unmodified.  If you typed while Pi worked,
   those unsaved edits are preserved and the transcript suggests
   `M-x diff-buffer-with-file` to reconcile them.  Other modified buffers are
   not saved automatically; Pi sees their disk versions.  Removed files are
   not recreated by the refresh.  The final reply remains in the transcript;
   it is **never inserted into your source**.

**Cancellation/failure is not an undo operation.**  `C-c C-k` stops a running
worker from the source or transcript, but file edits and command side effects
already performed remain.  Failed/aborted requests also refresh unmodified
buffers.  Use version control/backups to review or undo disk changes; there
is no longer a single Emacs undo entry for a request.  Failure blocks link to
details; `C-c C-c` reopens instructions for retry, and `C-c C-k` dismisses them.

The model list comes directly from that Pi worker's `get_available_models`
RPC command on every submission, including configured/custom providers that
Pi makes available.  Emacs does not maintain its own catalog or read credential
files.  With no available models, configure/login through Pi and try again;
no model prompt is sent.  Selection uses `set_model`, not CLI name matching,
so identical model IDs from different providers remain distinct.

Each request uses a fresh persisted Pi session in the project root (or
`default-directory` without a project).  It receives the filename, full-file
cursor location, major mode, and up to 12,000 characters on either side of
point, ignoring narrowing.  This excerpt does not limit Pi's read/edit tools.
Instructions/context are sent to the model provider and stored in Pi's normal
session history.  **No addon tool allowlist, extension/MCP disabling, or default
request deadline is imposed.**  Pi's normal configured tools (including
`bash`, `edit`, and `write` by default), extensions, MCP, project trust, provider
limits, OS permissions, and extension approval policies still apply.  This
package does not sandbox or automatically trust project code.

Customize `pi-inline-executable`, `pi-inline-extra-arguments` (for example
`("--model" "sonnet")`), `pi-inline-context-size` (nil includes the whole
buffer), or `pi-inline-timeout` (nil, no deadline, by default).  A `--model`
argument sets Pi's initial/default picker choice, not a forced selection.
Do not override RPC mode through extra arguments.  One request is allowed
per source buffer; different buffers can run concurrently.  Emacs' buffer
read-only flag is not a restriction on Pi's disk edits and is restored after
drafting/reloading.
Remote, indirect, and non-file/special buffers are not request sources.
Reverting the source does not stop a worker.  Killing/changing its mode removes
source UI but submitted work continues; cancel from its session view instead.
`M-x pi-inline/session` reopens the current/last transcript while its association
is available; the named transcript buffer also remains in the buffer list.

Outside the status point, `M-.` keeps normal definition lookup.  A lightweight
binding-only minor mode gives `C-c C-a` precedence in ordinary editing buffers,
including Org/Markdown, without loading Pi at startup.  Org attachment remains
available through `M-x org-attach`; Dired's Android mount shortcut is unchanged.
Disable `pi/global-inline-key-mode` to retain major-mode precedence instead.

Run the focused offline tests with:

```sh
emacs --batch -Q -L pkgs -l tests/pi-inline-tests.el -f ert-run-tests-batch-and-exit
```

The deterministic Python RPC fixture exercises real disk edits, multi-file
refresh, unsaved-buffer preservation, automatic saving, model discovery and
selection/cancellation, extension dialogs, and failures, without model calls,
credentials, or network access.  The full runner includes these tests.
The installed Pi CLI's model-discovery RPC was also smoke-tested without
sending a prompt.  Actual provider generation and graphical mouse hit-testing
still need manual validation.
