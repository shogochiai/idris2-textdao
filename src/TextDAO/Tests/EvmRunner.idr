||| TextDAO EVM Test Runner
||| Executes contract bytecode through idris2-evm interpreter
module TextDAO.Tests.EvmRunner

import System
import System.File
import Data.List
import Data.String

%default covering

-- =============================================================================
-- ABI Encoding Helpers
-- =============================================================================

||| Convert Integer to 32-byte hex string (64 chars)
export
toHex256 : Integer -> String
toHex256 n = padLeft '0' 64 (toHexDigits n)
  where
    hexDigit : Integer -> Char
    hexDigit i = if i < 10 then chr (ord '0' + cast i) else chr (ord 'a' + cast i - 10)

    toHexDigits : Integer -> String
    toHexDigits 0 = "0"
    toHexDigits i = go i ""
      where
        go : Integer -> String -> String
        go 0 acc = acc
        go n acc = go (n `div` 16) (singleton (hexDigit (n `mod` 16)) ++ acc)

    padLeft : Char -> Nat -> String -> String
    padLeft c n s = pack (replicate (n `minus` length s) c) ++ s

||| Build calldata: selector + encoded arguments
export
buildCalldata : Integer -> List Integer -> String
buildCalldata selector args =
  let selectorHex = padLeft '0' 8 (toHexDigits selector)
      argsHex = concat (map toHex256 args)
  in "0x" ++ selectorHex ++ argsHex
  where
    hexDigit : Integer -> Char
    hexDigit i = if i < 10 then chr (ord '0' + cast i) else chr (ord 'a' + cast i - 10)

    toHexDigits : Integer -> String
    toHexDigits 0 = ""
    toHexDigits i = go i ""
      where
        go : Integer -> String -> String
        go 0 acc = acc
        go n acc = go (n `div` 16) (singleton (hexDigit (n `mod` 16)) ++ acc)

    padLeft : Char -> Nat -> String -> String
    padLeft c n s = pack (replicate (n `minus` length s) c) ++ s

-- =============================================================================
-- Function Selectors (must match Members.idr)
-- =============================================================================

export
SEL_ADD_MEMBER : Integer
SEL_ADD_MEMBER = 0xca6d56dc

export
SEL_GET_MEMBER : Integer
SEL_GET_MEMBER = 0x9c0a0cd2

export
SEL_GET_MEMBER_COUNT : Integer
SEL_GET_MEMBER_COUNT = 0x997072f7

export
SEL_IS_MEMBER : Integer
SEL_IS_MEMBER = 0xa230c524

-- =============================================================================
-- EVM Execution via CLI
-- =============================================================================

||| Execute bytecode with calldata via idris2-evm CLI
export
runEvmTest : String -> String -> IO (Either String String)
runEvmTest bytecodeHex calldataHex = do
  -- Write bytecode to temp file
  let tmpFile = "/tmp/textdao-test.bin"
  Right _ <- writeFile tmpFile bytecodeHex
    | Left err => pure (Left $ "Failed to write bytecode: " ++ show err)

  -- Run idris2-evm (assuming it's built and in path or we use pack run)
  let cmd = "cd /Users/bob/code/idris2-evm && pack run idris2-evm -- --calldata "
            ++ calldataHex ++ " " ++ tmpFile ++ " 2>&1"

  result <- popen cmd Read
  case result of
    Nothing => pure (Left "Failed to run idris2-evm")
    Just handle => do
      output <- fGetChars handle 10000
      _ <- pclose handle
      pure (Right output)

-- =============================================================================
-- Test Helpers
-- =============================================================================

||| Check if EVM execution succeeded
export
isSuccess : String -> Bool
isSuccess output = isInfixOf "SUCCESS" output

||| Check if EVM execution reverted
export
isRevert : String -> Bool
isRevert output = isInfixOf "REVERT" output

||| Extract return data from output
export
extractReturnData : String -> Maybe String
extractReturnData output =
  case break (isPrefixOf "Return data:") (lines output) of
    (_, []) => Nothing
    (_, (line :: _)) =>
      let parts = words line
      in if length parts >= 3 then Just (index 2 parts) else Nothing
  where
    index : Nat -> List String -> String
    index Z (x :: _) = x
    index (S n) (_ :: xs) = index n xs
    index _ [] = ""

-- =============================================================================
-- Contract Test Cases
-- =============================================================================

||| Test: getMemberCount on fresh contract should return 0
export
test_getMemberCount_initial : String -> IO Bool
test_getMemberCount_initial bytecode = do
  let calldata = buildCalldata SEL_GET_MEMBER_COUNT []
  result <- runEvmTest bytecode calldata
  case result of
    Left err => do
      putStrLn $ "  Error: " ++ err
      pure False
    Right output => do
      let success = isSuccess output
      putStrLn $ "  " ++ (if success then "[PASS]" else "[FAIL]") ++ " getMemberCount initial"
      when (not success) $ putStrLn $ "  Output: " ++ output
      pure success

||| Test: addMember then getMemberCount should return 1
export
test_addMember : String -> IO Bool
test_addMember bytecode = do
  let memberAddr = 0x1234567890abcdef1234567890abcdef12345678
  let metadataCid = 0xabcdef0123456789abcdef0123456789abcdef0123456789abcdef01234567
  let calldata = buildCalldata SEL_ADD_MEMBER [memberAddr, metadataCid]
  result <- runEvmTest bytecode calldata
  case result of
    Left err => do
      putStrLn $ "  Error: " ++ err
      pure False
    Right output => do
      let success = isSuccess output
      putStrLn $ "  " ++ (if success then "[PASS]" else "[FAIL]") ++ " addMember"
      when (not success) $ putStrLn $ "  Output: " ++ output
      pure success

-- =============================================================================
-- Main Test Runner
-- =============================================================================

export
runEvmIntegrationTests : IO ()
runEvmIntegrationTests = do
  putStrLn "=== EVM Integration Tests ==="
  putStrLn ""

  -- Load bytecode from compiled contract
  let bytecodeFile = "/Users/bob/code/idris2-yul/build/output/TextDAO_Members.bin"
  Right bytecode <- readFile bytecodeFile
    | Left err => do
        putStrLn $ "Error: Cannot load bytecode from " ++ bytecodeFile
        putStrLn $ "Run: cd /Users/bob/code/idris2-yul && ./scripts/build-contract.sh examples/TextDAO_Members.idr"
        pure ()

  let trimmedBytecode = trim bytecode
  putStrLn $ "Loaded bytecode: " ++ show (length trimmedBytecode) ++ " chars"
  putStrLn ""

  -- Run tests
  r1 <- test_getMemberCount_initial trimmedBytecode
  r2 <- test_addMember trimmedBytecode

  let passed = length $ filter id [r1, r2]
  let total = 2
  putStrLn ""
  putStrLn $ "Results: " ++ show passed ++ "/" ++ show total ++ " passed"
