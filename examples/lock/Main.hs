{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import PlutusTx
import qualified PlutusTx.Prelude as Tx
import PlutusLedgerApi.V3
  (Datum (..), ScriptContext (..), ScriptInfo (..), getRedeemer)
import PlutusLedgerApi.Envelope (writeCodeEnvelope)

-- The on-chain rule: the transaction can spend the locked output only
-- if the redeemer equals the number stored in the datum.
{-# INLINEABLE lockTyped #-}
lockTyped :: ScriptContext -> Bool
lockTyped ctx =
  case scriptContextScriptInfo ctx of
    SpendingScript _ (Just (Datum datum)) ->
      case (fromBuiltinData datum, fromBuiltinData redeemer) of
        (Just secret, Just guess) ->
          Tx.traceIfFalse "wrong number" (guess Tx.== (secret :: Integer))
        _ -> Tx.traceError "datum or redeemer is not an integer"
    _ -> Tx.traceError "expected a spending script with a datum"
  where
    redeemer = getRedeemer (scriptContextRedeemer ctx)

-- The entry point the ledger runs. A Plutus V3 script receives one
-- argument: the script context, with the datum and the redeemer inside.
{-# INLINEABLE lockUntyped #-}
lockUntyped :: BuiltinData -> Tx.BuiltinUnit
lockUntyped ctx = Tx.check (lockTyped (unsafeFromBuiltinData ctx))

-- Compile the validator to Plutus Core at compile time.
lockScript :: CompiledCode (BuiltinData -> Tx.BuiltinUnit)
lockScript = $$(compile [|| lockUntyped ||])

main :: IO ()
main = do
  writeCodeEnvelope "lock validator" lockScript "lock.plutus"
  putStrLn "wrote lock.plutus"
