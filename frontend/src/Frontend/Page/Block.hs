{-# LANGUAGE ConstraintKinds            #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TupleSections              #-}
{-# LANGUAGE TypeApplications           #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeOperators              #-}
module Frontend.Page.Block where

------------------------------------------------------------------------------
import           Control.Monad
import           Control.Monad.Reader
import           Data.Functor
import qualified Data.Map.Strict as M
import           Data.Text (Text)
import qualified Data.Text as T
import           Data.Time.Clock.POSIX
import           GHCJS.DOM.Types (MonadJSM)
import           Numeric
import           Obelisk.Route
import           Obelisk.Route.Frontend
import           Reflex.Dom.Core hiding (Value)
import           Reflex.Network
import           Text.Printf (printf)
------------------------------------------------------------------------------
import           Chainweb.Api.Base64Url
import           Chainweb.Api.BlockHeader
import           Chainweb.Api.BlockPayload
import           Chainweb.Api.BlockPayloadWithOutputs
import           Chainweb.Api.BytesLE
import           Chainweb.Api.ChainId
import           Chainweb.Api.Common
import           Chainweb.Api.Hash
import           Chainweb.Api.MinerData
import           Common.Route
import           Common.Types
import           Common.Utils
import           Frontend.App
import           Frontend.AppState
import           Frontend.ChainwebApi
import           Frontend.Common
import           Frontend.Page.Common
import           Frontend.Page.Transaction
------------------------------------------------------------------------------


blockHashWidget
  :: (MonadApp r t m, MonadJSM (Performable m), HasJSContext (Performable m),
      RouteToUrl (R FrontendRoute) m, SetRoute t (R FrontendRoute) m, Monad (Client m),
      Prerender js t m
     )
  => ServerInfo
  -> NetId
  -> Int
  -> App (Text, R BlockRoute) t m ()
blockHashWidget si netId cid = do
  as <- ask
  let n = _as_network as
      chainwebHost = ChainwebHost (netHost n) (_siChainwebVer si)
      c = ChainId cid
  subPairRoute_ $ \hash -> do
    ebh <- getBlockHeader chainwebHost c hash
    void $ networkHold (inlineLoader "Retrieving block...") $ ffor ebh $ \case
      Nothing -> text "Block with that hash does not exist"
      Just bh -> blockPageNoPayload netId chainwebHost c bh True

blockHeightWidget
  :: (MonadApp r t m, MonadJSM (Performable m), HasJSContext (Performable m),
      RouteToUrl (R FrontendRoute) m, SetRoute t (R FrontendRoute) m, Monad (Client m),
      Prerender js t m
     )
  => ServerInfo
  -> NetId
  -> Int
  -> App (Int, R BlockRoute) t m ()
blockHeightWidget si netId cid = do
  as <- ask
  let n = _as_network as
      chainwebHost = ChainwebHost (netHost n) (_siChainwebVer si)
      c = ChainId cid
  subPairRoute_ $ \height -> do
    ebh <- getBlockHeaderByHeight chainwebHost c height
    void $ networkHold (inlineLoader "Retrieving block...") $ ffor ebh $ \case
      Nothing -> text "Block does not exist"
      Just bh -> blockPageNoPayload netId chainwebHost c bh False

blockLink
  :: (RouteToUrl (R FrontendRoute) m, SetRoute t (R FrontendRoute) m,
      DomBuilder t m,
      Prerender js t m
     )
  => NetId
  -> ChainId
  -> BlockHeight
  -> Text
  -> m ()
blockLink netId chainId height linkText =
  routeLink (addNetRoute netId (unChainId chainId) $ Chain_BlockHeight :/ (height, Block_Header :/ ())) $ text linkText

blockHashLink
  :: (RouteToUrl (R FrontendRoute) m, SetRoute t (R FrontendRoute) m,
      DomBuilder t m,
      Prerender js t m
     )
  => NetId
  -> ChainId
  -> Text
  -> Text
  -> m ()
blockHashLink netId chainId blockHash linkText =
  routeLink (addNetRoute netId (unChainId chainId) $ Chain_BlockHash :/ (blockHash, Block_Header :/ ())) $ text linkText

blockPageNoPayload
  :: (MonadApp r t m, MonadJSM (Performable m), HasJSContext (Performable m),
      RouteToUrl (R FrontendRoute) m, SetRoute t (R FrontendRoute) m, Monad (Client m),
      Prerender js t m
     )
  => NetId
  -> ChainwebHost
  -> ChainId
  -> (BlockHeader, Text)
  -> Bool
  -> App (R BlockRoute) t m ()
  -- -> m ()
blockPageNoPayload netId h c bh resolveOrphan = do
  let choose ep = case ep of
        Left e -> text $ "Block payload query failed: " <> T.pack e
        Right payload -> subRoute_ $ \case
          Block_Header -> blockHeaderPage netId h c bh payload resolveOrphan
          Block_Transactions -> transactionPage netId c payload
  pEvt <- getBlockPayloadWithOutputs h c (_blockHeader_payloadHash $ fst bh)
  void $ networkHold (inlineLoader "Retrieving payload...") (choose <$> pEvt)


blockHeaderPage
  :: (MonadApp r t m,
      RouteToUrl (R FrontendRoute) m, SetRoute t (R FrontendRoute) m,
      HasJSContext (Performable m),
      MonadJSM (Performable m),
      Prerender js t m
     )
  => NetId
  -> ChainwebHost
  -> ChainId
  -> (BlockHeader, Text)
  -> BlockPayloadWithOutputs
  -> Bool
  -> m ()
blockHeaderPage netId h c (bh, bhBinBase64) bp resolveOrphan = do
    orphanHash <- _blockHeader_hash . fst <$$$> getBlockHeaderByHeight h c (_blockHeader_height bh)
    let isJust e = case e of Just _ -> True; _ -> False
        displayOrphan = \case
           Just hh | hh /= _blockHeader_hash bh -> "(orphan)"
           _ -> ""
    orphanText <- holdDyn "" $ orphanHash <&> (\b -> if isJust b && resolveOrphan then displayOrphan b else "")
    el "h2" $ dynText ( ("Block Header " <>) <$> orphanText)
    elAttr "table" ("class" =: "ui definition table") $ do
      el "tbody" $ do
        tfield "Creation Time" $ text $ tshow $ posixSecondsToUTCTime $ _blockHeader_creationTime bh
        tfield "Chain" $ text $ tshow $ _blockHeader_chainId bh
        tfield "Block Height" $ text $ tshow $ _blockHeader_height bh
        tfield "Parent" $ parent $ _blockHeader_parent bh
        tfield "POW Hash" $ text $ either (const "") id (calcPowHash =<< decodeB64UrlNoPaddingText bhBinBase64)
        tfield "Target" $ text $ hexFromBytesLE $ _blockHeader_target bh
        tfield "Hash" $ text $ hashHex $ _blockHeader_hash bh
        tfield "Weight" $ text $ hexFromBytesLE $ _blockHeader_weight bh
        tfield "Epoch Start" $ text $ tshow $ posixSecondsToUTCTime $ _blockHeader_epochStart bh
        tfield "Neighbors" $ neighbors $ _blockHeader_neighbors bh
        tfield "Payload Hash" $ text $ hashB64U $ _blockHeader_payloadHash bh
        tfield "Chainweb Version" $ text $ _blockHeader_chainwebVer bh
        tfield "Flags" $ text $ T.pack $ printf "0x%08x" (_blockHeader_flags bh)
        tfield "Nonce" $ text $ T.pack $ showHex (_blockHeader_nonce bh) ""
        return ()
    blockPayloadWithOutputsWidget netId c bh bp
  where
    prevHeight = _blockHeader_height bh - 1
    parent p = blockLink netId (_blockHeader_chainId bh) prevHeight (hashHex p)
    neighbors ns = do
      forM_ (M.toList ns) $ \(cid,nh) -> do
        el "div" $ do
          text $ "Chain " <> tshow cid <> ": "
          blockLink netId cid prevHeight (hashHex nh)

blockPayloadWidget
  :: (MonadApp r t m,
      RouteToUrl (R FrontendRoute) m, SetRoute t (R FrontendRoute) m,
      Prerender js t m
     )
  => NetId
  -> ChainId
  -> BlockHeader
  -> BlockPayload
  -> m ()
blockPayloadWidget netId c bh bp = do
    el "h2" $ text "Block Payload"
    elAttr "table" ("class" =: "ui definition table") $ do
      el "tbody" $ do
        tfield "Miner" $ do
          el "div" $ text $ "Account: " <> _minerData_account (_blockPayload_minerData bp)
          el "div" $ text $ "Public Keys: " <> tshow (_minerData_publicKeys $ _blockPayload_minerData bp)
          el "div" $ text $ "Predicate: " <> _minerData_predicate (_blockPayload_minerData bp)
        tfield "Transactions Hash" $ text $ hashB64U $ _blockPayload_transactionsHash bp
        tfield "Outputs Hash" $ text $ hashB64U $ _blockPayload_outputsHash bp
        tfield "Payload Hash" $ text $ hashB64U $ _blockPayload_payloadHash bp
        tfield "Transactions" $ transactionsLink netId c $ _blockHeader_hash bh

blockPayloadWithOutputsWidget
  :: (MonadApp r t m,
      RouteToUrl (R FrontendRoute) m, SetRoute t (R FrontendRoute) m,
      Prerender js t m
     )
  => NetId
  -> ChainId
  -> BlockHeader
  -> BlockPayloadWithOutputs
  -> m ()
blockPayloadWithOutputsWidget netId c bh bp = do
    el "h2" $ text "Block Payload"
    elAttr "table" ("class" =: "ui definition table") $ do
      el "tbody" $ do
        tfield "Miner" $ do
          el "div" $ text $ "Account: " <> _minerData_account (_blockPayloadWithOutputs_minerData bp)
          el "div" $ text $ "Public Keys: " <> tshow (_minerData_publicKeys $ _blockPayloadWithOutputs_minerData bp)
          el "div" $ text $ "Predicate: " <> _minerData_predicate (_blockPayloadWithOutputs_minerData bp)
        tfield "Transactions Hash" $ text $ hashB64U $ _blockPayloadWithOutputs_transactionsHash bp
        tfield "Outputs Hash" $ text $ hashB64U $ _blockPayloadWithOutputs_outputsHash bp
        tfield "Payload Hash" $ text $ hashB64U $ _blockPayloadWithOutputs_payloadHash bp
        let coinbase = fromCoinbase $ _blockPayloadWithOutputs_coinbase bp
        tfield "Coinbase Output" $ do
          elClass "table" "ui definition table" $ el "tbody" $ do
          tfield "Gas" $ text $ tshow $ _toutGas coinbase
          tfield "Result" $ text $ join either unwrapJSON $ fromPactResult $ _toutResult coinbase
          tfield "Request Key" $ text $ hashB64U $ _toutReqKey coinbase
          tfield "Logs" $ text $ (maybe "" hashB64U $ _toutLogs coinbase)
          tfield "Metadata" $ renderMetaData netId c $ _toutMetaData coinbase
          maybe (pure ()) (tfield "Continuation" . text . tshow) $ _toutContinuation coinbase
          tfield "Transaction ID" $ maybe blank (text . tshow) $ _toutTxId coinbase

        let numberOfTransactions =
              case length $ _blockPayloadWithOutputs_transactionsWithOutputs bp of
                n | n <= 0 -> "No transactions"
                  | n == 1 -> "1 Transaction"
                  | otherwise -> tshow n <> " Transactions"
        tfield numberOfTransactions $ transactionsLink netId c $ _blockHeader_hash bh
  where
    fromCoinbase (Coinbase cb) = cb
    fromPactResult (PactResult pr) = pr
