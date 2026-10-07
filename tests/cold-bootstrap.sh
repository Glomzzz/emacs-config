#!/bin/sh
# Opt-in network smoke test.  Never reads or writes the user's Emacs cache.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
emacs=${EMACS:-emacs}
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
export HOME="$scratch/home"
export XDG_CONFIG_HOME="$scratch/config"
export XDG_CACHE_HOME="$scratch/cache"
export XDG_STATE_HOME="$scratch/state"
# Remove Nix/site package overlays: exercise package.el's full installation.
export EMACSLOADPATH=
export EMC_TEST_CONFIG_DIR="$root"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
cd "$scratch"

"$emacs" --batch -Q -l "$root/scripts/bootstrap.el"
# A second process must load normally without any installation/network calls.
"$emacs" --batch -Q \
  --eval '(progn (require (quote package)) (advice-add (quote package-install) :before (lambda (&rest _) (error "Normal startup attempted package installation"))) (advice-add (quote package-refresh-contents) :before (lambda (&rest _) (error "Normal startup attempted archive refresh"))))' \
  --eval '(setq user-emacs-directory (file-name-as-directory (getenv "EMC_TEST_CONFIG_DIR")))' \
  -l "$root/init.el" \
  --eval '(progn (dolist (package packages/declared) (unless (package-installed-p package) (error "Missing declared package: %s" package))) (unless (and (file-readable-p package-quickstart-file) (file-readable-p custom-file)) (error "Bootstrap did not persist selection/quickstart")) (message "Cold bootstrap and offline startup passed"))'
# Optional parser smoke coverage needs network access and C/C++ compilers.
if [ "${EMACS_TEST_INSTALL_GRAMMARS:-0}" = 1 ]; then
  "$emacs" --batch -Q \
    --eval '(setq user-emacs-directory (file-name-as-directory (getenv "EMC_TEST_CONFIG_DIR")))' \
    -l "$root/init.el" \
    --eval '(progn (require (quote treesit-auto)) (setq treesit-auto-langs (quote (typescript tsx typst)) treesit-auto-install t) (treesit-auto-install-all) (dolist (language treesit-auto-langs) (unless (treesit-ready-p language t) (error "Grammar installation failed: %s" language))))'
  export EMACS_TEST_REQUIRE_GRAMMARS=1
fi
"$emacs" --batch -Q -l "$root/tests/run.el"
