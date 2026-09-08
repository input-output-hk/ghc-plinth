{-# LANGUAGE TemplateHaskell #-}

module Main where

import PlutusTx
import qualified PlutusTx.Prelude as Tx
import qualified PlutusTx.Code as Code
import PlutusCore.Pretty (prettyPlcReadableSimple)
import Prettyprinter (defaultLayoutOptions, layoutPretty)
import Prettyprinter.Render.Text (renderStrict)
import Data.Text (unpack)

-- The on-chain function: add two integers.
addTyped :: Integer -> Integer -> Integer
addTyped x y = x Tx.+ y

-- Compile it to Plutus Core at compile time.
addScript :: CompiledCode (Integer -> Integer -> Integer)
addScript = $$(compile [|| addTyped ||])

-- Render compiled code as readable UPLC text.
renderUPLC :: CompiledCode a -> String
renderUPLC =
    unpack
  . renderStrict
  . layoutPretty defaultLayoutOptions
  . prettyPlcReadableSimple
  . Code.getPlcNoAnn

main :: IO ()
main = writeFile "add.uplc" (renderUPLC addScript)
