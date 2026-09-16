{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: fixed-width machine word (Word64).
module MachineWord where

import Data.Word (Word64)
import PlutusTx

code :: CompiledCode Word64
code = $$(PlutusTx.compile [|| 42 :: Word64 ||])
