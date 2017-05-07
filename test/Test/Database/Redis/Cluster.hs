{-# LANGUAGE OverloadedStrings #-}
module Test.Database.Redis.Cluster where

testHosts :: [ConnectInfo]
testHosts = do
  port <- [7000..7005]
  return Redis.defaultConnectInfo {
    connectHost = "127.0.0.1"
  , connectPort = Redis.PortNumber port
  }

allOk :: [Either a Redis.Status] -> Bool
allOk = and . fmap go
  where
    go (Right Redis.Ok) = True
    go _                = False

testRun = do
  slots <- getSlots testHosts
  putStrLn $ "All slots are empty: " <> show (slotsAreEmpty slots)
  meetings <- meet testHosts
  putStrLn $ "All meetings are Ok: " <> show (allOk meetings)
  slots <- getSlots testHosts
  putStrLn $ "All slots are empty: " <> show (slotsAreEmpty slots)
