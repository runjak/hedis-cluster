{-# LANGUAGE OverloadedStrings #-}
module Database.Redis.Cluster.Commands (
hashSlots, slotRange,
addSlots,
countFailureReports,
countKeysInSlot,
delSlots,
failover,
forget,
getKeysInSlot,
info,
keyslot,
meet, meet',
nodes,
replicate,
reset,
saveConfig,
setConfigEpoch,
setSlot,
slaves,
slots,
readonly,
readwrite
) where

import Data.ByteString (ByteString)
import Data.Monoid ((<>))
import Database.Redis (RedisCtx, Reply, Status, HostName, PortID)
import Network.Socket (PortNumber)
import Prelude hiding (replicate)
import Database.Redis.Cluster.Types hiding (slots)
import qualified Data.ByteString.Char8 as Char8
import qualified Data.Maybe as Maybe
import qualified Database.Redis as Redis

hashSlots :: Integer
hashSlots = 2^14

slotRange :: [Slot]
slotRange = [0..(hashSlots - 1)]

addSlots :: (RedisCtx m f) => [Slot] -> m (f Status)
addSlots [] = fail "addSlots requires at least one slot."
addSlots slots = -- FIXME TEST
  let slots' = fmap (Char8.pack . show) slots
  in Redis.sendRequest $ ["CLUSTER", "ADDSLOTS"] <> slots'

countFailureReports :: (RedisCtx m f) => NodeId -> m (f Integer)
countFailureReports nodeId = -- FIXME TEST
  let nodeId' = Char8.pack $ show nodeId
  in Redis.sendRequest ["CLUSTER", "COUNT-FAILURE-REPORTS", nodeId']

countKeysInSlot :: (RedisCtx m f) => Slot -> m (f Integer)
countKeysInSlot slot -- FIXME TEST
  | slot >= 0 && slot < hashSlots = Redis.sendRequest ["CLUSTER", "COUNTKEYSINSLOT", Char8.pack $ show slot]
  | otherwise = fail $ "Invalid slot given: " <> (show slot)

delSlots :: (RedisCtx m f) => [Slot] -> m (f Status)
delSlots [] = fail "delSlots requires at least one slot."
delSlots slots = -- FIXME TEST
  let slots' = fmap (Char8.pack . show) slots
  in Redis.sendRequest $ ["CLUSTER", "DELSLOTS"] <> slots'

failover :: (RedisCtx m f) =>  Maybe FailoverOptions -> m (f Status)
failover Nothing = Redis.sendRequest ["CLUSTER", "FAILOVER"] -- FIXME TEST
failover (Just Force) = Redis.sendRequest ["CLUSTER", "FAILOVER", "FORCE"]
failover (Just Takeover) = Redis.sendRequest ["CLUSTER", "FAILOVER", "TAKEOVER"]

forget :: (RedisCtx m f) => NodeId -> m (f Status)
forget nodeId = -- FIXME TEST
  let nodeId' = Char8.pack $ show nodeId
  in Redis.sendRequest ["CLUSTER", "FORGET", nodeId']

getKeysInSlot :: (RedisCtx m f) => Slot -> Count -> m (f [ByteString])
getKeysInSlot slot count =
  let slot' = Char8.pack $ show slot
      count' = Char8.pack $ show count
  in Redis.sendRequest ["CLUSTER", "GETKEYSINSLOT", slot', count'] -- FIXME TEST

info :: (RedisCtx m f) => m (f Info)
info = Redis.sendRequest ["CLUSTER", "INFO"] -- FIXME TEST

keyslot :: (RedisCtx m f) => Key -> m (f Slot)
keyslot key = Redis.sendRequest ["CLUSTER", "KEYSLOT", key] -- FIXME TEST

{-|
  Command a node to meet another node.
  PortNumber is expected to be the client facing PortNumber,
  and PortNumber for usage between nodes will be computed from it.
|-}
meet :: (RedisCtx m f) => HostName -> PortNumber -> m (f Status)
meet host port = do
  let host' = Char8.pack host
      port' = Char8.pack $ show port
  Redis.sendRequest ["CLUSTER", "MEET", host', port']

-- | Wrap meet for PortID instead of PortNumber.
meet' :: (RedisCtx m f) => HostName -> PortID -> m (f Status)
meet' host port =
  let port' = toClusterPortNumber port
  in maybe (fail "Invalid PortID given.") (meet host) port'
  where
    toClusterPortNumber :: PortID -> Maybe PortNumber
    toClusterPortNumber (Redis.Service _)    = Nothing
    toClusterPortNumber (Redis.UnixSocket _) = Nothing
    toClusterPortNumber (Redis.PortNumber p) = Just p

nodes :: (RedisCtx m f) => m (f NodeInfos)
nodes = Redis.sendRequest ["CLUSTER", "NODES"]

replicate :: (RedisCtx m f) => NodeId -> m (f Status)
replicate nodeId = Redis.sendRequest ["CLUSTER", "REPLICATE", nodeId]

reset :: (RedisCtx m f) => ResetOptions -> m (f Status)
reset Soft = Redis.sendRequest ["RESET", "SOFT"] -- FIXME TEST
reset Hard = Redis.sendRequest ["RESET", "HARD"]

saveConfig :: (RedisCtx m f) => m (f Status)
saveConfig = Redis.sendRequest ["CLUSTER", "SAVECONFIG"] -- FIXME TEST

setConfigEpoch :: (RedisCtx m f) => Epoch -> m (f Status)
setConfigEpoch epoch = Redis.sendRequest ["CLUSTER", "SET-CONFIG-EPOCH", Char8.pack $ show epoch] -- FIXME TEST

setSlot :: (RedisCtx m f) => Slot -> SetSlotSubcommand -> m (f Status)
setSlot slot slotCommand -- FIXME TEST
  | slot < hashSlots && slot >= 0 =
    let slot' = Char8.pack $ show slot
        baseCommand = ["CLUSTER", "SETSLOT", slot']
    in Redis.sendRequest $ baseCommand <> process slotCommand
  | otherwise = fail $ "Invalid slot number: " <> (show slot)
  where
    process :: SetSlotSubcommand -> [ByteString]
    process (Importing nodeId) = ["IMPORTING", Char8.pack $ show nodeId]
    process (Migrating nodeId) = ["MIGRATING", Char8.pack $ show nodeId]
    process Stable = ["STABLE"]
    process (Node nodeId) = ["NODE", Char8.pack $ show nodeId]

slaves :: (RedisCtx m f) => NodeId -> m (f NodeInfos)
slaves nodeId =
  let nodeId' = Char8.pack $ show nodeId
  in Redis.sendRequest ["CLUSTER", "SLAVES", nodeId'] -- FIXME TEST

slots :: (RedisCtx m f) => m (f SlotMap)
slots = Redis.sendRequest ["CLUSTER", "SLOTS"]

readonly :: (RedisCtx m f) => m (f Status)
readonly = Redis.sendRequest ["READONLY"]  -- FIXME TEST

readwrite :: (RedisCtx m f) => m (f Status)
readwrite = Redis.sendRequest ["READWRITE"]  -- FIXME TEST
