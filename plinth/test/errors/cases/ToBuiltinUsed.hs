{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: toBuiltin inside compiled code
-- (use toOpaque).
module ToBuiltinUsed where

import PlutusTx
import qualified PlutusTx.Builtins as Builtins

code :: CompiledCode (Integer -> Integer)
code = $$(PlutusTx.compile [|| Builtins.toBuiltin ||])
