{-# LANGUAGE OverloadedStrings #-}
module Database.Redis.Cluster where

import Control.Monad ((<=<))
import Data.IntMap (IntMap)
import Database.Redis.Cluster.Connection (Connection, ConnectInfo)
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Data.IntMap as IntMap
import qualified Database.Redis as Redis
import qualified Database.Redis.Cluster.Commands as Commands
import qualified Database.Redis.Cluster.Connection as Connection
import qualified Database.Redis.Cluster.Types as Types

meet :: Connection -> IO [Either Redis.Reply Redis.Status]
meet = go . Map.toList . Connection.connectionMap
  where
    go :: [(ConnectInfo, Redis.Connection)] -> IO [Either Redis.Reply Redis.Status]
    go [] = return []
    go ((cInfo, _):connections') = do
      let hostName = Redis.connectHost $ Connection.unConnectInfo cInfo
          portId = Redis.connectPort $ Connection.unConnectInfo cInfo
          command = Commands.meet' hostName portId
      mapM (Redis.runRedis `flip` command) $ fmap snd connections'

chunkSlots :: Integer -> [Types.SlotRange]
chunkSlots count
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
roundRobinSlots :: Int -> [[Types.SlotRange]]
roundRobinSlots count = toRange $ distribute count [0..(2^14 - 1)]
  where
    distribute :: Int -> [Types.Slot] -> [[Types.Slot]]
    distribute     _    [] = []
    distribute count range =
      let (x, xs) = List.splitAt count range
      in x:distribute count xs

    toRange :: [[Types.Slot]] -> [[Types.SlotRange]]
    toRange = fmap (fmap (\x -> (x, x))) . List.transpose

testHosts :: [Redis.ConnectInfo]
testHosts = do
  port <- [7000..7005]
  return Redis.defaultConnectInfo {
    Redis.connectHost = "127.0.0.1"
  , Redis.connectPort = Redis.PortNumber port
  }
