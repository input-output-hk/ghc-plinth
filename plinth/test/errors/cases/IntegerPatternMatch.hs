{-# LANGUAGE TemplateHaskell #-}
-- Unsupported construct: pattern match on an Integer literal.
module IntegerPatternMatch where

import PlutusTx

isAnswer :: Integer -> Bool
isAnswer 42 = True
isAnswer _ = False
{-# INLINABLE isAnswer #-}

code :: CompiledCode (Integer -> Bool)
code = $$(PlutusTx.compile [|| isAnswer ||])
