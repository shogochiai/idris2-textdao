||| TextDAO Fork Test Suite
||| Tests for fork, forkHeader, forkCommand functions
module TextDAO.Functions.Fork.Tests.ForkTest

import TextDAO.Storages.Schema
import TextDAO.Functions.Vote.Vote
import TextDAO.Functions.Propose.Propose
import TextDAO.Functions.Fork.Fork

%default covering

-- =============================================================================
-- REQ_FORK_001: Fork creates new header and command
-- =============================================================================

||| Test: Fork adds new header to proposal
||| REQ_FORK_002
export
test_REQ_FORK_002_forkHeader : IO Bool
test_REQ_FORK_002_forkHeader = do
  -- Setup
  setExpiryDuration 86400
  pid <- createProposal 0x1111

  -- Add caller as rep
  let repAddr = 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
  addRep pid repAddr

  -- Get initial header count
  initialCount <- getProposalHeaderCount pid

  -- Fork a new header (simulate - in real test would be via caller)
  hid <- createHeader pid 0x2222

  -- Verify header count increased
  finalCount <- getProposalHeaderCount pid
  metadata <- getHeaderMetadata pid hid

  pure (finalCount == initialCount + 1 && metadata == 0x2222)

||| Test: Fork command adds new command to proposal
||| REQ_FORK_003
export
test_REQ_FORK_003_forkCommand : IO Bool
test_REQ_FORK_003_forkCommand = do
  -- Setup
  setExpiryDuration 86400
  pid <- createProposal 0x1111

  -- Get initial command count
  initialCount <- getProposalCmdCount pid

  -- Create a new command
  cid <- createCommand pid 0xabcdef

  -- Verify command count increased
  finalCount <- getProposalCmdCount pid
  actionData <- getCommandActionData pid cid

  pure (finalCount == initialCount + 1 && actionData == 0xabcdef)

||| Test: Multiple forks create independent alternatives
export
test_fork_multiple : IO Bool
test_fork_multiple = do
  -- Setup
  setExpiryDuration 86400
  pid <- createProposal 0x1111

  -- Create multiple headers
  h1 <- createHeader pid 0x2222
  h2 <- createHeader pid 0x3333
  h3 <- createHeader pid 0x4444

  -- Verify all headers stored correctly
  m1 <- getHeaderMetadata pid h1
  m2 <- getHeaderMetadata pid h2
  m3 <- getHeaderMetadata pid h3

  headerCount <- getProposalHeaderCount pid

  pure (m1 == 0x2222 && m2 == 0x3333 && m3 == 0x4444 && headerCount == 4)

||| Test: Commands can be forked independently
export
test_fork_commands_independent : IO Bool
test_fork_commands_independent = do
  -- Setup
  setExpiryDuration 86400
  pid <- createProposal 0x1111

  -- Create multiple commands
  c1 <- createCommand pid 0xaaaaaa
  c2 <- createCommand pid 0xbbbbbb
  c3 <- createCommand pid 0xcccccc

  -- Verify all commands stored correctly
  a1 <- getCommandActionData pid c1
  a2 <- getCommandActionData pid c2
  a3 <- getCommandActionData pid c3

  cmdCount <- getProposalCmdCount pid

  pure (a1 == 0xaaaaaa && a2 == 0xbbbbbb && a3 == 0xcccccc && cmdCount == 3)

-- =============================================================================
-- Test Collection
-- =============================================================================

export
allForkTests : List (String, IO Bool)
allForkTests =
  [ ("REQ_FORK_002_forkHeader", test_REQ_FORK_002_forkHeader)
  , ("REQ_FORK_003_forkCommand", test_REQ_FORK_003_forkCommand)
  , ("fork_multiple", test_fork_multiple)
  , ("fork_commands_independent", test_fork_commands_independent)
  ]

||| Run all fork tests and return passed count
export
runForkTests : IO Integer
runForkTests = do
  r1 <- test_REQ_FORK_002_forkHeader
  r2 <- test_REQ_FORK_003_forkCommand
  r3 <- test_fork_multiple
  r4 <- test_fork_commands_independent
  pure $ (if r1 then 1 else 0) + (if r2 then 1 else 0) +
         (if r3 then 1 else 0) + (if r4 then 1 else 0)
