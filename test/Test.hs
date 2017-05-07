module Main where

import Control.Monad (forM_, unless)
import Test.HUnit (Assertion, Test(..))
import qualified System.Exit as Exit
import qualified Test.Database.Redis.Cluster.CRC16 as TestCRC16
import qualified Test.Database.Redis.Cluster.Types as TestTypes
import qualified Test.HUnit as HUnit

tests :: [(String, Test)]
tests = [
    ("Database.Redis.Cluster.CRC16", TestCRC16.test)
  , ("Database.Redis.Cluster.Types", TestTypes.test)
  ]

main :: IO ()
main = forM_ tests $ \(label, test) -> do
  putStrLn label
  count <- HUnit.runTestTT test
  let green = all (==0) [HUnit.errors count, HUnit.failures count]
  unless green $ Exit.exitFailure
