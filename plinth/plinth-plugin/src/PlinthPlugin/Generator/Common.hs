{-# LANGUAGE CPP #-}

module PlinthPlugin.Generator.Common
  ( Generator,
    applyAll,
    fieldNameOptions,
    makeGRHSs,
    makeInstanceDeclaration,
    makeLHsBind,
    makeRandomModule,
    makeRandomVariable,
    parseDerivingStrategy,
  )
where

import qualified Control.Monad.IO.Class as IO
import qualified Data.Char as Char
import qualified Data.IORef as IORef
import qualified Data.List as List
import qualified Data.Maybe as Maybe
import qualified Data.Text as Text
import qualified PlinthPlugin.Hs as Hs
import qualified PlinthPlugin.Hsc as Hsc
import qualified PlinthPlugin.Type.Constructor as Constructor
import qualified PlinthPlugin.Type.Field as Field
import qualified PlinthPlugin.Type.Type as Type
import qualified GHC.Data.Bag as Ghc
import qualified GHC.Hs as Ghc
import qualified GHC.Plugins as Ghc
import qualified GHC.Types.Fixity as Ghc
import qualified System.Console.GetOpt as Console
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

fieldNameOptions ::
  Ghc.SrcSpan -> [Console.OptDescr (String -> Ghc.Hsc String)]
fieldNameOptions srcSpan =
  [ Console.Option [] ["kebab"] (Console.NoArg $ pure . kebab) "",
    Console.Option [] ["camel"] (Console.NoArg $ pure . lower) "",
    Console.Option [] ["snake"] (Console.NoArg $ pure . snake) "",
    Console.Option [] ["prefix", "strip"] (Console.ReqArg (stripPrefix srcSpan) "PREFIX") "",
    Console.Option [] ["suffix"] (Console.ReqArg (stripSuffix srcSpan) "SUFFIX") "",
    Console.Option [] ["title"] (Console.NoArg $ pure . upper) "",
    Console.Option [] ["rename"] (Console.ReqArg (rename srcSpan) "OLD:NEW") ""
  ]

stripPrefix :: Ghc.SrcSpan -> String -> String -> Ghc.Hsc String
stripPrefix srcSpan prefix s1 = case List.stripPrefix prefix s1 of
  Nothing ->
    Hsc.throwError srcSpan
      . Ghc.text
      $ show prefix
        <> " is not a prefix of "
        <> show s1
  Just s2 -> pure s2

stripSuffix :: Ghc.SrcSpan -> String -> String -> Ghc.Hsc String
stripSuffix srcSpan suffix s1 = case Text.stripSuffix (Text.pack suffix) (Text.pack s1) of
  Nothing ->
    Hsc.throwError srcSpan
      . Ghc.text
      $ show suffix
        <> " is not a suffix of "
        <> show s1
  Just s2 -> pure $ Text.unpack s2

rename :: Ghc.SrcSpan -> String -> String -> Ghc.Hsc String
rename loc arg str =
  case Text.splitOn (Text.singleton ':') $ Text.pack arg of
    [old, new]
      | not (Text.null old || Text.null new) ->
          pure $
            if Text.pack str == old
              then Text.unpack new
              else str
    _ -> Hsc.throwError loc . Ghc.text $ show arg <> " is invalid"

-- | Applies all the monadic functions in order beginning with some starting
-- value.
applyAll :: Monad m => [a -> m a] -> a -> m a
applyAll fs x = case fs of
  [] -> pure x
  f : gs -> do
    y <- f x
    applyAll gs y

-- | Converts the first character into upper case.
upper :: String -> String
upper = overFirst Char.toUpper

-- | Converts the first character into lower case.
lower :: String -> String
lower = overFirst Char.toLower

overFirst :: (a -> a) -> [a] -> [a]
overFirst f xs = case xs of
  x : ys -> f x : ys
  _ -> xs

-- | Converts the string into kebab case.
--
-- >>> kebab "DoReMi"
-- "do-re-mi"
kebab :: String -> String
kebab = camelTo '-'

-- | Converts the string into snake case.
--
-- >>> snake "DoReMi"
-- "do_re_mi"
snake :: String -> String
snake = camelTo '_'

camelTo :: Char -> String -> String
camelTo char =
  let go wasUpper string = case string of
        "" -> ""
        first : rest ->
          if Char.isUpper first
            then
              if wasUpper
                then Char.toLower first : go True rest
                else char : Char.toLower first : go True rest
            else first : go False rest
   in go True

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

      -- A bare type variable, used as a type. Each location wrapper is a
      -- fresh expression so its annotation type is inferred per-position
      -- (a shared @loc@ binding monomorphises to the wrong annotation).
      tv :: Ghc.IdP Ghc.GhcPs -> Ghc.LHsType Ghc.GhcPs
      tv n = Hs.tyVar srcSpan (Ghc.L (Ghc.noAnnSrcSpan srcSpan) n)

      initial :: Ghc.LHsType Ghc.GhcPs
      initial = tv (Type.name type_)

      combine ::
        Ghc.LHsType Ghc.GhcPs -> Ghc.IdP Ghc.GhcPs -> Ghc.LHsType Ghc.GhcPs
      combine x v =
        Ghc.L (Ghc.noAnnSrcSpan srcSpan) (Ghc.HsAppTy ext x (tv v))

      bare :: Ghc.LHsType Ghc.GhcPs
      bare = List.foldl' combine initial $ Type.variables type_
   in case Type.variables type_ of
        [] -> bare
        _ -> Ghc.L (Ghc.noAnnSrcSpan srcSpan) $ Ghc.HsParTy Ghc.noAnn bare

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
#if __GLASGOW_HASKELL__ >= 910
      (Nothing, Ghc.noAnn, Ghc.NoAnnSortKey)
      hsImplicitBndrs
      lHsBinds
#else
      (Ghc.noAnn, Ghc.NoAnnSortKey)
      hsImplicitBndrs
      (Ghc.listToBag lHsBinds)
#endif
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
  Hs.mg
    ( Ghc.L srcSpan
        [ Hs.funMatch
            srcSpan
            (Ghc.L (Ghc.noAnnSrcSpan srcSpan) (Ghc.Unqual occName))
            lPats
            (makeGRHSs srcSpan hsExpr)
        ]
    )

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
-- > deriving C via Plinth
--
-- where @Plinth@ is the sentinel type @data Plinth@. Using a real type (rather
-- than a @Symbol@ string literal) means the name must be in scope, so when the
-- plugin is not loaded GHC reports a clean error instead of a confusing one.
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
  rdrName <- case Ghc.unLoc lHsType of
    Ghc.HsTyVar _ _ x -> Just $ Ghc.unLoc x
    _ -> Nothing
  case Ghc.occNameString $ Ghc.rdrNameOcc rdrName of
    "Plinth" -> Just []
    _ -> Nothing

