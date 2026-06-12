---
layout: default
title: Testing & benchmarks
nav_order: 4
---

# Testing &amp; benchmarks

## Example project

After building, run the `plinth-test.sh` script at the root of the
repository:

```console
$ ./plinth-test.sh
```

It builds the example Plinth project under `plinth/test/` with `uplc-ghc`
and regenerates its expected outputs. Set `CLEAN=1` to force a clean
rebuild:

```console
$ CLEAN=1 ./plinth-test.sh
```

See [Examples]({{ '/examples' | relative_url }}) for what the project contains.

## Benchmarks

`plinth-bench.sh` builds and runs the `plutus-benchmark` test-suites with
`uplc-ghc` and reports any diffs against the golden files committed under
`plutus/plutus-benchmark/` (it requires the `plutus` submodule):

```console
$ ./plinth-bench.sh
```

Each test-suite is a [tasty](https://hackage.haskell.org/package/tasty)
runner. When a golden comparison fails, the unified diff is streamed to
stdout, and an `.actual` sidecar file is written next to the corresponding
golden file under `plutus/plutus-benchmark/*/test/`.
