{-# LANGUAGE OverloadedStrings #-}
module Database.Redis.Cluster where

import Control.Arrow ((&&&))
import Control.Monad
import Data.Monoid ((<>))
import Data.IntMap (IntMap)
import Database.Redis.Cluster.Connection (Connection, ConnectInfo)
import qualified Control.Concurrent as Concurrent
import qualified Data.Either as Either
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Data.IntMap as IntMap
import qualified Database.Redis as Redis
import qualified Database.Redis.Cluster.Commands as Commands
import qualified Database.Redis.Cluster.Connection as Connection
import qualified Database.Redis.Cluster.Types as Types

meet :: Connection -> IO [Either Redis.Reply Redis.Status]
meet = meet' . Map.toList . Connection.connectionMap

meet' :: [(ConnectInfo, Redis.Connection)] -> IO [Either Redis.Reply Redis.Status]
meet' [] = return []
meet' ((_, conn):cs) = do
  let hostPortTuples = fmap ((Redis.connectHost &&& Redis.connectPort) . Connection.unConnectInfo . fst) cs
      commands = fmap (uncurry Commands.meet') hostPortTuples
  mapM (Redis.runRedis conn) commands

chunkSlots :: [Redis.Connection] -> IO [Either Redis.Reply Redis.Status]
chunkSlots connections =
  let slotRanges = chunkSlots' . fromIntegral $ length connections
  in zipWithM go connections slotRanges
  where
    go connection (startSlot, endSlot) =
      let command = Commands.addSlots [startSlot .. endSlot]
      in Redis.runRedis connection command

chunkSlots' :: Integer -> [Types.SlotRange]
chunkSlots' count
  | count <= 0 = []
  | otherwise =
    let (d, m) = (2^14) `divMod` count
    in fmap (mkRange d m) [0..(count - 1)]
    where
      mkRange d m i =
        let i' = i + 1
            addM = if i == 0 then m else 0
            addM' = m - addM
        in (i * d + addM', i' * d + addM + addM' - 1)

{-|
  Round robin distribution will likely not be practical,
  but can be used for testing purposes.
|-}
roundRobinSlots :: [Redis.Connection] -> IO [Either Redis.Reply Redis.Status]
roundRobinSlots connections =
  let slotRanges = roundRobinSlots' $ length connections
      runAddSlots conn range = Redis.runRedis conn $ Commands.addSlots range
  in zipWithM runAddSlots connections slotRanges

roundRobinSlots' :: Int -> [[Types.Slot]]
roundRobinSlots' count = List.transpose $ distribute count Commands.slotRange
  where
    distribute :: Int -> [Types.Slot] -> [[Types.Slot]]
    distribute     _    [] = []
    distribute count range =
      let (x, xs) = List.splitAt count range
      in x:distribute count xs

{-|
  This function is evil and may throw at you.
|-}
-- setupChunked :: Connection -> Int -> IO Bool
setupChunked connection replication = do
  let connections = Map.toList $ Connection.connectionMap connection
      masterCount = (length connections) `div` replication
      (masters, slaves) = splitAt masterCount connections
      connections' = fmap snd connections
      (masters', slaves') = splitAt masterCount connections'
      -- allOk = all (== (Right Redis.Ok))

  flushes <- Connection.redisAll connections' Redis.flushall
  -- unless (allOk flushes) . fail $
  --   "Some flushes failed: " <> show (Either.lefts flushes)

  resets <- Connection.redisAll connections' $ Commands.reset Types.Hard
  --unless (allOk resets) . fail $
  --  "Some resets failed: " <> show (Either.lefts resets)

  masterMeetings <- meet' masters
  putStrLn "Master meetings:"
  print masterMeetings

  slotAssignments <- chunkSlots masters'
  -- unless (allOk slotAssignments) . fail $
  --   "Some slotAssignments failed: " <> show (Either.lefts slotAssignments)

  putStrLn "Slots assigned."
  print slotAssignments
  Concurrent.threadDelay 1000000

  -- meetings <- meet connection
  -- unless (allOk meetings) . fail $
  --   "Some meetings failed: " <> show (Either.lefts meetings)

  masterNodeInfoLists' <- mapM (Redis.runRedis `flip` Commands.nodes) masters'
  let masterNodeInfoLists = Types.unNodeInfos <$> Either.rights masterNodeInfoLists'
  unless (length masterNodeInfoLists == masterCount) . fail $
    "Failed to aquire all nodeInfos: " <> show (Either.lefts masterNodeInfoLists')

  let filterMyselfs = filter (List.elem Types.Myself . Types.flags) . concat :: [[Types.NodeInfo]] -> [Types.NodeInfo]
      masterNodeIds = Types.nodeId <$> filterMyselfs masterNodeInfoLists
      -- masterHostnamePorts = (Just . (Types.hostName &&& Types.port)) <$> filterMyselfs masterNodeInfoLists

  -- zipWithM (\s mhp -> Redis.runRedis s $ Commands.slaveOf mhp) slaves masterHostnamePorts

  slaveMeetings <- meet' $ head masters : slaves
  putStrLn "Joined slaves to cluster."
  print slaveMeetings

  replications <- zipWithM Redis.runRedis slaves' $ fmap (Commands.replicate) masterNodeIds

  putStrLn "Replicated."

  return replications
  -- unless (allOk replications) . fail $
  --   "Failed to setup all replications: " <> show (Either.lefts replications)

  -- slotMaps <- mapM (Redis.runRedis `flip` Commands.slots) connections
  -- connection' <- foldM Connection.updateSlotMap connection $ Either.rights slotMaps

  -- return connection'

testHosts :: [Redis.ConnectInfo]
testHosts = do
  port <- [7000..7005]
  return Redis.defaultConnectInfo {
    Redis.connectHost = "127.0.0.1"
  , Redis.connectPort = Redis.PortNumber port
  }

testSetupChunked = do
  connection <- Connection.connect testHosts
  setupChunked connection 2

testReplication = do
  connection <- Connection.connect testHosts
  meet connection
  let (m:s:_) = Connection.getRedisConnections connection
  return (m, s)

testSlots = do
  connection <- Connection.connect testHosts
  let connections = Connection.getRedisConnections connection
  Connection.redisAll connections Commands.slots

testMeet = do
  connection <- Connection.connect testHosts
  meet connection

testInfo = do
  connection <- Connection.connect testHosts
  let connections = Connection.getRedisConnections connection
  mapM (Redis.runRedis `flip` Commands.info) connections

testNodes = do
  connection <- Connection.connect testHosts
  let connections = Connection.getRedisConnections connection
  mapM (Redis.runRedis `flip` Commands.nodes) connections
