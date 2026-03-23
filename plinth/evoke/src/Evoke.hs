module Evoke
  ( plugin,
  )
where

import qualified Control.Monad as Monad
import qualified Control.Monad.IO.Class as IO
import qualified Data.Bifunctor as Bifunctor
import qualified Data.Maybe as Maybe
import qualified Data.Version as Version
import qualified Evoke.Generator.AsData as AsData
import qualified Evoke.Generator.Optics as Optics
import qualified Evoke.Generator.Common as Common
import GHC.Hs
import qualified Evoke.Hsc as Hsc
import qualified Evoke.Options as Options
import qualified Evoke.Type.Config as Config
import qualified Evoke.Type.Flag as Flag
import qualified GHC.Hs as Ghc
import qualified GHC.Plugins as Ghc
import qualified Paths_evoke as This
import qualified System.Console.GetOpt as Console

-- | The compiler plugin. When built into the Plinth GHC binary this is
-- registered as a static plugin and is active for every compilation without
-- requiring a @-fplugin=Evoke@ pragma.
--
-- Once active, you can derive instances like this:
--
-- > data Shape = Point | Circle Integer Integer
-- >   deriving AsData via "Evoke"
-- >   deriving Optics via "Evoke"
plugin :: Ghc.Plugin
plugin =
  Ghc.defaultPlugin
    { Ghc.parsedResultAction = parsedResultAction,
      Ghc.pluginRecompile = Ghc.purePlugin
    }

parsedResultAction ::
  [Ghc.CommandLineOption] ->
  Ghc.ModSummary ->
  Ghc.ParsedResult ->
  Ghc.Hsc Ghc.ParsedResult
parsedResultAction commandLineOptions modSummary (Ghc.ParsedResult hsParsedModule msgs) = do
  let lHsModule1 = Ghc.hpm_module hsParsedModule
      srcSpan = Ghc.getLoc lHsModule1

  flags <- Options.parse Flag.options commandLineOptions srcSpan
  let config = Config.fromFlags flags

  Monad.when (Config.help config)
    . Hsc.throwError srcSpan
    . Ghc.vcat
    . fmap Ghc.text
    . lines
    $ Console.usageInfo ("Evoke version " <> version) Flag.options
  Monad.when (Config.version config) . Hsc.throwError srcSpan $
    Ghc.text version

  let moduleName = Ghc.moduleName $ Ghc.ms_mod modSummary
  lHsModule2 <- handleLHsModule config moduleName lHsModule1

  let newHsParsedModule = hsParsedModule { Ghc.hpm_module = lHsModule2 }
  pure $ Ghc.ParsedResult newHsParsedModule msgs

version :: String
version = Version.showVersion This.version

type LHsModule = Ghc.Located (Ghc.HsModule Ghc.GhcPs)

handleLHsModule ::
  Config.Config ->
  Ghc.ModuleName ->
  LHsModule ->
  Ghc.Hsc LHsModule
handleLHsModule config moduleName lHsModule = do
  hsModule <- handleHsModule config moduleName $ Ghc.unLoc lHsModule
  pure $ Ghc.L (Ghc.getLoc lHsModule) hsModule

handleHsModule ::
  Config.Config ->
  Ghc.ModuleName ->
  Ghc.HsModule Ghc.GhcPs ->
  Ghc.Hsc (Ghc.HsModule Ghc.GhcPs)
handleHsModule config moduleName hsModule = do
  (lImportDecls, lHsDecls) <-
    handleLHsDecls config moduleName $
      Ghc.hsmodDecls hsModule
  pure
    hsModule
      { Ghc.hsmodImports = Ghc.hsmodImports hsModule <> lImportDecls,
        Ghc.hsmodDecls = lHsDecls
      }

handleLHsDecls ::
  Config.Config ->
  Ghc.ModuleName ->
  [Ghc.LHsDecl Ghc.GhcPs] ->
  Ghc.Hsc ([Ghc.LImportDecl Ghc.GhcPs], [Ghc.LHsDecl Ghc.GhcPs])
handleLHsDecls config moduleName lHsDecls = do
  tuples <- mapM (handleLHsDecl config moduleName) lHsDecls
  pure . Bifunctor.bimap mconcat mconcat $ unzip tuples

handleLHsDecl ::
  Config.Config ->
  Ghc.ModuleName ->
  Ghc.LHsDecl Ghc.GhcPs ->
  Ghc.Hsc ([Ghc.LImportDecl Ghc.GhcPs], [Ghc.LHsDecl Ghc.GhcPs])
handleLHsDecl config moduleName lHsDecl = case Ghc.unLoc lHsDecl of
  Ghc.TyClD xTyClD tyClDecl1 -> do
    (mTyClDecl2, (lImportDecls, lHsDecls)) <- handleTyClDecl config moduleName tyClDecl1
    case mTyClDecl2 of
      Nothing ->
        pure (lImportDecls, lHsDecls)
      Just tyClDecl2 ->
        let newDecl = Ghc.L (Ghc.getLoc lHsDecl) (Ghc.TyClD xTyClD tyClDecl2)
         in pure (lImportDecls, newDecl : lHsDecls)
  _ -> pure ([], [lHsDecl])

handleTyClDecl ::
  Config.Config ->
  Ghc.ModuleName ->
  Ghc.TyClDecl Ghc.GhcPs ->
  Ghc.Hsc
    ( Maybe (Ghc.TyClDecl Ghc.GhcPs),
      ([Ghc.LImportDecl Ghc.GhcPs], [Ghc.LHsDecl Ghc.GhcPs])
    )
handleTyClDecl config moduleName tyClDecl = case tyClDecl of
  Ghc.DataDecl tcdDExt tcdLName tcdTyVars tcdFixity tcdDataDefn -> do
    (mHsDataDefn, (lImportDecls, lHsDecls)) <-
      handleHsDataDefn
        config
        moduleName
        tcdLName
        tcdTyVars
        tcdDataDefn
    pure
      ( fmap (Ghc.DataDecl tcdDExt tcdLName tcdTyVars tcdFixity) mHsDataDefn,
        (lImportDecls, lHsDecls)
      )
  _ -> pure (Just tyClDecl, ([], []))

handleHsDataDefn ::
  Config.Config ->
  Ghc.ModuleName ->
  Ghc.LIdP Ghc.GhcPs ->
  Ghc.LHsQTyVars Ghc.GhcPs ->
  Ghc.HsDataDefn Ghc.GhcPs ->
  Ghc.Hsc
    ( Maybe (Ghc.HsDataDefn Ghc.GhcPs),
      ([Ghc.LImportDecl Ghc.GhcPs], [Ghc.LHsDecl Ghc.GhcPs])
    )
handleHsDataDefn config moduleName lIdP lHsQTyVars hsDataDefn =
  case hsDataDefn of
    Ghc.HsDataDefn dd_ext dd_ctxt dd_cType dd_kindSig dd_cons dd_derivs ->
      do
        let consList = case dd_cons of
              Ghc.DataTypeCons _ cs -> cs
              Ghc.NewTypeCon c -> [c]

        (mHsDeriving, (lImportDecls, lHsDecls)) <-
          handleHsDeriving
            config
            moduleName
            lIdP
            lHsQTyVars
            consList
            dd_derivs

        pure
          ( fmap
              (\hsDeriving -> Ghc.HsDataDefn dd_ext dd_ctxt dd_cType dd_kindSig dd_cons hsDeriving)
              mHsDeriving,
            (lImportDecls, lHsDecls)
          )

handleHsDeriving ::
  Config.Config ->
  Ghc.ModuleName ->
  Ghc.LIdP Ghc.GhcPs ->
  Ghc.LHsQTyVars Ghc.GhcPs ->
  [Ghc.LConDecl Ghc.GhcPs] ->
  Ghc.HsDeriving Ghc.GhcPs ->
  Ghc.Hsc
    ( Maybe (Ghc.HsDeriving Ghc.GhcPs),
      ( [Ghc.LImportDecl Ghc.GhcPs],
        [Ghc.LHsDecl Ghc.GhcPs]
      )
    )
handleHsDeriving config moduleName lIdP lHsQTyVars lConDecls hsDeriving = do
  (dropOriginal, lHsDerivingClauses, (lImportDecls, lHsDecls)) <-
    handleLHsDerivingClauses config moduleName lIdP lHsQTyVars lConDecls hsDeriving
  pure
    ( if dropOriginal then Nothing else Just lHsDerivingClauses,
      (lImportDecls, lHsDecls)
    )

handleLHsDerivingClauses ::
  Config.Config ->
  Ghc.ModuleName ->
  Ghc.LIdP Ghc.GhcPs ->
  Ghc.LHsQTyVars Ghc.GhcPs ->
  [Ghc.LConDecl Ghc.GhcPs] ->
  Ghc.HsDeriving Ghc.GhcPs ->
  Ghc.Hsc
    ( Bool,
      [Ghc.LHsDerivingClause Ghc.GhcPs],
      ( [Ghc.LImportDecl Ghc.GhcPs],
        [Ghc.LHsDecl Ghc.GhcPs]
      )
    )
handleLHsDerivingClauses config moduleName lIdP lHsQTyVars lConDecls lHsDerivingClauses =
  do
    tuples <-
      mapM
        (handleLHsDerivingClause config moduleName lIdP lHsQTyVars lConDecls lHsDerivingClauses)
        lHsDerivingClauses
    let (mClauses, dropFlags, extras) = unzip3 tuples
        taggedExtras = zip dropFlags extras
        orderedExtras =
          fmap snd (filter fst taggedExtras)
            <> fmap snd (filter (not . fst) taggedExtras)
    pure
      ( or dropFlags,
        Maybe.catMaybes mClauses,
        Bifunctor.bimap mconcat mconcat $ unzip orderedExtras
      )

handleLHsDerivingClause ::
  Config.Config ->
  Ghc.ModuleName ->
  Ghc.LIdP Ghc.GhcPs ->
  Ghc.LHsQTyVars Ghc.GhcPs ->
  [Ghc.LConDecl Ghc.GhcPs] ->
  Ghc.HsDeriving Ghc.GhcPs ->
  Ghc.LHsDerivingClause Ghc.GhcPs ->
  Ghc.Hsc
    ( Maybe (Ghc.LHsDerivingClause Ghc.GhcPs),
      Bool,
      ( [Ghc.LImportDecl Ghc.GhcPs],
        [Ghc.LHsDecl Ghc.GhcPs]
      )
    )
handleLHsDerivingClause config moduleName lIdP lHsQTyVars lConDecls lHsDerivingClauses lHsDerivingClause =
  case Ghc.unLoc lHsDerivingClause of
    Ghc.HsDerivingClause _ deriv_clause_strategy deriv_clause_tys
      | Just options <- Common.parseDerivingStrategy deriv_clause_strategy -> do
          let nonEvokeClauses = filter
                ( \c -> case Ghc.unLoc c of
                    Ghc.HsDerivingClause _ s _ ->
                      Maybe.isNothing (Common.parseDerivingStrategy s)
                )
                lHsDerivingClauses
          (dropOriginal, lImportDecls, lHsDecls) <-
            handleLHsSigTypes config moduleName lIdP lHsQTyVars lConDecls options nonEvokeClauses
              . toLHsSigTypes
              $ Ghc.unLoc deriv_clause_tys
          pure (Nothing, dropOriginal, (lImportDecls, lHsDecls))
    _ -> pure (Just lHsDerivingClause, False, ([], []))

toLHsSigTypes :: Ghc.DerivClauseTys Ghc.GhcPs -> [Ghc.LHsSigType Ghc.GhcPs]
toLHsSigTypes derivClauseTys = case derivClauseTys of
  Ghc.DctSingle _ lHsSigType -> [lHsSigType]
  Ghc.DctMulti _ lHsSigTypes -> lHsSigTypes

handleLHsSigTypes ::
  Config.Config ->
  Ghc.ModuleName ->
  Ghc.LIdP Ghc.GhcPs ->
  Ghc.LHsQTyVars Ghc.GhcPs ->
  [Ghc.LConDecl Ghc.GhcPs] ->
  [String] ->
  Ghc.HsDeriving Ghc.GhcPs ->
  [Ghc.LHsSigType Ghc.GhcPs] ->
  Ghc.Hsc
    ( Bool,
      [Ghc.LImportDecl Ghc.GhcPs],
      [Ghc.LHsDecl Ghc.GhcPs]
    )
handleLHsSigTypes config moduleName lIdP lHsQTyVars lConDecls options lHsDerivingClauses lHsSigTypes =
  do
    tuples <-
      mapM
        (handleLHsSigType config moduleName lIdP lHsQTyVars lConDecls options lHsDerivingClauses)
        lHsSigTypes
    let (dropFlags, importLists, declLists) = unzip3 tuples
    pure (or dropFlags, mconcat importLists, mconcat declLists)

handleLHsSigType ::
  Config.Config ->
  Ghc.ModuleName ->
  Ghc.LIdP Ghc.GhcPs ->
  Ghc.LHsQTyVars Ghc.GhcPs ->
  [Ghc.LConDecl Ghc.GhcPs] ->
  [String] ->
  Ghc.HsDeriving Ghc.GhcPs ->
  Ghc.LHsSigType Ghc.GhcPs ->
  Ghc.Hsc
    ( Bool,
      [Ghc.LImportDecl Ghc.GhcPs],
      [Ghc.LHsDecl Ghc.GhcPs]
    )
handleLHsSigType config moduleName lIdP lHsQTyVars lConDecls options lHsDerivingClauses lHsSigType =
  do
    let srcSpan = Ghc.getLocA lHsSigType
    (dropOriginal, lImportDecls, lHsDecls) <- case getGenerator lHsSigType of
      Just generate ->
        generate lHsDerivingClauses moduleName lIdP lHsQTyVars lConDecls options srcSpan
      Nothing -> Hsc.throwError srcSpan $ Ghc.text "unsupported type class"

    verbose <- isVerbose config
    Monad.when verbose $ do
      IO.liftIO $ do
        putStrLn $ replicate 80 '-'
        mapM_ (putStrLn . Ghc.showPprUnsafe . Ghc.ppr) lImportDecls
        mapM_ (putStrLn . Ghc.showPprUnsafe . Ghc.ppr) lHsDecls

    pure (dropOriginal, lImportDecls, lHsDecls)

isVerbose :: Config.Config -> Ghc.Hsc Bool
isVerbose config = do
  dynFlags <- Ghc.getDynFlags
  pure $ Config.verbose config || Ghc.dopt Ghc.Opt_D_dump_deriv dynFlags

getGenerator :: Ghc.LHsSigType Ghc.GhcPs -> Maybe (Ghc.HsDeriving Ghc.GhcPs -> Common.Generator)
getGenerator lHsSigType = do
  className <- getClassName lHsSigType
  lookup className generators

generators :: [(String, Ghc.HsDeriving Ghc.GhcPs -> Common.Generator)]
generators =
  [ ("AsData", AsData.generate),
    ("Optics", Optics.generate)
  ]

getClassName :: Ghc.LHsSigType Ghc.GhcPs -> Maybe String
getClassName lHsSigType = do
  lHsType <- case Ghc.unLoc lHsSigType of
    Ghc.HsSig _ _ x -> Just x
  lIdP <- case Ghc.unLoc lHsType of
    Ghc.HsTyVar _ _ x -> Just x
    _ -> Nothing
  case Ghc.unLoc lIdP of
    Ghc.Unqual x -> Just $ Ghc.occNameString x
    _ -> Nothing
