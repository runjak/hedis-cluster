{-# LANGUAGE OverloadedStrings #-}
module Database.Redis.Cluster where

import Data.Monoid ((<>))
import Database.Redis (ConnectInfo(..), Connection)
import Database.Redis.Cluster.Types (SlotMap, Slot)
import qualified Database.Redis as Redis
import qualified Database.Redis.Cluster.Commands as Commands

-- FIXME return wrapper that makes more sense instead!
connect :: [ConnectInfo] -> IO [Connection]
connect = mapM Redis.checkedConnect

meet :: [ConnectInfo] -> IO [Either Redis.Reply Redis.Status]
meet (x:xs) = do
  let hostName = Redis.connectHost x
      portID = Redis.connectPort x
      command = Commands.meet' hostName portID
  connections <- connect xs
  mapM (Redis.runRedis `flip` command) connections
meet _ = return []

getSlots :: [ConnectInfo] -> IO [Either Redis.Reply SlotMap]
getSlots cInfos = do
  connections <- connect cInfos
  mapM (Redis.runRedis `flip` Commands.slots) connections

slotsAreEmpty :: [Either a SlotMap] -> Bool
slotsAreEmpty = and . fmap go
  where
    go (Right []) = True
    go _          = False

chunkSlots :: Int -> [[Slot]]
chunkSlots count = []

roundRobinSlots :: Int -> [[Slot]]
roundRobinSlots count = []
