module Isomers.Web.Builder where

import Prelude

import Data.Tuple.Nested ((/\), type (/\))
import Heterogeneous.Folding (class Folding, class HFoldl, hfoldl)
import Heterogeneous.Mapping (class Mapping, class MappingWithIndex)
import Isomers.Contrib (HJust(..)) as Contrib
import Isomers.Contrib.Heterogeneous.Filtering (CatMaybes(..))
import Isomers.Contrib.Heterogeneous.HEval (class HEval, DoApply(..), DoConst(..), DoHFilter(..), DoHIfThenElse(..), DoHMap(..), DoHMapWithIndex(..), DoIdentity(..), heval)
import Isomers.Contrib.Heterogeneous.HEval (type (<<<), (<<<), type (&&&), (&&&)) as H
import Isomers.Contrib.Heterogeneous.HMaybe (HJust(..), HNothing(..))
import Isomers.Contrib.Heterogeneous.List (type (:), (:))
import Isomers.Contrib.Type.Equality (class TypeEquals')
import Isomers.Contrib.Type.Equality (to') as Isomers.Contrib.Type.Equality
import Isomers.HTTP (Exchange) as HTTP
import Isomers.HTTP.ContentTypes (HtmlMime)
import Isomers.HTTP.Request.Method (Method(..))
import Isomers.Request (Accum) as Request
import Isomers.Request.Accum (insertReq) as Request.Accum
import Isomers.Response (Duplex, RawDuplex') as Response
import Isomers.Response.Raw.Duplexes (html) as Response.Raw.Duplexes
import Isomers.Response.Types (HtmlString)
import Isomers.Spec (BuilderStep, WithBody(..), accumSpec)
import Isomers.Spec (class Builder, AccumSpec, BuilderStep(..), Insert(..), Scalar(..), accumSpec) as Spec
import Isomers.Spec.Builder (Pass, pass)
import Isomers.Web.Builder.HEval (DoIsHJust(..), DoNull(..), FromHJust(..))
import Isomers.Web.Renderer (Renderer(..))
import Isomers.Web.Types (AccumWebSpec(..), GetRender, GetSpec, WebSpec(..), _GetRender, _GetSpec, rootAccumWebSpec)
import Prim.Row (class Cons, class Lacks) as Row
import Record.Extra (type (:::), SCons, SLProxy(..), SNil, kind SList)
import Type.Equality (to) as Type.Equality
import Type.Prelude (class IsSymbol, class TypeEquals, BProxy, SProxy(..))

data WebBuilderStep (debugPath ∷ SList) route = WebBuilderStep

toBuilderStep ∷ ∀ debugPath route. WebBuilderStep debugPath route → Spec.BuilderStep route
toBuilderStep _ = Spec.BuilderStep

class Builder (debugPath ∷ SList) a (body ∷ # Type) rnd route ireq oreq res | a route → body rnd ireq oreq res where
  accumWebSpec ∷ WebBuilderStep debugPath route → a → AccumWebSpec body rnd route ireq oreq res

data Rendered resDpl rnd
  = Rendered resDpl rnd

newtype Tagged (tag ∷ Symbol) a
  = Tagged a

-- | From list of responses we extract a pair
-- | which defines response duplex and renderer.
data ResponseRenderer (debugPath ∷ SList) ireq oreq = ResponseRenderer

-- | We unify requests in the case of rendered endpoints
-- | just for simplicity now (we don't need to carry two
-- | sets of renderers in the final spec).
-- | As a first attempt I'm going to use iso renderers
-- | in a pure "GET" setup (only for initial renders)
-- | so this limitation is a not real problem for me.
-- |
-- | There is no real rationale for this restriction
-- | though and maybe there are "fully iso" scenarios when
-- | such a case is desired. In such a case... please provide
-- | a PR :-P
instance foldingExtractRenderMatch ∷
  ( TypeEquals ireq oreq
  , TypeEquals ireq req
  , TypeEquals ires res
  , TypeEquals' rnd ((router /\ HTTP.Exchange ireq ires) → doc) ("foldingExtractRenderMatch:" ::: debugPath)
  ) ⇒
  Folding
    (ResponseRenderer debugPath ireq oreq)
    acc
    (Rendered (Response.Duplex ct ires ores) rnd)
    (Contrib.HJust (Tagged ct (Renderer router ireq ires doc))) where
  folding _ _ (Rendered dpl rnd) = Contrib.HJust (Tagged (Renderer $ Isomers.Contrib.Type.Equality.to' (SLProxy ∷ SLProxy ("foldingExtractRenderMatch:" ::: debugPath)) rnd))
else instance foldingExtractRenderNoMatch ∷
  Folding
    (ResponseRenderer debugPath ireq oreq)
    acc
    resDpl
    acc where
  folding _ acc _ = acc

-- | Drop rendering function from hlist of response duplexes.
data DropRender
  = DropRender

instance mappingDropRenderMatch ∷ Mapping DropRender (Rendered resDpl rnd) resDpl where
  mapping _ (Rendered resDpl rnd) = resDpl
else instance mappingDropRenderNoMatch ∷ Mapping DropRender resDpl resDpl where
  mapping _ resDpl = resDpl

data DoBuildAccumSpec route
  = DoBuildAccumSpec (BuilderStep route)

instance hevalDoBuildAccumSpec ∷
  (Spec.Builder a body route ireq oreq res) ⇒
  HEval (DoBuildAccumSpec route) (a → Spec.AccumSpec body route ireq oreq res) where
  heval (DoBuildAccumSpec step) i = Spec.accumSpec step i

-- | I'm handling this manually so I can recurse and
-- | handle other cases like `Rendered` separately.
instance builderWithBodyEndpoint ∷
  ( Row.Cons l i route ireq
  , Row.Cons l o route oreq
  , Row.Lacks l route
  , IsSymbol l
  , Builder ("WithBody" ::: debugPath) (Request.Accum body { | route } { | ireq } { | oreq } /\ res) body rnd { | route } { | ireq } { | oreq } res'
  ) ⇒ Builder debugPath (WithBody l body i o /\ res) body rnd { | route } { | ireq } { | oreq } res' where
  accumWebSpec _ ((WithBody dpl) /\ res) = do
    let
      s' = WebBuilderStep ∷ WebBuilderStep ("WithBody" ::: debugPath) { | route }
      req = Request.Accum.insertReq (SProxy ∷ SProxy l) dpl
    accumWebSpec s' (req /\ res ∷ Request.Accum body { | route } { | ireq } { | oreq } /\ res)
-- | I extract `ireq_`, `oreq_` from req to be able
-- | to construct the type of the `Renderer` because
-- | we pass a non mime `req_` to it finally: `HTTP.Exchange req_ ... → ...`.
-- | The unification of `ireq_` and `oreq_` is done when
-- | we find a renderer somewhere on the stack.
else instance builderEndpoinsAccessList ∷
  ( HFoldl (ResponseRenderer debugPath ireq_ oreq_) HNothing l rnd
  , TypeEquals (h : t) l
  , HEval DoIsHJust (rnd → BProxy hasRender)
  , TypeEquals req (Request.Accum b route_ ireq_ oreq_)
  , Spec.Builder (req /\ l'') b route ireq oreq res'
  , HEval
      ( DoBuildAccumSpec route
          H.<<< DoApply (l'' → req /\ l'')
          H.<<< DoHIfThenElse (DoConst (BProxy hasRender)) (DoApply (l' → Response.RawDuplex' HtmlMime HtmlString : l')) DoIdentity
          H.<<< DoHMap DropRender
      )
      (l → Spec.AccumSpec b route ireq oreq res')
  ) ⇒
  Builder debugPath (req /\ (h : t)) b rnd route ireq oreq res' where
  accumWebSpec step (req /\ (h : t)) = do
    let
      -- | I'm using this `l` alias
      l  = Type.Equality.to (h : t)
      render = hfoldl (ResponseRenderer ∷ ResponseRenderer debugPath ireq_ oreq_) HNothing l

      hasRender = heval DoIsHJust render

      spec =
        heval
          ( DoBuildAccumSpec (toBuilderStep step)
              H.<<< DoApply ((req /\ _) ∷ l'' → req /\ l'')
              H.<<< DoHIfThenElse (DoConst hasRender) (DoApply ((Response.Raw.Duplexes.html : _) ∷ l' → _ : l')) DoIdentity
              H.<<< DoHMap DropRender
          )
          l
    AccumWebSpec { render, spec }

else instance builderPlainEndpoint ∷
  ( Spec.Builder (a /\ d) body route ireq oreq res) ⇒
  Builder debugPath (a /\ d) body HNothing route ireq oreq res where
  accumWebSpec step t = AccumWebSpec { spec: accumSpec (toBuilderStep step) t, render: HNothing }

instance builderPlainResponseEndpoint ∷
  (Builder ("Pass" ::: debugPath) (Pass body route /\ Response.Duplex ct ires ores) body rnd route ireq oreq res) ⇒
  Builder debugPath (Response.Duplex ct ires ores) body rnd route ireq oreq res where
  accumWebSpec WebBuilderStep response = accumWebSpec (WebBuilderStep ∷ WebBuilderStep ("Pass" ::: debugPath) route) ((pass /\ response) ∷ (Pass body route /\ Response.Duplex ct ires ores))

instance builderResponseHListEndpoint ∷
  (Builder ("Pass" ::: debugPath) (Pass body route /\ (h : t)) body rnd route ireq oreq res) ⇒
  Builder debugPath ((h : t)) body rnd route ireq oreq res where
  accumWebSpec WebBuilderStep response = accumWebSpec (WebBuilderStep ∷ WebBuilderStep ("Pass" ::: debugPath) route) ((pass /\ response) ∷ (Pass body route /\ (h : t)))

instance builderSpec ∷
  Builder debugPath (AccumWebSpec b rnd route ireq oreq res) b rnd route ireq oreq res where
  accumWebSpec _ s = s

type DoFoldRender a
  = ( DoHIfThenElse DoNull (DoConst HNothing) (DoApply (a → HJust a))
        H.<<< DoHMap FromHJust
        H.<<< DoHFilter CatMaybes
        H.<<< DoHMap GetRender
    )

_DoFoldRender ∷ ∀ a. DoFoldRender a
_DoFoldRender =
  ( DoHIfThenElse DoNull (DoConst HNothing) (DoApply (HJust ∷ a → HJust a))
      H.<<< DoHMap FromHJust
      H.<<< DoHFilter CatMaybes
      H.<<< DoHMap _GetRender
  )

instance builderMethod ∷
  ( HEval
      ( ( (DoBuildAccumSpec route H.<<< DoApply (apis → Method apis) H.<<< DoHMap GetSpec)
            H.&&& DoFoldRender a
        )
          H.<<< DoHMap (WebBuilderStep debugPath route)
      )
      ({ | rec } → Spec.AccumSpec b route ireq oreq res /\ rnd)
  , Spec.Builder (Method apis) b route ireq oreq res
  ) ⇒
  Builder debugPath (Method { | rec }) b rnd route ireq oreq res where
  accumWebSpec step (Method rec) = do
    let
      split =
        (DoBuildAccumSpec (toBuilderStep step) H.<<< DoApply (Method ∷ apis → Method apis) H.<<< DoHMap _GetSpec)
          H.&&& (_DoFoldRender ∷ DoFoldRender a)

      spec /\ render = heval (split H.<<< DoHMap step) rec
    AccumWebSpec { render, spec }

instance builderRec ∷
  ( HEval
        ((DoBuildAccumSpec route H.<<< DoHMap GetSpec H.&&& DoFoldRender a) H.<<< DoHMapWithIndex (WebBuilderStep debugPath route))
        ({ | rec } → Spec.AccumSpec b route ireq oreq res /\ rnd)
    ) ⇒
  Builder debugPath { | rec } b rnd route ireq oreq res where
  accumWebSpec step rec = do
    let
      spec /\ render =
        heval
          ( ( DoBuildAccumSpec (toBuilderStep step) H.<<< DoHMap _GetSpec
                H.&&& (_DoFoldRender ∷ DoFoldRender a)
            )
              H.<<< DoHMapWithIndex step
          )
          rec
    AccumWebSpec { render, spec }

instance insertSpecBuilder ∷
  ( Builder ("Insert _" ::: debugPath) sub b rnd { | route' } ireq oreq res
  , Row.Cons l a route route'
  , IsSymbol l
  , Row.Lacks l route
  , Spec.Builder (Spec.Insert l a (Spec.AccumSpec b { | route' } ireq oreq res)) b { | route } ireq oreq res
  ) ⇒
  Builder debugPath (Spec.Insert l a sub) b rnd { | route } ireq oreq res where
  accumWebSpec step (Spec.Insert dpl sub) = do
    let
      step' = WebBuilderStep ∷ WebBuilderStep ("Insert _" ::: debugPath) { | route' }

      AccumWebSpec { render, spec } = accumWebSpec step' sub

      spec' = Spec.accumSpec (toBuilderStep step) (Spec.Insert dpl spec ∷ Spec.Insert l a (Spec.AccumSpec b { | route' } ireq oreq res))
    AccumWebSpec { render, spec: spec' }

instance scalarSpecBuilder ∷
  ( Builder ("Sub" ::: debugPath) sub b rnd a ireq oreq res
  , TypeEquals {} route
  , Spec.Builder (Spec.Scalar a (Spec.AccumSpec b a ireq oreq res)) b route ireq oreq res
  ) ⇒
  Builder debugPath (Spec.Scalar a sub) b rnd route ireq oreq res where
  accumWebSpec step (Spec.Scalar dpl sub) = do
    let
      step' = WebBuilderStep ∷ WebBuilderStep ("Sub" ::: debugPath) a

      AccumWebSpec { render, spec } = accumWebSpec step' sub

      spec' = Spec.accumSpec (toBuilderStep step) (Spec.Scalar dpl spec ∷ Spec.Scalar a (Spec.AccumSpec b a ireq oreq res))
    AccumWebSpec { render, spec: spec' }

instance builderBuilderStep ∷ Builder debugPath a b rnd route ireq oreq res ⇒ Mapping (WebBuilderStep debugPath route) a (AccumWebSpec b rnd route ireq oreq res) where
  mapping step a = accumWebSpec step a

instance builderBuilderStepNest ∷ Builder (idx ::: debugPath) a b rnd route ireq oreq res ⇒ MappingWithIndex (WebBuilderStep debugPath route) (SProxy idx) a (AccumWebSpec b rnd route ireq oreq res) where
  mappingWithIndex _ _ a = accumWebSpec (WebBuilderStep ∷ WebBuilderStep (idx ::: debugPath) route) a

webSpec :: forall a bd ireq oreq res rnd. Builder SNil a bd rnd {} ireq oreq res => a -> WebSpec bd rnd ireq oreq res
webSpec = rootAccumWebSpec <<< accumWebSpec (WebBuilderStep ∷ WebBuilderStep SNil {})
