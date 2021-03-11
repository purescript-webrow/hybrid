module Hybrid.App.Server where

import Prelude

import Data.Either (Either(..))
import Data.Lazy (Lazy, defer)
import Data.Maybe (Maybe(..))
import Data.Tuple.Nested (type (/\), (/\))
import Data.Variant (Variant)
import Heterogeneous.Folding (class FoldingWithIndex, class HFoldlWithIndex, hfoldlWithIndex)
import Heterogeneous.Mapping (class HMap, class Mapping, hmap)
import Hybrid.Api.Server (Result) as Api.Server
import Hybrid.Api.Server (Result) as Server
import Hybrid.Api.Spec (ResponseCodec(..))
import Hybrid.App.Client.Router (RouterInterface)
import Hybrid.App.Client.Router (print) as Client.Router
import Hybrid.App.Renderer (Renderer)
import Hybrid.App.Spec (Raw(..)) as Spec
import Hybrid.HTTP (Exchange(..)) as Hybrid.HTTP
import Hybrid.HTTP.Exchange (fromResponse) as Exchange
import Node.HTTP (Response) as Node.HTTP
import Prim.Row (class Cons) as Row
import Record (get) as Record
import Request.Duplex (Request, parse) as Request.Duplex
import Type.Equality (class TypeEquals, to)
import Type.Prelude (class IsSymbol, SProxy)

-- | On the server side we want to work with this type: `Response (Lazy String /\ Lazy doc)`
-- | It gives as a way to respond to API calls but also to direct
-- | requests made directly by browser (when 'Accept: "text/html").
-- |
-- | We need a request because final rendering component
-- | takes it as a part of input.
render ∷
  ∀ doc req res router.
  router →
  req →
  ResponseCodec res →
  Renderer router req res doc →
  Server.Result res →
  Server.Result (Lazy String /\ doc)
render _ request (ResponseCodec codec) renderer (Left raw) = Left raw
render clientRouter request (ResponseCodec codec) renderer (Right response) =
  let
    doc = renderer $ clientRouter /\ Exchange.fromResponse request response

    dump = defer \_ → codec.encode response
  in
    Right $ dump /\ doc


type Handler m req res
  = req → m (Server.Result res)

-- | We should move the renderer context (`clienentRouter` outside of the scope
-- | of this folding.
-- | This should be done by preprocessing initial records of handlers / renderers.
data RouterFolding clientRouter handlers resCodecs renderers
  = RouterFolding clientRouter { | handlers } { | resCodecs } { | renderers }

-- | This fold pattern maches over a request `Variant` to get
-- | renderer and handler.
instance routerFolding ::
  ( IsSymbol sym
  , Row.Cons sym (Handler m req res) handlers_ handlers
  , Row.Cons sym (ResponseCodec res) resCodecs_ resCodecs
  , Row.Cons sym (Renderer router req res doc) renderers_ renderers
  , Monad m
  ) =>
  FoldingWithIndex
    (RouterFolding router handlers resCodecs renderers)
    (SProxy sym)
    Unit
    req
    (m (Either Node.HTTP.Response (Lazy String /\ doc))) where
  foldingWithIndex (RouterFolding clientRouter handlers resCodecs renderers) prop _ req =
    let
      renderer = Record.get prop renderers

      handler = Record.get prop handlers

      resCodec = Record.get prop resCodecs

    in
      do
        res ← handler req
        -- | On the server side we always have a response
        -- | which we can render.
        pure $ render clientRouter req resCodec renderer res

data RoutingError
  = NotFound

router ∷
  ∀ clientRouter doc handlers m renderers request resCodecs.
  Monad m ⇒
  HFoldlWithIndex (RouterFolding clientRouter handlers resCodecs renderers) Unit (Variant request) (m (Api.Server.Result (Lazy String /\ doc))) ⇒
  clientRouter →
  Spec.Raw request resCodecs renderers →
  { | handlers } →
  Request.Duplex.Request →
  m (Either RoutingError (Api.Server.Result (Lazy String /\ doc)))
router clientRouter spec@(Spec.Raw { codecs, renderers }) handlers = go
  where
  go raw = do
    case Request.Duplex.parse codecs.request raw of
      Right req → Right <$> hfoldlWithIndex (RouterFolding clientRouter handlers codecs.response renderers) unit req
      Left err → pure $ Left NotFound

-- | Currently handler context is just a router printer function.
data ArgMapping ctx = ArgMapping ctx --

instance handlerContextMapping ∷
  (TypeEquals a (ctx → h)) ⇒
  Mapping (ArgMapping ctx) a h where
  mapping (ArgMapping ctx) f = (to f) ctx

router' ∷
  ∀ doc handlers handlers' m renderers request resCodecs.
  Monad m ⇒
  HMap (ArgMapping (Variant request → String)) { | handlers } { | handlers' } ⇒
  HFoldlWithIndex (RouterFolding (RouterInterface request) handlers' resCodecs renderers) Unit (Variant request) (m (Api.Server.Result (Lazy String /\ doc))) ⇒
  Spec.Raw request resCodecs renderers →
  { | handlers } →
  Request.Duplex.Request →
  m (Either RoutingError (Api.Server.Result (Lazy String /\ doc)))
router' spec@(Spec.Raw { codecs }) handlers =
  let
    print ∷ Variant request → String
    print route = Client.Router.print codecs.request (Hybrid.HTTP.Exchange route Nothing)

    handlers' ∷ { | handlers' }
    handlers' = hmap (ArgMapping print) handlers

    fakeClientRouter ∷ RouterInterface request
    fakeClientRouter =
      { navigate: const $ pure unit
      , redirect: const $ pure unit
      , print
      , submit: const $ pure unit
      }
  in
    router fakeClientRouter spec handlers'
