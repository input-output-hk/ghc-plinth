module PlinthPlugin.Type.Constructor
  ( Constructor (..),
    make,
  )
where

import qualified Control.Monad as Monad
import qualified Data.List as List
import qualified PlinthPlugin.Hsc as Hsc
import qualified PlinthPlugin.Type.Field as Field
import qualified GHC.Hs as Ghc
import qualified GHC.Plugins as Ghc

data Constructor = Constructor
  { name :: Ghc.IdP Ghc.GhcPs,
    fields :: [Field.Field]
  }

make :: Ghc.SrcSpan -> Ghc.LConDecl Ghc.GhcPs -> Ghc.Hsc Constructor
make srcSpan lConDecl = do
  (lIdP, hsConDeclDetails) <- case Ghc.unLoc lConDecl of
    Ghc.ConDeclH98 _ x _ _ _ y _ -> pure (x, y)
    _ -> Hsc.throwError srcSpan $ Ghc.text "unsupported LConDecl"
  theFields <- case hsConDeclDetails of
    Ghc.RecCon lConDeclFields ->
      fmap concat . Monad.forM (Ghc.unLoc lConDeclFields) $ \lConDeclField -> do
        (lFieldOccs, lHsType) <- case Ghc.unLoc lConDeclField of
          Ghc.ConDeclField _ x y _ -> pure (x, y)
        mapM (Field.make srcSpan lHsType) lFieldOccs
    Ghc.PrefixCon _ scaledTypes ->
      pure $ List.zipWith
        (\i (Ghc.HsScaled _ lHsType) -> Field.Field
          { Field.name = Ghc.mkVarOcc ("_field" <> show (i :: Int)),
            Field.type_ = Ghc.unLoc lHsType
          })
        [0 ..]
        scaledTypes
    _ -> Hsc.throwError srcSpan $ Ghc.text "unsupported HsConDeclDetails"
  pure Constructor {name = Ghc.unLoc lIdP, fields = theFields}
