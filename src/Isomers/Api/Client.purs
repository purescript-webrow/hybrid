module Isomers.Api.Client where

import Prelude

import Data.Functor.Variant (VariantF)
import Data.Newtype (class Newtype, unwrap, wrap)
import Data.Variant (Variant)
import Data.Variant (inj) as Variant
import Effect.Aff (Aff)
import Heterogeneous.Folding (class FoldingWithIndex, class HFoldlWithIndex, foldingWithIndex, hfoldlWithIndex)
import Isomers.HTTP (Exchange, Response)
import Isomers.HTTP.Fetch (exchange) as Fetch
import Isomers.HTTP.Request (Data(..)) as Request
import Isomers.HTTP.Response.Duplex (Duplex) as Response
import Prim.Row (class Cons, class Lacks) as Row
import Prim.RowList (class RowToList)
import Record (get, insert) as Record
import Request.Duplex (RequestDuplex')
import Type.Prelude (class IsSymbol, Proxy(..), RLProxy(..), SProxy)

-- | This folding allows us to build a request builder:
-- | a record which contains functions which builds a
-- | request value (nested Variant) which has structure
-- | corresponding to the labels path.
data RequestBuildersFolding a request
  = RequestBuildersFolding (a → request)

instance requestFoldingNewtypeVariantWrapper ::
  ( IsSymbol sym
  , Newtype (f (Variant v)) (Variant v)
  , Row.Cons sym (f (Variant v)) curr_ curr
  , RowToList v vl
  , Row.Lacks sym requestBuilders
  , Row.Cons sym { | subrequestBuilders } requestBuilders requestBuilders'
  , HFoldlWithIndex (RequestBuildersFolding (Variant v) request) {} (RLProxy vl) { | subrequestBuilders }
  ) =>
  FoldingWithIndex
    (RequestBuildersFolding (Variant curr) request)
    (SProxy sym)
    { | requestBuilders }
    (Proxy (f (Variant v)))
    { | requestBuilders' } where
  foldingWithIndex (RequestBuildersFolding inj) prop rb _ = do
    let
      inj' ∷ Variant v → request
      inj' = inj <<< Variant.inj prop <<< wrap

      subrequestBuilders = hfoldlWithIndex (RequestBuildersFolding inj') {} (RLProxy ∷ RLProxy vl)
    Record.insert prop subrequestBuilders rb
else instance requestFoldingVariant ::
  ( IsSymbol sym
  , RowToList v vl
  , Row.Cons sym (Variant v) curr_ curr
  , Row.Lacks sym requestBuilders
  , Row.Cons sym { | subrequestBuilders } requestBuilders requestBuilders'
  , HFoldlWithIndex (RequestBuildersFolding (Variant v) request) {} (RLProxy vl) { | subrequestBuilders }
  ) =>
  FoldingWithIndex
    (RequestBuildersFolding (Variant curr) request)
    (SProxy sym)
    { | requestBuilders }
    (Proxy (Variant v))
    { | requestBuilders' } where
  foldingWithIndex (RequestBuildersFolding inj) prop rb _ = do
    let
      f ∷ Variant v → Variant curr
      f = Variant.inj prop

      inj' = inj <<< f

      subrequestBuilders = hfoldlWithIndex (RequestBuildersFolding inj') {} (RLProxy ∷ RLProxy vl)
    Record.insert prop subrequestBuilders rb
else instance requestFoldingData ::
  ( IsSymbol sym
  , Row.Lacks sym requestBuilders
  , Row.Cons sym (d → request) requestBuilders requestBuilders'
  , Row.Cons sym (Request.Data d) r_ r
  ) =>
  FoldingWithIndex
    (RequestBuildersFolding (Variant r) request)
    (SProxy sym)
    { | requestBuilders }
    (Proxy (Request.Data d))
    { | requestBuilders' } where
  foldingWithIndex (RequestBuildersFolding inj) prop rb d = do
    let
      inj' = inj <<< Variant.inj prop <<< Request.Data
    Record.insert prop inj' rb

instance hfoldlWithIndexRequestBuildersFoldingVariantWrapper ∷
  ( HFoldlWithIndex (RequestBuildersFolding (Variant v) request) {} (RLProxy vl) { | requestBuilders }
  , Newtype (f (Variant v)) (Variant v)
  , RowToList v vl
  ) ⇒
  HFoldlWithIndex (RequestBuildersFolding (f (Variant v)) request) unit (Proxy (f (Variant v))) { | requestBuilders } where
  hfoldlWithIndex (RequestBuildersFolding f) init _ = hfoldlWithIndex (RequestBuildersFolding (f <<< wrap)) {} (RLProxy ∷ RLProxy vl)
else instance hfoldlWithIndexRequestBuildersFoldingVariant ∷
  ( HFoldlWithIndex (RequestBuildersFolding (Variant v) request) {} (RLProxy vl) { | requestBuilders }
  , RowToList v vl
  ) ⇒
  HFoldlWithIndex (RequestBuildersFolding (Variant v) request) unit (Proxy (Variant v)) { | requestBuilders } where
  hfoldlWithIndex cf init _ = hfoldlWithIndex cf {} (RLProxy ∷ RLProxy vl)

requestBuilders ∷ ∀ requestBuilders t. HFoldlWithIndex (RequestBuildersFolding t t) {} (Proxy t) { | requestBuilders } ⇒ Proxy t → { | requestBuilders }
requestBuilders = hfoldlWithIndex (RequestBuildersFolding (identity ∷ t → t)) {}

data ClientFolding request responseDuplexes
  = ClientFolding (RequestDuplex' request) responseDuplexes

-- | TODO: parameterize the client by fetching function
-- | so the whole exchange can be performed purely.
instance clientFoldingResponseDuplexNewtypeWrapper ∷
  ( Newtype (f responseDuplexes) responseDuplexes
  , FoldingWithIndex (ClientFolding request responseDuplexes) (SProxy sym) { | client } { | requestBuilders } { | client' }
  ) =>
  FoldingWithIndex
    (ClientFolding request (f responseDuplexes))
    (SProxy sym)
    { | client }
    { | requestBuilders }
    { | client' } where
  foldingWithIndex (ClientFolding reqDpl resDpl) prop c reqBld = do
    foldingWithIndex (ClientFolding reqDpl (unwrap resDpl)) prop c reqBld
else instance clientFoldingResponseDuplexRec ∷
  ( IsSymbol sym
  , Row.Lacks sym client
  , Row.Cons sym subclient client client'
  , Row.Cons sym subResponseDuplexes responseDuplexes_ responseDuplexes
  , Row.Cons sym subRequestBuilders requestBuilders_ requestBuilders
  , HFoldlWithIndex (ClientFolding request subResponseDuplexes) {} subRequestBuilders subclient
  ) =>
  FoldingWithIndex
    (ClientFolding request { | responseDuplexes })
    (SProxy sym)
    { | client }
    { | requestBuilders }
    { | client' } where
  foldingWithIndex (ClientFolding reqDpl resDpl) prop c reqBld = do
    let
      sResDpl = Record.get prop resDpl

      sReqBld = Record.get prop reqBld

      subclient = hfoldlWithIndex (ClientFolding reqDpl sResDpl) {} sReqBld
    Record.insert prop subclient c
else instance clientFoldingResponseData ∷
  ( IsSymbol sym
  , Row.Lacks sym client
  , Row.Cons sym (d → Aff (Exchange res request a)) client client'
  ) =>
  FoldingWithIndex
    (ClientFolding request (Response.Duplex Aff (VariantF res a) (VariantF res a)))
    (SProxy sym)
    { | client }
    (d → request)
    { | client' } where
  foldingWithIndex (ClientFolding reqDpl resDpl) prop c reqBld = do
    let
      exchange = \d → Fetch.exchange reqDpl (reqBld d) resDpl
    Record.insert prop exchange c

client ∷
  ∀ client requestBuilders responseDuplexes request.
  HFoldlWithIndex (RequestBuildersFolding request request) {} (Proxy request) { | requestBuilders } ⇒
  HFoldlWithIndex (ClientFolding request responseDuplexes) {} { | requestBuilders } { | client } ⇒
  RequestDuplex' request →
  responseDuplexes →
  { | client }
client reqDpl resDpl = do
  let
    rb ∷ { | requestBuilders }
    rb = hfoldlWithIndex (RequestBuildersFolding (identity ∷ request → request)) {} (Proxy ∷ Proxy request)
  hfoldlWithIndex (ClientFolding reqDpl resDpl) {} rb
