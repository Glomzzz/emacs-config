# Reading

The EPUB reader in `modules/feat/editor/reading.el`.

## EPUB Reading

Open an `.epub` with `C-x C-f` or `emc book.epub`. The reader in
`modules/feat/editor/reading.el` uses Nov and Visual Fill Column, both already
in the package declarations. Text stays centered at **80 columns** (roughly
40 full-width Han characters), soft-wraps in narrower windows, and reflows
when the window is resized. Width changes only adjust display margins: text
offsets, links, and bookmarks stay intact.

Books use the active theme's colors instead of publisher foreground/background
colors. The book/section title remains in Nov's header; a compact mode line
shows `Part N/M` and the position within that part. Parts are EPUB spine
entries plus the contents document, not equal-length chapters or a whole-book
percentage. Line numbers, the current-line stripe, and trailing-space markers
are disabled only in the book buffer.

| Key in an EPUB | Action |
| --- | --- |
| `SPC` / `DEL` (Backspace) | Page forward / backward, crossing section boundaries |
| `PgDown` / `PgUp`, `C-v` / `M-v` | Same section-aware paging |
| `j` / `k`, down / up | Move by displayed line |
| `n` / `p` or `]` / `[` | Next / previous section |
| `t` | Open the table of contents |
| `i` | Search the contents with Consult Imenu |
| `TAB` / `S-TAB`, `RET` | Next / previous link, follow link |
| `l` / `r` | Back / forward through reading history |
| `w` | Enter a reading width in columns |
| `+` / `-` | Widen / narrow by four columns (numeric prefixes multiply) |
| `=` | Reset to the default reading width |
| `?` | Show mode help and bindings |

Contents selection uses Nov's index with a local jump adapter: paths resolve
relative to the contents document while the actual section index stays updated.
This avoids Nov 0.5.0's temporary-index restoration after an Imenu jump, so
history, subsequent navigation, and the progress line remain consistent.

The added keys also work on linked text. `C-s` starts Nov's built-in
incremental search; repeat `C-s` after a failing search to continue into the
next part (`C-r` searches backward). Standard Emacs bookmarks
(`C-x r m`, `C-x r b`) retain the part and position. Nov saves the last reading
position at `(cache/file "nov-places")` when the book buffer is killed or Emacs
exits; merely closing a daemon client leaves the book open in the daemon.

Customize `reading/nov-text-width` for the default measure; `w`, `+`, and `-`
change only the current book until it is reopened. GUI body text keeps
`reading/nov-body-family` (LXGW WenKai) and extra leading. In a terminal, fonts,
font size, and cell height still belong to Kitty: **Ctrl+Alt+Shift+= / -** zoom
and **Ctrl+Alt+Shift+0** resets. The author's existing Nix Kitty configuration
already supplies the Latin/CJK fonts, and its CLI package list supplies
`unzip`, which Nov requires. No new system package, global Kitty typography
change, or automatic graphics activation is needed for text-first reading.
