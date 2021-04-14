module Isomers.Response.Encodings where

import Prelude

import Data.Argonaut (Json)
import Data.ArrayBuffer.Types (ArrayBuffer)
import Data.Map (Map)
import Data.Maybe (Maybe)
import Data.Newtype (class Newtype)
import Effect.Aff (Aff, Fiber)
import Network.HTTP.Types (Header, Status, HeaderName)
import Node.Buffer (Buffer) as Node.HTTP
import Node.Stream (Writable, Readable) as Node.Stream
import Type.Prelude (SProxy(..))

type Base body extra
  = { body ∷ body
    , status ∷ Status
    | extra
    }

-- | TODO: Move these to the `Isomers.Node.Response.Duplex.Encodings`
-- | We can probably provide some "basic"
-- | building blocks like `Str = (string ∷ String | res)`
-- | so we can provide basic responses for json, html etc.
data NodeBody
  = NodeBuffer Node.HTTP.Buffer
  | NodeStream (∀ r. Node.Stream.Readable r)
  -- | We can handle String in the upper layer
  -- | String
  | NodeWriter (∀ r. Node.Stream.Writable r → Aff Unit)

-- | TODO: Parametrize by `body` so other backends can work with this
-- | lib easily.
-- |
-- | I'm not able to confirm but it seems that headers value differ between
-- | `fetch` and `node`.
-- | When accessing fetch header we are getting back a "ByteString" value.
-- | I don't want to introduce parsing at this level.
-- | In the case of node we can use `setHeader` or `setHeaders`.
-- | I'm going to use one of these according to the number of values
-- | in the array.
type ServerHeaders
  = Array Header

type ServerResponse
  = ( Base
        (Maybe NodeBody)
        ( headers ∷ ServerHeaders )
    )

_string = SProxy ∷ SProxy "string"

type ClientBodyRow
  = ( arrayBuffer ∷ Fiber ArrayBuffer -- Effect (Promise ArrayBuffer)
    -- , blob ∷ Fiber Web.File.Blob -- Effect (Promise Blob)
    -- , blob ∷ Fiber Blob
    -- | Something like this should be possible when we have WritableStream ;-)
    -- , reader ∷ Web.Streams.WritableStream → Aff Unit
    -- | TODO: This was `Eff` originally. I've changed it to `Aff`
    -- | because it was easier.
    , json ∷ Fiber Json
    -- , stream ∷ Fiber (Web.Streams.ReadableStream Uint8Array)
    , string ∷ Fiber String -- Effect (Promise String)
    )

type ClientHeaders
  = Map HeaderName String

newtype ClientResponse = ClientResponse
  ( Base
      { | ClientBodyRow }
      ( headers ∷ ClientHeaders
      , url ∷ String
      )
  )
derive instance newtypeClientResponse ∷ Newtype ClientResponse _