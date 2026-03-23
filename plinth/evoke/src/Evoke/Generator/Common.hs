module Evoke.Generator.Common
  ( Generator,
    makeGRHSs,
    makeInstanceDeclaration,
    makeLHsBind,
    makeRandomModule,
    makeRandomVariable,
    parseDerivingStrategy,
  )
where

import qualified Control.Monad.IO.Class as IO
import qualified Data.IORef as IORef
import qualified Data.List as List
import qualified Data.Maybe as Maybe
import qualified Evoke.Hs as Hs
import qualified Evoke.Type.Constructor as Constructor
import qualified Evoke.Type.Field as Field
import qualified Evoke.Type.Type as Type
import qualified GHC.Data.Bag as Ghc
import qualified GHC.Hs as Ghc
import qualified GHC.Plugins as Ghc
import qualified GHC.Types.Fixity as Ghc
import qualified System.IO.Unsafe as Unsafe
import qualified Text.Printf as Printf

-- | The 'Bool' indicates whether the original declaration should be dropped
-- (replaced by the generated declarations). Most generators return 'False'.
type Generator =
  Ghc.ModuleName ->
  Ghc.LIdP Ghc.GhcPs ->
  Ghc.LHsQTyVars Ghc.GhcPs ->
  [Ghc.LConDecl Ghc.GhcPs] ->
  [String] ->
  Ghc.SrcSpan ->
  Ghc.Hsc
    (Bool, [Ghc.LImportDecl Ghc.GhcPs], [Ghc.LHsDecl Ghc.GhcPs])

makeLHsType ::
  Ghc.SrcSpan ->
  Ghc.ModuleName ->
  Ghc.OccName ->
  Type.Type ->
  Ghc.LHsType Ghc.GhcPs
makeLHsType srcSpan moduleName className =
  Ghc.L (Ghc.noAnnSrcSpan srcSpan)
    . Ghc.HsAppTy
      Ghc.noExtField
      ( Ghc.L (Ghc.noAnnSrcSpan srcSpan)
          . Ghc.HsTyVar Ghc.noAnn Ghc.NotPromoted
          . Ghc.L (Ghc.noAnnSrcSpan srcSpan)
          $ Ghc.Qual moduleName className
      )
    . toLHsType srcSpan

toLHsType :: Ghc.SrcSpan -> Type.Type -> Ghc.LHsType Ghc.GhcPs
toLHsType srcSpan type_ =
  let ext :: Ghc.NoExtField
      ext = Ghc.noExtField

      loc = Ghc.L (Ghc.noAnnSrcSpan srcSpan)

      initial :: Ghc.LHsType Ghc.GhcPs
      initial = loc . Ghc.HsTyVar Ghc.noAnn Ghc.NotPromoted . loc $ Type.name type_

      combine ::
        Ghc.LHsType Ghc.GhcPs -> Ghc.IdP Ghc.GhcPs -> Ghc.LHsType Ghc.GhcPs
      combine x =
        loc . Ghc.HsAppTy ext x . loc . Ghc.HsTyVar Ghc.noAnn Ghc.NotPromoted . loc

      bare :: Ghc.LHsType Ghc.GhcPs
      bare = List.foldl' combine initial $ Type.variables type_
   in case Type.variables type_ of
        [] -> bare
        _ -> loc $ Ghc.HsParTy Ghc.noAnn bare

makeHsContext ::
  Ghc.SrcSpan ->
  Ghc.ModuleName ->
  Ghc.OccName ->
  Type.Type ->
  [Ghc.LHsType Ghc.GhcPs]
makeHsContext srcSpan moduleName className =
  fmap
    ( Ghc.L (Ghc.noAnnSrcSpan srcSpan)
        . Ghc.HsAppTy
          Ghc.noExtField
          ( Ghc.L (Ghc.noAnnSrcSpan srcSpan)
              . Ghc.HsTyVar Ghc.noAnn Ghc.NotPromoted
              . Ghc.L (Ghc.noAnnSrcSpan srcSpan)
              $ Ghc.Qual moduleName className
          )
        . Ghc.L (Ghc.noAnnSrcSpan srcSpan)
        . Ghc.HsTyVar Ghc.noAnn Ghc.NotPromoted
        . Ghc.L (Ghc.noAnnSrcSpan srcSpan)
        . Ghc.Unqual
    )
    . List.nub
    . Maybe.mapMaybe
      ( \field -> case Field.type_ field of
          Ghc.HsTyVar _ _ lRdrName -> case Ghc.unLoc lRdrName of
            Ghc.Unqual occName | Ghc.isTvOcc occName -> Just occName
            _ -> Nothing
          _ -> Nothing
      )
    . concatMap Constructor.fields
    . Type.constructors

makeHsImplicitBndrs ::
  Ghc.SrcSpan ->
  Type.Type ->
  Ghc.ModuleName ->
  Ghc.OccName ->
  Ghc.LHsSigType Ghc.GhcPs
makeHsImplicitBndrs srcSpan type_ moduleName className =
  let withoutContext = makeLHsType srcSpan moduleName className type_
      context = makeHsContext srcSpan moduleName className type_
      withContext =
        if null context
          then withoutContext
          else
            Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
              Ghc.HsQualTy Ghc.noExtField (Ghc.L (Ghc.noAnnSrcSpan srcSpan) context) withoutContext
   in Ghc.L (Ghc.noAnnSrcSpan srcSpan) $ Ghc.HsSig Ghc.noExtField Ghc.mkHsOuterImplicit withContext

-- | Makes a random variable name using the given prefix.
makeRandomVariable :: Ghc.SrcSpan -> String -> Ghc.Hsc (Ghc.LIdP Ghc.GhcPs)
makeRandomVariable srcSpan prefix = do
  n <- bumpCounter
  pure . Ghc.L (Ghc.noAnnSrcSpan srcSpan) . Ghc.Unqual . Ghc.mkVarOcc $
    Printf.printf
      "%s%d"
      prefix
      n

-- | Makes a random module name. This will convert any periods to underscores
-- and add a unique suffix.
--
-- >>> makeRandomModule "Data.Aeson"
-- "Data_Aeson_1"
makeRandomModule :: Ghc.ModuleName -> Ghc.Hsc Ghc.ModuleName
makeRandomModule moduleName = do
  n <- bumpCounter
  pure . Ghc.mkModuleName $
    Printf.printf
      "%s_%d"
      (underscoreAll moduleName)
      n

underscoreAll :: Ghc.ModuleName -> String
underscoreAll = fmap underscoreOne . Ghc.moduleNameString

underscoreOne :: Char -> Char
underscoreOne c = case c of
  '.' -> '_'
  _ -> c

makeInstanceDeclaration ::
  Ghc.SrcSpan ->
  Type.Type ->
  Ghc.ModuleName ->
  Ghc.OccName ->
  [Ghc.LHsBind Ghc.GhcPs] ->
  Ghc.LHsDecl Ghc.GhcPs
makeInstanceDeclaration srcSpan type_ moduleName occName lHsBinds =
  let hsImplicitBndrs = makeHsImplicitBndrs srcSpan type_ moduleName occName
   in makeLHsDecl srcSpan hsImplicitBndrs lHsBinds

makeLHsDecl ::
  Ghc.SrcSpan ->
  Ghc.LHsSigType Ghc.GhcPs ->
  [Ghc.LHsBind Ghc.GhcPs] ->
  Ghc.LHsDecl Ghc.GhcPs
makeLHsDecl srcSpan hsImplicitBndrs lHsBinds =
  Ghc.L (Ghc.noAnnSrcSpan srcSpan)
    . Ghc.InstD Ghc.noExtField
    . Ghc.ClsInstD Ghc.noExtField
    $ Ghc.ClsInstDecl 
      (Ghc.noAnn, Ghc.NoAnnSortKey)
      hsImplicitBndrs
      (Ghc.listToBag lHsBinds)
      [] [] [] Nothing

makeLHsBind ::
  Ghc.SrcSpan ->
  Ghc.OccName ->
  [Ghc.LPat Ghc.GhcPs] ->
  Ghc.LHsExpr Ghc.GhcPs ->
  Ghc.LHsBind Ghc.GhcPs
makeLHsBind srcSpan occName pats =
  Hs.funBind srcSpan occName . makeMatchGroup srcSpan occName pats

makeMatchGroup ::
  Ghc.SrcSpan ->
  Ghc.OccName ->
  [Ghc.LPat Ghc.GhcPs] ->
  Ghc.LHsExpr Ghc.GhcPs ->
  Ghc.MatchGroup Ghc.GhcPs (Ghc.LHsExpr Ghc.GhcPs)
makeMatchGroup srcSpan occName lPats hsExpr =
  Ghc.MG Ghc.Generated
    (Ghc.L (Ghc.noAnnSrcSpan srcSpan) [Ghc.L (Ghc.noAnnSrcSpan srcSpan) $ makeMatch srcSpan occName lPats hsExpr])

makeMatch ::
  Ghc.SrcSpan ->
  Ghc.OccName ->
  [Ghc.LPat Ghc.GhcPs] ->
  Ghc.LHsExpr Ghc.GhcPs ->
  Ghc.Match Ghc.GhcPs (Ghc.LHsExpr Ghc.GhcPs)
makeMatch srcSpan occName lPats =
  Ghc.Match
    Ghc.noAnn
    ( Ghc.FunRhs
        (Ghc.L (Ghc.noAnnSrcSpan srcSpan) $ Ghc.Unqual occName)
        Ghc.Prefix
        Ghc.NoSrcStrict
    )
    lPats
    . makeGRHSs srcSpan

makeGRHSs ::
  Ghc.SrcSpan ->
  Ghc.LHsExpr Ghc.GhcPs ->
  Ghc.GRHSs Ghc.GhcPs (Ghc.LHsExpr Ghc.GhcPs)
makeGRHSs srcSpan hsExpr =
  Ghc.GRHSs Ghc.emptyComments [Hs.grhs srcSpan hsExpr] $
    Ghc.EmptyLocalBinds Ghc.noExtField

bumpCounter :: IO.MonadIO m => m Word
bumpCounter = IO.liftIO . IORef.atomicModifyIORef' counterRef $ \n -> (n + 1, n)

counterRef :: IORef.IORef Word
counterRef = Unsafe.unsafePerformIO $ IORef.newIORef 0
{-# NOINLINE counterRef #-}



-- | This plugin only fires on specific deriving strategies. In particular it
-- looks for clauses like this:
--
-- > deriving C via "Evoke ..."
--
-- This function is responsible for analyzing a deriving strategy to determine
-- if the plugin should fire or not.
parseDerivingStrategy ::
  Maybe (Ghc.LDerivStrategy Ghc.GhcPs) -> Maybe [String]
parseDerivingStrategy mLDerivStrategy = do
  lDerivStrategy <- mLDerivStrategy
  lHsSigType <- case Ghc.unLoc lDerivStrategy of
    Ghc.ViaStrategy (Ghc.XViaStrategyPs _ x) -> Just $ Ghc.unLoc x
    _ -> Nothing
  lHsType <- case lHsSigType of
    Ghc.HsSig _ _ x -> Just x
  hsTyLit <- case Ghc.unLoc lHsType of
    Ghc.HsTyLit _ x -> Just x
    _ -> Nothing
  fastString <- case hsTyLit of
    Ghc.HsStrTy _ x -> Just x
    _ -> Nothing
  case words $ Ghc.unpackFS fastString of
    "Evoke" : x -> Just x
    _ -> Nothing

