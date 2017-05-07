{-# LANGUAGE OverloadedStrings #-}
module Test.Database.Redis.Cluster.Types (test) where

import Test.HUnit (Assertion, Test(..))
import qualified Data.ByteString as ByteString
import qualified Data.Either as Either
import qualified Database.Redis.Cluster.Types as Types
import qualified Database.Redis as Redis
import qualified Test.HUnit as HUnit

test :: Test
test = TestList $ fmap TestCase [
    assertInfoDecode
  , assertNodeInfoDecode
  , assertSlotMapDecode
  ]

assertEither :: String -> Either a b -> Assertion
assertEither msg = HUnit.assertBool msg . Either.isRight

assertInfoDecode :: Assertion
assertInfoDecode = assertEither "Redis.decode Types.Info" testInfoDecode
  where
    testInfoDecode :: Either Redis.Reply Types.Info
    testInfoDecode = Redis.decode testInfoData

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

assertNodeInfoDecode :: Assertion
assertNodeInfoDecode = assertEither "Redis.decode Types.NodeInfo" testNodeInfoDecode
  where
    testNodeInfoDecode :: Either Redis.Reply [Types.NodeInfo]
    testNodeInfoDecode = Redis.decode testNodeInfoData

    testNodeInfoData :: Redis.Reply
    testNodeInfoData = Redis.MultiBulk . Just $ fmap Redis.SingleLine [
        "07c37dfeb235213a872192d90877d0cd55635b91 127.0.0.1:30004 slave         e7d1eecce10fd6bb5eb35b9f99a514335d9ba9ca 0 1426238317239 4 connected"
      , "67ed2db8d677e59ec4a4cefb06858cf2a1a89fa1 127.0.0.1:30002 master        -                                        0 1426238316232 2 connected 5461-10922"
      , "292f8b365bb7edb5e285caf0b7e6ddc7265d2f4f 127.0.0.1:30003 master        -                                        0 1426238318243 3 connected 10923-16383"
      , "6ec23923021cf3ffec47632106199cb7f496ce01 127.0.0.1:30005 slave         67ed2db8d677e59ec4a4cefb06858cf2a1a89fa1 0 1426238316232 5 connected"
      , "824fe116063bc5fcf9f4ffd895bc17aee7731ac3 127.0.0.1:30006 slave         292f8b365bb7edb5e285caf0b7e6ddc7265d2f4f 0 1426238317741 6 connected"
      , "e7d1eecce10fd6bb5eb35b9f99a514335d9ba9ca 127.0.0.1:30001 myself,master -                                        0             0 1 connected 0-5460"
      ]

assertSlotMapDecode :: Assertion
assertSlotMapDecode = assertEither "Redis.Decode Types.SlotMap" testSlotMapDecode
  where
    testSlotMapDecode :: Either Redis.Reply [Types.SlotMap]
    testSlotMapDecode = Redis.decode testSlotMapData

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
