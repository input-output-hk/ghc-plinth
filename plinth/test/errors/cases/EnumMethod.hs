{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: succ from the Haskell Enum class
-- (use PlutusTx.Enum).
module EnumMethod where

import PlutusTx

code :: CompiledCode (Integer -> Integer)
code = $$(PlutusTx.compile [|| \x -> succ (x :: Integer) ||])
