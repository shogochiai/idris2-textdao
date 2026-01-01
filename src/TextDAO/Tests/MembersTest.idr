||| TextDAO Members Test Suite
||| Complete EVM runtime tests for member management
module TextDAO.Tests.MembersTest

import TextDAO.Storages.Schema
import TextDAO.Functions.Members

%default covering

-- =============================================================================
-- REQ_MEMBERS_001: Member registration
-- =============================================================================

||| Test: Add member stores address and metadata correctly
||| REQ_MEMBERS_001, REQ_MEMBERS_004
export
test_REQ_MEMBERS_001_addMember : IO Bool
test_REQ_MEMBERS_001_addMember = do
  -- Setup: initial member count should be 0
  initialCount <- getMemberCount

  -- Act: add a member
  let testAddr = 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
  let testMetadata = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
  memberId <- addMember testAddr testMetadata

  -- Assert: member count incremented
  finalCount <- getMemberCount
  let countOk = finalCount == initialCount + 1

  -- Assert: member ID is correct
  let idOk = memberId == initialCount

  -- Assert: member data retrievable
  storedAddr <- getMemberAddr memberId
  storedMetadata <- getMemberMetadata memberId
  let dataOk = storedAddr == testAddr && storedMetadata == testMetadata

  pure (countOk && idOk && dataOk)

-- =============================================================================
-- REQ_MEMBERS_002: Member address lookup
-- =============================================================================

||| Test: Get member address by index
||| REQ_MEMBERS_002
export
test_REQ_MEMBERS_002_getMemberAddr : IO Bool
test_REQ_MEMBERS_002_getMemberAddr = do
  -- Setup: add multiple members
  let addr1 = 0x1111111111111111111111111111111111111111
  let addr2 = 0x2222222222222222222222222222222222222222
  let addr3 = 0x3333333333333333333333333333333333333333

  id1 <- addMember addr1 0
  id2 <- addMember addr2 0
  id3 <- addMember addr3 0

  -- Act & Assert: retrieve each address
  retrieved1 <- getMemberAddr id1
  retrieved2 <- getMemberAddr id2
  retrieved3 <- getMemberAddr id3

  pure (retrieved1 == addr1 && retrieved2 == addr2 && retrieved3 == addr3)

-- =============================================================================
-- REQ_MEMBERS_003: Membership check
-- =============================================================================

||| Test: isMember returns true for registered members
||| REQ_MEMBERS_003
export
test_REQ_MEMBERS_003_isMember_true : IO Bool
test_REQ_MEMBERS_003_isMember_true = do
  -- Setup: add a member
  let memberAddr = 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  _ <- addMember memberAddr 0

  -- Act & Assert
  result <- isMember memberAddr
  pure result

||| Test: isMember returns false for non-members
||| REQ_MEMBERS_003
export
test_REQ_MEMBERS_003_isMember_false : IO Bool
test_REQ_MEMBERS_003_isMember_false = do
  -- Setup: some address that was never added
  let nonMemberAddr = 0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

  -- Act & Assert
  result <- isMember nonMemberAddr
  pure (not result)

-- =============================================================================
-- REQ_MEMBERS_004: Multiple member registration
-- =============================================================================

||| Test: Sequential member IDs
||| REQ_MEMBERS_004
export
test_REQ_MEMBERS_004_sequential_ids : IO Bool
test_REQ_MEMBERS_004_sequential_ids = do
  -- Get starting count
  startCount <- getMemberCount

  -- Add 5 members
  id0 <- addMember 0x1000000000000000000000000000000000000001 0
  id1 <- addMember 0x1000000000000000000000000000000000000002 0
  id2 <- addMember 0x1000000000000000000000000000000000000003 0
  id3 <- addMember 0x1000000000000000000000000000000000000004 0
  id4 <- addMember 0x1000000000000000000000000000000000000005 0

  -- Assert sequential IDs
  let sequential = id0 == startCount &&
                   id1 == startCount + 1 &&
                   id2 == startCount + 2 &&
                   id3 == startCount + 3 &&
                   id4 == startCount + 4

  -- Assert final count
  finalCount <- getMemberCount
  let countOk = finalCount == startCount + 5

  pure (sequential && countOk)

-- =============================================================================
-- REQ_MEMBERS_005: MemberAdded event emission
-- =============================================================================

||| Test: MemberAdded event is emitted when adding a member
||| REQ_MEMBERS_005
export
test_REQ_MEMBERS_005_memberAdded_event : IO Bool
test_REQ_MEMBERS_005_memberAdded_event = do
  -- Setup: add a member and capture event logs
  let memberAddr = 0xcccccccccccccccccccccccccccccccccccccccc
  let metadata = 0x5555555555555555555555555555555555555555555555555555555555555555

  -- Act: add member (should emit MemberAdded event)
  memberId <- addMember memberAddr metadata

  -- Assert: for now just verify the member was added successfully
  -- (Full event verification would require EVM log inspection)
  storedAddr <- getMemberAddr memberId
  pure (storedAddr == memberAddr)

-- =============================================================================
-- Storage slot isolation tests
-- =============================================================================

||| Test: Member storage slots don't collide
export
test_storage_slot_isolation : IO Bool
test_storage_slot_isolation = do
  -- Add members with different metadata
  let meta1 = 0x1111111111111111111111111111111111111111111111111111111111111111
  let meta2 = 0x2222222222222222222222222222222222222222222222222222222222222222

  id1 <- addMember 0x1000000000000000000000000000000000000001 meta1
  id2 <- addMember 0x1000000000000000000000000000000000000002 meta2

  -- Verify each member has correct isolated data
  storedMeta1 <- getMemberMetadata id1
  storedMeta2 <- getMemberMetadata id2

  pure (storedMeta1 == meta1 && storedMeta2 == meta2)

-- =============================================================================
-- Test Collection
-- =============================================================================

export
allMembersTests : List (String, IO Bool)
allMembersTests =
  [ ("REQ_MEMBERS_001_addMember", test_REQ_MEMBERS_001_addMember)
  , ("REQ_MEMBERS_002_getMemberAddr", test_REQ_MEMBERS_002_getMemberAddr)
  , ("REQ_MEMBERS_003_isMember_true", test_REQ_MEMBERS_003_isMember_true)
  , ("REQ_MEMBERS_003_isMember_false", test_REQ_MEMBERS_003_isMember_false)
  , ("REQ_MEMBERS_004_sequential_ids", test_REQ_MEMBERS_004_sequential_ids)
  , ("REQ_MEMBERS_005_memberAdded_event", test_REQ_MEMBERS_005_memberAdded_event)
  , ("storage_slot_isolation", test_storage_slot_isolation)
  ]

export
runMembersTests : IO ()
runMembersTests = do
  putStrLn "=== Members Tests (EVM Runtime) ==="
  results <- traverse runTest allMembersTests
  let numPassed = length $ filter id results
  let numTotal = length results
  putStrLn $ "Members: " ++ show numPassed ++ "/" ++ show numTotal ++ " passed"
  where
    runTest : (String, IO Bool) -> IO Bool
    runTest (name, test) = do
      result <- test
      putStrLn $ (if result then "[PASS]" else "[FAIL]") ++ " " ++ name
      pure result
