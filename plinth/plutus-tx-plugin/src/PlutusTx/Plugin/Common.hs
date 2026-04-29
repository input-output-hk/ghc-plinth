module PlutusTx.Plugin.Common (mkCompiledCode) where

import Data.ByteString qualified as BS
import PlutusCore.Flat.Run (unflat)
import PlutusPrelude (fold)
import PlutusTx.Code

-- Note [Stub mkCompiledCode]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~
-- The Plinth static plugin (baked into uplc-ghc from the full
-- plutus-tx-plugin) contains a TH quote 'mkCompiledCode whose module is
-- frozen as PlutusTx.Plugin.Common. At plugin-execution time the quote is
-- resolved against the current compilation's package DB. The stub's unit
-- id (plutus-tx-plugin-1.61.0.0-inplace) collides with the unit id of the
-- full plugin used to build uplc-ghc, so the stub must expose a module
-- of this name defining 'mkCompiledCode', otherwise GHC panics with
-- "Failed to load interface for 'PlutusTx.Plugin.Common'".
mkCompiledCode :: forall a. BS.ByteString -> BS.ByteString -> BS.ByteString -> CompiledCode a
mkCompiledCode plcBS pirBS ci = SerializedCode plcBS (Just pirBS) (fold . unflat $ ci)
