# Files and Locations

Machine-specific paths, mount safety, and file-operation observers.

## Machine-Specific Locations

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

## File-Operation Observers

Dirvish task tracking observes its public yank handler and rsync command,
not the private process constructor or positional process `details` payload.
Progress uses the package's `dirvish-prop` accessor.  Disable observers with
`dirvish/task-tracking`; their removal does not alter Dirvish file operations.
`dirvish/selected-window-redisplay-only` controls the existing selected-window
redisplay workaround without changing package internals.
