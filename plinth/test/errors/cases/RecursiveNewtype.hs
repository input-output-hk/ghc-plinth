{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: recursive newtype (use data).
module RecursiveNewtype where

import PlutusTx

newtype Stream = Stream (Integer, Stream)

hd :: Stream -> Integer
hd (Stream (x, _)) = x
{-# INLINABLE hd #-}

code :: CompiledCode (Stream -> Integer)
code = $$(PlutusTx.compile [|| hd ||])
