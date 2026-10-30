# Dashboard

The `*Daily Dashboard*` buffer and its shortcut reminders.

## Daily Dashboard and Shortcut Memory Aid

`modules/ui/dashboard.el` provides `*Daily Dashboard*` using Emacs' built-in
buttons, with no extra package.  It opens on an ordinary empty startup and
in empty `emc`/emacsclient frames.  Explicit file requests, modified scratch
buffers, batch/bootstrap runs, and an existing `initial-buffer-choice` are
left alone.  The client callback is installed after command-line file
handling so a startup file is not split alongside an unwanted dashboard.

Open it again with **`C-c D`** (`M-x dashboard/open`).  Click an action, or
use `TAB` / `S-TAB` to select a button and `RET` to run it.  Each button shows
the normal global shortcut, not a dashboard-only mnemonic, so the same keys
work after leaving the dashboard.  `g` refreshes labels after rebinding keys;
unbound commands show their `M-x` name.  `q` leaves the dashboard.

| Daily action | Shortcut |
| --- | --- |
| Open file / recent files | `C-x C-f` / `C-c R` |
| Switch buffer | `C-x b` |
| Switch project / find project file | `C-x p p` / `C-x p f` |
| Browse directory | `C-x d` |
| Search files with ripgrep | `C-c s` |
| Jujutsu status | `C-x g` |
| Terminal / process tasks | `C-c t` / `C-c T` |
| Run a command | `M-x` |
| Describe a key / list bindings | `C-h k` / `C-h b` |
| Read manuals | `C-c i` |

Save, undo, duplication, formatting, completion, and structural-editing keys
appear as non-clickable reminders: they should run in an editing buffer,
not on the read-only dashboard.  Tool commands retain their normal prompts
and lazy loading.  Search/Jujutsu/project commands use the working directory
from which the dashboard was opened; no project scan or server startup runs
just to render buttons.  Vterm and ripgrep still need their external
prerequisites.

Customize `dashboard/show-on-startup` to nil and restart Emacs to disable
automatic display; the reopen shortcut remains available.  Ordinary TTY
startup and dedicated daemon/client TTY frames (empty and explicit-file
requests) were smoke-tested; graphical mouse interaction still needs manual
validation.
