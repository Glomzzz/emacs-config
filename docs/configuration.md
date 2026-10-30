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

### Byte compilation

Module sources load directly, which is simplest while editing.  For faster
startup, compile the modules and local packages once after changes:

```sh
emacs --batch -Q -l /path/to/emacs/scripts/byte-compile.el
```

`init.el` sets `load-prefer-newer`, so a source edited after compiling
loads instead of its older `.elc`.  Compiled files are gitignored.

### Key menus with Hydra

`modules/core/hydra.el` installs Hydra and its `:hydra` use-package keyword, so
a feature module can define a repeatable menu next to its other settings.  Put
menus under the `C-x C-h` prefix, which is otherwise unbound, and give each one
the `:ensure nil` form used by every other package here.  Keep the menu's
commands in the feature module; the menu only groups them.

| Key | Menu | Defined in |
| --- | --- | --- |
| `C-x C-h u` | undo-tree | `modules/feat/editing/undo.el` |
| `C-x C-h m` | multiple cursors | `modules/feat/editing/multi-cursor.el` |
| `C-x C-h d` | Dape debugging | `modules/feat/languages/debug.el` |
| `C-x C-h g` | diff-hl hunks | `modules/feat/workspace/git.el` |
| `C-x C-h f` | fingertip navigation | `modules/feat/editing/pairs.el` |
| `C-x C-h w` | windows | `modules/feat/workspace/navigation.el` |
| `C-x C-h b` | Ibuffer (also `.` inside Ibuffer) | `modules/feat/workspace/navigation.el` |
| `C-x C-h o` | recent buffers | `modules/feat/workspace/navigation.el` |
| `C-x C-h a` | avy line, region, and goto actions | `modules/feat/workspace/navigation.el` |
| `C-x C-h r` | rectangle editing | `modules/feat/editing/menus.el` |
| `C-x C-h k` | keyboard macros | `modules/feat/editing/menus.el` |

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

For a package distributed from a Git repository rather than an archive, use
`packages/declare-vc` before the same `use-package ... :ensure nil` form:

```elisp
(packages/declare-vc 'fingertip
                    '(:url "https://github.com/manateelazycat/fingertip"
                      :vc-backend Git))
```

This records the package and its source in `packages/declared` and
`packages/vc-sources` without fetching during normal startup.  Both bootstrap
paths install missing source packages with Emacs' built-in `package-vc-install`
under `(cache/folder "elpa")`, alongside archive packages.  Git and HTTPS access
to the source host are required.  Bootstrap reuses installed checkouts; use
`M-x package-vc-upgrade` to update an installed source package explicitly.

mu4e is an exception: it is supplied by Nix together with the matching `mu`
binary, so the mail module uses `use-package ... :ensure nil` without
`packages/declare`. Do not install a second mu4e through the package bootstrap.

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
writing state into the repository.  `cache/configure-state-paths` in
`modules/core/cache.el` points Emacs' state variables below the root; add new
state variables there.  The main paths currently include:

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

### Feature Guides

Each feature area has its own guide.  Keys, package choices, and module
ownership live with the feature; these guides explain the behavior.

| Guide | Covers |
| --- | --- |
| [Files and locations](features/files-and-locations.md) | Machine paths, FUSE mount safety, file-operation observers |
| [Appearance and terminal](features/appearance-and-terminal.md) | Themes, fonts, terminal display, images, keyboard input |
| [Reading](features/reading.md) | EPUB reader |
| [Dashboard](features/dashboard.md) | Daily dashboard and shortcut reminders |
| [Version control and mail](features/version-control-and-mail.md) | Majutsu and local mu4e |
| [Completion and search](features/completion-and-search.md) | Completion, Isearch, Consult, Avy, Corfu timing |
| [Help and documentation](features/help-and-documentation.md) | Helpful, Eldoc, Eldoc Box |
| [Editing](features/editing.md) | Project policies, pairing, delimiter colors, resource limits |
| [Inline Pi editing](features/pi-inline.md) | Pi file editing from Emacs |
| [Performance measurements](performance.md) | Opt-in synchronous workload harness |

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
In Rust buffers, **`C-c r`** runs `rust/rename` (`eglot-rename`); recent files
remain available globally as **`C-c R`**.

Rust uses a single **push diagnostic stream**.  Rust Analyzer's pull reports
contain native diagnostics, while compiler warnings such as `unused_variables`
arrive separately on save.  Eglot's pull refresh can clear the older compiler
warnings after any edit, even when the native report is empty.  The Rust module
uses Eglot's public server subclass/capability API to omit client pull support,
so Rust Analyzer pushes native diagnostics and compiler warnings together, and
ignores `:diagnosticProvider` buffer-locally in both Rust modes.  Other languages
retain their diagnostic negotiation.  Merely ignoring the server capability is
not enough: the server must also know to push native diagnostics.  Reconnect an
existing Rust server after changing this policy.  Native diagnostics still
update on edits; compiler warnings remain visible but may be stale until the
next save runs `cargo check`.  No automatic saves or extra compiler runs are
added.  Actual type/parameter inlay hints remain disabled; end-of-line warning
text is Flymake's diagnostic display, not an inlay hint.  An isolated real-server
smoke test verified warning retention after unsaved edits, live native syntax
diagnostics, removal after saving a fix, and absence of pull requests.

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

Typing `$` does not trigger automatic reindentation in Typst buffers.  In
particular, entering `$$` in `-` or `+` list contents preserves the existing
indentation instead of realigning it when the math expression becomes complete.
Explicit indentation, Return, and the other electric-indent triggers are unchanged.

Typst strings starting with `..`, `./`, or `/` get **Cape file completion** in
the normal Corfu popup, including immediately after the prefix.  Use `C-M-i`
for manual completion.  `./` and `../` resolve relative to the current source
file; `/` resolves relative to the nearest `.typst-root`, then the normal
project root, then the source directory when no project exists.  It is not
the filesystem root.  Completing a directory keeps its trailing slash so
completion can continue into it; quotes and the leading path prefix stay intact.
Spaces, Chinese filenames, and escaped quotes/backslashes are supported.

The Typst module supplies only string context, path-base selection, and string
quoting; Cape and Emacs own directory enumeration, matching, file metadata, and
completion insertion.  The path source takes priority over Tinymist only in
these strings, including after Eglot reconnects.  Other strings, code symbols,
and package imports keep their usual completion sources.  Tree-sitter rejects
markup/raw-text quotes and comments, including when earlier prose contains an
unmatched quote.  Without the grammar, basic Emacs string/comment syntax is
used instead; it cannot fully distinguish markup quotes from code strings.
No new package installation is needed because Cape is already declared.

In both Typst modes, **`M-.`** on a string such as `"algebra/lemma"` looks for
`<typst-root>/algebra/lemma.typ` first, then
`<typst-root>/statements/algebra/lemma.typ`.  The `.typ` suffix is appended
unless already present.  Paths starting with `./` instead search the current
source file's directory first, then its `statements/` subdirectory, even when
Emacs' working directory differs.  All other paths, including those starting
with `/`, keep using the Typst root: the nearest `.typst-root`, then the normal
project root, then the source directory if no project exists.  This lookup
policy is separate from file completion above.  Spaces, Chinese filenames,
and escaped quotes/backslashes work here too.  **`M-,`** returns to the original
location through normal Xref history.

If neither candidate exists, the minibuffer asks **`Create <path>.typ?`** using
the first lookup location, not the `statements/` fallback.  Answering `y` creates
missing parent directories and an empty file on disk, then opens it; `n` or
`C-g` leaves you in place without creating anything or changing Xref history.
Existing files are never overwritten.  Symbols, empty strings, directory paths
ending in `/`, URLs, and `@` package imports keep normal definition lookup
through Xref/Tinymist; **`C-u M-.`** always requests normal definition lookup,
without a creation prompt.  String detection has the same grammar-free
limitations described above.

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
available.  This prevents two formatters from racing on save.  The decision
is made on a buffer's first save, not when it opens, so Apheleia is not loaded
for programming buffers that are never saved or that Eglot formats.

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
`eglot-tempel`, so servers that return snippets (Rust Analyzer, HLS,
TypeScript Server) expand them with editable fields.  Tempel's purple argument
fields now finish automatically when the cursor leaves the whole snippet,
removing their highlights without deleting inserted text.  Moving within the
call, between arguments, or inside an enclosing snippet keeps the fields active;
both range boundaries remain editable.  This buffer-local cleanup reads Tempel's
range overlays because no public range API exists, then uses `tempel-done` to
finalize normally.  **`M-}`** / **`M-{`** move to the next/previous field;
**`M-RET`** finishes manually while inside the snippet, and
`C-u M-x tempel-done` clears all active snippets even from outside them.

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
select the registered configuration to verify it is available.  Once a
session is running, **`C-x C-h d`** opens the Dape menu: `c` continue, `n`
next, `i` step in, `o` step out, `r` restart, `b` toggle a breakpoint, `k` kill
the session, and `q` leave the menu.

`diff-hl` computes Git changes asynchronously so opening a source buffer does
not wait for the repository diff.  Markers can appear shortly after the
buffer is displayed; remote buffers remain excluded by the feature hook.  **`C-x C-h g`** opens a hunk
menu: `n` and `p` move between hunks, `*` shows the current hunk, and `q` leaves.

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
`tests/typst-completion-tests.el` exercises the real Cape file tables and
completion insertion in both Typst modes, plus context rejection and Eglot
completion-source ordering without starting a language server.
`tests/typst-navigation-tests.el` checks string file jumps, path resolution,
Xref return history, and normal-lookup fallbacks in both Typst modes.
`tests/typst-editing-tests.el` types math delimiters through the real command
loop to check indentation preservation in ordinary/nested lists, buffer-local
trigger settings, fallback insertion, and unchanged explicit/newline indentation.
`tests/reading-tests.el` uses a small bilingual EPUB fixture to check lazy
loading, buffer-local reading layout, theme colors on the first and subsequent
renders, width changes across multiple windows, link navigation, contents
selection, saved positions, and idempotent font remapping.
`tests/tty-tests.el` checks lazy terminal integration, GUI isolation, idempotent
mouse/tooltip setup, clipboard fallback/Wayland preference, saved backend
choices, and the opt-in graphics declaration.
`tests/refinement-tests.el` also exercises directory-local server settings,
configurable commands/paths, and a real asynchronous copy between temporary
files to verify Dirvish/dashboard integration.
`tests/dashboard-tests.el` verifies button dispatch and TAB/RET navigation,
shortcut labels, startup safeguards, and Emacs' real server selection path
for empty and explicit-file requests.
`tests/packages-tests.el` checks offline VC declarations and both bootstrap
installation paths without network requests.
`tests/pairs-tests.el` types through the real command loop with installed
Tree-sitter parsers to check Fingertip pairing, wrapping, deletion, quotes,
Rust apostrophes, operators, snippets, and So Long restoration.  It also checks
parser-free fallbacks and activation exclusions; parser-dependent tests skip
when their grammar is unavailable.  Build-patch tests verify idempotence,
preservation of upstream declarations, and unresolved-function-free compilation
of optional integration calls in a fresh `-Q` worker using the actual VC recipe.
`tests/snippets-tests.el` checks Rust argument-field cleanup through the command
loop in both Rust modes, plus field navigation, editable boundaries, nested
snippets, normal finalization, and buffer-local hook setup.
`tests/rust-tests.el` checks push-only capability negotiation, the Rust rename
shortcut, Rust-only buffer policies, and real Flymake overlays surviving unsaved
edits then clearing on a fresh diagnostic report, without starting a language
server.
Install declared packages before running the suite.

`emc/config-stale-p` includes top-level Elisp, `modules/`, and `pkgs/` in
its modification-time check.  Changes to a local package therefore mark the
daemon stale, just like module changes.  Test fixtures and Customize state
are excluded.  `emc/client-frames` recognizes both GUI and TTY clients; the old
`emc/gui-frames` name remains a compatibility alias.  The managed launcher's
`emc/launcher-state` permits a stale restart only with no client frames,
modified file buffers, or background mail sends.  A timed-out health check is
not permission to kill an active daemon.  Restart the daemon to apply
configuration changes; batch validation alone does not update a running session.

`C-c i` opens `consult-info`, and `M-g i` opens `consult-imenu`.  Do not
install a longer binding below `C-c i`: it is a command, not a prefix.

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
