{-# LANGUAGE ConstraintKinds            #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE RecursiveDo                #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TupleSections              #-}
{-# LANGUAGE TypeApplications           #-}
{-# LANGUAGE TypeFamilies               #-}
module Frontend.Page.Transaction where

------------------------------------------------------------------------------
import Control.Applicative
import Control.Lens
import Control.Monad
import Data.Aeson as A
import Data.Aeson.Lens
import Data.Foldable
import Data.Maybe
import qualified Data.Text as T
import Pact.Types.Continuation (PactExec)
import Reflex.Dom.Core hiding (Value)
------------------------------------------------------------------------------
-- import Chainweb.Api.BlockPayload
import Chainweb.Api.BlockPayloadWithOutputs
import Chainweb.Api.ChainId
import Chainweb.Api.ChainwebMeta
import Chainweb.Api.Hash
import Chainweb.Api.PactCommand
import Chainweb.Api.Payload
import Chainweb.Api.Sig
import Chainweb.Api.Signer
import Chainweb.Api.Transaction
import Common.Types
import Common.Utils
import Common.Route
import Frontend.App
import Frontend.Common
import Frontend.Page.Common

import Obelisk.Route
import Obelisk.Route.Frontend

------------------------------------------------------------------------------

transactionPage
  :: ( MonadApp r t m
     , RouteToUrl (R FrontendRoute) m
     , SetRoute t (R FrontendRoute) m
     , Prerender js t m
     )
  => NetId
  -> ChainId
  -> BlockPayloadWithOutputs
  -> m ()
transactionPage netId cid bp = do
    let txs = _blockPayloadWithOutputs_transactionsWithOutputs bp
    el "h2" $ text $ (tshow $ length txs) <> " Transactions"
    divClass "ui accordion" $ do
      forM_ txs $ \(t, tout) -> mdo
        open <- toggle False $ domEvent Click e
        let cmd = _transaction_cmd t
        let addActive cls active =
              ("class" =: if active then ("active " <> cls) else cls)
        (e,_) <- elDynAttr' "div" (addActive "title" <$> open) $ do
          elClass "i" "dropdown icon" blank
          elClass "pre" "custombreak" $ text $ payloadCode $ _pactCommand_payload cmd
        elDynAttr "div" (addActive "content" <$> open) $ do
          elClass "table" "ui definition table" $ do
            el "tbody" $ do
              tfield "Request Key" $ do
                let reqKey = hashB64U $ _transaction_hash t
                text reqKey
              tfield "Transaction Output" $ do
                elClass "table" "ui definition table" $ el "tbody" $ do
                  tfield "Gas" $ text $ tshow $ _toutGas tout
                  tfield "Result" $ text $ join either unwrapJSON $ fromPactResult $ _toutResult tout
                  tfield "Logs" $ text $ maybe "null " hashB64U $ _toutLogs tout
                  tfield "Metadata" $ renderMetaData netId cid $ _toutMetaData tout
                  tfield "Continuation" $ voidMaybe renderCont $ _toutContinuation tout
                  tfield "Transaction ID" $ maybe blank (text . tshow) $  _toutTxId tout
              tfield "Events" $ elClass "table" "ui definition table" $ el "tbody" $
                forM_ (_toutEvents tout) $ \ ev -> el "tr" $ do
                  elClass "td" "two wide" $ text (ename ev)
                  -- el "td" $ el "pre" $ text $ prettyJSON ev
                  elClass "td" "evtd" $ elClass "table" "evtable" $
                    forM_ (params ev) $ \v -> elClass "tr" "evtable" $ elClass "td" "evtable" $ text $ pactValueJSON v


              tfield "Payload" $ do
                let payload = _pactCommand_payload cmd
                renderPayload payload
              tfield "Nonce" $ text $ _pactCommand_nonce cmd
              tfield "Meta" $ do
                let meta = _pactCommand_meta cmd
                elClass "table" "ui definition table" $ el "tbody" $ do
                  tfield "Chain" $ text $ _chainwebMeta_chainId meta
                  tfield "Sender" $ text $ _chainwebMeta_sender meta
                  tfield "Gas Price" $ text $ tshow $ _chainwebMeta_gasPrice meta
                  tfield "Gas Limit" $ text $ tshow $ _chainwebMeta_gasLimit meta
                  tfield "TTL" $ text $ tshow $ _chainwebMeta_ttl meta
                  tfield "Creation Time" $ text $ tshow $ _chainwebMeta_creationTime meta
              tfield "Signers" $ do
                forM_ (_pactCommand_signers cmd) $ \s -> do
                  elClass "table" "ui definition table" $ el "tbody" $ do
                    tfield "Public Key" $ text $ _signer_pubKey s
                    tfield "Account" $ text $ fromMaybe "" $ _signer_addr s
                    tfield "Scheme" $ text $ fromMaybe "" $ _signer_scheme s
                    tfield "Signature Capabilites" $ do
                      when (not $ null $ _signer_capList s) $ do
                        elClass "table" "ui celled table" $ do
                          el "thead" $ do
                            el "tr" $ do
                              el "th" $ text "Name"
                              el "th" $ text "Arguments"
                          forM_ (_signer_capList s) $ \c -> do
                            el "tbody" $ do
                              elClass "tr" "top aligned" $ do
                                el "td" $ text $ _scName c
                                elClass "td" "top aligned"
                                  $ sequence
                                  $ fmap (el "div" . text) (unwrapJSON <$> _scArgs c) <|> empty
              tfield "Signatures" $ do
                forM_ (_transaction_sigs t) $ \s -> do
                  el "div" $ text $ unSig s
  where
    fromPactResult (PactResult pr) = pr

    renderCont v = case fromJSON v of
      Success (pe :: PactExec) -> renderPactExec pe
      A.Error e -> text $ T.pack $ "Unable to render continuation" <> e

    ename :: Value -> T.Text
    ename ev = delimView (key "module" . key "namespace" . _String) ev
        <> delimView (key "module" . key "name" . _String) ev
        <> mayview (key "name" . _String) ev

    params :: Value -> [Value]
    params ev = case fmap toList $ preview (key "params" . _Array) ev of
      Nothing -> []
      Just l -> l
