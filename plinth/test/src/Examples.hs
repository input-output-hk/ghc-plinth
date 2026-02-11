module Examples where

import PlutusTx
import PlutusTx.Prelude qualified as PlutusTx

-- succScript: \x -> x + 1
succScript :: CompiledCode (Integer -> Integer)
succScript =
  $$(PlutusTx.compile [||succTyped||])

{-# INLINEABLE succTyped #-}
succTyped :: Integer -> Integer
succTyped x = x PlutusTx.+ 1

