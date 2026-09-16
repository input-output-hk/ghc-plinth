{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: Double (floating point) literal.
module LitDouble where

import PlutusTx

code :: CompiledCode Double
code = $$(PlutusTx.compile [|| 1.5 :: Double ||])
