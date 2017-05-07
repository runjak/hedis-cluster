{-# LANGUAGE OverloadedStrings #-}
module Database.Redis.Cluster.CRC16 (
crc16,
computeSlot,
findSubKey,
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

-- | The crc16 variant to use with Redis.
crc16 :: ByteString -> Word16
crc16 = ByteString.foldl (CRC16.crc16_update 0x1021 False) 0

-- | Compute a Slot for a given ByteString.
computeSlot :: ByteString -> Slot
computeSlot = ((.&.) $ hashSlots - 1) . fromIntegral . crc16

-- | Find the section of a key to compute the slot for.
findSubKey :: ByteString -> ByteString
findSubKey key = case Char8.break (=='{') key of
  (whole, "") -> whole
  (_, xs) -> case Char8.break (=='}') (Char8.tail xs) of
    ("", _) -> key
    (subKey, _) -> subKey

-- | Compute the slot for a key.
keyToSlot :: ByteString -> Slot
keyToSlot = computeSlot . findSubKey
