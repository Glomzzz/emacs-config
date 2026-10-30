# Dashboard

`modules/ui/dashboard-config.el` configures the upstream `dashboard` package.
It replaces the local Daily Dashboard with the Emacs logo banner, the title
**“The truth is the whole.”**, five recent files, five bookmarks, and ten projects.
Projects come from the existing built-in project.el list (`C-x p p`).

Dashboard opens on an empty startup and in empty `emc`/emacsclient frames.
Explicit file requests, modified scratch buffers, batch/bootstrap runs, and an
existing `initial-buffer-choice` take precedence.  The client callback is
installed after command-line file handling so startup files are not split
alongside Dashboard.  Customize `dashboard/show-on-startup` to nil and restart
Emacs to disable automatic display.

Open Dashboard with **`C-c D`** (`M-x dashboard/open`).  Use `TAB` / `S-TAB` to
select an item and `RET` to visit it.  `g` refreshes and `q` leaves the buffer.
The package's section shortcuts are `r` for recent files, `m` for bookmarks,
and `p` for projects; `{` / `}` move between sections.

**`C-x C-h s`** opens Dashboard and its Hydra menu.  **`.`** opens the same menu
inside Dashboard.  Section navigation and refresh keep the menu active; opening
a file, bookmark, project, or buffer leaves it.

| Hydra key | Action |
| --- | --- |
| `n` / `p` | Next / previous section |
| `g` | Refresh Dashboard |
| `f` | Open a file |
| `r` | Consult recent files |
| `m` | Consult bookmarks |
| `P` | Switch project |
| `b` | Consult buffers |
| `q` | Leave the menu |

Dashboard is declared through the shared package workflow with `:ensure nil`.
Run `M-x packages/bootstrap` after loading a configuration with a newly added
Dashboard declaration; see the [configuration guide](../configuration.md) for
first-run bootstrap instructions.  Recent files, bookmarks, and project state
live below the shared cache root.  Dashboard uses the caller's working directory
for commands opened from its menu.
