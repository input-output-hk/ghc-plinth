{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: range syntax (enumFromTo).
module EnumRange where

import PlutusTx

code :: CompiledCode [Integer]
code = $$(PlutusTx.compile [|| [1 .. 10] :: [Integer] ||])
