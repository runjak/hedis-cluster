{-# LANGUAGE OverloadedStrings #-}
module Database.Redis.Cluster.Connection where

import Data.Function (on)
import Data.IntMap (IntMap)
import Data.Map (Map)
import Data.Monoid ((<>))
import qualified Data.IntMap as IntMap
import qualified Data.Map as Map
import qualified Data.Maybe as Maybe
import qualified Database.Redis as Redis
import qualified Database.Redis.Cluster.Commands as Commands
import qualified Database.Redis.Cluster.Types as Types

data ConnectInfo = ConnectInfo {
    unConnectInfo :: Redis.ConnectInfo,
    nodeId :: Maybe Types.NodeId
} deriving (Show)

instance Eq ConnectInfo where
  c1 == c2 =
    let π = unConnectInfo
        comparisons = [
          (==) `on` nodeId,
          (==) `on` (Redis.connectHost . π),
          (==) `on` (Redis.connectPort . π),
          (==) `on` (Redis.connectAuth . π),
          (==) `on` (Redis.connectDatabase . π),
          (==) `on` (Redis.connectMaxConnections . π),
          (==) `on` (Redis.connectMaxIdleTime . π)
          ]
    in all (\λ -> λ c1 c2) comparisons

instance Ord ConnectInfo where
  compare c1 c2 =
    let π = unConnectInfo
        comparisons = [
          compare `on` nodeId,
          compare `on` (Redis.connectHost . π),
          compare `on` (PortID . Redis.connectPort . π),
          compare `on` (Redis.connectAuth . π),
          compare `on` (Redis.connectDatabase . π),
          compare `on` (Redis.connectMaxConnections . π),
          compare `on` (Redis.connectMaxIdleTime . π)
          ]
        compared = fmap (\λ -> λ c1 c2) comparisons
    in head $ (filter (/= EQ) compared) <> [EQ]

{-|
  Newtype to implement Ord as a wrapper for Redis.PortID
|-}
newtype PortID = PortID {unPortID :: Redis.PortID}
  deriving (Eq)

instance Ord PortID where
  (PortID (Redis.Service    s1)) <= (PortID    (Redis.Service s2)) = s1 <= s2
  (PortID (Redis.Service    s1)) <= (PortID                     _) = True
  (PortID (Redis.PortNumber p1)) <= (PortID     (Redis.Service _)) = False
  (PortID (Redis.PortNumber p1)) <= (PortID (Redis.PortNumber p2)) = p1 <= p2
  (PortID (Redis.PortNumber p1)) <= (PortID                     _) = True
  (PortID (Redis.UnixSocket s1)) <= (PortID (Redis.UnixSocket s2)) = s1 <= s2
  (PortID (Redis.UnixSocket s1)) <= (PortID                     _) = False

class ToConnectInfo i where
  toConnectInfo :: i -> ConnectInfo

instance ToConnectInfo Redis.ConnectInfo where
  toConnectInfo i = ConnectInfo i Nothing

instance ToConnectInfo Types.SlotMapEntryNode where
  toConnectInfo i = ConnectInfo {
    unConnectInfo = Redis.defaultConnectInfo {
      Redis.connectHost = Types.slotMapHostName i,
      Redis.connectPort = Redis.PortNumber $ Types.slotMapPortNumber i
    },
    nodeId = Types.slotMapNodeId i
  }

type ConnectionMap = Map ConnectInfo Redis.Connection

type SlotConnectionMap = IntMap (ConnectInfo, [ConnectInfo])

data Connection = Connection {
  connectionMap     :: ConnectionMap,
  slotConnectionMap :: SlotConnectionMap
}

{-|
  Show instance added to aid debugging.
|-}
instance Show Connection where
  show connection = unlines [
    "Connection {connectionMap = ",
    show . Map.map (const "…") $ connectionMap connection,
    ", slotConnectionMap = ",
    show $ slotConnectionMap connection,
    "}"]

{-|
  Build the connection structure to a cluster
  and tries to fetch an initial slotMap.

  FIXME how to handle authorization against a cluster with potentially changing nodes?

  Idea: We could provide an interface that 'knows' how to get the authorization info
  so that different schemes can be provided as necessary.
|-}
connect :: (ToConnectInfo info) => [info] -> IO Connection
connect infos' = do
  let infos = fmap toConnectInfo infos'
  connections <- mapM (Redis.connect . unConnectInfo) infos
  return $ Connection {
    connectionMap = Map.fromList $ zip infos connections,
    slotConnectionMap = IntMap.empty
  }

updateSlotMap :: Connection -> Types.SlotMap -> IO Connection
updateSlotMap conn slotMap = do
  let slotTuples = fmap (\s -> (fromInteger $ Types.startSlot s,
                                toConnectInfo $ Types.masterNode s,
                                toConnectInfo <$> Types.slaveNodes s))
                        slotMap
      newSlotMap = IntMap.fromList $ fmap (\(i,m,s) -> (fromInteger i,
                                                        (m, s)))
                                          slotTuples
      cInfos = (\(_, m, s) -> m:s) =<< slotTuples
  newConnections <- mapM (Redis.connect . unConnectInfo) cInfos
  let newConnMap = Map.fromList $ zip cInfos newConnections
  return $ Connection {
    connectionMap = Map.union (connectionMap conn) newConnMap,
    slotConnectionMap = newSlotMap
  }

{-|
  Obtain a list of all Redis.Connection known to a Connection.
|-}
getRedisConnections :: Connection -> [Redis.Connection]
getRedisConnections = Map.elems . connectionMap

{-|
  Obtain a list of all Redis.Connection known as master nodes.
|-}
getMasterRedisConnections :: Connection -> [Redis.Connection]
getMasterRedisConnections connection =
  let masters = fmap fst . IntMap.elems $ slotConnectionMap connection
      lookup = Map.lookup `flip` (connectionMap connection)
  in Maybe.catMaybes $ fmap lookup masters

{-|
  Obtain a list of all Redis.Connection known as slave nodes.
|-}
getSlaveRedisConnections :: Connection -> [Redis.Connection]
getSlaveRedisConnections connection =
  let slaves = concat . fmap snd . IntMap.elems $ slotConnectionMap connection
      lookup = Map.lookup `flip` (connectionMap connection)
  in Maybe.catMaybes $ fmap lookup slaves

{-|
  Sequentially bother all given Redis.Connection with a given command.
|-}
redisAll :: [Redis.Connection] -> Redis.Redis b -> IO [b]
redisAll connections command = mapM (Redis.runRedis `flip` command) connections

{-|
  Sequentially bother given Redis.Connection with a command till first success.
|-}
redisTillSuccess :: [Redis.Connection] -> Redis.Redis (Either Redis.Reply b) -> IO ([Redis.Reply], Maybe b)
redisTillSuccess = go []
  where
    go errors     [] command = return (reverse errors, Nothing)
    go errors (c:cs) command =
      let onLeft  e = go (e:errors) cs command
          onRight x = return (reverse errors, Just x)
      in either onLeft onRight =<< Redis.runRedis c command
