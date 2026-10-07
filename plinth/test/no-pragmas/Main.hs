-- In uplc-ghc, -O0 does not imply -fignore-interface-pragmas.
{-# OPTIONS_GHC -O0 #-}

-- Note [No INLINABLE pragmas]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Plinth code can use functions of other modules and packages without
-- INLINABLE pragmas: Plinth.Plugin adds INLINABLE to every binding that
-- has no inline pragma of its own, so GHC keeps the unfoldings that the
-- Plinth compiler needs in the interface files.
--
-- In uplc-ghc, -O0 does not imply -fomit-interface-pragmas and
-- -fignore-interface-pragmas (see Note [Keep interface pragmas] in
-- ghc:GHC.Driver.Session), so -O0 does not remove the unfoldings.
--
-- This test uses the helpers of NoPragmas and NoPragmasO0 (library
-- plinth-validators). NoPragmasO0 and this module use -O0. Without the
-- unfoldings, the splice below fails to compile. The test also
-- evaluates the script, to check that the definitions are correct.
module Main (main) where

import PlutusTx
import PlutusTx.Eval (evaluatesWithoutError)
import PlutusTx.Prelude qualified as P
import System.Exit (exitFailure)

import NoPragmas
import NoPragmasO0

-- The script fails if the condition is false. It uses 'traceError' on
-- purpose: GHC must not know that the builtin 'error' is bottom, otherwise
-- the unfolding of 'traceError' contains (case error of {}), which Plinth
-- cannot compile. PlutusTx.Builtins.Internal hides this with an explicit
-- -fomit-interface-pragmas (see Note [Keep interface pragmas] in
-- ghc:GHC.Driver.Session).
script :: CompiledCode (Integer -> P.BuiltinUnit)
script =
  $$( PlutusTx.compile
        [||
        \expected ->
          P.check
            ( if P.not (isEven 7)
                P.&& sumTo 4 P.== 10
                P.&& productTo 4 P.== 24
                P.&& applyN 3 (P.+ 2) (sumAreas [Square 3, Rect 2 5]) P.== expected
                then True
                else P.traceError "no-pragmas: wrong result"
            )
        ||]
    )

run :: Integer -> Bool
run expected =
  evaluatesWithoutError (script `unsafeApplyCode` liftCodeDef expected)

main :: IO ()
main
  -- The negative case makes sure that the check is not vacuous.
  | run 25 && not (run 24) = putStrLn "no-pragmas: OK"
  | otherwise = putStrLn "no-pragmas: FAILED" >> exitFailure
