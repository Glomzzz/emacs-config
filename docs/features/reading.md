# Reading

EPUB and PDF reading.  The EPUB reader is in `modules/feat/editor/reading.el`;
the PDF integration is in `modules/feat/editor/pdf.el`.

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

## PDF Reading

Graphical frames open PDFs in [Emacs Reader](https://codeberg.org/MonadicSheep/emacs-reader),
a MuPDF-based reader installed from Codeberg through `packages/declare-vc`.
Terminal frames keep DocView, because Reader draws through Emacs image support
and the terminal path is kitty-graphics.

First setup takes three steps:

1. `M-x packages/bootstrap` installs the `reader` package.
2. Restart Emacs (or the daemon), so the package is active in the session.
3. `M-x pdf/build` builds the dynamic module against nixpkgs' MuPDF and loads
   it.  No further restart is needed for the first build.

After `M-x package-vc-upgrade RET reader RET`, run `M-x pdf/build` and restart
Emacs.  A loaded module cannot be replaced in the same process.

The build runs `nix build` for MuPDF's `dev` and `out` outputs.  Out-links in
`(cache/folder "pdf")` keep those store paths alive, so `nix-collect-garbage`
keeps the library.  The module records that library path, so it loads without
`LD_LIBRARY_PATH`.  `pdf/build-cflags` defaults to `-O2`, because the upstream
Makefile sets no optimization level.  Deleting the cache root removes the
out-links; run `M-x pdf/build` again to restore them.

Only PDF is registered for Reader.  EPUB stays with nov, and other formats keep
their modes.  `M-x reader-open-doc` still opens any format Reader supports.  If
the module is missing or fails to load, a graphical PDF falls back to DocView
with a message.  Large PDFs open in Reader without Emacs' size prompt
(`large-file-warning-threshold`); DocView and other files keep the prompt.

Reader is lazy: `packages/declare-vc` makes no network request at startup, and
Reader loads on the first PDF.  Its upstream save-place hook would load the
package for every file, so the config runs that restore only in Reader buffers.

| PDF key | Action |
| --- | --- |
| `n` / `p` | Next / previous page |
| `C-n` / `C-p` | Scroll down / up |
| `C-b` / `C-f` | Scroll left / right |
| `M-<` / `M->` | First / last page |
| `M-g g` | Go to a page |
| `+` / `-` / `=` | Zoom in / out / reset |
| `H` / `W` | Fit height / width |
| `O` | Outline |
| `C-x r b` | Bookmarks |
| `Q` | Quit the buffer |

Not available yet: search, text selection, annotations, and SyncTeX.  Upstream
plans selection and annotations for 0.5.0, which needs Emacs 32's canvas image
type.  Until then, `C-s` in a DocView buffer searches, and `M-x doc-view-open-text`
shows a PDF as text.
