{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: Data.ByteString.ByteString
-- (use BuiltinByteString).
module TypeByteString where

import Data.ByteString (ByteString)
import PlutusTx

code :: CompiledCode (ByteString -> ByteString)
code = $$(PlutusTx.compile [|| \x -> x ||])
