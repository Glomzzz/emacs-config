# Emacs Configuration Guide

This configuration is a small, source-based Emacs distribution.  `init.el`
is the entry point, package declarations live beside the feature that uses
them, and mutable Emacs data is kept below the cache root instead of in the
repository.  For first-run commands, prerequisites, and separate NixOS and
non-NixOS launcher installation, see [Install `emc`](emc-installation.md).

## 1. How the Configuration Works

The important files and directories are:

```text
early-init.el                 Early package and cache paths
init.el                       Main entry point and module loader
modules/
  mod.el                      Root module index
  core/
    mod.el                    Core module index
    cache.el                  Cache path helpers
    packages.el               package.el/use-package bootstrap helpers
    emc.el                    Launcher and stale-config entry points
  feat/
    mod.el                    Feature module index
    completion/                Completion submodules and index
    editing/                  Editing commands and integrations
    editor/                   Editor defaults and persistent state
    files/                    Dired and file operations
    languages/                Shared language APIs and language modules
      support/                One language-support module per language
    process/                  Terminals and task processes
    workspace/                Project, Git, and navigation integrations
  ui/
    mod.el                    UI module index
    *.el                      Theme, appearance, and UI integrations
pkgs/                         Small local packages shipped with the config
tests/                        Batch configuration regression tests
docs/                         Configuration documentation
```

### Load order

1. Emacs loads `early-init.el`.  It loads `modules/core/cache.el`, disables
   package startup initialization, places package files and persistent state
   under the cache root, and redirects native compilation (ELN) there.
2. Emacs loads `init.el`.  It loads the cache helpers again when necessary for
   `-Q`/batch bootstrap runs, sets fallback state paths, and defines
   `mod/import`.
3. `init.el` calls `(mod/import '("modules/"))`.  A path ending in `/` means
   `mod.el`, so this loads `modules/mod.el`.
4. `modules/mod.el` imports `core/`, `ui/`, and `feat/`.  Each directory has
   its own `mod.el`, which contains the explicit load order for that area.

`mod/import` resolves paths relative to the file containing the call.  Keep
imports relative and keep the order intentional: a module can rely on earlier
modules having loaded, but should not search arbitrary directories or load the
whole configuration a second time.

### Adding a module

For a small change, add it to the existing feature file that owns the
behavior.  For a distinct integration:

1. Create `modules/feat/example.el` (or a file under an existing feature
   subdirectory).
2. Add its relative path to the nearest `mod.el`; the top-level feature index
   imports each feature directory.
3. Put package declarations, setup, and feature-owned functions in that file.
4. Load the file in a clean batch run or restart the daemon before testing.

The same rule applies to `modules/core/` and `modules/ui/`.  A file that is
not listed by an index is not part of the normal configuration.

### Packages and Cache

#### Declaring a Package

`modules/core/packages.el` provides the package contract used by every
feature:

```elisp
(require 'packages)

(packages/declare 'example-package)
(use-package example-package
  :ensure nil
  :commands (example-command)
  :custom
  (example-option t)
  :bind (("C-c x" . example-command)))
```

Use `packages/declare` once for every package the module needs, before its
`use-package` form.  `:ensure nil` is deliberate: this configuration controls
installation centrally instead of allowing every `use-package` form to make
its own network request.

During normal startup, `packages/declare` only records the package in
`packages/declared`; it does not install anything.  Missing packages are
installed in one of two bootstrap paths:

- **First run:** `emacs --batch -Q -l /path/to/emacs/scripts/bootstrap.el`.
  The script sets `packages/bootstrap-mode` to `t` before loading `init.el`.
  In that mode declarations install missing packages as they are evaluated,
  and `packages/save-selection` persists `package-selected-packages` and
  refreshes quickstart metadata.  This was tested with an isolated empty
  cache and network installation, followed by a normal batch load.
- On an already working installation, run `M-x packages/bootstrap` after
  loading to install newly added declarations.  This is **not** a reliable
  cold-start procedure: eager dependencies such as `colorful-mode` can fail
  before that command is available.

The author's managed systemd preflight is external to this repository.
Neither it nor a service is required; the standalone batch entry point and
portable `scripts/emc` launcher are shipped here.

The configured package archives are GNU ELPA, NonGNU ELPA, and MELPA.  Archive
metadata is refreshed at most once during a bootstrap pass.  A package that is
already provided by Emacs can still be expressed with `packages/declare` when
it is useful for documenting the module; it remains `:ensure nil`.

Package activation uses Emacs' `package-quickstart` file at
`cache/file "package-quickstart.el"` so startup reads one generated autoload
file instead of every installed package's autoload file.  The bootstrap path
refreshes that file after installing declarations; run
`M-x package-quickstart-refresh` after manually changing the package set.

#### Cache Root

All cache helpers are defined in `modules/core/cache.el`:

```elisp
(cache/folder "feature-name") ; creates and returns a directory
(cache/file "feature/state")  ; creates the parent and returns a file path
```

The root is:

```text
$XDG_CACHE_HOME/emacs/     when XDG_CACHE_HOME is set
~/.cache/emacs/             otherwise
```

To inspect the expanded path from a running Emacs, evaluate `cache/root`;
`(cache/tree-sitter)` and `(cache/eln)` show the two specialized directories.

**Despite its name, this root is not entirely disposable.**  Customize,
history, project lists, backups, and recovery files below it are meaningful
state.  Whole-cache cleanup deletes them along with packages and grammars.
Back up the root, preserve recovery data, and remove only known regenerable
subdirectories (`eln/`, package quickstart, or reinstallable grammars/packages)
when troubleshooting.  `XDG_STATE_HOME` is not used yet; changing
`XDG_CACHE_HOME` starts with a different set of state as well as packages.

Use `cache/folder` and `cache/file` instead of hard-coding `~/.cache` or
writing state into the repository.  The main paths currently include:

| Path | Purpose |
| --- | --- |
| `elpa/` | `package.el` packages |
| `package-quickstart.el` | Generated package activation/autoload cache |
| `eln/` | Native-compilation artifacts via `startup-redirect-eln-cache` |
| `tree-sitter/` | Tree-sitter grammar shared libraries |
| `backups/` | Versioned backup files |
| `auto-save-files/` | Per-file auto-save data |
| `auto-save-list/` | Auto-save bookkeeping |
| `tramp-auto-save/` | TRAMP auto-save data |
| `custom.el` | Emacs Customize state |
| `history`, `recentf`, `places` | Minibuffer, recent-file, and save-place state |
| `nov-places` | EPUB reading positions for `nov-mode` |
| `transient/` | Transient history and values |
| `projects.eld` | Project list state |
| `dired-async.log` | Asynchronous Dired log |
| `debug-adapters/`, `dape-breakpoints` | Dape adapter and breakpoint state |

`cache/tree-sitter` is added to `treesit-extra-load-path`.  The
`treesit/install` advice also redirects the default output of
`treesit-install-language-grammar` into that directory.  `cache/eln` is set
before packages load, so native compilation does not fill the repository or
the default Emacs cache with configuration-specific artifacts.

### Machine-Specific Locations

`modules/core/locations.el` is the single source for project/Desktop paths,
Android/Mac-mini mount paths, and the Mac-mini SSH host/remote home.  Customize
these options rather than editing file commands, Recentf exclusions, and
Auto Revert separately.  `locations/unreliable-path-p` derives exclusions
from current mount settings without probing the filesystem; add extra risky
mounts through `locations/additional-unreliable-directories`.
The remote home defaults to `~/`, resolved by TRAMP on the remote host, not
`/Users/glom/` or the local user's home.  Trust defaults derive from
`locations/projects-directory`, but explicit `trusted-content` Customize
choices still take precedence.

Desktop actions use configurable argument lists: `dirvish/drag-command`
(default ripdrag -x), `dirvish/file-manager-command` (default Thunar),
`mounts/android-command`, and `mounts/mac-mini-connect-command`.  Files are
passed as separate process arguments, not interpolated into shell commands.
Missing tools report the configured executable, without assuming NixOS is
how every machine must install it.

### File-Operation Observers

Dirvish task tracking observes its public yank handler and rsync command,
not the private process constructor or positional process `details` payload.
Progress uses the package's `dirvish-prop` accessor.  Disable observers with
`dirvish/task-tracking`; their removal does not alter Dirvish file operations.
`dirvish/selected-window-redisplay-only` controls the existing selected-window
redisplay workaround without changing package internals.

### Theme Compatibility

Gruber Darker's legacy nil face colors are normalized only while
`theme/load-gruber-darker` loads that theme.  The original Emacs face API is
restored even if loading fails; other themes and Customize are untouched.

Corfu's fallback colors derive from the active theme's `default`, `highlight`,
`region`, and `fringe` faces instead of a separate hard-coded palette.  Its
completion and documentation popups follow theme changes automatically;
theme-provided Corfu faces and Customize settings still take precedence.
Vertico already inherits standard theme faces.

### Portable Appearance

`appearance/font-families` keeps Cascadia Mono NF first, then tries installed
fallbacks.  `appearance/font-height` defaults to 160 (16 pt); nil leaves the
frame height unchanged.  `appearance/script-font-families` configures Unicode,
CJK, symbols, emoji, and Greek preferences.  Unavailable fonts leave Emacs'
font fallback intact.  The `unicode` entry supplies a fallback for otherwise
unspecified characters, not an override for ASCII; the primary family and
exact point height are restored after fontset updates.  On NixOS install
`pkgs.cascadia-code` for the family named `Cascadia Mono NF` (the separately
named Caskaydia Nerd Font package is not the same family).
Customize these options and run
`M-x appearance/apply-fonts`; new GUI frames apply them automatically, while
TTY and display-less daemon frames do not query fonts.

The hl-line fallback inherits the active theme's `highlight` face (still
`#282828` with Gruber Darker).  Theme-specific hl-line faces and Customize
settings override it normally; changing to a light theme does not retain a
hard-coded dark stripe.

### Daily Dashboard and Shortcut Memory Aid

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
| Open file / recent files | `C-x C-f` / `C-c r` |
| Switch buffer | `C-x b` |
| Switch project / find project file | `C-x p p` / `C-x p f` |
| Browse directory | `C-x d` |
| Search files with ripgrep | `C-c s` |
| Git status | `C-x g` |
| Terminal / process tasks | `C-c t` / `C-c T` |
| Run a command | `M-x` |
| Describe a key / list bindings | `C-h k` / `C-h b` |
| Read manuals | `C-c i` |

Save, undo, duplication, formatting, completion, and structural-editing keys
appear as non-clickable reminders: they should run in an editing buffer,
not on the read-only dashboard.  Tool commands retain their normal prompts
and lazy loading.  Search/Git/project commands use the working directory
from which the dashboard was opened; no project scan or server startup runs
just to render buttons.  Vterm and ripgrep still need their external
prerequisites.

Customize `dashboard/show-on-startup` to nil and restart Emacs to disable
automatic display; the reopen shortcut remains available.  Ordinary TTY
startup and dedicated daemon/client TTY frames (empty and explicit-file
requests) were smoke-tested; graphical mouse interaction still needs manual
validation.

### Completion Responsiveness

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

### Documentation at Point

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

The popup's text matches the source frame's default font family and size,
including the source buffer's `text-scale-mode` zoom.  A public
`eldoc-box-buffer-setup-hook` applies the doc-buffer face remap before the
package measures popup geometry; reused popups replace the old scale rather
than accumulating zoom.  Documentation colors and Markdown styling remain
owned by Eldoc Box and the active theme.  Ordinary and zoomed font sizes
were checked against the source text in a real GUI.

### Project Editing Policies

Save-time whitespace cleanup defaults to code/config buffers only; text,
Markdown, and Org keep meaningful trailing spaces.  Set
`editor/trim-trailing-whitespace` to nil in `.dir-locals.el` to disable it
for a project, or t to opt a text buffer in.  Remote/large buffers still skip
cleanup.  Formatters continue to own their language's formatting rules.
Sentence/fill patterns and bidirectional text layout use Emacs/major-mode
defaults rather than global handwritten regexes or forced left-to-right text.

### Shared Resource Limits

`modules/core/buffers.el` owns `buffers/feature-size-limit` (2 MiB-sized
character count by default), used by pairing, whitespace cleanup, highlighting,
line numbers, automatic completion, and Git markers.
`buffers/color-preview-size-limit` defaults to 1 MiB-sized character count.
Customize either limit; nil removes the size restriction.
Other package-specific limits remain in their own package options.

### Pairing and Structural Editing

`modules/feat/editing/pairs.el` uses non-strict Smartparens instead of
`electric-pair-mode`.  Only one engine owns pairing.  Automatic pairing is
opted into programming/config modes and Markdown/Org, not ordinary prose,
minibuffers, terminals, or special/read-only buffers.  Buffers of 2 MiB or
more skip activation; So Long also disables Smartparens on very long lines.

The upstream `smartparens-config` supplies language rules, including Lisp
quote prefixes, Haskell primes, Rust lifetimes, and Markdown/Org markup.
Normal deletion, kill/yank, and temporarily unbalanced code are allowed:
strict mode is not enabled and no bulk replacement of Emacs keybindings is
installed.  Typing an opener wraps an active selection rather than replacing
it; Backspace inside an empty pair removes both delimiters.  Matching closers
are skipped only at the end of an expression, never by jumping over its
contents.  Manually escaped quotes inside strings remain literal rather than
inserting a second escaped quote.

JavaScript/TypeScript and Rust do not automatically pair or skip `<`/`>`:
these characters are ambiguous comparisons, shifts, arrows, and type syntax.
Their language modules keep angle brackets for explicit wrapping only.
This deliberate policy avoids trying to infer intent with fragile regexes.
`pairs/automatic-angle-pairing` and `pairs/pair-escaped-quotes` can opt back
into upstream behavior; restart after changing these load-time policies.
`pairs/enabled-modes` controls automatic activation without editing hooks.
Use Smartparens' own options for skipping, deletion, and wrapping preferences.

Smartparens commands live under a buffer-local `C-c p` prefix:

| Key | Action |
| --- | --- |
| `C-c p (` / `[` / `{` | Wrap the selection or next expression |
| `C-c p <` | Explicit angle wrapping in supported modes |
| `C-c p s` / `S` | Slurp the next/previous expression into the pair |
| `C-c p b` / `B` | Barf the last/first expression out of the pair |
| `C-c p u` | Remove the enclosing delimiters (splice) |
| `C-c p r` | Raise an expression out of its parent |
| `C-c p n` / `p` | Move forward/backward by expression |
| `C-c p q` | Insert the next character literally (also `C-q`) |
| `C-c p t` | Disable Smartparens in this buffer |
| `C-c p ?` | Open the Smartparens cheat sheet |

After disabling the mode, use `M-x smartparens-mode` to enable it again.
Smartparens is declared through the normal package workflow and pinned to
MELPA: the old NonGNU build lacks its Dash dependency and current Tree-sitter
integration.  Dash is installed as a dependency, not configured separately.
Run `M-x packages/bootstrap` before using the integration on a new machine.

## 2. Adding Language Support

The four files directly under `modules/feat/languages/` are shared APIs:

| File | API and responsibility |
| --- | --- |
| `treesit.el` | Adds the grammar cache path, redirects grammar installs, and provides `treesit/register-language`. |
| `lsp.el` | Configures Eglot and provides `lsp/format-on-save`; it does not start Eglot globally. |
| `format.el` | Configures Apheleia and provides `format/mode-maybe` as the unmanaged-buffer fallback. |
| `debug.el` | Configures Dape and provides `debug/register-config` for language-specific adapters. |

Do not add a language's mode, server, formatter, grammar, or debugger details to
these shared files.  Put all of one language's details in
`modules/feat/languages/support/<language>.el`.  This keeps each language
independently addable and makes the module the single owner of its toolchain.

### Complete language workflow

For a hypothetical `foo` language:

1. Create `modules/feat/languages/support/foo.el`.
2. Add `"foo.el"` to `modules/feat/languages/support/mod.el`, after the shared
   language APIs are loaded by `modules/feat/languages/mod.el`.
3. Configure the major mode and file extension.  Declare an external Emacs
   Lisp mode package with `packages/declare`; omit the declaration for a mode
   built into Emacs.
4. Call `treesit/register-language` when the language uses the global
   `treesit-auto` integration.  Add a Tree-sitter source only when the grammar
   is not already supplied by Emacs or a `treesit-auto` recipe.
5. Add Eglot hooks for every mode the language can use, including the fallback
   non-Tree-sitter mode, and register the language server command in
   `eglot-server-programs`.
6. Choose formatting ownership.  If Eglot exposes formatting, configure that
   server capability and let `lsp/format-on-save` own save-time formatting.
   Register the same formatter in Apheleia for buffers Eglot does not manage.
7. Register a Dape configuration with `debug/register-config` when the
   language has a debugger.  The configuration names the adapter, modes,
   launch or attach request, executable, and program or working directory.
8. Run `M-x packages/bootstrap` if the language module declares an Emacs Lisp
   package that is not installed.
9. Verify the external commands, open a sample file, and test each integration
   before considering the language complete.

The following template includes all four integrations.  Remove optional
pieces only when the language genuinely does not provide them:

```elisp
;;; foo.el --- Foo language support -*- lexical-binding: t; -*-

(require 'packages)

;; Register this grammar with the shared treesit-auto integration.
(treesit/register-language 'foo)

;; Add this only when treesit-auto does not already know the grammar source.
(with-eval-after-load 'treesit
  (add-to-list 'treesit-language-source-alist
               '(foo . ("https://github.com/example/tree-sitter-foo" "main"))))

;; Omit the declaration when the mode is built into Emacs.
(packages/declare 'foo-ts-mode)
(use-package foo-ts-mode
  :ensure nil
  :mode "\\.foo\\'"
  :hook ((foo-ts-mode . eglot-ensure)
         (foo-mode . eglot-ensure)))

;; Eglot is enabled by the language, not by a global prog-mode hook.
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(foo-ts-mode . ("foo-language-server" "--stdio")))
  (add-to-list 'eglot-server-programs
               '(foo-mode . ("foo-language-server" "--stdio"))))

;; Apheleia is the fallback when Eglot is not managing the buffer.
(with-eval-after-load 'apheleia
  (setf (alist-get 'foo apheleia-formatters)
        '("foo-format" "--stdin"))
  (setf (alist-get 'foo-ts-mode apheleia-mode-alist) 'foo)
  (setf (alist-get 'foo-mode apheleia-mode-alist) 'foo))

;; Dape configuration names the adapter and the modes where it is offered.
(debug/register-config
 'foo-debug
 '((modes (foo-ts-mode foo-mode))
   :type "foo"
   :request "launch"
   :command "foo-debug-adapter"
   :cwd dape-cwd
   :program dape-buffer-default))

;;; foo.el ends here
```

External executables such as language servers, formatters, and debug adapters
are normally supplied by NixOS or Home Manager.  `package.el` only manages
Emacs Lisp packages declared in the language module.

`modules/feat/languages/support/nix.el` is the current reference module.  It
registers `nix` with Tree-sitter, starts `nixd` for both `nix-ts-mode` and
`nix-mode`, uses Alejandra for Eglot formatting, and registers Alejandra as the
Apheleia fallback.  It does not register a Dape configuration because this
configuration does not currently provide a Nix debug adapter.

`c.el`, `cpp.el`, and `rust.el` follow the same shape: clangd and
rust-analyzer are registered for both the Tree-sitter and fallback modes,
clang-format and rustfmt own the Apheleia side, and Dape's built-in
mode-scoped configurations (`gdb` for C/C++, `lldb-dap` for Rust) cover
debugging without a language-specific registration.

`haskell.el` owns `.hs`, `.lhs`, and `.hsc` buffers through `haskell-mode`.
It registers `hie.yaml`, `stack.yaml`, `cabal.project`, `package.yaml`, and
package `*.cabal` files in `project-vc-extra-root-markers`.  Emacs' built-in
project finder chooses the nearest root across Haskell and JavaScript
markers, even without VCS metadata; roots inside Git repositories retain
Git-aware file listing and ignore rules.  Neither language installs a
competing global project finder.  It replaces Eglot's bundled
`static-ls` candidate with `haskell-language-server-wrapper`, launched with
`-j 2` by default (`haskell/server-threads` is customizable or directory-local;
nil lets HLS choose), and the buffer sets
`eglot-sync-connect` to nil so Emacs never blocks on HLS's slow cold start.
HLS starts automatically for every Haskell buffer, using the nearest
project cradle when the file belongs to one and its default plain-GHC
session for standalone files.  Apheleia/Ormolu owns save-time formatting even while
Eglot manages the buffer: the module sets `format/apheleia-owns` because
HLS formatting is a synchronous request that can block a save while the
server loads the cradle.  Completion ordering is owned by HLS's `sortText`
and Eglot's completion metadata, not custom parsing of labels or HLS-private
resolve data.  `haskell/max-completions` defaults to 1000 and can be adjusted
per project through directory-local variables.

`markdown.el` is the editing-and-preview exception: `markdown-mode` owns
`.md`/`.markdown`/`.mdx` buffers (with `gfm-mode` for README files), and
preview uses markdown-mode's own commands — `markdown-live-preview-mode`
(`C-c C-c l`) renders in an Emacs window, `markdown-export-and-preview`
(`C-c C-c v`) opens the exported HTML in the browser — both backed by pandoc.
Both write their HTML under `/tmp/emacs/markdown-preview/` (via
`temporary-file-directory`) instead of next to the source file; set
`markdown/preview-directory` to relocate them.  Markdown is deliberately not
registered with treesit-auto because Emacs' `markdown-ts-mode` derives from
`text-mode` and would drop the editing and preview commands.

`javascript.el` owns JavaScript, TypeScript, and TSX.  `.ts` selects
`typescript-mode` (remapped to `typescript-ts-mode`); `.tsx` selects the
configuration's `typescript-tsx-mode` fallback (remapped to `tsx-ts-mode`).
The fallback inherits basic TypeScript editing, not JSX-aware parsing.
With grammars installed, the file-opening tests check the actual parser
language as well as the major mode.  It registers the
`javascript`, `typescript`, and `tsx` Tree-sitter grammars, starts
`typescript-language-server` for the fallback and Tree-sitter modes, and uses
Prettier through Apheleia when Eglot is not managing the buffer; Prettier
infers the parser from each buffer's filename, including JSX and TSX.  It
registers `package.json`, `deno.json`, `deno.jsonc`, and `tsconfig.json`
with the same VC-aware project finder as Haskell.  Lockfiles are not markers
on their own, so a stray `bun.lock` cannot claim unrelated trees.  Runtime
and compiler commands explicitly use the nearest JavaScript manifest,
even when another language's marker is closer.  `M-x
javascript/run` chooses Deno for Deno projects, Bun for Bun projects, and
Node otherwise.  `javascript/runtime` can select node/bun/deno explicitly
in `.dir-locals.el`; TypeScript alone no longer implies Bun.  Set
`javascript/run-command`, `javascript/build-command`, or
`javascript/check-command` for project scripts instead of generated commands.
Shell command overrides require the usual directory-local approval.  `M-x javascript/compile` runs
`tsc` for TypeScript or `node --check` for JavaScript; `M-x javascript/check`
uses the same validation path without emitting TypeScript output.  Dape offers
Node, Bun, Deno, attach, and Chrome configurations through the Nix-provided
`vscode-js-debug` adapter exposed as `js-debug`.  The adapter command,
inspector port, and browser URL are the project-local options
`javascript/debug-adapter-command`, `javascript/inspector-port`, and
`javascript/browser-url`.  Deno debug permissions default to none; opt into
specific flags with `javascript/deno-permissions` (directory-local approval
required), rather than granting `--allow-all` globally.

`typst.el` associates `.typ` with a grammar-free `typst-mode` derived from
`text-mode`.  This allows treesit-auto's installation prompt to run before
entering `typst-ts-mode`; declining installation leaves a usable text buffer.
With the grammar installed it remaps to `typst-ts-mode`.  Reopen or revert
a fallback buffer after manually installing the grammar.  Both modes start
`tinymist`, configured to use Typstyle for Eglot-managed formatting, while
`typstyle` is registered as the Apheleia fallback.  Place an empty
`.typst-root` file in the document's root directory to make it an Eglot/Tinymist
workspace root, including for files in subdirectories and projects without Git.
The marker is registered with `project-vc-extra-root-markers`, so nested roots
retain Git-aware file listing and ignore rules.  As with Haskell and JavaScript,
project.el chooses the nearest registered marker; without `.typst-root`, normal
project discovery still applies.

### Tree-sitter grammar

`treesit-auto` is enabled globally for languages registered by their feature
modules and asks before installing a missing grammar.  The current
configuration registers `c`, `cpp`, `javascript`, `typescript`, `tsx`, `nix`,
`rust`, and `typst`, which keeps the recipe/grammar scan limited to those
languages.
When a grammar source is needed, run
`M-x treesit-install-language-grammar` and choose the language, or evaluate
`(treesit-install-language-grammar 'foo)`.  The shared advice places
the resulting library under `cache/tree-sitter`
(`~/.cache/emacs/tree-sitter/`, or the equivalent `$XDG_CACHE_HOME` path).

If the language is not represented by a `treesit-auto` recipe, the mode module
must still provide its own way to select `foo-ts-mode`; registering a source
alone does not create a major-mode remap.

### Eglot and formatting ownership

The base LSP module does not enable Eglot globally for every programming
buffer.  Each language opts in with an `eglot-ensure` hook.
`format/eglot-owns-p` selects Eglot only when it manages the buffer,
advertises the needed formatting capability, and the language does not
prefer Apheleia.  `lsp/format-on-save` uses this predicate for whole-buffer
formatting and disables Apheleia only while Eglot owns that operation.
Unmanaged buffers and servers without formatting support keep Apheleia
available.  This prevents two formatters from racing on save.

A language can keep Apheleia in charge by setting `format/apheleia-owns`
buffer-locally.  Both save-time formatting and `C-c f`
(`funcs/format-buffer`) honor that preference.  `haskell.el` uses this
because HLS formatting is synchronous and can wait for a cradle load.
Manual Eglot formatting requires range-formatting support when a region is
active; if only whole-buffer formatting is supported, it formats the whole
buffer instead.  Apheleia remains the fallback when Eglot cannot format the
buffer at all.

Flymake only starts backends such as `eglot-flymake-backend` in buffers whose
files are listed in `trusted-content`.  The default trust list is `~/git/`
and this Emacs configuration directory, not the whole home directory or
`/tmp/`: trusting content can permit automatic code execution, not just
diagnostics.  Add only reviewed directories with
`M-x customize-variable RET trusted-content`; a saved Customize choice
takes precedence over the defaults.  Untrusted files do not get these
backends until explicitly trusted.  `flymake-show-diagnostics-at-end-of-line`
is set to `short` so the most severe diagnostic is summarized at the end of
its line, alongside the fringe indicators, `M-g f` (`consult-flymake`), and
`M-x flymake-show-buffer-diagnostics`.

Eglot enables LSP snippet completions only when Yasnippet is available.
`completion/snippets.el` bridges that capability to Tempel with
`eglot-tempel`, so servers that return snippets (HLS, TypeScript Server)
expand them with editable fields.

If a server needs language-specific initialization options, define a
`foo/eglot-workspace-configuration` function in the language module and
register it with `lsp/register-workspace-configuration`.  Eglot evaluates
`eglot-workspace-configuration` in a temporary buffer, so a buffer-local
value is ignored; the shared dispatcher in `lsp.el` looks the
configuration up by the server's major mode.  Keep the function in the
language file rather than changing `lsp.el`.

`lsp.el` also advises `eglot-completion-at-point` so a server-provided
`CompletionItem.command` runs after a completion is accepted and its edits
have succeeded, in the originating buffer.  The public `jsonrpc-request`
wrapper retains commands returned by `completionItem/resolve` from the
current Eglot server on the original completion item, preserving Eglot's
resolution cache without an extra request.  There is no private
`eglot--request` advice or inspection of server mode slots.  The bridge
still needs Eglot's candidate item property (no public equivalent exists);
`lsp/completion-command-support` can disable it, including its advice, if
an Eglot update supplies native handling.  Property-less candidates from *Completions* are looked up in the
original completion table.  HLS uses this for `extend import`;
`haskell.el` raises `maxCompletions` to `haskell/max-completions` (1000 by
default) so unimported names are returned before the import command runs.

### Debugging with Dape

`debug/register-config` accepts a Dape configuration name and a configuration
plist.  The `modes` entry limits the configuration to the language's major
modes; `:type`, `:request`, `:command`, `:cwd`, and `:program` are typical
launch fields.  Use `:request "attach"` and an appropriate `:port` or `:host`
when the adapter attaches to an existing process.  Check Dape's
`dape-configs` documentation for adapter-specific fields.  Run `M-x dape` and
select the registered configuration to verify it is available.

`diff-hl` computes Git changes asynchronously so opening a source buffer does
not wait for the repository diff.  Markers can appear shortly after the
buffer is displayed; remote buffers remain excluded by the feature hook.

### Language support checklist

- Add one module under `modules/feat/languages/support/` and list it in that
  directory's `mod.el`.
- Confirm the mode, Tree-sitter registration/source, Eglot server, formatter,
  and Dape configuration all live in that one language file.
- Verify every external executable with `executable-find`.
- Install a missing grammar and confirm `(treesit-ready-p 'foo t)` when
  applicable.
- Open a sample file and check `major-mode`, `(eglot-managed-p)`, and
  `apheleia-mode`.
- Run `M-x dape` and confirm the language configuration appears and can start
  a session or reports only the expected missing adapter/program.
- Check `*Warnings*`, `*Messages*`, and the user service journal after a clean
  restart.

## 3. Validation and Daemon Refresh

Run the regression suite from the configuration root:

```sh
emacs --batch -Q -l tests/run.el
```

The runner loads the complete configuration, reuses installed packages, and
redirects persistent state to a temporary directory.  It reuses installed
grammars for actual `.ts`/`.tsx`/`.typ` file-opening tests, suppresses grammar
installation prompts, and tests grammar-free fallbacks.  It does not install
packages, start language servers, or change the running daemon.
Set `EMACS_TEST_REQUIRE_GRAMMARS=1` to fail rather than skip parser tests when
the TypeScript, TSX, or Typst grammar is missing.  For an isolated network
installation plus normal offline startup, run `sh tests/cold-bootstrap.sh`.
`sh tests/launcher-tests.sh` checks launcher argument forwarding with mocked
binaries, without starting a real daemon.  Tests cover
trust boundaries, project roots and Git ignore rules, completion commands
and resolution caching, formatter ownership, navigation bindings,
stale-config detection, and interactive pairing/structural editing.
`tests/refinement-tests.el` also exercises directory-local server settings,
configurable commands/paths, and a real asynchronous copy between temporary
files to verify Dirvish/dashboard integration.
`tests/dashboard-tests.el` verifies button dispatch and TAB/RET navigation,
shortcut labels, startup safeguards, and Emacs' real server selection path
for empty and explicit-file requests.
`tests/pairs-tests.el` types through the real command loop to check wrapping,
closing-delimiter skipping, deletion, apostrophes, operators, and snippets.
Install declared packages before running the suite.

`emc/config-stale-p` includes top-level Elisp, `modules/`, and `pkgs/` in
its modification-time check.  Changes to a local package therefore mark the
daemon stale, just like module changes.  Test fixtures and Customize state
are excluded.  Restart the daemon to apply configuration changes; batch
validation alone does not update a running session.

`C-c i` opens `consult-info`, and `M-g i` opens `consult-imenu`.  Do not
install a longer binding below `C-c i`: it is a command, not a prefix.

### Opt-in Performance Measurements

Run the isolated synchronous workload harness from the configuration root:

```sh
emacs --batch -Q -l tests/benchmark.el
EMACS_BENCHMARK_ITERATIONS=100 emacs --batch -Q -l tests/benchmark.el
```

It reuses installed packages and loads the config with temporary state, without
installing packages, starting language servers, or touching the running daemon.
Nothing in the normal configuration loads this harness.  It measures:

- Orderless filtering of 10,000 synthetic candidate names;
- fresh Cape Dabbrev tables at broad (`benchw`, 2000 candidates) and narrower
  (`benchword19`, 100 candidates) prefixes, comparing the configured scan scope
  against same-mode scanning in alternating A/B and B/A order each round;
- cached Dabbrev queries after priming a table at the broad prefix and extending
  the buffer's input to the narrower prefix.  Priming and the edit are untimed;
  this measures repeated table queries, not a full typing sequence;
- repeated local file visits with normal mode hooks, below and above the shared
  buffer-size limit.  The result includes whether line numbers were enabled.

Each workload has three untimed warmups.  A single GC precedes each series
(including a paired comparison), not each sample.  Natural GC stays enabled.
The runner reports median, nearest-rank p95, maximum, and GC count/time measured
inside each timed callback, plus a stable result count or size.  Separate
GC-free and GC-hit populations show their own sample counts and wall-time
statistics; an empty population is explicitly reported, never replaced by zero.
GC-hit times are not estimated by subtracting GC time, and a collection during
one callback can reflect allocations from earlier callbacks.  Collections
between callbacks are reported separately, outside the workload rows.

Fresh-table timings represent repeated completion-session startup.  Cape can
reuse its table when a prefix is extended, so do not interpret these as the
cost of every keystroke.  The cached case verifies that reuse without changing
runtime settings or adding a configuration-owned completion cache.

The runner also prints Emacs build features, relevant package versions, and
runtime settings.  The default is 30 samples; set `EMACS_BENCHMARK_ITERATIONS`
between 1 and 1000.  Small runs and sparse GC-hit populations are smoke tests,
not trustworthy tail estimates.  There are no machine-dependent pass/fail
timing thresholds or claims of GUI/LSP/input-to-screen latency.

Compare several alternating runs of identical fixtures on the same machine,
Emacs build, and package versions; record the Git revision and working-tree
changes beside each result.  Do not infer an interactive speedup from one batch
run.  For actual typing/scrolling pauses, start the built-in profiler with
`M-x profiler-start` (CPU or CPU+memory), reproduce a short workload, then use
`M-x profiler-stop` and `M-x profiler-report`.  Sampling shows attribution, not
precise end-to-end latency, and profiling itself adds overhead.

This workflow follows the useful lesson of
[emacs-perf's latency design](https://git.ksqsf.moe/ksqsf/emacs-perf/commit/0b180d8e1d46bdc81e9bb9c960d8bcbae93542cc):
optimize repeatable tail pauses and validate results, not just average CPU.
Its compiled-regexp, loader-cache, and incremental-GC experiments require a
patched Emacs binary and are not emulated by this configuration.  Keep runtime
GC limits bounded; raising them indefinitely is not incremental collection.

## 4. Function Naming

Custom functions use the feature alias as their namespace.  Do not introduce
new `my/...` or `my-...` names.  The namespace is the owning module, followed
by a short action or query:

```text
feature/action
```

Current examples:

| Old style | Current name | Owner |
| --- | --- | --- |
| `my/treesit-install-language-grammar-to-cache` | `treesit/install` | `modules/feat/languages/treesit.el` |
| `my/format-buffer` | `funcs/format-buffer` | `modules/feat/editing/funcs.el` |
| `my-duplicate-line` | `funcs/duplicate-line` | `modules/feat/editing/funcs.el` |
| `my-mark-whole-line` | `funcs/mark-whole-line` | `modules/feat/editing/funcs.el` |
| `my-open-line-below` | `funcs/open-line-below` | `modules/feat/editing/funcs.el` |
| `my-open-line-above` | `funcs/open-line-above` | `modules/feat/editing/funcs.el` |
| `my/magit-status-window` | `git/status-window` | `modules/feat/workspace/git.el` |
| `my/gui-frames` | `emc/gui-frames` | `modules/core/emc.el` |
| `my/eglot-format-on-save` | `lsp/format-on-save` | `modules/feat/languages/lsp.el` |
| `my/apheleia-mode-maybe` | `format/mode-maybe` | `modules/feat/languages/format.el` |
| `my/nix-configure-apheleia` | `nix/configure-apheleia` | `modules/feat/languages/support/nix.el` |
| `my/async-enable-dired` | `dired-async/enable` | `modules/feat/files/dired-async.el` |
| `my/tempel-setup-capf` | `snippets/setup-capf` | `modules/feat/completion/snippets.el` |
| `my/vertico-rename-bindings` | `completion/vertico-rename-bindings` | `modules/feat/completion/minibuffer.el` |

Private helpers use the same feature identity with Emacs' double-hyphen
convention, for example `dired-async--refresh` and
`theme--custom-theme-set-faces`.  Variables and constants follow the same
rule; `debug/dape-language-configs` is the shared Dape registry.

When defining or renaming a function, update every function reference as
well as definitions:

- `#'feature/action` in hooks, advice, and keymaps;
- quoted symbols in `add-hook`, `advice-add`, and `use-package` forms;
- external callers in Nix or shell-generated launcher expressions.

Useful searches are:

```text
rg -n '\bmy[-/]' modules init.el early-init.el
rg -n 'feature/action' modules /path/to/external/caller
```

After a rename, restart the daemon or reload the affected module, then verify
`(fboundp 'feature/action)` and any relevant key or hook.  Do not rename
third-party package symbols; only names owned by this configuration follow
the feature namespace rule.
