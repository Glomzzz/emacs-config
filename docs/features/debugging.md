# Debugging with Dape

`modules/feat/languages/debug.el` configures Dape as the Debug Adapter Protocol
client.  It works alongside Eglot and provides the same debugging commands in
terminal and graphical Emacs.  Language modules own adapter launch settings;
external debugger executables are supplied by the system or development shell.

Open the menu with **`C-x C-h d`**.  Stepping, breakpoint edits, evaluation, and
session selection keep the Hydra active.  Other keys run their normal commands
without closing it, so you can move around source buffers between operations.
`q` leaves the menu without ending the debug session.  Launching, configuration
editing, and opening debug panes leave the menu so those interfaces receive
their normal keys.

| Keys | Action |
| --- | --- |
| `n` / `i` / `o` | Next line / step in / step out |
| `c` / `p` | Continue / pause |
| `r` | Restart the current stack frame, if supported by the adapter |
| `ss` / `st` / `sf` | Select session / thread / stack frame |
| `su` / `sd` | Move up / down the stack |
| `sl` / `sb` / `se` | Show scope variables / breakpoints / watched expressions |
| `bb` / `bd` / `bD` | Toggle breakpoint / delete at point / delete all |
| `bc` / `bh` / `bl` | Conditional / hit-count / log breakpoint |
| `bf` | Add a function breakpoint |
| `bs` / `bL` | Save / load breakpoints |
| `dd` | Launch with Dape's configuration prompt and history |
| `ds` | Restart the session, or the last configuration when no session is active |
| `de` | Edit `dape-configs` through Customize |
| `ee` / `er` / `es` | Evaluate an expression / active region / symbol at point |
| `ea` | Toggle a watched expression, defaulting to the region or symbol |
| `ui` / `ur` | Toggle info panes / open the REPL |
| `k` | Terminate the session |
| `Q` | Disconnect while asking the adapter to leave the debuggee running |
| `q` | Leave the Hydra |

Two keys differ from the earlier compact menu: **`bb` replaces `b`** for toggling
a breakpoint, and **`ds` replaces `r`** for restarting the session.  `r` now
restarts a stack frame, matching the expanded menu's stepping controls.

`dd` uses the normal Dape prompt: select a named configuration and override
properties inline, or use `M-p` / `M-n` for recent launch history.  For example,
`gdb :program "./build/example"` selects the built-in GDB adapter configuration.
`ds` also falls back to the latest launch history after a session ends.  Persistent
launch settings belong in the language module or a project `.dir-locals.el`;
review directory-local settings before accepting them.

`sl` selects the scope tab, which may initially show arguments, locals, or
another adapter-provided scope.  Use `TAB` / `S-TAB` in the info pane to cycle
its related tabs.  The `sb` and `se` commands select the breakpoint and watch
tabs directly.  Dape opens its REPL and info panes automatically when a session
starts; the configured arrangement places info panes on the right.

`er` requires an active region.  `es` evaluates the symbol without prompting and
preserves point and mark.  The menu's evaluation commands use DAP's **watch
context** so plain expressions work with adapters such as GDB whose REPL context
expects debugger commands.  Use `ur` for the native debugger REPL.  Conditions,
hit counts, logpoints, frame restart, and disconnect behavior depend on adapter
capabilities; Dape reports unsupported operations.

Adapters are stored below `(cache/folder "debug-adapters")`, and the default
breakpoint file is `(cache/file "dape-breakpoints")`.  Dape is declared through
the shared `packages/declare` / `:ensure nil` workflow.  SVG support is not
required for its terminal UI.
