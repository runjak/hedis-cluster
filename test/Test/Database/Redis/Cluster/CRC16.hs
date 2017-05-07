{-# LANGUAGE OverloadedStrings #-}
module Test.Database.Redis.Cluster.CRC16 (test) where

import Database.Redis.Cluster.Commands (hashSlots)
import Test.HUnit (Assertion, Test(..))
import qualified Database.Redis.Cluster.CRC16 as CRC16
import qualified Test.HUnit as HUnit

test :: Test
test = TestList $ fmap TestCase [
    assertCrc16
  , assertComputeSlot
  , assertFindSubKey
  ]

assertCrc16 :: Assertion
assertCrc16 = HUnit.assertBool "CRC16.crc16" testCrc16
  where
    testCrc16 :: Bool
    testCrc16 = 0x31c3 == CRC16.crc16 "123456789"

assertComputeSlot :: Assertion
assertComputeSlot = HUnit.assertBool "CRC16.computeSlot" testComputeSlot
  where
    testComputeSlot :: Bool
    testComputeSlot =
      let input = "test"
          a = CRC16.computeSlot input
          b = (fromIntegral $ CRC16.crc16 input) `mod` hashSlots
      in a == b

assertFindSubKey :: Assertion
assertFindSubKey = HUnit.assertBool "CRC16.findSubKey" testFindSubKey
  where
    testFindSubKey :: Bool
    testFindSubKey =
      let cases = [ ("{user1000}.following", "user1000")
                  , ("foo{}{bar}", "foo{}{bar}")
                  , ("foo{{bar}}", "{bar")
                  , ("foo{bar}{zap}", "bar")]
      in all (\(x, y) -> CRC16.findSubKey x == y) cases
