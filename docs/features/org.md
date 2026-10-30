# Org, agenda, notes, and citations

`modules/feat/org/` owns the Org agenda, capture, org-roam notes, and citar
citations.  Org ships with Emacs, so it has no package declaration.  org-roam,
citar, and counsel (for `counsel-org-tag`) are declared with `packages/declare`
and loaded lazily.

| File | Responsibility |
| --- | --- |
| `mod.el` | Feature index |
| `org.el` | Directory and path defaults, buffer setup, the LAST_MODIFIED keyword, TODO keywords, and `C-c C-q` |
| `agenda.el` | `C-c a`, agenda options, the `d` and `p` custom commands, and their skip functions |
| `capture.el` | `C-c c`, capture templates, and refile settings |
| `roam.el` | org-roam notes: `C-c n` keys and database sync |
| `bibliography.el` | citar: `C-c B`, `C-c b`, and the org-cite processors |

## Directory layout

Paths derive from `org-directory` (`~/org/`).  The configuration does not create
them, so create the directories you use:

```text
~/org/
  Agenda/             agenda files                  (org/agenda-files)
  refile.org          capture and refile inbox      (org/refile-file)
  roam/               org-roam notes                (org-roam-directory)
  References/
    references.bib    bibliography                  (org/bibtex-files)
    ...               PDFs and attachments          (org/bibtex-library)
```

org-roam keeps its database synchronized only when `~/org/roam/` exists when
org-roam loads.  Without the directory, the configuration still starts; create
the directory and restart Emacs to enable synchronization.

## Keys

| Key | Command | Scope |
| --- | --- | --- |
| `C-c a` | `org-agenda` | Global.  Eglot-managed buffers use `eglot-code-actions` on this key. |
| `C-c c` | `org-capture` | Global |
| `C-c C-q` | `counsel-org-tag` | Org buffers |
| `C-c n f` | `org-roam-node-find` | Global |
| `C-c n i` / `o` / `t` / `a` / `l` | Insert node, create ID, add tag, add alias, toggle backlinks | Org buffers |
| `C-c b` | `org-cite-insert` | Org buffers |
| `C-c B` | `citar-open` | Global |

The agenda has two custom commands:

- `C-c a d` shows the high-priority tasks, today's agenda, and all normal-priority
  tasks.
- `C-c a p` shows Projects: tasks to refile, stuck projects, NEXT tasks inside
  projects, and tasks ready to archive.

Set `org/hide-scheduled-and-waiting-next-tasks` to nil to include WAITING and
scheduled items in the Project Next Tasks view.

## Menus

Each menu groups commands from its feature file under `C-x C-h`, following the
Hydra convention in `docs/configuration.md`.

| Key | Menu | Scope | Heads |
| --- | --- | --- | --- |
| `C-x C-h A` | Agenda views and capture | Global | `a` dispatcher, `d` daily, `p` projects, `t` TODO list, `m` tags, `s` search, `c` capture |
| `C-x C-h O` | Heading editing | Org buffers | `n` / `p` next and previous heading, `c` cycle, `t` TODO, `+` / `-` priority, `T` tags, `s` schedule, `d` deadline, `i` / `o` clock in and out, `r` refile, `a` archive subtree |
| `C-x C-h N` | org-roam notes | Global | `f` find, `c` capture, `i` insert link, `l` backlinks, `s` sync database |
| `C-x C-h B` | Bibliography | Global | `o` open resources, `f` library file, `e` BibTeX entry, `l` URL or DOI, `a` add file to library |

- The heading menu stays open so repeated edits are quick; `q` leaves it.  The
  other menus close after one command.
- The heading menu lives in Org buffers only, like the Markdown menu.  The org-roam
  keys that need an Org node (`C-c n o`, `C-c n t`, `C-c n a`) remain available
  in Org buffers.
- Inserting a citation stays on `C-c b`, where org-cite inserts it.

## Behavior

- **LAST_MODIFIED.**  Org buffers update the `#+last_modified:` keyword in the
  preamble before each save.  The hook is buffer-local.
- **Stuck projects.**  A project is a TODO heading with at least one TODO heading
  below it.  It is stuck when no NEXT task sits below it.  WAITING NEXT tasks do
  not count.
- **Project Next Tasks.**  Shows NEXT tasks that belong to a project.  Projects,
  habits, and single tasks are hidden.
- **Tasks to archive.**  Shows DONE tasks whose body has no timestamp from the
  current or previous month.
- **Citations.**  citar is the org-cite processor for insert, follow, and
  activation.  It opens attachments with the platform opener: `open` on macOS,
  `xdg-open` on Linux.

## State

Persistent Org and org-roam state stays under the cache root, set by
`cache/configure-state-paths` in `modules/core/cache.el`:

| Path | State |
| --- | --- |
| `org/id-locations.el` | `id:` link locations |
| `org/clock-save.el` | Clock persistence, when enabled |
| `org/persist/` | Org persistent cache |
| `org/roam.db` | org-roam database |

## Renamed helpers

The pasted configuration used `pv/` and `bh/` names.  They are now `org/` names
under the feature namespace rule.  The pasted `bh/` helpers were not included in
the paste, so `agenda.el` provides equivalents named by what they do:

| Pasted name | Current name |
| --- | --- |
| `pv/org-set-last-modified` | `org/set-last-modified` |
| `pv/init-org-hook` | `org/setup-buffer` |
| `pv/org-skip-subtree-if-habit` | `org/skip-subtree-if-habit` |
| `pv/org-skip-subtree-if-priority` | `org/skip-subtree-if-priority` |
| `bh/skip-non-stuck-projects` | `org/skip-non-stuck-projects` |
| `bh/skip-projects-and-habits-and-single-tasks` | `org/skip-projects-and-habits-and-single-tasks` |
| `bh/skip-non-archivable-tasks` | `org/skip-non-archivable-tasks` |
| `bh/hide-scheduled-and-waiting-next-tasks` | `org/hide-scheduled-and-waiting-next-tasks` |

## Validation

`tests/org-tests.el` checks the keys, state paths, citar processor setup, capture
templates, the skip rules, LAST_MODIFIED updates, the four menus (bindings,
mode-locality, and the command each head runs), and an end-to-end Projects
agenda built from a temporary file.  The org-roam menu is checked only for its
autoload, so the suite does not load org-roam.
