# Workspaces with Tabspaces

`modules/feat/workspace/workspaces.el` adds buffer-isolated workspaces on top
of Emacs' native tab bar.  Each tab keeps its own window layout and buffer
list.  The tab bar itself is hidden (`tab-bar-show` is nil), so workspaces are
selected with the commands below rather than from a visible strip.  Set
`tab-bar-show` to t to show the bar again.  Buffers are still shared Emacs buffers: adding a file to two workspaces
does not create independent copies of its contents.

Tabspaces loads from `emacs-startup-hook`, after feature declarations have
finished.  This keeps its Dired dependencies from activating file integrations
partway through module loading.  It uses the shared package declaration and
bootstrap workflow with `:ensure nil`; no installation runs during startup.

## Commands

The workspace prefix is **`C-c w`**.  The existing **`C-c P`** Projectile prefix
and **`C-x C-h w`** window menu are unchanged.

| Key | Action |
| --- | --- |
| `C-c w s` | Switch to a workspace, or create one by name |
| `C-c w o` | Open an existing project in its workspace, or create a project/workspace |
| `C-c w b` | Select a buffer from the current workspace |
| `C-c w t` | Select a buffer and switch to its workspace |
| `C-c w n` | Rename the workspace |
| `C-c w d` | Close the workspace without killing its buffers |
| `C-c w r` / `C-c w R` | Remove current / selected buffer from the workspace |
| `C-c w S` | Save a complete snapshot of all tabs |
| `C-c w L` | Restore the current project's session, or the global snapshot outside a project |
| `C-c w .` / `C-x C-h W` | Open the workspace Hydra |

The Hydra provides switch/create (`s`), project (`o`), Consult buffer selection
(`b`), next/previous tab (`n`/`p`), rename (`R`), close (`d`), buffer removal
(`r`), and session save/restore (`S`/`L`).  Each action leaves the menu.
Native `C-x t` tab commands remain available.

**Closing a workspace is not killing its buffers.**  The upstream `C-c w k`
command does both; use it only when the workspace's buffers can be discarded.
Removing a buffer keeps it alive and, with the upstream default, makes it
available in the Default workspace.

## Consult and project commands

**`C-x b`** retains Consult, with a workspace-local ordinary buffer source.
Use **`< w`** to narrow to workspace buffers and **`< b`** to select from all
buffers.  Recent files, bookmarks, and other Consult sources remain available;
they are not restricted to the workspace.

The integration copies Consult's public buffer source and scopes only its
candidate lookup.  It does not change the global `consult-buffer-list-function`:
**`C-x p b`** still selects all project buffers, multi-buffer searches retain
their normal scope, and recent-file deduplication stays global.  Disabling
`tabspaces-mode` restores the original Consult buffer source.

Project.el keeps the same language-aware root discovery used by Eglot,
Consult, and Dashboard.  Tabspaces' project fallback and interception of
`project-switch-project` are disabled; use **`C-c w o`** explicitly for a project
workspace.  Projectile continues using its own project discovery as documented
in [Projects](projects.md).

Automatic `project-todo.org` creation is disabled.  Opening an existing
marker-only project does not initialize version control.  The upstream
open-or-create command can initialize version control when explicitly used to
create a new project in an unrecognized directory.

## Session saving and automatic restoration

Automatic restoration is enabled.  On a regular interactive startup, Tabspaces
restores the global snapshot.  In daemon mode it waits for the **first client
frame**, where the saved window layouts have a real frame size.  It does not
restore the snapshot again for each subsequent client frame.

On normal exit, Tabspaces saves per-project sessions and non-project tabs.
An additional exit hook then writes a complete global snapshot, so project tabs
also return automatically next time.  Project sessions are restored on demand
when a project workspace is opened.  **`C-c w S`** writes the complete snapshot
manually without waiting for exit.  There is no periodic idle saver by default;
a crash can lose workspace changes since the last save.

All session state lives below `cache/root`, never in project directories:

| Path | State |
| --- | --- |
| `tabspaces/session.el` | Complete startup snapshot |
| `tabspaces/projects/<sha256>.el` | Per-project session, keyed by the full expanded project path |

Using full-path hashes prevents different projects with the same basename from
sharing a session file.  Paths are not resolved through remote hosts just to
calculate a cache filename.  These files are meaningful state, not disposable
build artifacts.

Batch loads, bootstrap, compilation, and regression runs do not automatically
restore or save real sessions.  Tests use temporary state and explicitly enable
the workspace mode when exercising it.

Restored terminal buffers start fresh processes; running programs, output, and
terminal state are not resurrected.  Tabspaces skips TRAMP records on restore.
Its session restoration targets one frame, not a multi-frame desktop.  Saved
local files can run the configuration's usual file/mode hooks when reopened.
Restart the daemon when ready to use the integration; tests do not modify the
running daemon.
