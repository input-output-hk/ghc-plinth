module PlinthPlugin.Generator.Match
  ( generate,
  )
where

import qualified Data.List as List
import qualified PlinthPlugin.Constant.Module as Module
import qualified PlinthPlugin.Generator.Common as Common
import qualified PlinthPlugin.Hs as Hs
import qualified PlinthPlugin.Hsc as Hsc
import qualified PlinthPlugin.Type.Constructor as Constructor
import qualified PlinthPlugin.Type.Field as Field
import qualified PlinthPlugin.Type.Type as Type
import qualified GHC.Hs as Ghc
import qualified GHC.Plugins as Ghc
import qualified GHC.Types.Fixity as Ghc
import qualified GHC.Types.SourceText as Ghc

-- | Generates a CPS-style destructor function for 'AsData' sum types.
--
-- Given:
--
-- > data Example a = Ex1 Integer | Ex2 a a
-- >   deriving (AsData, Match) via Plinth
--
-- Generates:
--
-- > matchExample :: Example a -> (Integer -> r_N) -> (a -> a -> r_N) -> r_N
-- > matchExample (Example_BD d_) f_0 f_1 =
-- >   let tag_ = fst (PlutusTx.Builtins.unsafeDataAsConstr d_)
-- >       args_ = snd (PlutusTx.Builtins.unsafeDataAsConstr d_)
-- >   in if tag_ == 0
-- >      then f_0 ((PlutusTx.unsafeFromBuiltinData (head args_)) :: Integer)
-- >      else f_1 ((PlutusTx.unsafeFromBuiltinData (head args_)) :: a)
-- >               ((PlutusTx.unsafeFromBuiltinData (head (tail args_))) :: a)
--
-- For a single-constructor type, the tag check is omitted entirely:
--
-- > data Address = Address Credential (Maybe StakingCredential)
-- >   deriving (AsData, Match) via Plinth
--
-- Generates:
--
-- > matchAddress :: Address -> (Credential -> Maybe StakingCredential -> r_N) -> r_N
-- > matchAddress (Address_BD d_) f_ =
-- >   let args_ = snd (PlutusTx.Builtins.unsafeDataAsConstr d_)
-- >   in f_ ((PlutusTx.unsafeFromBuiltinData (head args_)) :: Credential)
-- >          ((PlutusTx.unsafeFromBuiltinData (head (tail args_))) :: Maybe StakingCredential)
generate :: Ghc.HsDeriving Ghc.GhcPs -> Common.Generator
generate _ _moduleName lIdP lHsQTyVars lConDecls _options srcSpan = do
  type_ <- Type.make lIdP lHsQTyVars lConDecls srcSpan
  let constructors = Type.constructors type_
  when (null constructors) $
    Hsc.throwError srcSpan $ Ghc.text "Match requires at least one constructor"

  plutusTx <- Common.makeRandomModule Module.plutusTx
  plutusTxBuiltins <- Common.makeRandomModule Module.plutusTxBuiltins

  let lImportDecls =
        Hs.importDecls
          srcSpan
          [ (Module.plutusTx, plutusTx),
            (Module.plutusTxBuiltins, plutusTxBuiltins)
          ]

  decls <- makeMatchDecls srcSpan type_ constructors plutusTx plutusTxBuiltins
  pure (False, lImportDecls, decls)

when :: Applicative f => Bool -> f () -> f ()
when True action = action
when False _ = pure ()

-- | The internal BD constructor name (same convention as 'AsData').
internalConName :: Type.Type -> Ghc.OccName
internalConName type_ =
  Ghc.mkDataOcc $
    Ghc.occNameString (Ghc.rdrNameOcc (Type.name type_)) <> "_BD"

-- | @"match" <> TypeName@, e.g. @matchExample@.
matchFunOcc :: Type.Type -> Ghc.OccName
matchFunOcc type_ =
  Ghc.mkVarOcc $
    "match" <> Ghc.occNameString (Ghc.rdrNameOcc (Type.name type_))

makeMatchDecls ::
  Ghc.SrcSpan ->
  Type.Type ->
  [Constructor.Constructor] ->
  Ghc.ModuleName ->
  Ghc.ModuleName ->
  Ghc.Hsc [Ghc.LHsDecl Ghc.GhcPs]
makeMatchDecls srcSpan type_ constructors plutusTx plutusTxBuiltins = do
  let funOcc = matchFunOcc type_
      funId = Ghc.L (Ghc.noAnnSrcSpan srcSpan) (Ghc.Unqual funOcc)
      internalCon =
        Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
          Ghc.mkRdrUnqual (internalConName type_)

  dVar <- Common.makeRandomVariable srcSpan "d_"
  tagVar <- Common.makeRandomVariable srcSpan "tag_"
  argsVar <- Common.makeRandomVariable srcSpan "args_"
  contVars <- mapM (\_ -> Common.makeRandomVariable srcSpan "f_") constructors
  rVar <- Common.makeRandomVariable srcSpan "r_"

  let sigDecl = makeSigDecl srcSpan type_ constructors funId rVar
      valDecl =
        makeValDecl
          srcSpan
          constructors
          funOcc
          dVar
          tagVar
          argsVar
          internalCon
          contVars
          plutusTx
          plutusTxBuiltins

  pure [sigDecl, valDecl]

-- | Build the type signature.
--
-- @matchExample :: Example a -> (Integer -> r_N) -> (a -> a -> r_N) -> r_N@
makeSigDecl ::
  Ghc.SrcSpan ->
  Type.Type ->
  [Constructor.Constructor] ->
  Ghc.LIdP Ghc.GhcPs ->
  Ghc.LIdP Ghc.GhcPs ->
  Ghc.LHsDecl Ghc.GhcPs
makeSigDecl srcSpan type_ constructors funId rVar =
  let loc = Ghc.noAnnSrcSpan srcSpan

      rTy = Ghc.L loc $ Ghc.HsTyVar Ghc.noAnn Ghc.NotPromoted rVar

      -- A -> B -> ... -> r  for a constructor's fields
      mkContTy fields =
        foldr
          (\field acc -> Hs.funTy srcSpan (Ghc.L loc (Field.type_ field)) acc)
          rTy
          fields

      -- Wrap in parens unless nullary (just r)
      mkContTyPar fields = case fields of
        [] -> rTy
        _ -> Ghc.L loc $ Ghc.HsParTy Ghc.noAnn (mkContTy fields)

      outerTy = mkOuterTy srcSpan type_
      contTys = fmap (mkContTyPar . Constructor.fields) constructors

      -- TypeName vars -> cont0 -> ... -> r
      fullTy =
        foldr
          (\argTy acc -> Hs.funTy srcSpan argTy acc)
          rTy
          (outerTy : contTys)
   in Ghc.noLocA $ Ghc.SigD Ghc.noExtField $
        Ghc.TypeSig Ghc.noAnn [funId] $
          Ghc.HsWC Ghc.noExtField $
            Ghc.L loc $
              Ghc.HsSig Ghc.noExtField Ghc.mkHsOuterImplicit fullTy

-- | @TypeName a b ...@ as an 'LHsType', parenthesised when there are type vars.
mkOuterTy :: Ghc.SrcSpan -> Type.Type -> Ghc.LHsType Ghc.GhcPs
mkOuterTy srcSpan type_ =
  let -- Fresh location wrappers per position (a shared @loc@ monomorphises
      -- to the wrong annotation type under GHC ≥ 9.10).
      tv n = Hs.tyVar srcSpan (Ghc.L (Ghc.noAnnSrcSpan srcSpan) n)
      initial = tv (Type.name type_)
      applied =
        List.foldl'
          ( \acc v ->
              Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
                Ghc.HsAppTy Ghc.noExtField acc (tv v)
          )
          initial
          (Type.variables type_)
   in case Type.variables type_ of
        [] -> applied
        _ -> Ghc.L (Ghc.noAnnSrcSpan srcSpan) $ Ghc.HsParTy Ghc.noAnn applied

-- | Build the function value declaration.
makeValDecl ::
  Ghc.SrcSpan ->
  [Constructor.Constructor] ->
  Ghc.OccName ->
  Ghc.LIdP Ghc.GhcPs ->
  Ghc.LIdP Ghc.GhcPs ->
  Ghc.LIdP Ghc.GhcPs ->
  Ghc.LIdP Ghc.GhcPs ->
  [Ghc.LIdP Ghc.GhcPs] ->
  Ghc.ModuleName ->
  Ghc.ModuleName ->
  Ghc.LHsDecl Ghc.GhcPs
makeValDecl srcSpan constructors funOcc dVar tagVar argsVar internalCon contVars plutusTx plutusTxBuiltins =
  let ptx = Hs.qualVar srcSpan plutusTx
      blt = Hs.qualVar srcSpan plutusTxBuiltins

      -- head (tail^n args_)
      nthElem n =
        Hs.app srcSpan
          (Hs.var srcSpan (Hs.unqual srcSpan (Ghc.mkVarOcc "head")))
          ( Hs.par srcSpan $
              iterate
                ( \e ->
                    Hs.app srcSpan
                      (Hs.var srcSpan (Hs.unqual srcSpan (Ghc.mkVarOcc "tail")))
                      (Hs.par srcSpan e)
                )
                (Hs.var srcSpan argsVar)
                !! n
          )

      -- (unsafeFromBuiltinData (head/tail^n args_)) :: FieldType
      decodeField n field =
        typeAnnotate srcSpan (Field.type_ field) $
          Hs.app srcSpan
            (ptx (Ghc.mkVarOcc "unsafeFromBuiltinData"))
            (Hs.par srcSpan (nthElem n))

      -- f_ decoded_field_0 decoded_field_1 ...
      applyFn fVar fields =
        List.foldl'
          (Hs.app srcSpan)
          (Hs.var srcSpan fVar)
          (zipWith decodeField [0 ..] fields)

      -- Nested if-else dispatch; last constructor falls through without a tag check
      makeDispatch [] _ = error "Match.makeDispatch: empty list"
      makeDispatch [(fVar, con)] _ = applyFn fVar (Constructor.fields con)
      makeDispatch ((fVar, con) : rest) (idx : idxs) =
        Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
          Ghc.HsIf Ghc.noAnn
            ( Hs.opApp srcSpan
                (Hs.var srcSpan tagVar)
                (Hs.var srcSpan (Hs.unqual srcSpan (Ghc.mkVarOcc "==")))
                (intLit srcSpan idx)
            )
            (applyFn fVar (Constructor.fields con))
            (makeDispatch rest idxs)
      makeDispatch _ [] = error "Match.makeDispatch: ran out of indices"

      needsTag = length constructors > 1
      needsArgs = any (not . null . Constructor.fields) constructors

      constrExpr =
        Hs.app srcSpan
          (blt (Ghc.mkVarOcc "unsafeDataAsConstr"))
          (Hs.var srcSpan dVar)

      getFst = Hs.app srcSpan (Hs.var srcSpan (Hs.unqual srcSpan (Ghc.mkVarOcc "fst"))) (Hs.par srcSpan constrExpr)
      getSnd = Hs.app srcSpan (Hs.var srcSpan (Hs.unqual srcSpan (Ghc.mkVarOcc "snd"))) (Hs.par srcSpan constrExpr)

      mkLetFun var rhs =
        Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
          Ghc.FunBind Ghc.noExtField var
            (Hs.mg (Ghc.L srcSpan [Hs.funMatch srcSpan var [] (Common.makeGRHSs srcSpan rhs)]))

      tagBind = mkLetFun tagVar getFst
      argsBind = mkLetFun argsVar getSnd

      letBinds =
        (if needsTag then [tagBind] else [])
          <> (if needsArgs then [argsBind] else [])

      innerBody = case constructors of
        [con] -> applyFn (head contVars) (Constructor.fields con)
        _ -> makeDispatch (zip contVars constructors) [0 ..]

      body =
        if null letBinds
          then innerBody
          else
            Hs.letE srcSpan (Hs.valLocalBinds letBinds) innerBody

      -- (TypeName_BD d_) or (TypeName_BD _) when d_ is unused
      innerPat =
        if null letBinds
          then Ghc.L (Ghc.noAnnSrcSpan srcSpan) $ Ghc.WildPat Ghc.noExtField
          else Hs.varPat srcSpan dVar

      dPat =
        Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
          Ghc.ConPat Ghc.noAnn internalCon (Ghc.PrefixCon [] [innerPat])

      allPats = dPat : fmap (Hs.varPat srcSpan) contVars

   in Ghc.noLocA $ Ghc.ValD Ghc.noExtField $
        Ghc.unLoc (Common.makeLHsBind srcSpan funOcc allPats body)

-- | Wrap an expression with a type annotation: @(expr :: ty)@.
typeAnnotate ::
  Ghc.SrcSpan ->
  Ghc.HsType Ghc.GhcPs ->
  Ghc.LHsExpr Ghc.GhcPs ->
  Ghc.LHsExpr Ghc.GhcPs
typeAnnotate srcSpan ty expr =
  Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
    Ghc.ExprWithTySig Ghc.noAnn expr $
      Ghc.HsWC Ghc.noExtField $
        Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
          Ghc.HsSig Ghc.noExtField Ghc.mkHsOuterImplicit
            (Ghc.L (Ghc.noAnnSrcSpan srcSpan) ty)

-- | Integer overloaded literal.
intLit :: Ghc.SrcSpan -> Integer -> Ghc.LHsExpr Ghc.GhcPs
intLit = Hs.intLit
