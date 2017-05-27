{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
module Simple where

import Control.Monad
import Data.Monoid ((<>))
import qualified Data.Either as Either
import qualified Database.Redis as Redis
import qualified Data.ByteString.Char8 as Char8

testHosts :: [Redis.ConnectInfo]
testHosts = do
  port <- [7000..7005]
  return Redis.defaultConnectInfo {
    Redis.connectHost = "127.0.0.1"
  , Redis.connectPort = Redis.PortNumber port
  }

masterReplicaTest :: IO ()
masterReplicaTest = do
  let [master, replica] = take 2 testHosts

  putStrLn "Hosts to use:"
  print [master, replica]

  mConnection <- Redis.connect master
  rConnection <- Redis.connect replica

  let slotRange = fmap (Char8.pack . show) [0..(2^14 - 1)]
      assignSlots = Redis.sendRequest $ ["CLUSTER", "ADDSLOTS"] <> slotRange
  (assignment :: Either Redis.Reply Redis.Status) <- Redis.runRedis mConnection assignSlots

  putStrLn "Assign slots to master:"
  print assignment

  let meetMaster = Redis.sendRequest ["CLUSTER", "MEET", "127.0.0.1", "7000"]
  (meeting :: Either Redis.Reply Redis.Status) <- Redis.runRedis rConnection meetMaster

  putStrLn "Meeting the master:"
  print meeting

  let getNodes = Redis.sendRequest ["CLUSTER", "NODES"]
  (masterNodes :: Either Redis.Reply Redis.Reply) <- Redis.runRedis mConnection getNodes

  putStrLn "Master nodes:"
  print masterNodes

  let (Right (Redis.Bulk (Just reply))) = masterNodes
      masterLine = head . filter (Char8.isInfixOf "myself") $ Char8.lines reply
      masterId = head $ Char8.words masterLine

  putStrLn "Master has id:"
  print masterId

  let replicateMaster = Redis.sendRequest ["CLUSTER", "REPLICATE", masterId]
  (replication :: Either Redis.Reply Redis.Status) <- Redis.runRedis rConnection replicateMaster

  putStrLn "Replication status:"
  print replication

  (nodeInfo :: [Either Redis.Reply Redis.Reply]) <- mapM (Redis.runRedis `flip` getNodes) [mConnection, rConnection]
  putStrLn "Node info:"
  mapM print $ Either.rights nodeInfo

  return ()
