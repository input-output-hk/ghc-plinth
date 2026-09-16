{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE ExistentialQuantification #-}
-- Unsupported construct: existentially quantified data type.
module Existential where

import PlutusTx

data Box = forall a. Box a

mkBox :: Integer -> Box
mkBox = Box
{-# INLINABLE mkBox #-}

code :: CompiledCode (Integer -> Box)
code = $$(PlutusTx.compile [|| mkBox ||])
