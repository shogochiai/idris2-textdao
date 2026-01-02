||| TextDAO Propose Test Suite
||| Complete EVM runtime tests for proposal creation
module TextDAO.Functions.Propose.Tests.ProposeTest

import TextDAO.Storages.Schema
import TextDAO.Functions.Members.Members
import TextDAO.Functions.Propose.Propose

%default covering

-- =============================================================================
-- REQ_PROPOSE_001: Proposal creation
-- =============================================================================

||| Test: Member can create proposal
||| REQ_PROPOSE_001, REQ_PROPOSE_005
export
test_REQ_PROPOSE_001_createProposal : IO Bool
test_REQ_PROPOSE_001_createProposal = do
  -- Setup: configure deliberation
  setExpiryDuration 86400  -- 1 day
  setSnapInterval 3600     -- 1 hour

  -- Setup: get initial count
  initialCount <- getProposalCount

  -- Act: create proposal
  let headerMetadata = 0xabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd
  pid <- createProposal headerMetadata

  -- Assert: proposal ID correct
  let idOk = pid == initialCount

  -- Assert: count incremented
  finalCount <- getProposalCount
  let countOk = finalCount == initialCount + 1

  -- Assert: header stored
  storedMetadata <- getHeaderMetadata pid 1
  let metadataOk = storedMetadata == headerMetadata

  pure (idOk && countOk && metadataOk)

-- =============================================================================
-- REQ_PROPOSE_002: Header storage
-- =============================================================================

||| Test: Header metadata stored at correct slot
||| REQ_PROPOSE_002
export
test_REQ_PROPOSE_002_storeHeader : IO Bool
test_REQ_PROPOSE_002_storeHeader = do
  -- Setup
  setExpiryDuration 86400
  pid <- createProposal 0x1111111111111111111111111111111111111111111111111111111111111111

  -- Act: store additional header
  let header2Metadata = 0x2222222222222222222222222222222222222222222222222222222222222222
  storeHeader pid 2 header2Metadata
  setProposalHeaderCount pid 2

  -- Assert: both headers retrievable
  header1 <- getHeaderMetadata pid 1
  header2 <- getHeaderMetadata pid 2

  let header1Ok = header1 == 0x1111111111111111111111111111111111111111111111111111111111111111
  let header2Ok = header2 == header2Metadata

  pure (header1Ok && header2Ok)

-- =============================================================================
-- REQ_PROPOSE_003: Proposal metadata initialization
-- =============================================================================

||| Test: Proposal meta fields initialized correctly
||| REQ_PROPOSE_003
export
test_REQ_PROPOSE_003_initMeta : IO Bool
test_REQ_PROPOSE_003_initMeta = do
  -- Setup: configure
  let expiryDuration = 86400
  setExpiryDuration expiryDuration
  setSnapInterval 3600

  -- Act: create proposal
  pid <- createProposal 0xabcd

  -- Assert: meta fields
  createdAt <- getProposalCreatedAt pid
  expiration <- getProposalExpiration pid
  headerCount <- getProposalHeaderCount pid
  cmdCount <- getProposalCmdCount pid
  approvedHeader <- getApprovedHeaderId pid
  approvedCmd <- getApprovedCmdId pid
  executed <- isFullyExecuted pid

  -- createdAt should be set (non-zero in real EVM)
  -- expiration should be createdAt + expiryDuration
  let expirationOk = expiration == createdAt + expiryDuration
  let headerCountOk = headerCount == 1  -- 1 header created
  let cmdCountOk = cmdCount == 0
  let notApproved = approvedHeader == 0 && approvedCmd == 0
  let notExecuted = not executed

  pure (expirationOk && headerCountOk && cmdCountOk && notApproved && notExecuted)

-- =============================================================================
-- REQ_PROPOSE_004: Multiple headers
-- =============================================================================

||| Test: Create multiple headers in proposal
||| REQ_PROPOSE_004
export
test_REQ_PROPOSE_004_multipleHeaders : IO Bool
test_REQ_PROPOSE_004_multipleHeaders = do
  -- Setup
  setExpiryDuration 86400
  pid <- createProposal 0x1111

  -- Act: add more headers
  hid2 <- createHeader pid 0x2222
  hid3 <- createHeader pid 0x3333

  -- Assert: header IDs sequential
  let idsOk = hid2 == 2 && hid3 == 3

  -- Assert: header count updated
  headerCount <- getProposalHeaderCount pid
  let countOk = headerCount == 3

  -- Assert: all headers retrievable
  h1 <- getHeaderMetadata pid 1
  h2 <- getHeaderMetadata pid 2
  h3 <- getHeaderMetadata pid 3

  let dataOk = h1 == 0x1111 && h2 == 0x2222 && h3 == 0x3333

  pure (idsOk && countOk && dataOk)

-- =============================================================================
-- REQ_PROPOSE_005: Multiple proposals
-- =============================================================================

||| Test: Create multiple proposals with isolated state
||| REQ_PROPOSE_005
export
test_REQ_PROPOSE_005_multipleProposals : IO Bool
test_REQ_PROPOSE_005_multipleProposals = do
  -- Setup
  setExpiryDuration 86400

  -- Act: create 3 proposals
  pid1 <- createProposal 0xaaaa
  pid2 <- createProposal 0xbbbb
  pid3 <- createProposal 0xcccc

  -- Assert: sequential IDs
  let idsOk = pid2 == pid1 + 1 && pid3 == pid2 + 1

  -- Assert: isolated header data
  h1 <- getHeaderMetadata pid1 1
  h2 <- getHeaderMetadata pid2 1
  h3 <- getHeaderMetadata pid3 1

  let dataOk = h1 == 0xaaaa && h2 == 0xbbbb && h3 == 0xcccc

  pure (idsOk && dataOk)

-- =============================================================================
-- Config dependency tests
-- =============================================================================

||| Test: Proposal uses current config values
export
test_config_dependency : IO Bool
test_config_dependency = do
  -- Setup: set specific config
  setExpiryDuration 172800  -- 2 days
  setSnapInterval 7200      -- 2 hours

  -- Act
  pid <- createProposal 0x1234

  -- Assert: expiration uses config
  createdAt <- getProposalCreatedAt pid
  expiration <- getProposalExpiration pid

  pure (expiration == createdAt + 172800)

-- =============================================================================
-- Test Collection
-- =============================================================================

export
allProposeTests : List (String, IO Bool)
allProposeTests =
  [ ("REQ_PROPOSE_001_createProposal", test_REQ_PROPOSE_001_createProposal)
  , ("REQ_PROPOSE_002_storeHeader", test_REQ_PROPOSE_002_storeHeader)
  , ("REQ_PROPOSE_003_initMeta", test_REQ_PROPOSE_003_initMeta)
  , ("REQ_PROPOSE_004_multipleHeaders", test_REQ_PROPOSE_004_multipleHeaders)
  , ("REQ_PROPOSE_005_multipleProposals", test_REQ_PROPOSE_005_multipleProposals)
  , ("config_dependency", test_config_dependency)
  ]

export
runProposeTests : IO ()
runProposeTests = do
  putStrLn "=== Propose Tests (EVM Runtime) ==="
  results <- traverse runTest allProposeTests
  let numPassed = length $ filter id results
  let numTotal = length results
  putStrLn $ "Propose: " ++ show numPassed ++ "/" ++ show numTotal ++ " passed"
  where
    runTest : (String, IO Bool) -> IO Bool
    runTest (name, test) = do
      result <- test
      putStrLn $ (if result then "[PASS]" else "[FAIL]") ++ " " ++ name
      pure result
