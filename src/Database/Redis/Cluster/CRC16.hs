{-# LANGUAGE OverloadedStrings #-}
module Database.Redis.Cluster.CRC16 (
keyToSlot
) where

import Data.Bits ((.&.))
import Data.ByteString (ByteString)
import Database.Redis.Cluster.Types (Slot)
import Database.Redis.Cluster.Commands (hashSlots)
import GHC.Word (Word8, Word16)
import qualified Data.Bits as Bits
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Char8 as Char8
import qualified Data.Digest.CRC16 as CRC16
import qualified GHC.Word as Word

crc16 :: ByteString -> Word16
crc16 = ByteString.foldl (CRC16.crc16_update 0x1021 False) 0

testCrc16 :: Bool
testCrc16 = 0x31c3 == crc16 "123456789"

computeSlot :: ByteString -> Slot
computeSlot = ((.&.) $ hashSlots - 1) . fromIntegral . crc16

testComputeSlot :: Bool
testComputeSlot =
  let input = "test"
      a = computeSlot input
      b = (fromIntegral $ crc16 input) `mod` hashSlots
  in a == b

findSubKey :: ByteString -> ByteString
findSubKey key = case Char8.break (=='{') key of
  (whole, "") -> whole
  (_, xs) -> case Char8.break (=='}') (Char8.tail xs) of
    ("", _) -> key
    (subKey, _) -> subKey

testFindSubKey :: Bool
testFindSubKey =
  let cases = [ ("{user1000}.following", "user1000")
              , ("foo{}{bar}", "foo{}{bar}")
              , ("foo{{bar}}", "{bar")
              , ("foo{bar}{zap}", "bar")]
  in all (\(x, y) -> findSubKey x == y) cases

keyToSlot :: ByteString -> Slot
keyToSlot = computeSlot . findSubKey
