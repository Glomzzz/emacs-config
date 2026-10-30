# Editing

Project editing policies, pairing, delimiter colors, and resource limits.

## Project Editing Policies

Save-time whitespace cleanup defaults to code/config buffers only; text,
Markdown, and Org keep meaningful trailing spaces.  Set
`editor/trim-trailing-whitespace` to nil in `.dir-locals.el` to disable it
for a project, or t to opt a text buffer in.  Remote/large buffers still skip
cleanup.  Formatters continue to own their language's formatting rules.
Sentence/fill patterns and bidirectional text layout use Emacs/major-mode
defaults rather than global handwritten regexes or forced left-to-right text.

## Shared Resource Limits

`modules/core/buffers.el` owns `buffers/feature-size-limit` (2 MiB-sized
character count by default), used by pairing, whitespace cleanup, highlighting,
line numbers, automatic completion, and Git markers.
`buffers/color-preview-size-limit` defaults to 1 MiB-sized character count.
Customize either limit; nil removes the size restriction.
Other package-specific limits remain in their own package options.

## Delimiter Nesting Colors

`modules/ui/ui.el` declares Rainbow Delimiters through the normal package
bootstrap.  It loads on first eligible programming/config buffer, with
explicit hooks for `yaml-mode` and `yaml-ts-mode` as well.  Five depth colors
cycle for deeper nesting; theme/package faces choose the actual colors.
No Tree-sitter parser is required, so Emacs Lisp buffers benefit too.
YAML colors apply to inline brackets/braces, not indentation levels.

Automatic activation skips remote, large, special, and minibuffer buffers,
using `buffers/feature-size-limit`.  So Long disables the mode for very long
lines and restores it on revert.  Show Paren continues to highlight the
matching delimiter, while Fingertip retains ownership of structural editing;
neither one's settings or shortcuts are changed.  Toggle the colors with
`M-x rainbow-delimiters-mode` and customize
`rainbow-delimiters-max-face-count` to change the color cycle length.

## Pairing and Structural Editing

`modules/feat/editing/pairs.el` uses
[Fingertip](https://github.com/manateelazycat/fingertip), installed from Git
through `packages/declare-vc`.  Smartparens and its language rules have been
removed; `electric-pair-mode` stays disabled so only one engine owns pairing.
Run the package bootstrap, then restart Emacs to apply this replacement.
Already installed Smartparens files are left untouched but are no longer used.

Fingertip's VC build runs `scripts/patch-fingertip.el` before byte/native
compilation to add missing declarations for its optional SGML, web-mode, and
IELM functions.  Only Fingertip is added to `package-vc-allow-build-commands`;
other VC packages are not authorized by this change.  The patch is idempotent,
preserves upstream declarations, and does not load or install optional modes
or suppress compiler warnings.  Reinstalls and `M-x package-vc-upgrade` use the
same build step.  Normal startup does not rewrite package sources.  An existing
checkout can be patched once by running the script from its directory with
`emacs --batch -Q -l /path/to/emacs/scripts/patch-fingertip.el -f pairs/patch-fingertip`,
then recompiling `fingertip.el`.

Automatic activation requires **an active Tree-sitter parser** and a mode in
`pairs/enabled-modes` (programming/config modes, Markdown/Org, and
`typst-ts-mode` by default).  This covers the configured Tree-sitter language
modes, including TSX and Typst.  Emacs Lisp, Org, Markdown, Haskell, and other
parser-free/fallback buffers keep ordinary insertion, **without automatic
pairing**.  No compatibility layer or second pairing engine is installed.
Minibuffers, terminals, special/read-only buffers, and buffers of 2 MiB or more
skip activation.  So Long also disables Fingertip for very long lines.
If you manually create a parser after entering a mode, run `M-: (pairs/enable)`
to recheck eligibility; no grammar is installed just to enable pairing.

Fingertip owns `()` / `[]` / `{}`, their Chinese equivalents `（）` / `「」` /
`【】`, and quotes.  `<`, `>`, `%`, and `=` stay literal.  Upstream leaves Rust
apostrophes literal, so lifetimes and labels do not acquire extra quotes.
Space inside empty braces/brackets adds padding; RET splits empty pairs and
indents.  **Backspace** (`DEL` and graphical `<backspace>`) uses ordinary
Emacs deletion: it deletes the character to the left, including opening/closing
brackets and quotes, instead of protecting them or moving across them.  Between
an empty pair, it deletes only the opening delimiter and leaves the closing one.
`C-d` still protects nonempty delimiters; `C-k` uses Fingertip's structural kill.
Closing brackets can jump out across the remaining contents of a pair.  Apart
from Backspace, these are upstream Fingertip semantics, not the previous
non-strict Smartparens policies.

A double quote typed **inside a string inserts an escaped quote** instead of
skipping the closing quote; move right to leave the string.  Use the explicit
wrapping commands below to choose delimiters around a selection.  Ordinary
selection replacement and programmatic snippet insertion remain unchanged.
`C-q` inserts a literal character.  Backspace can leave delimiters unbalanced;
disable the mode temporarily for ordinary forward deletion or other
unstructured editing.

Structural commands keep a buffer-local `C-c p` prefix rather than adopting
upstream's suggested Meta bindings, which conflict with snippets, registers,
and Eldoc scrolling:

| Key | Action |
| --- | --- |
| `C-c p (` / `[` / `{` | Wrap the selection or syntax node |
| `C-c p "` / `'` | Wrap with double/single quotes |
| `C-c p u` | Remove the enclosing delimiters (unwrap) |
| `C-c p n` / `p` | Jump right/left by syntax node |
| `C-c p m` | Jump to the matching delimiter |
| `C-c p j` | Leave the pair and insert a newline |
| `C-c p a` | Jump to the beginning of a definition |
| `C-c p q` | Insert the next character literally (also `C-q`) |
| `C-c p t` | Disable Fingertip in this buffer |
| `C-c p ?` | Describe Fingertip and its active bindings |

After disabling it, use `M-x fingertip-mode` to enable it again only in a
buffer with an active parser.  The old Smartparens slurp/barf, raise, and angle
wrapping shortcuts are not retained: Fingertip has no direct equivalents.
`pairs/enabled-modes` controls eligibility, not the parser requirement.

## Undo History

`undo-tree` (`modules/feat/editing/undo.el`) keeps every edit branch, not a
single linear list.  `global-undo-tree-mode` enables it in ordinary buffers.

| Key | Action |
| --- | --- |
| `C-/` or `C-_` | Undo (`undo-tree-undo`) |
| `M-_` or `C-?` | Redo (`undo-tree-redo`) |
| `C-x u` | Visualize the undo tree (`undo-tree-visualize`) |

`C-x u` therefore no longer runs the built-in `undo` command.  The tree is
kept in memory only (`undo-tree-auto-save-history` is nil), so it is discarded
when the buffer is killed or Emacs exits, and nothing is written under the cache
root.
