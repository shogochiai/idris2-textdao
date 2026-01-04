||| TextDAO All Tests - Complete EVM Runtime Test Suite
|||
||| Aggregates all tests for spec-test parity analysis with lazy core ask
||| NOTE: This version avoids putStrLn to prevent REVERT in EVM execution
module TextDAO.Tests.AllTests

import TextDAO.Storages.Schema
import TextDAO.Tests.SchemaTest
import TextDAO.Functions.Members.Tests.MembersTest
import TextDAO.Functions.Propose.Tests.ProposeTest
import TextDAO.Functions.Vote.Tests.VoteTest
import TextDAO.Functions.Tally.Tests.TallyTest
import TextDAO.Functions.Fork.Tests.ForkTest
import TextDAO.Functions.Execute.Tests.ExecuteTest
import TextDAO.Functions.Text.Tests.TextTest
import TextDAO.Tests.EvmTest

%default covering

-- =============================================================================
-- EVM Return Primitive
-- =============================================================================

%foreign "evm:return"
prim__return : Integer -> Integer -> PrimIO ()

evmReturn : Integer -> Integer -> IO ()
evmReturn off len = primIO (prim__return off len)

-- =============================================================================
-- Simple Test Runner (No IO Output)
-- =============================================================================

||| Convert bool to integer for counting
boolToInt : Bool -> Integer
boolToInt True = 1
boolToInt False = 0

||| Run a single test and return result
runTest : (String, IO Bool) -> IO Bool
runTest (_, test) = test

||| Run a list of tests and count passing/failing
runTestList : List (String, IO Bool) -> IO Integer
runTestList [] = pure 0
runTestList ((_, test) :: rest) = do
  result <- test
  restCount <- runTestList rest
  pure $ (if result then 1 else 0) + restCount

-- =============================================================================
-- Main Test Runner (EVM Compatible - No putStrLn)
-- =============================================================================

||| Sum a list of integers
sumInts : List Integer -> Integer
sumInts [] = 0
sumInts (x :: xs) = x + sumInts xs

||| Count passed tests
countPassed : List Bool -> Integer
countPassed results = sumInts (map boolToInt results)

||| Helper to calculate and return passed count
finishTests : List Bool -> IO Integer
finishTests results =
  let passedCount = countPassed results
  in do mstore 0 passedCount
        evmReturn 0 32
        pure passedCount

||| Run all tests and return total passed count
||| This version does NOT use putStrLn which causes REVERT in EVM
export
runAllTests : IO Integer
runAllTests = do
  -- Run Members tests
  m1 <- test_REQ_MEMBERS_001_addMember
  m2 <- test_REQ_MEMBERS_002_getMemberAddr
  m3 <- test_REQ_MEMBERS_003_isMember_true
  m4 <- test_REQ_MEMBERS_003_isMember_false
  m5 <- test_REQ_MEMBERS_004_sequential_ids
  m6 <- test_REQ_MEMBERS_005_memberAdded_event
  m7 <- test_storage_slot_isolation

  -- Run Propose tests
  p1 <- test_REQ_PROPOSE_001_createProposal
  p2 <- test_REQ_PROPOSE_002_storeHeader
  p3 <- test_REQ_PROPOSE_003_initMeta
  p4 <- test_REQ_PROPOSE_004_multipleHeaders
  p5 <- test_REQ_PROPOSE_005_multipleProposals

  -- Run Vote tests
  v1 <- test_REQ_VOTE_001_castVote
  v2 <- test_REQ_VOTE_002_isRep_true
  v3 <- test_REQ_VOTE_002_isRep_false
  v4 <- test_REQ_VOTE_003_multipleVotes
  v5 <- test_REQ_VOTE_004_isExpired

  -- Run Tally tests
  t1 <- test_REQ_TALLY_001_tallyCall
  t2 <- test_REQ_TALLY_002_calcScores
  t3 <- test_REQ_TALLY_003_notApproved
  t4 <- test_REQ_TALLY_004_approveProposal
  t5 <- test_REQ_TALLY_005_snapEpoch

  -- Run Fork tests
  f1 <- test_REQ_FORK_002_forkHeader
  f2 <- test_REQ_FORK_003_forkCommand
  f3 <- test_fork_multiple
  f4 <- test_fork_commands_independent

  -- Run Execute tests
  x1 <- test_REQ_EXECUTE_001_execute
  x2 <- test_REQ_EXECUTE_002_notApproved
  x3 <- test_execute_once
  x4 <- test_not_executed_initially

  -- Run Text tests
  tx1 <- test_REQ_TEXT_001_createText
  tx2 <- test_REQ_TEXT_002_textCount
  tx3 <- test_text_multiple
  tx4 <- test_text_proposal_link

  -- Run EVM tests
  e1 <- test_REQ_EVM_001_selector_dispatch
  e2 <- test_REQ_EVM_002_calldata_parsing
  e3 <- test_REQ_EVM_003_return_encoding
  e4 <- test_REQ_EVM_004_revert_unauthorized

  -- Calculate and return total
  finishTests [m1, m2, m3, m4, m5, m6, m7,
               p1, p2, p3, p4, p5,
               v1, v2, v3, v4, v5,
               t1, t2, t3, t4, t5,
               f1, f2, f3, f4,
               x1, x2, x3, x4,
               tx1, tx2, tx3, tx4,
               e1, e2, e3, e4]

-- =============================================================================
-- Main Entry Point
-- =============================================================================

main : IO ()
main = do
  _ <- runAllTests
  pure ()
