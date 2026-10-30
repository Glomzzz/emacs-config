# Projects with Projectile and Counsel

`modules/feat/workspace/projects.el` enables Projectile and Counsel-Projectile.
The prefix is **`C-c P`** (uppercase P); **`C-c p`** remains Fingertip's
structural-editing prefix in source buffers.

| Key | Action |
| --- | --- |
| `C-c P f` | Find a project file with Counsel |
| `C-c P d` | Find a project directory with Counsel |
| `C-c P b` | Switch project buffers with Counsel |
| `C-c P p` | Switch known projects with Counsel |
| `C-c P SPC` | Combined project file/buffer selection |
| `C-c P s r` | Search the project with ripgrep |
| `C-c P A` | Add a known project explicitly |
| `C-c P c c` | Compile the project |
| `C-c P k` | Kill project buffers |

**`C-x C-h P`** opens the Projectile Hydra, also available as **`C-c P .`**.
Each action leaves the menu before opening its picker or command prompt.

| Hydra key | Action |
| --- | --- |
| `p` / `f` / `d` / `b` | Switch project / find file / directory / buffer |
| `SPC` | Combined project file/buffer selection |
| `s` | Search with ripgrep |
| `c` / `t` / `r` | Compile / test / run project |
| `a` / `x` | Add / remove a known project |
| `S` / `k` | Save / kill project buffers |
| `i` | Invalidate project cache |
| `q` | Leave the menu |

Projectile shows a fixed **Projectile** mode-line label and does not automatically
add visited projects to its known-project list.  Use `C-c P A` or
`M-x projectile-add-known-project` to register a project.  Projectile keeps its
own list; Dashboard continues to show the existing project.el list.

Counsel-Projectile uses Ivy directly for its commands.  Global `ivy-mode` and
`counsel-mode` are not enabled: ordinary minibuffers retain Vertico, existing
Consult bindings remain available, and Corfu continues handling completion in
source buffers.  These text-based interfaces work in terminal and GUI Emacs.

Projectile's automatic project.el finder is removed by a `projectile-mode-hook`,
including when the mode is re-enabled.  Eglot, Consult's existing project
commands, and Dashboard retain project.el's nearest language-marker discovery.
Projectile commands use Projectile's own root discovery and can therefore choose
a different root, especially with nested projects or a `.projectile` file.

The shared cache configuration stores known projects, file-visit ranking data,
and optional saved sessions below `cache/root`:

| Path | State |
| --- | --- |
| `projectile/projects.eld` | Explicitly registered projects |
| `projectile/frecency.eld` | File-visit ranking |
| `projectile/sessions/` | Optional per-project saved sessions |

File indexes use memory caching (`projectile-enable-caching` is `t`), so the
current Projectile version does not write persistent indexes into project roots.
Both packages use `packages/declare` with `:ensure nil`; install declarations
through the shared package bootstrap on another machine.
