#!/usr/bin/env bash
# Capture where a stuck Emacs daemon is blocked.
#
# Run this while `systemctl --user status emacs` shows
# "deactivating (stop-sigterm)" or "(final-sigterm)".  It records each
# thread's kernel wait channel and current syscall, then tries a gdb
# backtrace.  Output goes to ~/.cache/emacs/diagnostics/.
#
# gdb needs ptrace access to the daemon.  With kernel.yama.ptrace_scope=1 (the
# default here), that fails for a normal user because systemd started the
# daemon.  For the backtrace, run `sudo sysctl kernel.yama.ptrace_scope=0',
# run this script as your user, then restore the value to 1.  The thread
# wait-channel section works without either.  Do not run the script itself
# under sudo: it reads the --user systemd unit.

set -u

unit=${1:-emacs}
pid=$(systemctl --user show -p MainPID --value "$unit")
state=$(systemctl --user show -p ActiveState,SubState --value "$unit" | tr '\n' ' ')

if [ -z "$pid" ] || [ "$pid" = 0 ]; then
    echo "No running main process for $unit (state: $state)" >&2
    exit 1
fi

out_dir="$HOME/.cache/emacs/diagnostics"
mkdir -p "$out_dir"
out="$out_dir/hang-$(date +%Y%m%dT%H%M%S).txt"

{
    echo "time: $(date -Iseconds)"
    echo "unit: $unit  pid: $pid  state: $state"
    echo
    systemctl --user status "$unit" --no-pager 2>&1 | head -15
    echo
    echo "=== threads: tid name state wchan syscall"
    for task in /proc/"$pid"/task/*; do
        tid=$(basename "$task")
        tstate=$(awk '/^State/{print $2}' "$task/status" 2>/dev/null)
        comm=$(cat "$task/comm" 2>/dev/null)
        wchan=$(cat "$task/wchan" 2>/dev/null)
        sysc=$(cut -d' ' -f1 "$task/syscall" 2>/dev/null)
        echo "$tid $comm state=$tstate wchan=${wchan:-?} syscall=${sysc:-?}"
    done
    echo
    echo "=== gdb backtrace (needs ptrace access; see header)"
    if command -v gdb >/dev/null 2>&1; then
        gdb -p "$pid" -batch -nx \
            -ex 'set pagination off' \
            -ex 'thread apply all bt 25' \
            -ex 'detach' 2>&1 | head -600
    else
        echo "gdb not found in PATH"
    fi
} > "$out" 2>&1

echo "Wrote $out"
