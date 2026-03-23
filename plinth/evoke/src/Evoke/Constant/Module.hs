module Evoke.Constant.Module
  ( controlLens,
    plutusTx,
    plutusTxBuiltins,
  )
where

import qualified GHC.Unit.Module as Ghc

controlLens :: Ghc.ModuleName
controlLens = Ghc.mkModuleName "Control.Lens"

plutusTx :: Ghc.ModuleName
plutusTx = Ghc.mkModuleName "PlutusTx"

plutusTxBuiltins :: Ghc.ModuleName
plutusTxBuiltins = Ghc.mkModuleName "PlutusTx.Builtins"
