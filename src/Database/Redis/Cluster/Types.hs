{-# LANGUAGE OverloadedStrings #-}
module Database.Redis.Cluster.Types (
Slot,
SlotRange,
NodeId,
FailoverOptions(..),
Count,
Info(..),
Key,
NodeInfo(..),
NodeInfoFlag(..),
LinkState(..),
NodeSlot(..),
ResetOptions(..),
Epoch,
SetSlotSubcommand(..),
SlotMap,
SlotMapEntry(..),
SlotMapEntryNode(..)
) where

import Data.ByteString (ByteString)
import Data.Function (on)
import Data.IntMap (IntMap)
import Data.Map (Map)
import Data.Monoid ((<>))
import Database.Redis (HostName)
import Network.Socket (PortNumber)
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Char8 as Char8
import qualified Data.Char as Char
import qualified Data.Either as Either
import qualified Data.HashMap.Strict as HashMap
import qualified Data.IntMap as IntMap
import qualified Data.Map as Map
import qualified Data.Maybe as Maybe
import qualified Database.Redis as Redis

readInteger :: ByteString -> Maybe Integer
readInteger = fmap fst . Char8.readInteger

readPortNumber :: ByteString -> Maybe PortNumber
readPortNumber x = case reads (Char8.unpack x) of
  [(p, _)] -> Just p
  _ -> Nothing

type Slot = Integer

type SlotRange = (Slot, Slot)

type NodeId = ByteString

readMasterNodeId :: ByteString -> Maybe NodeId
readMasterNodeId "-"    = Nothing
readMasterNodeId nodeId = Just nodeId

data FailoverOptions = Force | Takeover

type Count = Int

data Info = Info {
  clusterState                 :: ClusterState,
  clusterSlotsAssigned         :: Integer,
  clusterSlotsOk               :: Integer,
  clusterSlotsPfail            :: Integer,
  clusterSlotsFail             :: Integer,
  clusterKnownNodes            :: Integer,
  clusterSize                  :: Integer,
  clusterCurrentEpoch          :: Integer,
  clusterMyEpoch               :: Integer,
  clusterStatsMessagesSent     :: Integer,
  clusterStatsMessagesReceived :: Integer
  } deriving (Show, Eq, Ord)

data ClusterState =
    ClusterStateOk
  | ClusterStateFail
  deriving (Show, Eq, Ord)

readClusterState :: ByteString -> ClusterState
readClusterState "ok" = ClusterStateOk
readClusterState _    = ClusterStateFail

instance Redis.RedisResult Info where
  decode r@(Redis.Bulk mData) = maybe (Left r) Right $ do
    lines <- fmap (fmap (Char8.filter (/= '\r')) . Char8.lines) mData
    let entries   = HashMap.fromList . Maybe.catMaybes $ fmap mkTuple lines
        lookup  k = readInteger =<< HashMap.lookup k entries
        lookup' k = readClusterState <$> HashMap.lookup k entries
    Info <$> lookup' "cluster_state"
         <*> lookup  "cluster_slots_assigned"
         <*> lookup  "cluster_slots_ok"
         <*> lookup  "cluster_slots_pfail"
         <*> lookup  "cluster_slots_fail"
         <*> lookup  "cluster_known_nodes"
         <*> lookup  "cluster_size"
         <*> lookup  "cluster_current_epoch"
         <*> lookup  "cluster_my_epoch"
         <*> lookup  "cluster_stats_messages_sent"
         <*> lookup  "cluster_stats_messages_received"
    where
      mkTuple :: ByteString -> Maybe (ByteString, ByteString)
      mkTuple x = case Char8.split ':' x of
        [key, value] -> Just (key, value)
        _            -> Nothing
  decode r = Left r

type Key = ByteString

data NodeInfo = NodeInfo {
  nodeId       :: NodeId,
  hostName     :: HostName,
  port         :: PortNumber,
  flags        :: [NodeInfoFlag],
  masterNodeId :: Maybe NodeId,
  pingSent     :: Integer,
  pongRecv     :: Integer,
  configEpoch  :: Epoch,
  linkState    :: LinkState,
  slots        :: [NodeSlot]
} deriving (Show, Eq, Ord)

data NodeInfoFlag =
    Myself    -- | The node you are contacting.
  | Master    -- | Node is a master.
  | Slave     -- | Node is a slave.
  | Pfail     -- | Node is in PFAIL state. Not reachable for the node you a re contacting, but still logically reachable (not in FAIL state).
  | Fail      -- | Node is in FAIL state. It was not reachable for multiple nodes that promoted the PFAIL state to FAIL.
  | Handshake -- | Untrusted node, we are handshaking.
  | NoAddr    -- | No address known for this node.
  | NoFlags   -- | No flags at all.
  deriving (Show, Eq, Ord)

readNodeFlags :: ByteString -> [NodeInfoFlag]
readNodeFlags = Maybe.catMaybes . fmap go . Char8.split ','
  where
    go :: ByteString -> Maybe NodeInfoFlag
    go "myself"    = Just Myself
    go "master"    = Just Master
    go "slave"     = Just Slave
    go "fail?"     = Just Pfail
    go "fail"      = Just Fail
    go "handshake" = Just Handshake
    go "noaddr"    = Just NoAddr
    go "noflags"   = Just NoFlags
    go _           = Nothing

instance Redis.RedisResult NodeInfo where
  decode r@(Redis.SingleLine line) = maybe (Left r) Right $ case Char8.words line of
    (nodeId : hostNamePort : flags : masterNodeId : pingSent : pongRecv : epoch : linkState : slots) ->
      case Char8.split ':' hostNamePort of
        [hostName, port] -> NodeInfo <$> pure nodeId
                                     <*> pure (Char8.unpack hostName)
                                     <*> readPortNumber port
                                     <*> pure (readNodeFlags flags)
                                     <*> pure (readMasterNodeId masterNodeId)
                                     <*> readInteger pingSent
                                     <*> readInteger pongRecv
                                     <*> readInteger epoch
                                     <*> readLinkState linkState
                                     <*> pure (Maybe.catMaybes $ fmap readNodeSlot slots)
        _ -> Nothing
    _ -> Nothing
  decode r = Left r

data LinkState =
    Connected
  | Disconnected
  deriving (Show, Eq, Ord)

readLinkState :: ByteString -> Maybe LinkState
readLinkState "connected"    = Just Connected
readLinkState "disconnected" = Just Disconnected
readLinkState _ = Nothing

data NodeSlot =
    SingleSlot Slot
  | SlotRange Slot Slot
  deriving (Show, Eq, Ord)

readNodeSlot :: ByteString -> Maybe NodeSlot
readNodeSlot x = case Char8.split '-' x of
  [start, end] -> SlotRange <$> readInteger start <*> readInteger end
  [slot]       -> SingleSlot <$> readInteger slot
  _ -> Nothing

data ResetOptions = Soft | Hard

type Epoch = Integer

data SetSlotSubcommand = Importing NodeId | Migrating NodeId | Stable | Node NodeId

type SlotMap = [SlotMapEntry]

data SlotMapEntry = SlotMapEntry {
  startSlot  :: Slot,
  endSlot    :: Slot,
  masterNode :: SlotMapEntryNode,
  slaveNodes :: [SlotMapEntryNode]
} deriving (Show, Eq, Ord)

instance Redis.RedisResult SlotMapEntry where
  decode r@(Redis.MultiBulk (Just (
      Redis.SingleLine startSlot
    : Redis.SingleLine endSlot
    : nodes))) =
    let entryNodes = Either.rights $ fmap Redis.decode nodes
    in maybe (Left r) Right $ case entryNodes of
      (masterNode:slaveNodes) -> SlotMapEntry <$> readInteger startSlot
                                              <*> readInteger endSlot
                                              <*> pure masterNode
                                              <*> pure slaveNodes
      _ -> Nothing
  decode r = Left r

data SlotMapEntryNode = SlotMapEntryNode {
  slotMapHostName   :: HostName,
  slotMapPortNumber :: PortNumber,
  slotMapNodeId     :: Maybe NodeId
} deriving (Show, Eq)

-- | Custom order of comparisons:
instance Ord SlotMapEntryNode where
  compare n1 n2 =
    let comparisons = [ compare `on` slotMapNodeId
                      , compare `on` slotMapHostName
                      , compare `on` slotMapPortNumber
                      ]
        compared = fmap (\λ -> λ n1 n2) comparisons
    in head $ (filter (/= EQ) compared) <> [EQ]

instance Redis.RedisResult SlotMapEntryNode where
  decode r@(Redis.MultiBulk (Just [
      Redis.SingleLine hostName
    , Redis.SingleLine portNumber
    ])) = maybe (Left r) Right $
          SlotMapEntryNode <$> pure (Char8.unpack hostName)
                           <*> readPortNumber portNumber
                           <*> pure Nothing
  decode r@(Redis.MultiBulk (Just [
      Redis.SingleLine hostName
    , Redis.SingleLine portNumber
    , Redis.SingleLine nodeId
    ])) = maybe (Left r) Right $
          SlotMapEntryNode <$> pure (Char8.unpack hostName)
                           <*> readPortNumber portNumber
                           <*> pure (Just nodeId)
  decode r = Left r
