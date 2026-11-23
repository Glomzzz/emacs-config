#!/bin/sh
# Offline sendmail fixture: never opens a socket or reads credentials.
# POSIX sh only, so the mail tests need no python3 on PATH.
set -eu

root=${MAIL_ASYNC_TEST_ROOT:?MAIL_ASYNC_TEST_ROOT must name the test directory}
printf 'started\n' >> "$root/starts"
: > "$root/started"
deadline=$(( $(date +%s) + 10 ))
while [ ! -e "$root/release" ]; do
    if [ "$(date +%s)" -gt "$deadline" ]; then
        echo "synthetic transport timed out" >&2
        exit 75
    fi
    sleep 0.02
done
{
    printf '['
    separator=
    for argument in "$@"; do
        escaped=$(printf '%s' "$argument" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
        printf '%s"%s"' "$separator" "$escaped"
        separator=', '
    done
    printf ']\n'
} > "$root/arguments.json"
cat > "$root/wire.eml"
if [ "${MAIL_ASYNC_TEST_FAIL:-}" = 1 ]; then
    echo "synthetic SMTP rejection" >&2
    exit 69
fi
echo "synthetic SMTP acceptance"
