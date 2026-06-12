---
layout: default
title: Test and benchmark the compiler
parent: How-to guides
nav_order: 3
---

# Test and benchmark the compiler

Both scripts below require a built `uplc-ghc` (see
[Build the compiler from source]({% link how-to/build.md %})).

## Run the example project tests

From the root of the repository:

```console
$ ./plinth-test.sh
```

It builds the example Plinth project under `plinth/test/` with `uplc-ghc` and
regenerates its expected outputs. Set `CLEAN=1` to force a clean rebuild:

```console
$ CLEAN=1 ./plinth-test.sh
```

## Run the benchmarks

`plinth-bench.sh` builds and runs the `plutus-benchmark` test-suites with
`uplc-ghc` and reports any diffs against the golden files committed under
`plutus/plutus-benchmark/` (it requires the `plutus` submodule):

```console
$ ./plinth-bench.sh
```

Each test-suite is a [tasty](https://hackage.haskell.org/package/tasty) runner.
When a golden comparison fails, the unified diff is streamed to stdout and an
`.actual` sidecar file is written next to the corresponding golden file under
`plutus/plutus-benchmark/*/test/`.
