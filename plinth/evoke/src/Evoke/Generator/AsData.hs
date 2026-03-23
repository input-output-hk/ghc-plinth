module Evoke.Generator.AsData
  ( generate,
  )
where

import qualified Data.List as List
import qualified Evoke.Constant.Module as Module
import qualified Evoke.Generator.Common as Common
import qualified Evoke.Hs as Hs
import qualified Evoke.Hsc as Hsc
import qualified Evoke.Type.Constructor as Constructor
import qualified Evoke.Type.Field as Field
import qualified Evoke.Type.Type as Type
import qualified GHC.Hs as Ghc
import qualified GHC.Data.Bag as Bag
import qualified GHC.Plugins as Ghc
import qualified GHC.Types.Fixity as Ghc
import qualified GHC.Types.SourceText as Ghc

-- | Replaces the original data declaration with a newtype backed by
-- 'BuiltinData', generates bidirectional pattern synonyms for each
-- constructor, and derives 'ToData'/'FromData' via GND.
--
-- Given:
--
-- > data Example a = Ex1 Integer | Ex2 a a
-- >   deriving AsData via "Evoke AsData"
--
-- Generates:
--
-- > newtype Example a = Example_BD PlutusTx.Builtins.BuiltinData
-- >   deriving newtype (PlutusTx.ToData, PlutusTx.FromData)
-- >
-- > pattern Ex1 :: Integer -> Example a
-- > pattern Ex1 x0_ <-
-- >   Example_BD ((\d_ -> PlutusTx.unsafeFromBuiltinData
-- >     (PlutusTx.headBuiltinList (PlutusTx.sndPair (PlutusTx.unsafeDataAsConstr d_)))) -> x0_)
-- >   where Ex1 x0_ = Example_BD (PlutusTx.mkConstr 0 [PlutusTx.toBuiltinData x0_])
-- >
-- > pattern Ex2 :: a -> a -> Example a
-- > pattern Ex2 x0_ x1_ <-
-- >   Example_BD ((\d_ -> let args_ = PlutusTx.sndPair (PlutusTx.unsafeDataAsConstr d_)
-- >                        in (PlutusTx.unsafeFromBuiltinData (PlutusTx.headBuiltinList args_),
-- >                            ...)) -> (x0_, x1_))
-- >   where Ex2 x0_ x1_ = Example_BD (PlutusTx.mkConstr 1 [...])
-- >
-- > {-# COMPLETE Ex1, Ex2 #-}
generate :: Ghc.HsDeriving Ghc.GhcPs -> Common.Generator
generate remainingDerivs _moduleName lIdP lHsQTyVars lConDecls _options srcSpan = do
  type_ <- Type.make lIdP lHsQTyVars lConDecls srcSpan
  let constructors = Type.constructors type_
  when (null constructors) $
    Hsc.throwError srcSpan $ Ghc.text "AsData requires at least one constructor"

  plutusTx <- Common.makeRandomModule Module.plutusTx
  plutusTxBuiltins <- Common.makeRandomModule Module.plutusTxBuiltins

  let lImportDecls =
        Hs.importDecls
          srcSpan
          [ (Module.plutusTx, plutusTx),
            (Module.plutusTxBuiltins, plutusTxBuiltins)
          ]

      newtypeDecl =
        makeNewtypeDecl srcSpan type_ plutusTx plutusTxBuiltins remainingDerivs

      completeDecl =
        makeCompleteDecl srcSpan constructors

  patSynDecls <-
    mapM
      (\(idx, con) -> makePatSynDecl srcSpan type_ con idx plutusTx plutusTxBuiltins)
      (zip [0 ..] constructors)

  pure (True, lImportDecls, newtypeDecl : patSynDecls <> [completeDecl])

when :: Applicative f => Bool -> f () -> f ()
when True action = action
when False _ = pure ()

-- | The internal constructor name for the newtype.
internalConName :: Type.Type -> Ghc.OccName
internalConName type_ =
  Ghc.mkDataOcc $
    Ghc.occNameString (Ghc.rdrNameOcc (Type.name type_)) <> "_BD"

-- | Generate: @newtype Example a = Example_BD BuiltinData@
-- @  deriving newtype (ToData, FromData)@
makeNewtypeDecl ::
  Ghc.SrcSpan ->
  Type.Type ->
  Ghc.ModuleName ->
  Ghc.ModuleName ->
  Ghc.HsDeriving Ghc.GhcPs ->
  Ghc.LHsDecl Ghc.GhcPs
makeNewtypeDecl srcSpan type_ plutusTx plutusTxBuiltins remainingDerivs =
  let tyName = Ghc.rdrNameOcc $ Type.name type_
      lTypeName = Ghc.noLocA $ Ghc.mkRdrUnqual tyName
      lConName = Ghc.noLocA $ Ghc.mkRdrUnqual (internalConName type_)

      builtinDataTy =
        Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
          Ghc.HsTyVar
            Ghc.noAnn
            Ghc.NotPromoted
            (Ghc.L (Ghc.noAnnSrcSpan srcSpan) $ Ghc.Qual plutusTxBuiltins (Ghc.mkTcOcc "BuiltinData"))

      conDecl =
        Ghc.noLocA $
          Ghc.ConDeclH98
            { Ghc.con_ext = Ghc.noAnn,
              Ghc.con_name = lConName,
              Ghc.con_forall = False,
              Ghc.con_ex_tvs = [],
              Ghc.con_mb_cxt = Nothing,
              Ghc.con_args =
                Ghc.PrefixCon
                  []
                  [Ghc.HsScaled (Ghc.HsUnrestrictedArrow (Ghc.noHsUniTok)) builtinDataTy],
              Ghc.con_doc = Nothing
            }

      -- deriving newtype (ToData, FromData) plus any remaining clauses
      gndClause = makeGndClause srcSpan plutusTx
      derivs = gndClause : remainingDerivs

      dataDefn =
        Ghc.HsDataDefn
          { Ghc.dd_ext = Ghc.noExtField,
            Ghc.dd_ctxt = Nothing,
            Ghc.dd_cType = Nothing,
            Ghc.dd_kindSig = Nothing,
            Ghc.dd_cons = Ghc.NewTypeCon conDecl,
            Ghc.dd_derivs = derivs
          }

      -- Preserve type variables from the original type
      tyVars = mkTyVars srcSpan (Type.variables type_)

      tyClDecl =
        Ghc.DataDecl
          { Ghc.tcdDExt = Ghc.noAnn,
            Ghc.tcdLName = lTypeName,
            Ghc.tcdTyVars = tyVars,
            Ghc.tcdFixity = Ghc.Prefix,
            Ghc.tcdDataDefn = dataDefn
          }
   in Ghc.noLocA (Ghc.TyClD Ghc.noExtField tyClDecl)

-- | Build @deriving newtype (PlutusTx.ToData, PlutusTx.FromData)@.
makeGndClause ::
  Ghc.SrcSpan ->
  Ghc.ModuleName ->
  Ghc.LHsDerivingClause Ghc.GhcPs
makeGndClause srcSpan plutusTx =
  let strategy =
        Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
          Ghc.NewtypeStrategy Ghc.noAnn

      mkCls occ =
        Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
          Ghc.HsSig
            Ghc.noExtField
            Ghc.mkHsOuterImplicit
            ( Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
                Ghc.HsTyVar
                  Ghc.noAnn
                  Ghc.NotPromoted
                  (Ghc.L (Ghc.noAnnSrcSpan srcSpan) $ Ghc.Qual plutusTx occ)
            )

      tys =
        Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
          Ghc.DctMulti Ghc.noExtField [mkCls (Ghc.mkClsOcc "ToData"), mkCls (Ghc.mkClsOcc "FromData"), mkCls (Ghc.mkClsOcc "UnsafeFromData")]
   in Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
        Ghc.HsDerivingClause Ghc.noAnn (Just strategy) tys

-- | Build @{-# COMPLETE Ex1, Ex2 #-}@.
makeCompleteDecl ::
  Ghc.SrcSpan ->
  [Constructor.Constructor] ->
  Ghc.LHsDecl Ghc.GhcPs
makeCompleteDecl srcSpan constructors =
  let conNames =
        fmap
          (Ghc.L (Ghc.noAnnSrcSpan srcSpan) . Ghc.mkRdrUnqual . Ghc.rdrNameOcc . Constructor.name)
          constructors
   in Ghc.noLocA . Ghc.SigD Ghc.noExtField $
        Ghc.CompleteMatchSig
          (Ghc.noAnn, Ghc.NoSourceText)
          (Ghc.L srcSpan conNames)
          Nothing

-- | Generate the bidirectional pattern synonym for one constructor.
makePatSynDecl ::
  Ghc.SrcSpan ->
  Type.Type ->
  Constructor.Constructor ->
  Integer ->
  Ghc.ModuleName ->
  Ghc.ModuleName ->
  Ghc.Hsc (Ghc.LHsDecl Ghc.GhcPs)
makePatSynDecl srcSpan type_ constructor idx plutusTx plutusTxBuiltins = do
  let fields = Constructor.fields constructor
      arity = length fields

  vars <- mapM (\_ -> Common.makeRandomVariable srcSpan "x_") fields
  dVar <- Common.makeRandomVariable srcSpan "d_"
  tagVar <- Common.makeRandomVariable srcSpan "tag_"
  argsVar <- Common.makeRandomVariable srcSpan "args_"

  let conRdrName = Constructor.name constructor
      lConName = Ghc.L (Ghc.noAnnSrcSpan srcSpan) $ Ghc.mkRdrUnqual (Ghc.rdrNameOcc conRdrName)
      internalCon = Ghc.L (Ghc.noAnnSrcSpan srcSpan) $ Ghc.mkRdrUnqual (internalConName type_)

      -- The "where" (builder) body:
      -- Example_BD (mkConstr idx [toBuiltinData (x0_ :: T0), ...])
      encodeArgs =
        fmap
          ( \(v, field) ->
              Hs.app
                srcSpan
                (Hs.qualVar srcSpan plutusTx (Ghc.mkVarOcc "toBuiltinData"))
                -- type annotation so GHC can resolve ToData instance
                (Hs.par srcSpan $ typeAnnotate srcSpan (Field.type_ field) (Hs.var srcSpan v))
          )
          (zip vars fields)

      builderBody =
        Hs.app
          srcSpan
          ( Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
              Ghc.HsVar Ghc.noExtField internalCon
          )
          ( Hs.par srcSpan $
              Hs.app
                srcSpan
                ( Hs.app
                    srcSpan
                    (Hs.qualVar srcSpan plutusTxBuiltins (Ghc.mkVarOcc "mkConstr"))
                    (intLit srcSpan idx)
                )
                (Hs.explicitList srcSpan encodeArgs)
          )

      -- The match (destructor) pattern uses a view pattern:
      -- Example_BD (viewFn -> matchPat)
      viewFn = makeViewFn srcSpan fields idx dVar tagVar argsVar plutusTx plutusTxBuiltins
      matchPat = makeMatchPat srcSpan arity vars

      matchPat' =
        Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
          Ghc.ConPat
            Ghc.noAnn
            internalCon
            ( Ghc.PrefixCon
                []
                [ Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
                    Ghc.ViewPat Ghc.noAnn viewFn matchPat
                ]
            )

      -- pattern synonym args
      patArgs = Ghc.PrefixCon [] vars

      -- The explicit bidirectional direction
      builderMatch =
        Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
          Ghc.Match
            Ghc.noAnn
            (Ghc.FunRhs lConName Ghc.Prefix Ghc.NoSrcStrict)
            (fmap (Hs.varPat srcSpan) vars)
            (Common.makeGRHSs srcSpan builderBody)

      patSynBind =
        Ghc.PatSynBind Ghc.noExtField $
          Ghc.PSB
            { Ghc.psb_ext = Ghc.noAnn,
              Ghc.psb_id = lConName,
              Ghc.psb_args = patArgs,
              Ghc.psb_def = matchPat',
              Ghc.psb_dir = Ghc.ExplicitBidirectional $
                Ghc.MG
                  Ghc.Generated
                  (Ghc.L (Ghc.noAnnSrcSpan srcSpan) [builderMatch])
            }

  pure $
    Ghc.noLocA $
      Ghc.ValD Ghc.noExtField patSynBind

-- | Wrap an expression with a type annotation: @(expr :: ty)@.
typeAnnotate ::
  Ghc.SrcSpan ->
  Ghc.HsType Ghc.GhcPs ->
  Ghc.LHsExpr Ghc.GhcPs ->
  Ghc.LHsExpr Ghc.GhcPs
typeAnnotate srcSpan ty expr =
  Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
    Ghc.ExprWithTySig
      Ghc.noAnn
      expr
      ( Ghc.HsWC Ghc.noExtField $
          Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
            Ghc.HsSig
              Ghc.noExtField
              Ghc.mkHsOuterImplicit
              (Ghc.L (Ghc.noAnnSrcSpan srcSpan) ty)
      )

-- | Build the view function for deconstruction.
--
-- Always checks the constructor tag; returns @Maybe@ so GHC can try the
-- next pattern alternative if the tag doesn't match:
--
-- @\d_ -> let tag_ = fst (unsafeDataAsConstr d_)
--              args_ = snd (unsafeDataAsConstr d_)
--          in if tag_ == idx then Just \<result\> else Nothing@
--
-- @\<result\>@ is @()@ for nullary constructors, @(x :: T)@ for arity-1,
-- or a tuple for higher arities.
makeViewFn ::
  Ghc.SrcSpan ->
  [Field.Field] ->
  Integer ->
  Ghc.LIdP Ghc.GhcPs ->
  Ghc.LIdP Ghc.GhcPs ->
  Ghc.LIdP Ghc.GhcPs ->
  Ghc.ModuleName ->
  Ghc.ModuleName ->
  Ghc.LHsExpr Ghc.GhcPs
makeViewFn srcSpan fields idx dVar tagVar argsVar plutusTx plutusTxBuiltins =
  let ptx = Hs.qualVar srcSpan plutusTx
      blt = Hs.qualVar srcSpan plutusTxBuiltins
      arity = length fields

      -- fst / snd (unsafeDataAsConstr d_)
      constrExpr =
        Hs.app srcSpan
          (blt (Ghc.mkVarOcc "unsafeDataAsConstr"))
          (Hs.var srcSpan dVar)

      getFst = Hs.app srcSpan (Hs.var srcSpan (Hs.unqual srcSpan (Ghc.mkVarOcc "fst"))) (Hs.par srcSpan constrExpr)
      getSnd = Hs.app srcSpan (Hs.var srcSpan (Hs.unqual srcSpan (Ghc.mkVarOcc "snd"))) (Hs.par srcSpan constrExpr)

      -- helper: 0-arg let binding  var = rhs
      mkLetFun var rhs =
        Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
          Ghc.FunBind Ghc.noExtField var
            ( Ghc.MG Ghc.Generated
                ( Ghc.L (Ghc.noAnnSrcSpan srcSpan)
                    [ Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
                        Ghc.Match Ghc.noAnn
                          (Ghc.FunRhs var Ghc.Prefix Ghc.NoSrcStrict)
                          []
                          (Common.makeGRHSs srcSpan rhs)
                    ]
                )
            )

      tagBind = mkLetFun tagVar getFst
      argsBind = mkLetFun argsVar getSnd

      -- head (tail^n argsVar)
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

      -- (unsafeFromBuiltinData e) :: fieldType
      decode fieldType e =
        typeAnnotate srcSpan fieldType $
          Hs.app srcSpan
            (ptx (Ghc.mkVarOcc "unsafeFromBuiltinData"))
            (Hs.par srcSpan e)

      -- value to wrap in Just
      inner = case arity of
        0 ->
          Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
            Ghc.ExplicitTuple Ghc.noAnn [] Ghc.Boxed
        1 ->
          decode (Field.type_ (head fields)) (nthElem 0)
        _ ->
          let elems = fmap (\(n, f) -> decode (Field.type_ f) (nthElem n)) (zip [0 ..] fields)
           in Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
                Ghc.ExplicitTuple Ghc.noAnn (fmap Hs.tupArg elems) Ghc.Boxed

      justInner =
        Hs.app srcSpan
          (Hs.var srcSpan (Hs.unqual srcSpan (Ghc.mkDataOcc "Just")))
          (Hs.par srcSpan inner)

      nothingExpr =
        Hs.var srcSpan (Hs.unqual srcSpan (Ghc.mkDataOcc "Nothing"))

      -- tagVar == idx
      cond =
        Hs.opApp srcSpan
          (Hs.var srcSpan tagVar)
          (Hs.var srcSpan (Hs.unqual srcSpan (Ghc.mkVarOcc "==")))
          (intLit srcSpan idx)

      ifExpr =
        Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
          Ghc.HsIf Ghc.noAnn cond justInner nothingExpr

      -- omit argsBind for nullary constructors (avoid unused-variable warning)
      letBinds = if arity == 0 then [tagBind] else [tagBind, argsBind]

      body =
        Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
          Ghc.HsLet
            Ghc.noAnn
            Ghc.noHsTok
            (Ghc.HsValBinds Ghc.noAnn (Ghc.ValBinds Ghc.NoAnnSortKey (Bag.listToBag letBinds) []))
            Ghc.noHsTok
            ifExpr
   in Hs.lam srcSpan . Hs.mg $
        Ghc.L srcSpan
          [ Hs.match srcSpan Ghc.LambdaExpr
              [Hs.varPat srcSpan dVar]
              (Common.makeGRHSs srcSpan body)
          ]

-- | Build the match pattern for the view result.
-- Always wrapped in @Just@: nullary → @Just ()@, arity 1 → @Just x0_@,
-- arity n → @Just (x0_, x1_, ...)@
makeMatchPat ::
  Ghc.SrcSpan ->
  Int ->
  [Ghc.LIdP Ghc.GhcPs] ->
  Ghc.LPat Ghc.GhcPs
makeMatchPat srcSpan arity vars =
  let inner = case arity of
        0 ->
          Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
            Ghc.TuplePat Ghc.noAnn [] Ghc.Boxed
        1 ->
          Hs.varPat srcSpan (head vars)
        _ ->
          Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
            Ghc.TuplePat Ghc.noAnn (fmap (Hs.varPat srcSpan) vars) Ghc.Boxed
   in Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
        Ghc.ConPat Ghc.noAnn
          (Ghc.L (Ghc.noAnnSrcSpan srcSpan) (Ghc.mkRdrUnqual (Ghc.mkDataOcc "Just")))
          (Ghc.PrefixCon [] [inner])

-- | Rebuild 'LHsQTyVars' from the type variable 'RdrName's.
mkTyVars :: Ghc.SrcSpan -> [Ghc.IdP Ghc.GhcPs] -> Ghc.LHsQTyVars Ghc.GhcPs
mkTyVars srcSpan vars =
  Ghc.HsQTvs Ghc.noExtField $
    fmap
      ( \v ->
          Ghc.L (Ghc.noAnnSrcSpan srcSpan) $
            Ghc.UserTyVar Ghc.noAnn () (Ghc.L (Ghc.noAnnSrcSpan srcSpan) v)
      )
      vars

-- | Integer overloaded literal.
intLit :: Ghc.SrcSpan -> Integer -> Ghc.LHsExpr Ghc.GhcPs
intLit s n =
  Ghc.L (Ghc.noAnnSrcSpan s) $
    Ghc.HsOverLit Ghc.noAnn $
      Ghc.OverLit Ghc.noExtField (Ghc.HsIntegral (Ghc.IL Ghc.NoSourceText False n))

