# Emacs Configuration

An opinionated, modular, source-based personal Emacs configuration targeting
Emacs 31.x.  Start with the standalone [installation and `emc` launcher
guide](docs/emc-installation.md), with separate NixOS and non-NixOS paths,
prerequisites, and validation limits.  See the
[configuration guide](docs/configuration.md) for package management and layout.

## First run

Put the checkout in `~/.config/emacs` (back up any existing configuration),
then **bootstrap before starting Emacs**:

```sh
emacs --batch -Q -l "$HOME/.config/emacs/scripts/bootstrap.el"
emacs --init-directory="$HOME/.config/emacs"
```

The batch script sets `packages/bootstrap-mode` before loading `init.el`.
An empty cache cannot reliably start far enough to run `M-x packages/bootstrap`.
No external systemd setup is required; `scripts/emc` is included for on-demand
daemon/client use.  Installation needs network access.  Read the guide before
clearing the cache: it currently also holds backups, recovery files, and state.

## License

Original code and documentation in this repository are licensed under
[MIT](LICENSE).  Emacs, downloaded packages, grammars, fonts, and external
tools retain their own licenses; this does not relicense them.  MIT is
GPL-compatible, but distribution of a combined GPL-covered work must still
comply with the GPL.  Any future copied/adapted upstream code must retain its
copyright and license notices, with its scope identified explicitly.

## Credits

Thanks to [ksqsf/emacs-perf](https://git.ksqsf.moe/ksqsf/emacs-perf) for
informing the performance refinement work, particularly its
[latency-profiler design](https://git.ksqsf.moe/ksqsf/emacs-perf/commit/0b180d8e1d46bdc81e9bb9c960d8bcbae93542cc):
measure repeatable tail pauses rather than average CPU alone, bound background
work, and validate that optimizations preserve behavior.

Those principles informed the large-buffer resource guards and opt-in
benchmarks in this configuration.  This is methodological inspiration, not
vendored fork code; the fork's experimental incremental GC, compiled-regexp
APIs, and loader cache are not included here.
