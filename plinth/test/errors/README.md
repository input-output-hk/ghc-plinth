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

Every error carries a source location in its GHC header
("File.hs:l:c: error: [PLINTH-000NN]"). The Location column tells how
precise it is: "expression" points at the offending expression,
"definition" at the function or value whose compilation failed, and
"splice" at the whole `$$(PlutusTx.compile ...)` expression. A splice
location often means GHC inlined a small same-module function into
the splice before the plugin ran.

| Case                | Construct                          | Location    |
|---------------------|------------------------------------|-------------|
| DeepChain           | error inside nested INLINABLE fns  | expression  |
| EnumMethod          | Prelude Enum method                | splice      |
| EnumRange           | range syntax / enumFromTo          | splice      |
| Existential         | existential data type              | definition  |
| GadtExtension       | GADTs extension                    | definition  |
| HaskellEq           | Prelude Eq method                  | splice      |
| HaskellOrd          | Prelude Ord method                 | splice      |
| HaskellShow         | Prelude Show method                | splice      |
| IOAction            | IO action                          | splice      |
| IntegerPatternMatch | pattern match on Integer literal   | splice      |
| IrreducibleTypeFamily | irreducible type family application | definition |
| LitChar             | Char literal                       | splice      |
| LitDouble           | Double literal                     | splice      |
| LitString           | String literal ([Char])            | splice      |
| MachineInt          | Int                                | splice      |
| MachineWord         | Word64                             | splice      |
| MutualData          | mutually recursive data types      | definition  |
| NoUnfolding         | imported function w/o INLINABLE    | splice      |
| PolyKindsExtension  | PolyKinds extension                | definition  |
| PreludeError        | Prelude.error                      | splice      |
| PreludeUndefined    | Prelude.undefined                  | splice      |
| RecursiveNewtype    | recursive newtype                  | definition  |
| ToBuiltinUsed       | toBuiltin in compiled code         | splice      |
| TypeByteString      | ByteString type                    | definition  |
| TypeText            | Text type                          | definition  |

## How the location machinery works

- injectAnchors (plutus-tx-plugin:PlutusTx.Plugin.Common) wraps
  variables (bare or under a wrapper, e.g. class methods) and
  literals in `anchor @loc` when `preserve-source-locations` is on.
- injectUnsupportedMarkers (plutus-tx-plugin:PlutusTx.Plugin.Unsupported)
  always wraps known-unsupported expressions in `unsupported @msg
  @loc`: methods of the base Eq, Ord, Show and Enum classes, range
  syntax, Prelude.error / errorWithoutStackTrace / undefined, and
  expressions with IO types. Each entry carries a "use X instead"
  suggestion.
- Every compiled definition gets a fall-back context frame with the
  binder's location: the marked expression itself
  (withDefinitionContext in plutus-tx-plugin:PlutusTx.Plugin.Common)
  and every function whose body or unfolding the compiler enters
  (hoistExpr in plutus-tx-plugin:PlutusTx.Compiler.Expr). Datatype
  definitions carry the source span of their type constructor and
  data constructors in the PIR annotations.
- runPluginM throws a located GHC diagnostic (PlinthDiagnostic, with
  a [PLINTH-000NN] error code per error class) at the innermost span
  in the error context, so GHC prints the "File.hs:l:c: error:"
  header and the source snippet with the caret.
- The Core shown in "Context:" frames is rendered with the GHC
  suppression flags (no occurrence info, coercions, uniques, ticks)
  and with the anchor/unsupported markers stripped.

## Known reporting gaps (as pinned by the goldens)

The goldens document the current behavior, including its defects.
When you fix one of these, update the golden files.

1. Code written inside `[|| ... ||]` quotes keeps only the
   splice-point location through typed TH, so errors there point at
   the whole splice. GHC also inlines small same-module functions
   into the splice before the plugin runs, which turns their
   definition-level locations into splice-level ones.

2. Context frames show GHC Core (suppressed, but still Core:
   dictionary methods like `$fShowInteger_$cshow`, `IS`/`IP`
   constructors), which does not resemble the user's source code.

3. The markers are injected into every module that uplc-ghc compiles,
   including off-chain code, where the OPAQUE identity wrappers can
   block GHC optimizations. Evaluate gating the injection on modules
   that contain Plinth code, or stripping the markers with a cheap
   Core pass after the Plinth pass.

## Notes on the runner

The runner normalizes the output before the comparison: it strips
ANSI escapes, GHC uniques (`x_a5GN` -> `x`), `[N of M]` progress
lines, and CR characters. Files named `*Helper.hs` in `cases/` are
companion modules for multi-module cases, not test cases.
