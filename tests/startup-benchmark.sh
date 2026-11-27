#!/bin/sh
# Wall-clock startup samples for the configuration, one fresh Emacs per sample.
# Usage: sh tests/startup-benchmark.sh [runs]     (default 7, minimum 1)
# Each sample uses tests/startup-profile.el, so temporary state is used and the
# user's recentf/history files are not written.  Compare before and after on the
# same machine, Emacs build, and package set; record the Git revision beside it.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
runs=${1:-7}
emacs=${EMACS:-emacs}
case "$runs" in ''|*[!0-9]*|0) echo "runs must be a positive integer" >&2; exit 1 ;; esac

i=0
samples=$(while [ "$i" -lt "$runs" ]; do
  "$emacs" --batch -Q -l "$root/tests/startup-profile.el" 2>&1 \
    | sed -n 's/^startup-profile-total-ms //p'
  i=$((i + 1))
done | sort -n)

printf '%s\n' "$samples" | awk -v runs="$runs" '
  { v[NR] = $1 }
  END {
    if (NR == 0) { print "no samples: check " ENVIRON["PWD"] " and emacs" > "/dev/stderr"; exit 1 }
    printf "startup samples=%d min=%.1fms median=%.1fms max=%.1fms\n", NR, v[1], v[int((NR + 1) / 2)], v[NR]
  }'
