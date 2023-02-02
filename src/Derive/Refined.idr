||| This module derives functionality for refinement type. In general,
||| a refinement type is of the following shape:
|||
||| ```idris
||| record Percent where
|||   constructor MkPercent
|||   value : Double
|||   0 prf : IsPercent value
||| ```
|||
||| That is, a value paired with a predicate on that value. The
||| predicate can be an explicit or implicit argument of any
||| quantity.
module Derive.Refined

import public Language.Reflection.Derive

%default total

--------------------------------------------------------------------------------
--          View
--------------------------------------------------------------------------------

||| Proof that a constructor argument `arg` is a dependent type
||| on a second argument of name `name`, that is, `arg` is
||| of type `p nm` for some predicate `p`.
public export
data AppVar : (arg : PArg n) -> (nm : Name) -> Type where
  IsAppVar :
       {0 n1, n2   : Name}
    -> {0 p        : PArg n}
    -> (0 prf : (n1 == n2) === True)
    -> AppVar (PApp p (PVar n2)) n1

||| Tests if `arg` is a dependent type on a value with name `nm`.
public export
appVar : (nm : Name) -> (arg : PArg n) -> Maybe (AppVar arg nm)
appVar nm (PApp p (PVar n2)) with (nm == n2) proof eq
  _ | True  = Just (IsAppVar eq)
  _ | False = Nothing
appVar n1 _                          = Nothing

||| A proof (value of a predicate) in a refined type must be
||| an explicit or auto-implicit argument of that type.
public export
data ProofInfo : PiInfo TTImp -> Type where
  PIAuto     : ProofInfo AutoImplicit
  PIExplicit : ProofInfo ExplicitArg

||| Tests if `pi` explicit or auto-implicit
public export
proofInfo : (pi : PiInfo TTImp) -> Maybe (ProofInfo pi)
proofInfo ExplicitArg  = Just PIExplicit
proofInfo AutoImplicit = Just PIAuto
proofInfo _            = Nothing

||| Proof that the argument list of a data constructor
||| consists of erased implicits followed by a single
||| explicit value, followed by an explicit or auto-implicit
||| predicate on the value.
public export
data RefinedArgs : (args : Vect m (ConArg n)) -> Type where
  RArgs : 
       {0 nm    : Name}
    -> {0 t1,t2 : PArg n}
    -> {0 mn    : Maybe Name}
    -> {0 c     : Count}
    -> {0 pi    : PiInfo TTImp}
    -> ProofInfo pi
    -> AppVar t2 nm
    -> RefinedArgs [CArg (Just nm) MW ExplicitArg t1 , CArg mn c pi t2]
  
  RImplicit : 
       {0 as : _}
    -> {0 t  : TTImp}
    -> {0 ix : Fin n}
    -> RefinedArgs as
    -> RefinedArgs (ParamArg ix t :: as)

||| Tests if the arguments of a data constructor are valid
||| arguments of a refined type.
public export
refinedArgs : (as : Vect m (ConArg n)) -> Maybe (RefinedArgs as)
refinedArgs [CArg (Just n1) MW ExplicitArg _, CArg _ M0 pi t] =
  [| RArgs (proofInfo pi) (appVar n1 t) |]
refinedArgs (ParamArg ix t :: as) = RImplicit <$> refinedArgs as
refinedArgs _ = Nothing

--------------------------------------------------------------------------------
--          fromInteger
--------------------------------------------------------------------------------

||| Extracts the predicate from the constructor of a refined type.
export
proofType :
     Vect n Name
  -> (as : Vect m (ConArg n))
  -> RefinedArgs as
  -> TTImp
proofType ns (_ :: as) (RImplicit x)        = proofType ns as x
proofType ns [_, CArg _ _ _ t2] (RArgs x y) = fromApp t2 y
  where
    fromApp : (t : PArg n) -> AppVar t nm -> TTImp
    fromApp (PApp p _) (IsAppVar _) = ttimp ns p

||| Extracts the predicate from the constructor of a refined type.
export
isErased :
     (as : Vect m (ConArg n))
  -> RefinedArgs as
  -> Bool
isErased (_ :: as) (RImplicit x)        = isErased as x
isErased [_, CArg _ M0 _ _] (RArgs x y) = True
isErased [_, CArg _ _ _ _]  (RArgs x y) = False

||| Extracts the value type from the constructor of a refined type.
export
valType :
     Vect n Name
  -> (as : Vect m (ConArg n))
  -> RefinedArgs as
  -> TTImp
valType ns [CArg _ _ _ t, _] (RArgs x y)   = ttimp ns t
valType ns (_ :: as)         (RImplicit x) = valType ns as x

||| Applies the data constructor of a refinement type to a
||| refined value. We assume that a proof of validity of
||| the correct count is already in scope.
|||
||| In case of an explicit proof argument, we pass the argument
||| by invoking `%search`, in case of an auto-implicit proof argument,
||| proof search will do this for us automatically.
export
appCon : TTImp -> (c : ParamCon n) -> RefinedArgs c.args -> TTImp
appCon t (MkParamCon cn _ as) x = fromArgs (var cn .$ t) as x
  where
    fromArgs : TTImp -> (as : Vect k (ConArg n)) -> RefinedArgs as -> TTImp
    fromArgs s [_, CArg mn c ExplicitArg _]  (RArgs x y)  = s .$ `(%search)
    fromArgs s [_, CArg mn c _ _]            (RArgs x y)  = s
    fromArgs s (ParamArg _ _ :: as)          (RImplicit x) = fromArgs s as x

||| Proof that a data type is a refinement type: A data type with a single
||| data constructor taking an arbitrary number or erased implicit arguments,
||| a single explicit value argument of quantity "any" and an explict or
||| auto-implicit predicate on the value.
public export
data RefinedInfo : ParamTypeInfo -> Type where
  RI : 
       {0 c : ParamCon n}
    -> RefinedArgs c.args
    -> RefinedInfo (MkParamTypeInfo ti p ns [c] s)

export
refinedInfo : (p : ParamTypeInfo) -> Res (RefinedInfo p)
refinedInfo (MkParamTypeInfo t _ _ [c] _) = case refinedArgs c.args of
  Just x  => Right (RI x)
  Nothing => Left "\{t.name} is not a refinement type with an explicit or auto-implicit proof"
refinedInfo p = Left "\{p.getName} is not a single-constructor data type"

||| Function for refining a value at runtime. This returns a `Maybe` of
||| the refinement type.
export
refineClaim : (fun : Name) -> (p : ParamTypeInfo) -> RefinedInfo p -> Decl
refineClaim fun (MkParamTypeInfo ti p ns [c] s) (RI x) =
  let res  := `(Maybe ~(ti.applied))
      vtpe := valType ns c.args x
      tpe  := piAll `(~(vtpe) -> ~(res)) ti.implicits
   in public' fun tpe

export
refineDef : (fun : Name) -> (p : ParamTypeInfo) -> RefinedInfo p -> Decl
refineDef fun (MkParamTypeInfo ti p ns [c] s) (RI x) =
  let prf  := proofType ns c.args x
      v    := varStr "v"
      lhs  := var fun .$ v
      rhs0 := `(case hdec0 {p = ~(proofType ns c.args x)} ~(v) of
                     Just0 _   => Just $ ~(appCon v c x)
                     Nothing0  => Nothing)
      rhs  := `(case hdec {p = ~(proofType ns c.args x)} ~(v) of
                     Just _   => Just $ ~(appCon v c x)
                     Nothing  => Nothing)
   in def fun [lhs .= if isErased c.args x then rhs0 else rhs]

export
refineTL : (fun : Name) -> (p : ParamTypeInfo) -> RefinedInfo p -> TopLevel
refineTL fun p x = TL (refineClaim fun p x) (refineDef fun p x)

export
fromIntTL : (refine : Name) -> (p : ParamTypeInfo) -> RefinedInfo p -> TopLevel
fromIntTL r p _ =
  let arg  := p.applied
      vr   := var r
      fun  := the Name "fromInteger"
      pi   := `((n : Integer) -> {auto 0 _ : IsJust (~(vr) $ fromInteger n)} -> ~(arg))
      tpe  := piAll pi (allImplicits p "Num")
      df   := def fun [ var fun .$ `(n) .= `(fromJust $ ~(vr) (fromInteger n)) ]
   in TL (public' fun tpe) df

export
fromDblTL : (refine : Name) -> (p : ParamTypeInfo) -> RefinedInfo p -> TopLevel
fromDblTL r p _ =
  let arg  := p.applied
      vr   := var r
      fun  := the Name "fromDouble"
      pi   := `((n : Double) -> {auto 0 _ : IsJust (~(vr) $ fromDouble n)} -> ~(arg))
      tpe  := piAll pi (allImplicits p "FromDouble")
      df   := def fun [ var fun .$ `(n) .= `(fromJust $ ~(vr) (fromDouble n)) ]
   in TL (public' fun tpe) df

export
fromStrTL : (refine : Name) -> (p : ParamTypeInfo) -> RefinedInfo p -> TopLevel
fromStrTL r p _ =
  let arg  := p.applied
      vr   := var r
      fun  := the Name "fromString"
      pi   := `((n : String) -> {auto 0 _ : IsJust (~(vr) $ fromString n)} -> ~(arg))
      tpe  := piAll pi (allImplicits p "FromString")
      df   := def fun [ var fun .$ `(n) .= `(fromJust $ ~(vr) (fromString n)) ]
   in TL (public' fun tpe) df

--------------------------------------------------------------------------------
--          Derive
--------------------------------------------------------------------------------

export %inline
refineName : Named a => a -> Name
refineName v = funName v "refine"

export %inline
Refined : List Name -> ParamTypeInfo -> Res (List TopLevel)
Refined nms p = map (pure . refineTL (refineName p) p) $ refinedInfo p

export %inline
RefinedInteger : List Name -> ParamTypeInfo -> Res (List TopLevel)
RefinedInteger nms p = map decls $ refinedInfo p
  where
    decls : RefinedInfo p -> List TopLevel
    decls x =
      let fun := refineName p
       in [ refineTL fun p x, fromIntTL fun p x ]

export %inline
RefinedDouble : List Name -> ParamTypeInfo -> Res (List TopLevel)
RefinedDouble nms p = map decls $ refinedInfo p
  where
    decls : RefinedInfo p -> List TopLevel
    decls x =
      let fun := refineName p
       in [ refineTL fun p x, fromIntTL fun p x, fromDblTL fun p x ]

export %inline
RefinedString : List Name -> ParamTypeInfo -> Res (List TopLevel)
RefinedString nms p = map decls $ refinedInfo p
  where
    decls : RefinedInfo p -> List TopLevel
    decls x =
      let fun := refineName p
       in [ refineTL fun p x, fromStrTL fun p x ]
