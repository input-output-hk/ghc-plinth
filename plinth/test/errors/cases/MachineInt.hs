{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: machine Int (use Integer).
module MachineInt where

import PlutusTx

code :: CompiledCode Int
code = $$(PlutusTx.compile [|| 1 :: Int ||])
