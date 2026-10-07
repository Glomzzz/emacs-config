# Install this configuration and `emc`

This is an opinionated personal configuration, not a hermetic Emacs binary
bundle.  Nix is optional.  `scripts/emc` is a portable launcher included here;
it starts a dedicated `emc` daemon on demand and forwards arguments to
`emacsclient`.  It does **not** require systemd or the author's NixOS dotfiles,
install packages implicitly, or restart a live daemon behind your back.

## Prerequisites and support

- **Emacs 31.x** is the current target.  Batch validation was performed with
  Emacs 31.1 on x86_64 NixOS, a PGTK build with `TREE_SITTER`, `MODULES`,
  `GNUTLS`, `SQLITE3`, and native compilation.  The author's image-scaling
  patch is not required.  Emacs 29/30 are not currently supported/tested by
  this configuration (it uses newer APIs such as `trusted-content`).
- **Essential:** Git, HTTPS access with working CA certificates to GNU ELPA,
  NonGNU ELPA (currently the Tsinghua mirror), and MELPA, plus writable cache
  storage.  Emacs Lisp packages are installed by `package.el`, not Nix.
- **For Tree-sitter grammar installation:** Git and working C/C++ compilers
  (`cc`/`c++`).  Emacs must be built with Tree-sitter.  Grammars are downloaded
  separately, on demand; bootstrap does not install them.
- **For Vterm:** Emacs built with dynamic module support, CMake, a C compiler,
  make, and libvterm development files (including pkg-config metadata).
  Package bootstrap installs the Lisp package but does not prove the native
  module can build.  On NixOS, prefer a matching Nix-built Vterm package;
  see below.  Other platforms can use the upstream native build on first use.
- **Fonts:** preferred defaults are Cascadia Mono NF, Noto Sans, LXGW WenKai,
  Noto Sans Symbols 2, and Noto Color Emoji.  Fonts are appearance choices,
  not startup dependencies; unavailable fonts fall back to installed fonts.
- **Platforms:** Linux is the primary target.  Other Linux distributions are
  expected to work with equivalent dependencies but are not validated here.
  macOS is best-effort; native Windows is untested.  File helpers use Unix
  tools, and task pause/resume relies on OS signals.  Interactive GUI/TTY
  behavior still needs manual validation on each target.

Check the build with:

```sh
emacs --version
emacs --batch -Q --eval '(princ system-configuration-features)'
```

## 1. Put the configuration in a writable checkout

Download/clone this repository into `~/.config/emacs`, or choose another
absolute path.  Back up any existing Emacs configuration first.  The commands
below assume the default path; replace it throughout if needed.  This guide
uses explicit paths, so an existing `~/.emacs.d` cannot silently take priority.
Do not copy the author's cache, Customize state, or private local files.

## 2a. NixOS users

Add essentials to your own NixOS module; do not import the author's external
Home Manager configuration.  For example, with nixpkgs providing Emacs 31:

```nix
{ pkgs, ... }:
let
  # Build Vterm against the same Emacs; package.el still owns the other Lisp
  # packages.  Match the Emacs variant to your desktop (PGTK for Wayland).
  emacs = (pkgs.emacsPackagesFor pkgs.emacs31-pgtk).emacsWithPackages
    (epkgs: [ epkgs.vterm ]);
in {
  environment.systemPackages = [ emacs pkgs.git pkgs.gcc ];
  fonts.packages = with pkgs; [
    cascadia-code noto-fonts lxgw-wenkai
    noto-fonts-color-emoji
  ];
  # Fonts and language tools can instead be managed in Home Manager.
}
```

`cascadia-code` includes the exact `Cascadia Mono NF` family used by the
configuration.  `nerd-fonts.caskaydia-mono` is a separately named font family,
not a drop-in installation for that setting.  Activate the font declaration
before starting Emacs; a running process may need restarting to discover
newly installed font families.

Package attribute names depend on your pinned nixpkgs.  If your pin lacks
Emacs 31, update/select an appropriate pin rather than silently substituting
an older build.  Build/test your system configuration before switching it;
this repository does not supply a NixOS flake or change your system for you.

After activating your package declaration, run the common bootstrap below
**as your ordinary user**, not root.  To install `emc` declaratively with
Home Manager, use the absolute path to your writable checkout:

```nix
{ config, ... }: {
  home.file.".local/bin/emc" = {
    source = config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/.config/emacs/scripts/emc";
  };
  home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];
}
```

Alternatively package the launcher with `writeShellScriptBin`, making the
chosen Emacs and matching emacsclient available on its PATH.  NixOS users can
use the same on-demand daemon as everyone else; no service is necessary.
If you already manage an Emacs systemd user service, keep using its matching
client/socket instead of starting a second daemon.  Run the batch bootstrap
before starting that service.  The author's external `emacs.service` preflight
and stale-restart launcher are **not** required or included here.

## 2b. Non-NixOS users

Install Emacs 31 with the required build features through your distribution's
packages, a trusted newer-package repository, or a source build.  Install Git
and CA certificates through that platform's package manager.  Install C/C++
compilers for grammars and CMake/make/pkg-config/libvterm development files
if you want Vterm.  There is no universal package command for Emacs 31 across
all distributions; verify the version rather than assuming `apt install
emacs` (or its equivalent) supplies it.

Fonts and the language tools in the table below are optional.  No Nix command,
mount script, Thunar installation, or systemd service is needed to start Emacs.

## 3. Bootstrap **before** starting Emacs

With an empty cache, normal startup can fail on eager dependencies such as
`colorful-mode`.  Starting Emacs and then running `M-x packages/bootstrap`
is therefore **not a first-run installation procedure**.

From any directory run:

```sh
emacs --batch -Q -l "$HOME/.config/emacs/scripts/bootstrap.el"
```

The standalone script resolves its checkout path, sets
`packages/bootstrap-mode` **before** loading `init.el`, installs declarations,
and writes package selection and quickstart metadata.  It exits nonzero if
initialization fails.  The equivalent explicit invocation is:

```sh
emacs --batch -Q \
  --eval '(setq user-emacs-directory (expand-file-name "~/.config/emacs/") user-init-file (expand-file-name "init.el" user-emacs-directory) packages/bootstrap-mode t)' \
  -l "$HOME/.config/emacs/init.el"
```

This is a network operation and executes downloaded package code.  Use trusted
archives.  On failure, fix the reported network/package/build issue and rerun;
installed packages are reused.  A cold network bootstrap and subsequent
normal batch load were tested in an isolated HOME/cache on NixOS/Emacs 31.1,
without the Nix site-package overlay.  Third-party test/extension byte-compile
warnings may occur; bootstrap success is not proof of every optional native
integration working.  Package versions are not locked to a release manifest.

Then check the configuration without touching a running daemon:

```sh
emacs --batch -Q -l "$HOME/.config/emacs/tests/run.el"
```

## 4. Install and use `emc`

Non-NixOS users (or NixOS users not managing this file with Home Manager):

```sh
mkdir -p "$HOME/.local/bin"
install -m 755 "$HOME/.config/emacs/scripts/emc" "$HOME/.local/bin/emc"
# Add ~/.local/bin to PATH in your shell's startup file.
```

Usage:

```sh
emc                         # new GUI frame with DISPLAY/Wayland, otherwise TTY
emc --create-frame --no-wait path/to/file.tsx
emc --tty path/to/file.typ
# You can also bypass the launcher:
emacs --init-directory="$HOME/.config/emacs"
```

Overrides: `EMACS` and `EMACSCLIENT` name executable paths; `EMC_CONFIG_DIR`
is the checkout path; `EMC_SERVER_NAME` defaults to `emc`.  Keep the same server
name and environment across calls.  The daemon inherits the first launcher's
PATH and desktop environment; restart it after changing installed tools or
session variables.  Two simultaneous first launches can race; retry after
the daemon finishes starting.  A five-second probe timeout does not mean it
is safe to kill a busy editor; the launcher will not terminate it.

After saving buffers, explicitly restart to load configuration changes:

```sh
emacsclient --socket-name=emc --eval '(kill-emacs)'
emc
```

`emc/config-stale-p` remains available for custom integrations, but the portable
launcher intentionally does not perform destructive automatic restarts.

## Optional language and desktop tools

Install only the toolchains you use; they are **not** prerequisites for
bootstrap or general text editing.  Eglot hooks can report a missing server
when you open a language buffer until its server is installed.

| Workflow | External commands |
| --- | --- |
| C/C++ | `clangd`, `clang-format`; `gdb` for Dape |
| Rust | `rust-analyzer`, `rustfmt`; `lldb-dap` for Dape |
| Nix | `nixd`, `alejandra` |
| Haskell | `haskell-language-server-wrapper`, project-compatible GHC, `ormolu` |
| JavaScript/TypeScript/TSX | `typescript-language-server`, Node/`npx`, Prettier, `tsc`; Bun/Deno optional; `js-debug` for Dape |
| Typst | `tinymist`, `typstyle`; `typst` for compiling documents |
| Markdown preview | `pandoc` |
| Search / file manager | `rg`, `fd`, GNU `ls`; `rsync` for rsync operations |
| Optional desktop actions | `ripdrag`, Thunar (both commands configurable) |
| Optional device/mount actions | Your own `android-phone` / `mac-mini-connect` helpers, SSH/rsync; not shipped here |

Use NixOS/Home Manager packages, a project dev shell, or your platform's package
manager.  Language modules in `modules/feat/languages/support/` define the exact
server, formatter, and debugger commands.  Trust only reviewed projects via
`trusted-content`; do not globally trust your home directory just to silence
prompts.  `.tsx` needs the TSX grammar, not just TypeScript.  Without the Typst
grammar `.typ` opens in a text-derived fallback and can offer installation.

## Data safety and validation limits

**The current cache root also holds meaningful persistent state.**
`$XDG_CACHE_HOME/emacs` (default `~/.cache/emacs`) contains Customize settings,
history, project lists, backups, and auto-save/recovery files as well as
packages and grammars.  Do not delete the whole directory as routine cache
cleanup.  Back it up; see [the path table](configuration.md#cache-root).
`XDG_STATE_HOME` is not yet used.  Preserve recovery files before cleanup.

Opt-in tests:

```sh
sh "$HOME/.config/emacs/tests/launcher-tests.sh"  # mocked client; no real daemon
sh "$HOME/.config/emacs/tests/cold-bootstrap.sh" # network, isolated HOME/cache
EMACS_TEST_REQUIRE_GRAMMARS=1 emacs --batch -Q \
  -l "$HOME/.config/emacs/tests/run.el"           # requires TS, TSX, Typst grammars
```

Set `EMACS_TEST_INSTALL_GRAMMARS=1` when running `tests/cold-bootstrap.sh`
to also download/build the TypeScript, TSX, and Typst grammars and require
all parser tests.  This needs C/C++ compilers.  This complete cold path was
tested locally with no site-package overlay.  The GitHub Actions workflow
runs it without restoring a package cache; CI execution itself must be
confirmed on the hosting service.

Cold-bootstrap smoke coverage does not validate GUI/TTY interaction, Vterm's
native build, or external LSP/DAP sessions.  Validate those manually before
calling your own deployment ready to use.
