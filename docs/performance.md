# Performance Measurements

Opt-in synchronous workload harness for the configuration.

## Opt-in Performance Measurements

Run the isolated synchronous workload harness from the configuration root:

```sh
emacs --batch -Q -l tests/benchmark.el
EMACS_BENCHMARK_ITERATIONS=100 emacs --batch -Q -l tests/benchmark.el
```

It reuses installed packages and loads the config with temporary state, without
installing packages, starting language servers, or touching the running daemon.
Nothing in the normal configuration loads this harness.  It measures:

- Orderless filtering of 10,000 synthetic candidate names;
- fresh Cape Dabbrev tables at broad (`benchw`, 2000 candidates) and narrower
  (`benchword19`, 100 candidates) prefixes, comparing the configured scan scope
  against same-mode scanning in alternating A/B and B/A order each round;
- cached Dabbrev queries after priming a table at the broad prefix and extending
  the buffer's input to the narrower prefix.  Priming and the edit are untimed;
  this measures repeated table queries, not a full typing sequence;
- repeated local file visits with normal mode hooks, below and above the shared
  buffer-size limit.  The result includes whether line numbers were enabled.

Each workload has three untimed warmups.  A single GC precedes each series
(including a paired comparison), not each sample.  Natural GC stays enabled.
The runner reports median, nearest-rank p95, maximum, and GC count/time measured
inside each timed callback, plus a stable result count or size.  Separate
GC-free and GC-hit populations show their own sample counts and wall-time
statistics; an empty population is explicitly reported, never replaced by zero.
GC-hit times are not estimated by subtracting GC time, and a collection during
one callback can reflect allocations from earlier callbacks.  Collections
between callbacks are reported separately, outside the workload rows.

Fresh-table timings represent repeated completion-session startup.  Cape can
reuse its table when a prefix is extended, so do not interpret these as the
cost of every keystroke.  The cached case verifies that reuse without changing
runtime settings or adding a configuration-owned completion cache.

The runner also prints Emacs build features, relevant package versions, and
runtime settings.  The default is 30 samples; set `EMACS_BENCHMARK_ITERATIONS`
between 1 and 1000.  Small runs and sparse GC-hit populations are smoke tests,
not trustworthy tail estimates.  There are no machine-dependent pass/fail
timing thresholds or claims of GUI/LSP/input-to-screen latency.

Compare several alternating runs of identical fixtures on the same machine,
Emacs build, and package versions; record the Git revision and working-tree
changes beside each result.  Do not infer an interactive speedup from one batch
run.  For actual typing/scrolling pauses, start the built-in profiler with
`M-x profiler-start` (CPU or CPU+memory), reproduce a short workload, then use
`M-x profiler-stop` and `M-x profiler-report`.  Sampling shows attribution, not
precise end-to-end latency, and profiling itself adds overhead.

This workflow follows the useful lesson of
[emacs-perf's latency design](https://git.ksqsf.moe/ksqsf/emacs-perf/commit/0b180d8e1d46bdc81e9bb9c960d8bcbae93542cc):
optimize repeatable tail pauses and validate results, not just average CPU.
Its compiled-regexp, loader-cache, and incremental-GC experiments require a
patched Emacs binary and are not emulated by this configuration.  Keep runtime
GC limits bounded; raising them indefinitely is not incremental collection.
