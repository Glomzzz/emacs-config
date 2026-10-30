# Appearance and Terminal

Themes, fonts, terminal display, optional images, and keyboard input.

## Theme Compatibility

Gruber Darker's legacy nil face colors are normalized only while
`theme/load-gruber-darker` loads that theme.  The original Emacs face API is
restored even if loading fails; other themes and Customize are untouched.

Corfu's fallback colors derive from the active theme's `default`, `highlight`,
`region`, and `fringe` faces instead of a separate hard-coded palette.  Its
completion and documentation popups follow theme changes automatically;
theme-provided Corfu faces and Customize settings still take precedence.
Vertico already inherits standard theme faces.

## Smart Mode Line

`modules/ui/modeline.el` installs Smart Mode Line and its Rich Minority
dependency through the shared package bootstrap.  Its `respectful` theme
uses the existing theme's colors; Gruber Darker remains enabled.  Projectile
path replacement is disabled so redisplay does not perform extra project
root discovery, especially for remote files.

Minor-mode labels are filtered by **mode symbol**, not their displayed text.
The allowlist `modeline/visible-minor-modes` keeps:

- Flymake diagnostics and envrc environment status;
- overwrite, keyboard-macro recording, and Isearch state;
- multiple cursors, rectangle modes, and hidden-unmatched-line editing;
- active Dired asynchronous jobs and Typst watch mode.

Routine labels such as Which Key, Zoom, Undo Tree, Projectile, Eldoc, and
Outline are hidden.  **The modes, keymaps, commands, and global
`minor-mode-alist` are unchanged.**  Eglot/Dape status, major mode,
modified/read-only/remote state, narrowing, and version-control information
remain in their existing mode-line sections.  Status-specific faces, hover
text, and mouse actions are preserved rather than overwritten by Rich
Minority's generic styling.

Customize `modeline/visible-minor-modes` to add or remove indicators; the next
mode-line update uses the new list.  `C-h m` still lists active modes even
when their labels are hidden.  Smart Mode Line handles minor-mode truncation
in narrow windows.  Emacs 31's separate `mode-line-minor-modes` slot is wired
to the same filtered renderer; older inline minor-mode layouts use Smart
Mode Line's normal integration.  Setup is idempotent when the module reloads.

Restart the daemon to apply the saved configuration.  Batch tests do not
change the running session.  The upstream packages emit some obsolete API
and missing lexical-binding warnings during compilation on Emacs 31; the
configuration module itself byte-compiles without warnings.

## Portable Appearance

`appearance/font-families` keeps Cascadia Mono NF first, then tries installed
fallbacks.  `appearance/font-height` defaults to 160 (16 pt); nil leaves the
frame height unchanged.  `appearance/script-font-families` configures Unicode,
CJK, symbols, emoji, and Greek preferences.  Explicit script choices update
each graphical frame's own fontset, so a cached system fallback cannot override
them.  Chinese text and punctuation use LXGW WenKai, with Noto Sans CJK SC as
the fallback; these render `。`, `，`, and `、` at the bottom rather than using
centered Noto Serif CJK TC glyphs.  Unavailable fonts leave Emacs'
font fallback intact.  The `unicode` entry supplies a shared fallback for
otherwise unspecified characters, not an override for ASCII; the primary
family and exact point height are restored after fontset updates.  On NixOS install
`pkgs.cascadia-code` for the family named `Cascadia Mono NF` (the separately
named Caskaydia Nerd Font package is not the same family).
Customize these options and run
`M-x appearance/apply-fonts`; new GUI frames apply them automatically, while
TTY and display-less daemon frames do not query fonts.

The hl-line fallback inherits the active theme's `highlight` face (still
`#282828` with Gruber Darker).  Theme-specific hl-line faces and Customize
settings override it normally; changing to a light theme does not retain a
hard-coded dark stripe.

## Terminal Display, Fonts, Mouse, and Clipboard

`emc` defaults to a blocking terminal client, including when files are supplied
on a graphical desktop.  Use `emc -c` (optionally `-n`) to explicitly request a
GUI frame.  The author's external Nix configuration routes editor environment
variables, Git, Niri shortcuts, and desktop file associations through that
terminal-first launcher, with a separate **Emacs (GUI)** entry.  The standalone
`emacs` binary retains its normal batch/daemon/GUI command-line semantics.

`modules/ui/tty.el` enables mouse input, Unicode popup borders, and native
TTY tooltips when a terminal connects.  Ordinary GUI/batch startup does not
load the terminal integrations.  Emacs 31 has native TTY child frames, which
the installed Corfu uses for completion and documentation popups; do not add
`corfu-terminal` on this version.  Eldoc keeps its normal terminal display;
use `M-x eldoc-doc-buffer` to read complete documentation in a window.

`xclip-mode` supplies local desktop clipboard access for terminal frames,
without replacing GUI frames' clipboard backend.  It prefers `wl-copy` and
`wl-paste` on Wayland, honors a saved `xclip-method`, and is not enabled when
no supported local clipboard tools are available.  Normal `M-w`, `C-w`, and
`C-y` use the clipboard.  Headless installations keep their existing terminal
backend; clipboard reading through a remote terminal is not promised.

Fonts are controlled by the terminal, **not** `appearance/apply-fonts` or
`text-scale-mode`.  The author's Nix configuration uses Kitty with Cascadia
Mono NF at 15 pt, LXGW WenKai for Han and Chinese punctuation, Noto Color
Emoji, and Symbols Nerd Font Mono.  Terminal zoom changes the whole window;
arbitrary per-face fonts/sizes and pixel scrolling remain GUI features.
Some multi-codepoint emoji can still have width/cursor limitations in Emacs 31.

Run `M-x tty/describe` for a capability summary and `M-x kkp-status` for the
actual keyboard negotiation status.  Hold Shift while dragging to use the
terminal's own text selection instead of Emacs' mouse handling.

`C-z` suspends a terminal Emacs as usual.  In graphical frames it sets the mark
(`funcs/mark-or-suspend`, which `C-u` passes to `set-mark-command`); `C-SPC`
sets the mark in either kind of frame.

## Optional Terminal Images and PDFs

`kitty-graphics.el` is declared from its **v1.4.0** release, but is neither
loaded nor enabled on normal startup.  Run the package bootstrap after adding
this declaration.  In a supporting terminal:

1. Run **`M-x kitty-graphics-mode`** to enable images for this Emacs process.
2. Run **`M-x kitty-graphics-doctor`** to check the selected terminal backend.
3. Open an image or PDF (`doc-view-mode`), or use Org's normal
   `C-c C-x C-v` inline-image command.  Enable graphics before opening the file;
   revert/reopen an already-open document if necessary.
4. Run `M-x kitty-graphics-mode` again to disable it.

Kitty's graphics protocol is preferred in Kitty.  Foot can use the Sixel
fallback when `img2sixel` (libsixel) or ImageMagick is installed.  ImageMagick
and Ghostscript are supplied by the author's Nix configuration for image
conversion and DocView.  This is not native GUI-equivalent image support:
third-party advice and redisplay hooks implement it, and tmux/scrolling/mixed
client sessions have upstream limitations.  The mode is global to the daemon,
although graphics are routed to individual client terminals.

**`M-x kitty-graphics-org-heading-sizes`** separately enables enlarged Org
headings on supporting Kitty versions.  Leave it off for heavy editing;
upstream recommends it mainly for reading, and multiple windows on the same
buffer can differ.  `M-x kitty-graphics-typst-preview` offers optional Typst
math previews when the Typst CLI is installed.  Video, the experimental inline
browser, and automatic heading resizing are deliberately disabled.

## Terminal Keyboard Input

`modules/feat/editor/emacs.el` declares `kkp` and enables `global-kkp-mode`
when a terminal frame is initialized, including `emacsclient -t` frames.
GUI-only sessions do not load the package.  KKP negotiates support with the
terminal; unsupported terminals keep their existing keyboard protocol.
The package defaults enable key disambiguation and alternate-key reporting,
so supporting terminals such as Foot can transmit `C-.`, `C-,`, `C-'`,
and more modified keys without handwritten escape-sequence mappings.

Run the package bootstrap after adding this declaration, then restart Emacs.
Use `M-x kkp-status` inside a terminal frame to check negotiation and `C-h k`
to inspect a received key.  Desktop and terminal shortcuts still take
precedence; KKP cannot recover combinations intercepted before Emacs sees them.

While KKP is active, `C-g` arrives as an escape sequence rather than the
traditional single interrupt byte.  Ordinary command-loop cancellation works,
but blocking synchronous subprocesses may not be interruptible with `C-g`,
and the traditional TTY emergency escape behavior is not preserved.  The
package's legacy-key subprocess workaround remains at its upstream default
(disabled); use `M-x global-kkp-mode` to disable KKP if necessary.
