module Examples where

import PlutusTx
import PlutusTx.Prelude qualified as PlutusTx

import qualified Utils

-- succScript: \x -> x + 1
succScript :: CompiledCode (Integer -> Integer)
succScript =
  $$(PlutusTx.compile [||succTyped||])

succTyped :: Integer -> Integer
succTyped x = Utils.plusInteger x 1

-- eqCheckScript: return unit if the integers are equal, otherwise fail
eqCheckScript :: CompiledCode (Integer -> Integer -> PlutusTx.BuiltinUnit)
eqCheckScript =
  $$(PlutusTx.compile [||eqCheckTyped||])

eqCheckTyped :: Integer -> Integer -> PlutusTx.BuiltinUnit
eqCheckTyped x y = PlutusTx.check (x PlutusTx.== y)
