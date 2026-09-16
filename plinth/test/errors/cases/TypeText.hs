{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: Data.Text.Text (use BuiltinString).
module TypeText where

import Data.Text (Text)
import PlutusTx

code :: CompiledCode (Text -> Text)
code = $$(PlutusTx.compile [|| \x -> x ||])
