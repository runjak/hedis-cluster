{-# LANGUAGE OverloadedStrings #-}
module Database.Redis.Cluster.Types (
Slot,
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
import Data.Monoid ((<>))
import Database.Redis (HostName)
import Network.Socket (PortNumber)
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Char8 as Char8
import qualified Data.Char as Char
import qualified Data.Either as Either
import qualified Data.HashMap.Strict as HashMap
import qualified Data.Maybe as Maybe
import qualified Database.Redis as Redis

readInteger :: ByteString -> Maybe Integer
readInteger = fmap fst . Char8.readInteger

readPortNumber :: ByteString -> Maybe PortNumber
readPortNumber x = case reads (Char8.unpack x) of
  [(p, _)] -> Just p
  _ -> Nothing

type Slot = Integer

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

testInfoData :: Redis.Reply
testInfoData = Redis.Bulk . Just $ ByteString.intercalate "\r\n" [
    "cluster_state:ok"
  , "cluster_slots_assigned:16384"
  , "cluster_slots_ok:16384"
  , "cluster_slots_pfail:0"
  , "cluster_slots_fail:0"
  , "cluster_known_nodes:6"
  , "cluster_size:3"
  , "cluster_current_epoch:6"
  , "cluster_my_epoch:2"
  , "cluster_stats_messages_sent:1483972"
  , "cluster_stats_messages_received:1483968"
  ]

testInfoDecode :: Either Redis.Reply Info
testInfoDecode = Redis.decode testInfoData

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

testNodeInfoData :: Redis.Reply
testNodeInfoData = Redis.MultiBulk . Just $ fmap Redis.SingleLine [
    "07c37dfeb235213a872192d90877d0cd55635b91 127.0.0.1:30004 slave         e7d1eecce10fd6bb5eb35b9f99a514335d9ba9ca 0 1426238317239 4 connected"
  , "67ed2db8d677e59ec4a4cefb06858cf2a1a89fa1 127.0.0.1:30002 master        -                                        0 1426238316232 2 connected 5461-10922"
  , "292f8b365bb7edb5e285caf0b7e6ddc7265d2f4f 127.0.0.1:30003 master        -                                        0 1426238318243 3 connected 10923-16383"
  , "6ec23923021cf3ffec47632106199cb7f496ce01 127.0.0.1:30005 slave         67ed2db8d677e59ec4a4cefb06858cf2a1a89fa1 0 1426238316232 5 connected"
  , "824fe116063bc5fcf9f4ffd895bc17aee7731ac3 127.0.0.1:30006 slave         292f8b365bb7edb5e285caf0b7e6ddc7265d2f4f 0 1426238317741 6 connected"
  , "e7d1eecce10fd6bb5eb35b9f99a514335d9ba9ca 127.0.0.1:30001 myself,master -                                        0             0 1 connected 0-5460"
  ]

testNodeInfoDecode :: Either Redis.Reply [NodeInfo]
testNodeInfoDecode = Redis.decode testNodeInfoData

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
} deriving (Show, Eq, Ord)

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

testSlotMapData :: Redis.Reply
testSlotMapData =
  let l = Redis.SingleLine
      m = Redis.MultiBulk . Just
      a = m . fmap l
  in m [
      m [
        m [l "0",     l "4095",  a ["127.0.0.1", "7000"], a ["127.0.0.1", "7004"]]
      , m [l "12288", l "16383", a ["127.0.0.1", "7003"], a ["127.0.0.1", "7007"]]
      , m [l "4096",  l "8191",  a ["127.0.0.1", "7001"], a ["127.0.0.1", "7005"]]
      , m [l "8192",  l "12287", a ["127.0.0.1", "7002"], a ["127.0.0.1", "7006"]]]
    , m [
        m [l "0",     l "5460",  a ["127.0.0.1", "30001", "09dbe9720cda62f7865eabc5fd8857c5d2678366"]
                              ,  a ["127.0.0.1", "30004", "821d8ca00d7ccf931ed3ffc7e3db0599d2271abf"]]
      , m [l "5461",  l "10922", a ["127.0.0.1", "30002", "c9d93d9f2c0c524ff34cc11838c2003d8c29e013"]
                               , a ["127.0.0.1", "30005", "faadb3eb99009de4ab72ad6b6ed87634c7ee410f"]]
      , m [l "10923", l "16383", a ["127.0.0.1", "30003", "044ec91f325b7595e76dbcb18cc688b6a5b434a1"]
                               , a ["127.0.0.1", "30006", "58e6e48d41228013e5d9c1c37c5060693925e97e"]]]
    ]

testSlotMapDecode :: Either Redis.Reply [SlotMap]
testSlotMapDecode = Redis.decode testSlotMapData
