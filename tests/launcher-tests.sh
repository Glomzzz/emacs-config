#!/bin/sh
# Exercise launcher arguments without starting or restarting a real daemon.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
mkdir -p "$scratch/config with spaces"
touch "$scratch/config with spaces/init.el"
export EMC_CONFIG_DIR="$scratch/config with spaces" EMC_SERVER_NAME=test-emc
export EMACS="$scratch/emacs" EMACSCLIENT="$scratch/emacsclient"
export EMC_TEST_LOG="$scratch/log" EMC_TEST_ALIVE="$scratch/alive"

printf '%s\n' '#!/bin/sh' 'printf "emacs\\n" >> "$EMC_TEST_LOG"' \
  'printf "<%s>\\n" "$@" >> "$EMC_TEST_LOG"' 'touch "$EMC_TEST_ALIVE"' > "$EMACS"
printf '%s\n' '#!/bin/sh' 'printf "client\\n" >> "$EMC_TEST_LOG"' \
  'printf "<%s>\\n" "$@" >> "$EMC_TEST_LOG"' \
  'case " $* " in *" --eval "*) test -e "$EMC_TEST_ALIVE" ;; esac' > "$EMACSCLIENT"
chmod +x "$EMACS" "$EMACSCLIENT"

"$root/scripts/emc" --tty "$scratch/file with spaces.tsx"
grep -Fx "<--init-directory=$EMC_CONFIG_DIR>" "$EMC_TEST_LOG"
grep -Fx '<--daemon=test-emc>' "$EMC_TEST_LOG"
grep -Fx "<$scratch/file with spaces.tsx>" "$EMC_TEST_LOG"
grep -Fx '<--socket-name=test-emc>' "$EMC_TEST_LOG"
: > "$EMC_TEST_LOG"
DISPLAY= WAYLAND_DISPLAY= "$root/scripts/emc"
! grep -Fx emacs "$EMC_TEST_LOG"
grep -Fx '<--tty>' "$EMC_TEST_LOG"
: > "$EMC_TEST_LOG"
DISPLAY=:1 "$root/scripts/emc"
grep -Fx '<--create-frame>' "$EMC_TEST_LOG"
rm "$EMC_CONFIG_DIR/init.el"
if "$root/scripts/emc" 2>/dev/null; then
  echo 'Expected missing-config error' >&2
  exit 1
fi
echo 'Launcher tests passed'
