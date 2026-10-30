# Completion and Search

Completion, Isearch, Consult, visible-text jumps, and responsiveness.

## Literal Filenames in Completion

In `C-x C-f`, **`RET`** opens the highlighted completion, while **`M-RET`**
accepts exactly what you typed.  For example, type `plan.org` and press
`M-RET` to visit a new `plan.org`, even if `plt-plan.org` is highlighted.
Save the new buffer with `C-x C-s` to create the file on disk.  **`C-u RET`**
also accepts literal input.  Directory navigation and normal candidate
selection are unchanged.

## Completion Session History

**`M-R`** (`vertico-repeat`) reopens the last recorded completion command
with its previous input; **`C-u M-R`** selects an older session.  Inside a
Vertico prompt, **`C-r`** (`vertico-repeat-select`) offers only sessions for
the current command.  **`M-r`** still inserts ordinary minibuffer history
through Consult, and directory navigation keeps its existing keys.

The public `vertico-repeat` extension ships with Vertico, so no additional
package is installed.  Savehist stores its history at `(cache/file "history")`.
The extension's default filters omit empty input and M-x sessions.  Repetition reruns the command in the current context; it is not
an exact snapshot of files, buffers, or an old working directory.

## Incremental Search

`C-s` / `C-r` start built-in Isearch forward/backward.  **Enter** (`RET` or
graphical Return) repeats in the current direction without ending the search;
`C-s` / `C-r` during search retain their normal direction-switching behavior,
and subsequent Enter presses follow that direction.  The wrapper uses
Isearch's own direction state, not an extra variable or advice.  Numeric
prefixes follow the built-in repeat commands when `isearch-allow-prefix`
is enabled; this configuration does not change that option.  The existing
wrap pause remains: after reaching the last match, repeat again to wrap.

**Esc** (the graphical `<escape>` event) finishes at the current match,
including when the query is empty.  `C-g` retains normal Isearch cancellation
behavior.  The terminal `ESC` character remains a Meta prefix so `M-e` and
`M-s` still work; terminals that send only this character for Escape can use
`M-RET` to finish at the current match instead.  Empty-query Enter uses search
history just like `C-s`, rather than opening a nonincremental search prompt.

Backspace deletes the last character of the search query (`isearch-del-char`),
even after repeating a search, instead of undoing the last search/navigation
state.  The prompt shows the current/total match count, such as `2/5`, using
Isearch's lazy highlighting.  Extra match highlights are still cleared when
the search ends.

These settings live together in `modules/feat/editor/emacs.el`.  Consult's
Isearch history (`M-e`) and result-list search (`M-s l` / `M-s L`) bindings
remain unchanged.  No additional search package is installed.

## Consult Preview Policy

Press **`M-.`** in Consult's file-oriented prompts to preview the selected
candidate.  Ripgrep/Grep, recent files, bookmarks, and Xref use manual
previews.  File registers, recent files, project recent files (including
`< p` / `< F` narrowing), and bookmarks also require `M-.` when offered
as sources in `C-x b` or the other Consult buffer-switching commands.
Selecting a candidate with RET still opens it normally.

Already-open buffers, `consult-line`, and Imenu keep automatic previews
after 200 ms; theme and manual previews wait 400 ms.  Consult still owns
preview cleanup, permitted hooks, and its exclusions for remote/encrypted
files.  Manual preview does not bypass those exclusions and no private
preview advice is installed.  Customize the public `consult-preview-key`
and `consult-customize` settings in `modules/feat/workspace/navigation.el`
if you prefer another trade-off.

## Visible Text Jumps

**`C-'`** (`avy-goto-char-timer`) jumps to visible text in any ordinary
window of the selected frame.  Type a short query, then pause for 500 ms
or press RET; if several matches remain, type the label shown beside the
one you want.  A single match jumps immediately after query entry.
`C-g` cancels, and `M-x avy-pop-mark` returns to the previous location.
This is separate from Consult's buffer/project searches.

Avy is declared in `modules/feat/workspace/navigation.el` and loads only
on first use.  It has no background mode or timer; the delay applies only
while entering a jump query.  `C-;` remains `embark-dwim`, `M-'` remains
`consult-register-store`, and Isearch keeps its existing bindings.  No
Pinyin extension or `avy-setup-default` key remapping is enabled.  Some
terminals cannot transmit `C-'`; use M-x or a GUI frame in that case.
Run the package bootstrap before using Avy on a new machine.

## Completion Responsiveness

Corfu starts automatic completion after a two-character prefix and a 200 ms
pause; backends can override the prefix threshold.  Manual
`completion-at-point` (normally `C-M-i`) remains available for shorter input.
Candidate documentation waits 500 ms initially and 200 ms after selection
changes to avoid resolving every briefly selected candidate.  This does not
change Eldoc's separate idle delay or server-provided completion ordering.

Cape's Dabbrev fallback scans only the current buffer.  Customize
`cape-dabbrev-buffer-function` to `cape-same-mode-buffers` to restore
cross-buffer candidates, or set it buffer-locally for a project.  These
settings trade a slightly later popup and fewer fallback words for less
background work; they do not add completion caches or private package advice.

When Corfu is enabled, remote buffers and buffers at or above
`buffers/feature-size-limit` get buffer-local `corfu-auto` set to nil before
its timer hooks are installed.  Manual completion still works.  This check
runs at activation, not on every keystroke; toggle Corfu off/on to recheck a
buffer that grew past the limit.  Existing buffer-local opt-outs are preserved.

So Long disables Corfu along with Font Lock and line numbers for minified
files; `so-long-revert` restores the modes it disabled.
