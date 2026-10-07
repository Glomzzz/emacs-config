# Emacs Configuration

A modular, source-based Emacs configuration.  See the
[configuration guide](docs/configuration.md) for setup, package management,
module layout, and validation.

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
