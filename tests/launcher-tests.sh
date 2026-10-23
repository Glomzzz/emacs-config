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

printf '%s\n' '#!/bin/sh' 'printf "emacs\n" >> "$EMC_TEST_LOG"' \
  'printf "<%s>\n" "$@" >> "$EMC_TEST_LOG"' 'touch "$EMC_TEST_ALIVE"' > "$EMACS"
printf '%s\n' '#!/bin/sh' 'printf "client\n" >> "$EMC_TEST_LOG"' \
  'printf "<%s>\n" "$@" >> "$EMC_TEST_LOG"' \
  'case " $* " in *" --eval "*) test -e "$EMC_TEST_ALIVE" ;; esac' > "$EMACSCLIENT"
chmod +x "$EMACS" "$EMACSCLIENT"

has() { grep -Fx -- "$1" "$EMC_TEST_LOG" >/dev/null; }
clear_log() { : > "$EMC_TEST_LOG"; }

# First launch, file names with spaces, and no implicit fallback editor.
"$root/scripts/emc" "$scratch/file with spaces.tsx"
has "<--init-directory=$EMC_CONFIG_DIR>"
has '<--daemon=test-emc>'
has "<$scratch/file with spaces.tsx>"
has '<--socket-name=test-emc>'
has '<--alternate-editor=false>'
has '<--tty>'

# Desktop environment variables must not change the default frontend.
for display in headless x11 wayland; do
  clear_log
  case "$display" in
    headless) DISPLAY= WAYLAND_DISPLAY= "$root/scripts/emc" ;;
    x11) DISPLAY=:1 WAYLAND_DISPLAY= "$root/scripts/emc" ;;
    wayland) DISPLAY= WAYLAND_DISPLAY=wayland-1 "$root/scripts/emc" ;;
  esac
  ! has emacs
  has '<--tty>'
  ! has '<--create-frame>'
done

# Explicit GUI requests remain asynchronous when requested.
clear_log
"$root/scripts/emc" --create-frame --no-wait "$scratch/file with spaces.tsx"
has '<--create-frame>'
has '<--no-wait>'
! has '<--tty>'
clear_log
"$root/scripts/emc" -c "$scratch/gui.txt"
has '<-c>'
! has '<--tty>'

# Control requests are not turned into interactive terminal sessions.
clear_log
"$root/scripts/emc" --eval '(+ 1 2)'
has '<(+ 1 2)>'
! has '<--tty>'
clear_log
"$root/scripts/emc" --help
has '<--help>'
! has '<--eval>'
! has emacs
clear_log
"$root/scripts/emc" --version
has '<--version>'
! has '<--eval>'

# A value resembling an option is not a frontend request; -- ends options.
clear_log
"$root/scripts/emc" --socket-name --eval "$scratch/file.txt"
has '<--tty>'
clear_log
"$root/scripts/emc" -- --create-frame
has '<--tty>'
has '<-->'

# Detaching a terminal client would immediately tear down its terminal.
clear_log
if "$root/scripts/emc" --no-wait "$scratch/file.txt" 2>/dev/null; then
  echo 'Expected --no-wait rejection for a TTY client' >&2
  exit 1
fi
[ ! -s "$EMC_TEST_LOG" ]

rm "$EMC_CONFIG_DIR/init.el"
if "$root/scripts/emc" 2>/dev/null; then
  echo 'Expected missing-config error' >&2
  exit 1
fi
echo 'Launcher tests passed'
