{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: IO action inside compiled code.
module IOAction where

import PlutusTx

code :: CompiledCode (IO ())
code = $$(PlutusTx.compile [|| return () :: IO () ||])
