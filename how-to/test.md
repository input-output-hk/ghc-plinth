---
title: Test a Plinth contract locally
permalink: /how-to/test/
---
This guide shows how to test a Plinth validator **locally** &mdash; no node, no
live network. Because [Plinth is a subset of Haskell]({% link explanation/standalone-compiler.md %}),
you can test it at several levels, cheapest first:

1. the validator logic as **ordinary Haskell**;
2. the **compiled script** evaluated on the [CEK machine]({% link explanation/plutus-core.md %});
3. the script's **execution budget**, computed off-chain;
4. full **transactions** against a simulated ledger.

The first three need nothing beyond the libraries your project already depends on
(`plutus-tx`); the fourth pulls in a separate ledger emulator. This guide assumes
you have a compiled validator (a `CompiledCode`) &mdash; see
[The structure of a Plinth smart contract]({% link explanation/structure.md %}).

## The example

A tiny self-contained validator with real pass/fail logic: the on-chain rule is
plain Haskell, wrapped in the untyped `BuiltinData -> BuiltinUnit` form the ledger
runs, then frozen into a value with `PlutusTx.compile` (the same idiom as the
[project template]({% link tutorials/first-smart-contract.md %})):

```haskell
{-# LANGUAGE TemplateHaskell #-}

module MyValidator where

import PlutusTx
import PlutusTx.Prelude qualified as PlutusTx

-- on-chain rule: ordinary Haskell, in the Plinth subset
{-# INLINEABLE mustEqual #-}
mustEqual :: Integer -> Bool
mustEqual redeemer = redeemer PlutusTx.== 42

-- the untyped wrapper the ledger actually runs
{-# INLINEABLE untypedValidator #-}
untypedValidator :: BuiltinData -> PlutusTx.BuiltinUnit
untypedValidator arg =
  PlutusTx.check (mustEqual (PlutusTx.unsafeFromBuiltinData arg))

validatorCode :: CompiledCode (BuiltinData -> PlutusTx.BuiltinUnit)
validatorCode = $$(PlutusTx.compile [|| untypedValidator ||])
```

`PlutusTx.check` turns the `Bool` into a `BuiltinUnit`: a `True` result evaluates
to unit (the script *succeeds*), a `False` calls `error` (the script *fails*).

A real validator decodes a full `ScriptContext` from that single `BuiltinData`
argument rather than a bare `Integer`; here we keep the argument trivial so the
tests stay self-contained. See
[The Plinth contract language]({% link explanation/plinth-language.md %}) for the
real decoding.

## Test the logic as ordinary Haskell

`mustEqual` is just a Haskell function, so the fastest test exercises it directly
with [tasty](https://hackage.haskell.org/package/tasty) &mdash; no compilation to
UPLC at all:

```haskell
import Test.Tasty
import Test.Tasty.HUnit
import MyValidator (mustEqual)

logicTests :: TestTree
logicTests = testGroup "logic"
  [ testCase "accepts 42" $ mustEqual 42 @?= True
  , testCase "rejects 0"  $ mustEqual 0  @?= False
  ]
```

This is the tightest inner loop, and it is where property tests
([QuickCheck](https://hackage.haskell.org/package/QuickCheck)) belong. Be clear
about what it checks, though: the **Haskell meaning** of your rule, not the
compiled on-chain program. For that, evaluate the compiled code.

## Evaluate the compiled script

To run the actual on-chain program, apply an argument to `validatorCode` and
evaluate it on the CEK machine. `PlutusTx.unsafeApplyCode` and `liftCodeDef` bake
a `BuiltinData` argument into the compiled code (the same application machinery
used to apply [parameters]({% link explanation/structure.md %})), and
`evaluateCompiledCode` from `PlutusTx.Eval` runs it:

```haskell
import PlutusTx (unsafeApplyCode, liftCodeDef, toBuiltinData)
import PlutusTx.Eval (EvalResult (..), evaluateCompiledCode)
import Data.Either (isLeft, isRight)

runWith :: Integer -> EvalResult
runWith n =
  evaluateCompiledCode
    (validatorCode `unsafeApplyCode` liftCodeDef (toBuiltinData n))

evalTests :: TestTree
evalTests = testGroup "compiled script"
  [ testCase "accepts 42" $
      assertBool "should succeed" (isRight (evalResult (runWith 42)))
  , testCase "rejects 0" $
      assertBool "should fail"    (isLeft  (evalResult (runWith 0)))
  ]
```

`EvalResult` carries everything the run produced:

```haskell
data EvalResult = EvalResult
  { evalResult       :: Either CekEvaluationException (NTerm DefaultUni DefaultFun ())
  , evalResultBudget :: ExBudget
  , evalResultTraces :: [Text]
  }
```

A `Right` means the script succeeded; a `Left` means it errored (a failed
validation). `displayEvalResult :: EvalResult -> Text` renders the result, budget,
and traces together &mdash; handy when a test fails. Evaluating the compiled code
this way also catches anything that type-checks as Haskell but does not survive
compilation to the Plinth subset.

The `plutus-tx:plutus-tx-testlib` sublibrary wraps the success/failure check in
ready-made assertions (`assertEvaluatesSuccessfully`, `assertEvaluatesWithError`)
if you prefer them to pattern-matching on `evalResult`.

## Measure the execution budget

On-chain, every CEK step costs from a budget of
[execution units]({% link explanation/plutus-core.md %}), and because evaluation
is deterministic the cost can be computed off-chain in advance. `evaluateCompiledCode`
already returns it:

```haskell
import PlutusCore.Evaluation.Machine.ExBudget (ExBudget (..))

budgetOf42 :: ExBudget
budgetOf42 = evalResultBudget (runWith 42)
-- exBudgetCPU budgetOf42, exBudgetMemory budgetOf42
```

Asserting on the budget catches **cost regressions** &mdash; a refactor that
quietly makes a script more expensive. The `plutus-tx:plutus-tx-testlib`
sublibrary provides `goldenBudget` for exactly this: it records the budget in a
golden file and fails when the number drifts, using the same tasty/golden
mechanism described under
[Test and benchmark]({% link how-to/build.md %}#test-and-benchmark).

When you need the figures *exactly* as the ledger computes them (rather than the
default CEK parameters `evaluateCompiledCode` uses), serialise the script with
`serialiseCompiledCode` and run it through
`PlutusLedgerApi.Common.evaluateScriptCounting`. That path is more faithful but
more involved: it wants the serialised script decoded with `deserialiseScript`,
an `EvaluationContext` built from cost-model parameters, and a target protocol
version. For day-to-day testing, `evaluateCompiledCode` is enough.

## Simulate at the ledger level

Script-level tests answer "given this argument, does the validator pass and what
does it cost?" They do **not** model transactions: multiple UTxOs, datums and
redeemers attached to inputs, fees, minting, validity intervals, or several
validators interacting. For that you need an emulated ledger.

The maintained tool is [`clb`](https://github.com/mlabs-haskell/clb) (a Cardano
Ledger Backend / "emulator"), which runs the real `cardano-ledger` rules
in-process: you build and submit transactions against a mock chain, advance slots,
and assert on the outcome &mdash; no node required. A test reads roughly as: start
an empty ledger, pay funds into your script address, then submit a spending
transaction with a redeemer and assert it validates (or is rejected). See the
`clb` documentation for the current API.

**The old Plutus Application Framework is deprecated.** Many older tutorials test
contracts with the off-chain `Contract` monad, `EmulatorTrace`, and
`ContractModel`. That framework is discontinued &mdash; do not use it for new
work. Today the split is: on-chain logic in Plinth (tested as above), off-chain
transaction building with `cardano-api`, and ledger simulation with `clb`.
{:.warning}

`clb` is a separate, heavier dependency than the `plutus-tx`-only tests above. As
with the [vendored crypto libraries]({% link how-to/use.md %}), confirm it
resolves against your pinned library set, and treat this setup as for learning and
experimentation, not production.
{:.warning}

## See also

- [The structure of a Plinth smart contract]({% link explanation/structure.md %})
  &mdash; where the off-chain test code sits, and applying parameters with
  `unsafeApplyCode`.
- [How smart contracts run: Plutus Core and the CEK machine]({% link explanation/plutus-core.md %})
  &mdash; why off-chain evaluation and costing are faithful to the chain.
- [Build Plinth from source]({% link how-to/build.md %}) &mdash; the
  tasty/golden test mechanism the compiler's own suites use.
- [Generate a blueprint]({% link how-to/generate-blueprint.md %}) &mdash; the
  other main thing off-chain code does with a `CompiledCode`.
- [Plinth user guide](https://plutus.cardano.intersectmbo.org/docs/) &mdash; the
  complete reference for writing Plinth.
