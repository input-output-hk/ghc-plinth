{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
-- Unsupported construct: irreducible type family application.
module IrreducibleTypeFamily where

import PlutusTx

type family F a

identity :: F Integer -> F Integer
identity x = x
{-# INLINABLE identity #-}

code :: CompiledCode (F Integer -> F Integer)
code = $$(PlutusTx.compile [|| identity ||])
