# Help and Documentation

Helpful, Eldoc, and Eldoc Box at point.

## Emacs Lisp Help

`modules/feat/editor/help.el` declares Helpful without loading it at startup.
The normal help keys load it on first use:

| Key | Helpful command |
| --- | --- |
| `C-h f` | `helpful-callable` — function, macro, or special form |
| `C-h v` | `helpful-variable` |
| `C-h k` | `helpful-key` — also used by the dashboard button |
| `C-h x` | `helpful-command` — interactive commands only |
| `C-h C-.` | `helpful-at-point` — inspect the current Elisp symbol |

Helpful shows source, references, symbol properties, and debugging actions.
`q` uses the package's normal special-buffer behavior.  The original
`describe-function`, `describe-variable`, `describe-key`, and
`describe-command` remain available through M-x; `C-h o` still runs
built-in `describe-symbol`.  Manual search (`C-c i`) and automatic Eldoc
are unchanged.  No private Helpful advice or symbol-table mutation is
installed.  Run the package bootstrap before using Helpful on a new machine.

## Documentation at Point

Programming buffers use automatic Eldoc after **600 ms of idle time** at
the text cursor (not mouse hover).  Graphical frames enable the public
`eldoc-box-hover-at-point-mode`; terminal frames keep built-in Eldoc display.
The at-point popup suppresses display for 500 ms after motion.  Requesting
at 300 ms could deliver documentation while suppressed, with no retry until
the cursor moved again.  The completion module now owns the longer delay;
Eglot does not reset it.  Server response latency is additional, and a
language backend must provide documentation for the symbol at point.
`C-M-d` calls `eldoc-box-help-at-point` in a GUI and requests normal Eldoc in
terminals.  The package owns its display hooks and cursor-following behavior;
this configuration does not advise private Eldoc update functions, suppress
comments globally, or install a private Eldoc Box renderer.

Eglot code-action suggestions do not contribute text to Eldoc: the public
`eglot-code-action-indications` option keeps only fringe/margin indicators,
not `eldoc-hint`.  Undocumented symbols and empty space therefore do not show
an action-hint popup.  Server hover documentation, signatures, and Flymake
diagnostics keep their normal display.  **`C-c a`** runs `eglot-code-actions`
in Eglot-managed buffers, offering actions at point or for the active region;
`M-x eglot-code-actions` remains available.  `C-.` still runs Embark.

While the Eldoc popup is visible, **`M-n`** scrolls down three lines and
**`M-p`** scrolls up three lines without moving the source cursor or switching
focus.  A numeric prefix changes the line count (for example `C-u 8 M-n`).
These bindings apply only in Eldoc Box at-point hover buffers; they do not
replace ordinary buffer or minibuffer keys.  At the ends, scrolling is a
no-op.  The package's public command allowlist keeps these doc-only actions
from triggering its usual motion-based dismissal.  `C-g` still dismisses.
If you prefer direct reading, `C-M-d` when the popup is already visible
focuses it; `q` closes it and returns focus.  Ordinary mouse-wheel commands
are not remapped by this change and can still dismiss the at-point popup.

The popup's text matches the source frame's default font family and size,
including the source buffer's `text-scale-mode` zoom.  A public
`eldoc-box-buffer-setup-hook` applies the doc-buffer face remap before the
package measures popup geometry; reused popups replace the old scale rather
than accumulating zoom.  Documentation colors and Markdown styling remain
owned by Eldoc Box and the active theme.  Ordinary and zoomed font sizes
were checked against the source text in a real GUI.
