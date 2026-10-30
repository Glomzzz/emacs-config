# Version Control and Mail

Majutsu for Jujutsu repositories and the local mu4e client.

## Jujutsu (Majutsu)

`modules/feat/workspace/jujutsu.el` declares
[Majutsu](https://majutsu.org/) from its upstream Git repository through
`packages/declare-vc`.  Run the package bootstrap after adding it; normal
startup neither fetches the package nor loads its interface.

In a Jujutsu workspace, **`C-x g`** (`M-x majutsu-log`, also available as
`M-x majutsu`) opens the change graph and working-copy status.
**`C-x M-g`** opens `majutsu-dispatch`, the command menu.  **`C-x j`** and
**`C-x M-j`** remain aliases for those commands.  Within Majutsu, `g`
refreshes and `q` leaves the buffer.  The dashboard opens Majutsu too.

Magit's standalone global bindings are disabled, including the old
`C-c M-g` file menu.  Magit remains installed because Majutsu depends on it;
its commands are still available explicitly through M-x and the graphical
Git launcher helper.

The external `jj` executable must be on Emacs' `PATH` (upstream requires
0.41.0 or later); the author's NixOS configuration already supplies it.
Emacs package dependencies are installed by the bootstrap, not Nix.
Majutsu is experimental and follows the upstream default branch; use
`M-x package-vc-upgrade` to update it explicitly.

## Local Email

`modules/feat/mail.el` provides lazy mu4e access on **`C-c M`** (`M-x mu4e`).
The existing **`C-c m`** still opens manual pages. This machine's external
programs and account are supplied by Home Manager in
`~/nixos-config/modules/home/programs/mail/default.nix`; see
`~/nixos-config/docs/mail.md` for installation, credentials, and first sync.
No mail is retrieved or indexed just by starting Emacs.

**Sending is asynchronous.** In a mu4e compose buffer, `C-c C-c` sends and
closes on success; `C-c C-s` sends and keeps the buffer. The local
`pkgs/mail-async.el` integration runs msmtp in a separate process and keeps
the draft read-only with `[sending mail]` in the mode line until it exits.
You can switch buffers and keep working while SMTP, TLS, or credential
unlocking is in progress. Only SMTP success runs Message/mu4e's normal Sent
filing and draft cleanup. A failed send restores editing, retains the draft,
and opens a `*Mail delivery*` error buffer; there is no automatic retry.
`M-x mail-async/status` shows a pending draft's log, and
`M-x mail-async/cancel` stops it after a warning. Cancellation/connection loss
is not recall: check whether a message was already accepted before retrying.
If SMTP succeeded but local filing failed, resubmission is blocked to avoid
duplicate delivery; inspect the error and recover the Sent copy locally.

MIME preparation, attachment reads/encoding, and OpenPGP message signing or
encryption still happen in Emacs before submission and can take time for large
messages. This is background SMTP, not a persistent outgoing queue. Save work
and wait for pending sends before exiting/restarting Emacs; a forced shutdown
can leave a private staging file and an uncertain delivery result.

systemd synchronizes Infomaniak into `~/Maildir/infomaniak/` every five minutes;
mu4e indexes immediately on opening and every five minutes while running.
These are separate timers: new upstream mail can take nearly ten minutes to
appear in the UI, plus sync time/scheduling delays. Retrieval continues without
Emacs; indexing waits until mu4e is running.
`M-x mu4e-update-index` refreshes the index immediately but does not retrieve
mail. For immediate retrieval use `systemctl --user start mbsync.service` and
then update the index. No external `mu index` job runs alongside mu4e, avoiding
database-lock conflicts. Both retrieval and msmtp's authenticated STARTTLS use
the encrypted GNOME Login keyring, unlocked by password login. No YubiKey is
needed for ordinary fetching/sending. A locked/missing credential skips scheduled
sync without prompting; unlock Login in `seahorse`, then retry. Use
`infomaniak-password store` to enter a mailbox device password privately, or
`infomaniak-password import-pass` for a one-time YubiKey-backed migration. The
old pass entry is only an optional backup; there is no automatic GPG fallback.
`infomaniak-password check` verifies availability without printing the secret.
The password is never embedded in Elisp or Nix. OpenPGP message signing/encryption
can still use the YubiKey independently.

Before composing, replying, trashing, or archiving, verify the special-folder
roles in webmail, sync/index, and run **`M-x mail/configure-folders`**. It prompts
for Sent, Drafts, Trash, and Archive from mu4e's synchronized folder list and
saves the confirmed `mail/special-folders` mapping in the existing Customize
file. Getters refuse unset/missing Maildirs rather than create guessed folders.
Read/search is available before mappings are configured. The guard covers the
special-folder actions, not arbitrary moves or explicit permanent deletion.
Sent messages are kept; check webmail for correct placement/possible provider
copies during a manual send/reply test. No message is sent automatically.
