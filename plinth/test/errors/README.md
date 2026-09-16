# Plinth error-message golden tests

This directory holds golden tests for the compile-time error messages
of the Plinth compiler (uplc-ghc). Each file in `cases/` uses one
Haskell construct that Plinth does not support. The runner compiles
each case, expects the compilation to fail, and compares the compiler
output with the golden file in `golden/`.

The plutus-tx-plugin test-suites only test the `defer-errors` path,
which drops source locations and source snippets. These tests capture
the real user-facing output, so changes to error reporting show up as
golden diffs here.

## Usage

```
# run (after plinth-build.sh and the plinth/test build):
./run-error-tests.sh

# update the golden files:
ACCEPT=1 ./run-error-tests.sh

# use a different compiler:
GHC=/path/to/uplc-ghc ./run-error-tests.sh
```

`plinth-test.sh` runs this suite automatically.

All cases compile with `preserve-source-locations` enabled, because
the goal of this suite is to track how much source-location
information each error carries.

## Cases

Every error now carries a source location in its GHC header
("File.hs:l:c: error:"). "splice" means the location of the
`$$(PlutusTx.compile ...)` expression; "definition" means the
fall-back location of the enclosing top-level binder.

| Case                | Construct                          | Location    |
|---------------------|------------------------------------|-------------|
| EnumRange           | range syntax / enumFromTo          | definition  |
| Existential         | existential data type              | splice      |
| GadtExtension       | GADTs extension                    | definition  |
| HaskellEq           | Prelude Eq method                  | splice      |
| HaskellOrd          | Prelude Ord method                 | splice      |
| HaskellShow         | Prelude Show method                | splice      |
| IOAction            | IO action                          | splice      |
| IntegerPatternMatch | pattern match on Integer literal   | splice      |
| IrreducibleTypeFamily | irreducible type family application | splice    |
| LitChar             | Char literal                       | splice      |
| LitDouble           | Double literal                     | splice      |
| LitString           | String literal ([Char])            | splice      |
| MachineInt          | Int                                | splice      |
| MachineWord         | Word64                             | splice      |
| MutualData          | mutually recursive data types      | definition  |
| NoUnfolding         | imported function w/o INLINABLE    | splice      |
| PolyKindsExtension  | PolyKinds extension                | definition  |
| PreludeError        | Prelude.error                      | splice      |
| RecursiveNewtype    | recursive newtype                  | splice      |
| ToBuiltinUsed       | toBuiltin in compiled code         | splice      |
| TypeByteString      | ByteString type                    | definition  |
| TypeText            | Text type                          | definition  |

## How the location machinery works

- injectAnchors (plutus-tx-plugin:PlutusTx.Plugin.Common) wraps
  variables (bare or under a wrapper, e.g. class methods) and
  literals in `anchor @loc` when `preserve-source-locations` is on.
- injectUnsupportedMarkers (plutus-tx-plugin:PlutusTx.Plugin.Unsupported)
  always wraps known-unsupported expressions (base Eq/Ord methods,
  IO types) in `unsupported @msg @loc`.
- Every compiled definition gets a fall-back context frame with the
  binder's location (withDefinitionContext in
  plutus-tx-plugin:PlutusTx.Plugin.Common).
- runPluginM throws a located GHC diagnostic at the innermost span in
  the error context, so GHC prints the "File.hs:l:c: error:" header
  and the source snippet with the caret.

## Known reporting gaps (as pinned by the goldens)

The goldens document the current behavior, including its defects.
When you fix one of these, update the golden files.

1. Locations point at the whole splice (or at the definition when no
   anchor survives to the failure point), not at the offending
   sub-expression. Code from `[|| ... ||]` quotes keeps only the
   splice-point location through typed TH.

2. Raw GHC Core in context frames. `Context: Compiling code:` frames
   print desugared Core (dictionary methods, `tagToEnum#`, `IS`/`IP`
   constructors, casts), which does not resemble the user's source
   code.

3. Misleading message for existentials (`Existential`): the error is
   a generic free-variable error about a type variable, not a message
   that existential quantification is unsupported.

4. `PreludeError`: the context dumps the whole CallStack machinery
   instead of pointing at `error` and suggesting
   `PlutusTx.Prelude.error`.

5. `MutualData`: the PIR-level message leaks the internal `Ann`
   record (`annSrcSpans = { no-src-span }` etc.).

## Notes on the runner

The runner normalizes the output before the comparison: it strips
ANSI escapes, GHC uniques (`x_a5GN` -> `x`), `[N of M]` progress
lines, and CR characters. Files named `*Helper.hs` in `cases/` are
companion modules for multi-module cases, not test cases.
