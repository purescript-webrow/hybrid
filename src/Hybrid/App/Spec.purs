module Hybrid.App.Spec where

import Prelude

import Control.Alt ((<|>))
import Data.Maybe (Maybe, fromMaybe)
import Data.Tuple (fst, snd)
import Data.Tuple.Nested ((/\), type (/\))
import Data.Variant (Variant)
import Data.Variant (class Contractable, contract, expand) as Variant
import Data.Variant.Internal (VariantRep(..))
import Data.Variant.Prefix (NilExpr, PrefixCases, PrefixStep, UnprefixCases, UnprefixStep)
import Data.Variant.Prefix (add, remove) as Variant.Prefix
import Heterogeneous.Folding (class FoldingWithIndex, class HFoldlWithIndex, foldingWithIndex, hfoldlWithIndex)
import Heterogeneous.Mapping (class HMap, class HMapWithIndex, class Mapping, class MappingWithIndex, hmap, hmapWithIndex)
import Hybrid.Api.Spec (Codecs)
import Hybrid.Contrib.Type.Eval.Tuple (Tuples)
import Prim.Row (class Cons, class Union) as Row
import Prim.RowList (Cons, Nil) as RowList
import Prim.RowList (class RowToList, kind RowList)
import Prim.Symbol (class Append) as Symbol
import Record (union) as Record
import Record.Builder (Builder) as Record.Builder
import Record.Prefix (PrefixProps, add) as Record.Prefix
import Request.Duplex (RequestDuplex(..), RequestDuplex')
import Request.Duplex (prefix) as Request.Duplex
import Request.Duplex.Generic.Variant (Updater, modify, update, variant) as Request.Duplex.Generic.Variant
import Request.Duplex.Generic.Variant (class VariantParser, class VariantPrinter)
import Request.Duplex.Parser (RequestParser(..), RouteError(..), RouteResult(..)) as Request.Duplex.Parser
import Request.Duplex.Parser (RequestParser)
import Request.Duplex.Printer (RequestPrinter(..))
import Type.Eval (class Eval)
import Type.Eval.Foldable (FoldrWithIndex)
import Type.Eval.Function (type (<<<))
import Type.Eval.RowList (FromRow, ToRow)
import Type.Prelude (class IsSymbol, RLProxy(..), RProxy, SProxy(..), reflectSymbol)
import Unsafe.Coerce (unsafeCoerce)

newtype Raw req res rnd
  = Raw
  { codecs ∷ Codecs req res
  , renderers ∷ { | rnd }
  }

-- | A "magic wrapper" around `Codecs` record which exposes API type using more convenient type signature.
-- | newtype Spec ... = Spec ...
type PrefixRouters
  = Boolean

data FstDuplex
  = FstDuplex PrefixRouters

instance fstDuplex ∷ (IsSymbol prop) ⇒ MappingWithIndex FstDuplex (SProxy prop) (RequestDuplex a a /\ b) (RequestDuplex a a) where
  mappingWithIndex (FstDuplex prefixRouters) prop =
    if prefixRouters then
      Request.Duplex.prefix (reflectSymbol prop) <<< fst
    else
      fst

data Fst
  = Fst

instance fst ∷ Mapping Fst (a /\ b) a where
  mapping _ = fst

data Snd
  = Snd

instance snd ∷ Mapping Snd (a /\ b) b where
  mapping _ = snd

-- | Build a `Spec` value from a record of endpoints of the shape `requestDuplex /\ ResponseCodec a /\ Renderer req res doc`.
endpoints ∷
  ∀ r req reqs reqsl res rnd t.
  RowToList reqs reqsl ⇒
  VariantParser reqsl reqs req ⇒
  VariantPrinter reqsl reqs req ⇒
  HMapWithIndex FstDuplex r (Record reqs) ⇒
  HMap Snd r { | t } ⇒
  HMap Fst { | t } ({ | res }) ⇒
  HMap Snd { | t } ({ | rnd }) ⇒
  PrefixRouters →
  r →
  Raw req res rnd
endpoints p r =
  let
    request = Request.Duplex.Generic.Variant.variant (hmapWithIndex (FstDuplex p) r)

    t = hmap Snd r
  in
    Raw
      { codecs:
          { request
          , response: hmap Fst t
          }
      , renderers: hmap Snd t
      }

duplex ∷
  ∀ a rnd req req' res.
  Eval (Tuples a (RProxy req)) (RProxy req') ⇒
  RequestDuplex' a →
  Raw req res rnd →
  Raw req' res rnd
duplex (RequestDuplex aprt aprs) (Raw { codecs: codecs@{ request: RequestDuplex vprt vprs }, renderers }) = Raw { renderers, codecs: codecs { request = request' } }
  where
  prs' = ado
    a ← aprs
    v ← vprs
    let
      VariantRep { type: t, value } = unsafeCoerce v
    in unsafeCoerce (VariantRep { type: t, value: a /\ value })

  prt' v =
    let
      t ∷ a /\ Variant req
      t =
        let
          VariantRep { type: t, value } = unsafeCoerce v

          a /\ b = value
        in
          a /\ unsafeCoerce (VariantRep { type: t, value: b })

      a /\ v' = t
    in
      aprt a <> vprt v'

  request' = RequestDuplex prt' prs'

data PrefixLabels (sep ∷ Symbol)
  = PrefixLabels

-- | A recursive call so we are able to prefix nested records.
instance foldingWithIndexPrefixNested ::
  ( HFoldlWithIndex (PrefixLabels sep) (Raw () () ()) { | r } (Raw req res doc)
  , FoldingWithIndex (PrefixLabels sep) (SProxy l) accum (Raw req res doc) o
  ) =>
  FoldingWithIndex
    (PrefixLabels sep)
    (SProxy l)
    accum
    { | r }
    o where
  foldingWithIndex pref prop accum r =
    let
      (raw ∷ Raw req res doc) = hfoldlWithIndex
        pref
        (Raw { codecs: { request: RequestDuplex mempty fail, response: {} }, renderers: {} } ∷ Raw () () ())
        r
    in
      foldingWithIndex pref prop accum raw

instance foldingWithIndexPrefixLabels ::
  ( IsSymbol l
  , IsSymbol sep
  , IsSymbol sym
  , Symbol.Append l sep sym
  , Row.Union response piresponse response'
  , Row.Union piresponse response response'
  , Row.Union render pirender render'
  , Row.Union pirender render render'
  , Row.Union request pirequest request'
  , Row.Union pirequest request request'
  , Variant.Contractable request' request
  , Variant.Contractable request' pirequest
  , RowToList irequest irl
  , RowToList pirequest pirl
  , Eval ((ToRow <<< FoldrWithIndex (PrefixStep sym) NilExpr <<< FromRow) (RProxy irequest)) (RProxy pirequest)
  , HFoldlWithIndex (PrefixCases sym pirequest) Unit (Variant irequest) (Variant pirequest)
  , Eval ((ToRow <<< FoldrWithIndex (UnprefixStep sym) NilExpr <<< FromRow) (RProxy pirequest)) (RProxy irequest)
  , HFoldlWithIndex (UnprefixCases sym irequest) Unit (Variant pirequest) (Variant irequest)
  , HFoldlWithIndex
      (Record.Prefix.PrefixProps sym)
      (Record.Builder.Builder {} {})
      { | iresponse }
      (Record.Builder.Builder {} { | piresponse })
  , HFoldlWithIndex
      (Record.Prefix.PrefixProps sym)
      (Record.Builder.Builder {} {})
      { | irender }
      (Record.Builder.Builder {} { | pirender })
  ) =>
  FoldingWithIndex
    (PrefixLabels sep)
    (SProxy l)
    (Raw request response render)
    (Raw irequest iresponse irender)
    (Raw request' response' render') where
  foldingWithIndex _ _ (Raw s) (Raw is) =
    Raw
      { codecs:
          { response: Record.union s.codecs.response (Record.Prefix.add prop is.codecs.response) ∷ { | response' }
          , request:
              RequestDuplex
                ( \i →
                    let
                      pir ∷ Maybe (Variant pirequest)
                      pir = Variant.contract i

                      ir ∷ Maybe (Variant irequest)
                      ir = Variant.Prefix.remove prop <$> pir

                      r ∷ Maybe (Variant request)
                      r = Variant.contract i
                    in
                      fromMaybe
                        (RequestPrinter identity)
                        (prt <$> r <|> iprt <$> ir)
                )
                (Variant.expand <$> prs <|> (expandIreq <$> iprs))
          }
      , renderers: Record.union s.renderers (Record.Prefix.add prop is.renderers) ∷ { | render' }
      }
    where
    prop = SProxy ∷ SProxy sym

    expandIreq ∷ Variant irequest → Variant request'
    expandIreq = Variant.expand <<< p
      where
      p ∷ Variant irequest → Variant pirequest
      p = Variant.Prefix.add prop

    RequestDuplex prt prs = s.codecs.request

    RequestDuplex iprt iprs = is.codecs.request

-- | Given a record of specs we generate a single spec
-- | with prefixed rows in all specs records
-- | (renderers, `codecs.request`) but also in
-- | `codecs.response` Variant.
prefixLabels ::
  ∀ r req res rnd sep.
  HFoldlWithIndex (PrefixLabels sep) (Raw () () ()) { | r } (Raw req res rnd) =>
  SProxy sep →
  { | r } →
  Raw req res rnd
prefixLabels _ r =
  hfoldlWithIndex
    (PrefixLabels ∷ PrefixLabels sep)
    (Raw { codecs: { request: RequestDuplex mempty fail, response: {} }, renderers: {} } ∷ Raw () () ())
    r

fail ∷ RequestParser (Variant ())
fail = Request.Duplex.Parser.Chomp $ const $ Request.Duplex.Parser.Fail Request.Duplex.Parser.EndOfPath

class PrefixPath (rl ∷ RowList) request where
  prefixPath ∷ RLProxy rl → Request.Duplex.Generic.Variant.Updater { | request }

instance prefixPathNil ∷ PrefixPath RowList.Nil request where
  prefixPath _ = mempty
else instance prefixPathEmptyCons ::
  (PrefixPath tail request, Row.Cons "" (Raw request response render) r' request) =>
  PrefixPath (RowList.Cons "" (Raw request response render) tail) request where
  prefixPath _ = prefixPath (RLProxy ∷ RLProxy tail)
else instance prefixPathCons ::
  (IsSymbol sym, PrefixPath tail request, Row.Cons sym (Raw req response render) r' request) =>
  PrefixPath (RowList.Cons sym (Raw req response render) tail) request where
  prefixPath _ = Request.Duplex.Generic.Variant.modify prop step <> prefixPath (RLProxy ∷ RLProxy tail)
    where
    step (Raw { codecs: { request: r, response }, renderers }) =
      Raw
        { codecs:
            { request: Request.Duplex.prefix (reflectSymbol prop) r
            , response
            }
        , renderers
        }

    prop = SProxy ∷ SProxy sym

-- | Additionally to prefixing labels we also
-- | add string label prefix to the url path.
prefix ∷
  ∀ i il req res rnd sep.
  HFoldlWithIndex (PrefixLabels sep) (Raw () () ()) { | i } (Raw req res rnd) =>
  RowToList i il ⇒
  PrefixPath il i ⇒
  SProxy sep →
  { | i } →
  Raw req res rnd
prefix sep request = prefixLabels sep (Request.Duplex.Generic.Variant.update (prefixPath (RLProxy ∷ RLProxy il)) request)