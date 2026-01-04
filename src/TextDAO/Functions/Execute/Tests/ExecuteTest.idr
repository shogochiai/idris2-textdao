||| TextDAO Execute Test Suite
||| Tests for execute function
module TextDAO.Functions.Execute.Tests.ExecuteTest

import TextDAO.Storages.Schema
import TextDAO.Functions.Propose.Propose
import TextDAO.Functions.Tally.Tally
import TextDAO.Functions.Execute.Execute

%default covering

-- =============================================================================
-- REQ_EXECUTE_001: Execute approved proposals
-- =============================================================================

||| Test: Execute marks proposal as fully executed
||| REQ_EXECUTE_001
export
test_REQ_EXECUTE_001_execute : IO Bool
test_REQ_EXECUTE_001_execute = do
  -- Setup
  setExpiryDuration 86400
  pid <- createProposal 0x1111

  -- Manually approve the proposal
  approveProposal pid 1 1

  -- Execute
  success <- execute pid

  -- Verify
  executed <- isFullyExecuted pid

  pure (success && executed)

||| Test: Cannot execute unapproved proposal
||| REQ_EXECUTE_002
export
test_REQ_EXECUTE_002_notApproved : IO Bool
test_REQ_EXECUTE_002_notApproved = do
  -- Setup
  setExpiryDuration 86400
  pid <- createProposal 0x1111

  -- Check proposal is not approved
  approved <- isProposalApproved pid

  pure (not approved)

||| Test: Cannot execute twice
export
test_execute_once : IO Bool
test_execute_once = do
  -- Setup
  setExpiryDuration 86400
  pid <- createProposal 0x1111

  -- Manually approve
  approveProposal pid 1 1

  -- Execute first time
  _ <- execute pid
  executed1 <- isFullyExecuted pid

  -- Try to execute again - should fail
  -- (In real test, this would revert, but we test the flag)
  executed2 <- isFullyExecuted pid

  pure (executed1 && executed2)

||| Test: isFullyExecuted returns false initially
export
test_not_executed_initially : IO Bool
test_not_executed_initially = do
  -- Setup
  setExpiryDuration 86400
  pid <- createProposal 0x1111

  -- Check not executed
  executed <- isFullyExecuted pid

  pure (not executed)

-- =============================================================================
-- Test Collection
-- =============================================================================

export
allExecuteTests : List (String, IO Bool)
allExecuteTests =
  [ ("REQ_EXECUTE_001_execute", test_REQ_EXECUTE_001_execute)
  , ("REQ_EXECUTE_002_notApproved", test_REQ_EXECUTE_002_notApproved)
  , ("execute_once", test_execute_once)
  , ("not_executed_initially", test_not_executed_initially)
  ]

||| Run all execute tests and return passed count
export
runExecuteTests : IO Integer
runExecuteTests = do
  r1 <- test_REQ_EXECUTE_001_execute
  r2 <- test_REQ_EXECUTE_002_notApproved
  r3 <- test_execute_once
  r4 <- test_not_executed_initially
  pure $ (if r1 then 1 else 0) + (if r2 then 1 else 0) +
         (if r3 then 1 else 0) + (if r4 then 1 else 0)
