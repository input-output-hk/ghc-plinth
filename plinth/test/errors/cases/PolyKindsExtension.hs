{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE PolyKinds #-}
-- Unsupported construct: the PolyKinds language extension.
module PolyKindsExtension where

import PlutusTx

identity :: Integer -> Integer
identity x = x
{-# INLINABLE identity #-}

code :: CompiledCode (Integer -> Integer)
code = $$(PlutusTx.compile [|| identity ||])
