{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: unbounded range syntax.
module EnumRangeUnbounded where

import PlutusTx

code :: CompiledCode [Integer]
code = $$(PlutusTx.compile [|| [1 ..] :: [Integer] ||])
