# Codewars

`modules/feat/codewars.el` pulls Codewars kata into local project directories
and runs tests from Emacs.  Attempt and Submit stay in the browser.

## Why Attempt and Submit are in the browser

Codewars has no public API for running tests or submitting solutions.  The
trainer runs both through a cross-origin runner iframe, which needs your
logged-in session.  Emacs therefore does not reproduce that protocol.  It
pulls the kata with the public API, which needs no login, and
`codewars/open-trainer` opens the trainer for the rest.

## Commands

`C-x C-h K` opens the menu:

| Key | Command | Does |
| --- | --- | --- |
| `p` | `codewars/pull` | Prompts for a slug, id, or URL and a language, then creates the project |
| `t` | `codewars/test` | Runs the test command for the language in the project |
| `d` | `codewars/open-description` | Opens the project's `README.md` |
| `o` | `codewars/open-trainer` | Opens the trainer in the browser for Attempt and Submit |

## Project layout

```text
~/codewars/<slug>/
  .codewars        plist: :id, :slug, :name, :language
  README.md        title, rank, link, and the API description
  solution.<ext>   empty on first pull; never overwritten by a later pull
```

`codewars/directory` changes the root.  Each language's file extension comes
from `codewars/extensions`; unlisted languages use their name.

`codewars/default-language` is Haskell, so the language prompt starts there
when the kata offers it.  Haskell projects use the plain-GHC HLS session,
which needs no cabal or stack file.

The project directory is added to `trusted-content` when the module loads and
again on each pull.  Flymake's Eglot backend runs only in trusted files, so
without this, a kata would get no diagnostics.  Pulled code is your own, so the
directory is trusted the same way `~/git/` is.

## Testing

`codewars/test-commands` maps a language to the command that runs in the
project directory, for example `("rust" . "cargo test")`.  Languages without
an entry prompt for a command.  The command runs through `compile`, so
`C-x `` and the `C-x C-h c` menu work on its errors.

Sample tests are not pulled.  Codewars loads the starter code and sample
tests with client-side JavaScript, and that source is not documented.  Write
your own tests in the project, or paste the sample tests from the trainer.

## Tests

`tests/codewars-tests.el` runs offline.  It stubs the API fetch and covers
slug parsing, project creation, metadata lookup, the trainer URL, the test
command, and the menu binding.  Run the suite with:

```sh
emacs --batch -Q -l tests/run.el
```
