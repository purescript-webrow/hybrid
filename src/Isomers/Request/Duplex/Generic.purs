module Isomers.Request.Duplex.Generic where

import Prelude

import Data.Symbol (class IsSymbol)
import Data.Variant (Variant)
import Data.Variant (inj) as Variant
import Heterogeneous.Folding (class FoldingWithIndex, class HFoldlWithIndex, hfoldlWithIndex)
import Heterogeneous.Mapping (class HMapWithIndex, class MappingWithIndex, hmapWithIndex)
import Isomers.HTTP.Request (Method(..)) as Request
import Isomers.HTTP.Request.Method (toHTTPMethod)
import Isomers.Request.Duplex.Type (Duplex, prefix)
import Isomers.Request.Duplex.Type (withMethod) as Type
import Isomers.Request.Duplex.Variant (empty) as Request.Duplex.Variant
import Isomers.Request.Duplex.Variant (injInto)
import Prim.Row (class Cons, class Union) as Row
import Type.Prelude (SProxy, reflectSymbol)

newtype VariantStep = VariantStep (∀ body i o s. IsSymbol s ⇒ SProxy s → Duplex body i o → Duplex body i o)

-- | Fold over a record with duplexes and build duplex
-- | for a variant.
instance foldingVariantStepDuplex ∷
  ( Row.Cons l o () lo
  , Row.Union vo lo vo'
  , Row.Cons l o vo vo'
  , Row.Cons l i vi vi'
  , IsSymbol l
  ) ⇒
  FoldingWithIndex VariantStep (SProxy l) (Duplex body (Variant vi) (Variant vo)) (Duplex body i o) (Duplex body (Variant vi') (Variant vo')) where
  foldingWithIndex (VariantStep step) l vd d = do
    let
      f = injInto l <<< step l
    f d vd

-- | Just an alias
class HFoldlWithIndex VariantStep (Duplex body (Variant ()) (Variant ())) rec (Duplex body (Variant i) (Variant o)) <= HFoldlVariantStep body rec (i ∷ # Type) (o ∷ # Type)
instance hfoldlVariantStep ∷ (HFoldlWithIndex VariantStep (Duplex body (Variant ()) (Variant ())) rec (Duplex body (Variant i) (Variant o))) ⇒ HFoldlVariantStep body rec i o

type PrefixRoutes = Boolean

variant ∷ ∀ body vi vo rec.
  HFoldlVariantStep body rec vi vo ⇒
  PrefixRoutes →
  rec →
  Duplex body (Variant vi) (Variant vo)
variant prefixRoutes rec = do
  hfoldlWithIndex (VariantStep step) (Request.Duplex.Variant.empty ∷ Duplex body _ _) rec
  where
    step ∷ ∀ si so sb ss. IsSymbol ss ⇒ SProxy ss → Duplex sb si so → Duplex sb si so
    step l = if prefixRoutes
      then
        prefix (reflectSymbol l)
      else
        identity


-- | TODO: I'm not sure if this record based encoding related
-- | stuff should reside here or rather in `Isomers.Spec`.
-- |
-- | It seems that `VariantStep` function is not enough because
-- | we have to restrict symbols which we accept in the
-- | processing function.
data MethodStep = MethodStep

instance mappingMethodStep ∷
  (IsSymbol l, Row.Cons l Unit ms ("DELETE" :: Unit , "POST" :: Unit, "PUT" :: Unit, "GET" ∷ Unit))
  ⇒ MappingWithIndex MethodStep (SProxy l) (Duplex body i o) (Duplex body i o) where
  mappingWithIndex _ l v = Type.withMethod (toHTTPMethod m) v
    where
      m ∷ Request.Method (Variant ("DELETE" :: Unit , "POST" :: Unit, "PUT" :: Unit, "GET" ∷ Unit))
      m = Request.Method (Variant.inj l unit)


byMethod ∷ ∀ body vi vo rec rec'.
  HMapWithIndex MethodStep rec rec' ⇒
  HFoldlVariantStep body rec' vi vo ⇒
  rec →
  Duplex body (Variant vi) (Variant vo)
byMethod rec = do
  let
    rec' = hmapWithIndex MethodStep rec
  hfoldlWithIndex (VariantStep (const $ identity)) (Request.Duplex.Variant.empty ∷ Duplex body _ _) rec'

