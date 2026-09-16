{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE GADTs #-}
-- Unsupported construct: the GADTs language extension.
module GadtExtension where

import PlutusTx

data Expr a where
  IntE :: Integer -> Expr Integer

eval :: Expr Integer -> Integer
eval (IntE i) = i
{-# INLINABLE eval #-}

code :: CompiledCode (Expr Integer -> Integer)
code = $$(PlutusTx.compile [|| eval ||])
