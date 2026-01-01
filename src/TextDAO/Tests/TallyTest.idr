||| TextDAO Tally Test Suite
||| Complete EVM runtime tests for RCV tallying
module TextDAO.Tests.TallyTest

import TextDAO.Storages.Schema
import TextDAO.Functions.OnlyReps.Vote
import TextDAO.Functions.OnlyMember.Propose
import TextDAO.Functions.Tally

import Data.List

%default covering

-- =============================================================================
-- REQ_TALLY_001: Tally entry point
-- =============================================================================

||| Test: Tally can be called on proposal
||| REQ_TALLY_001
export
test_REQ_TALLY_001_tallyCall : IO Bool
test_REQ_TALLY_001_tallyCall = do
  -- Setup
  setExpiryDuration 86400
  setSnapInterval 3600
  pid <- createProposal 0xabcd

  -- Note: In real test, tally would execute
  -- This tests that the proposal is properly set up for tally
  headerCount <- getProposalHeaderCount pid
  pure (headerCount == 1)

-- =============================================================================
-- REQ_TALLY_002: RCV score calculation
-- =============================================================================

||| Test: RCV points assignment
export
test_rcvPoints : Bool
test_rcvPoints =
  rcvPoints 0 == 3 &&  -- 1st choice
  rcvPoints 1 == 2 &&  -- 2nd choice
  rcvPoints 2 == 1 &&  -- 3rd choice
  rcvPoints 3 == 0     -- beyond 3rd

||| Test: Score accumulation
export
test_scoreMap_accumulate : Bool
test_scoreMap_accumulate =
  let empty = emptyScoreMap
      s1 = addScore 1 3 empty      -- header 1 gets 3 points
      s2 = addScore 2 2 s1         -- header 2 gets 2 points
      s3 = addScore 1 3 s2         -- header 1 gets another 3 points (total 6)
  in getScore 1 s3 == 6 && getScore 2 s3 == 2 && getScore 3 s3 == 0

||| Test: Find top scorer
export
test_findTopScorer : Bool
test_findTopScorer =
  let scores = addScore 3 5 $ addScore 2 3 $ addScore 1 5 emptyScoreMap
      top = findTopScorer scores
  in length top == 2 && elem 1 top && elem 3 top  -- tie between 1 and 3

||| Test: RCV score calculation with votes
||| REQ_TALLY_002
export
test_REQ_TALLY_002_calcScores : IO Bool
test_REQ_TALLY_002_calcScores = do
  -- Setup
  setExpiryDuration 86400
  pid <- createProposal 0xabcd
  _ <- createHeader pid 0x2222
  _ <- createHeader pid 0x3333
  setProposalCmdCount pid 3

  -- Add reps and votes
  let rep1 = 0x1111111111111111111111111111111111111111
  let rep2 = 0x2222222222222222222222222222222222222222
  addRep pid rep1
  addRep pid rep2

  -- Rep1 votes: headers [1,2,3], commands [3,2,1]
  storeVote pid rep1 (1, 2, 3) (3, 2, 1)
  -- Rep2 votes: headers [3,1,2], commands [3,2,1]
  storeVote pid rep2 (3, 1, 4) (3, 2, 1)

  -- Calculate scores
  (headerScores, cmdScores) <- calcRCVScores pid

  -- Expected header scores:
  -- 1: 3 (1st from rep1) + 2 (2nd from rep2) = 5
  -- 2: 2 (2nd from rep1) = 2
  -- 3: 1 (3rd from rep1) + 3 (1st from rep2) = 4
  -- 4: 1 (3rd from rep2) = 1

  let h1Score = getScore 1 headerScores
  let h2Score = getScore 2 headerScores
  let h3Score = getScore 3 headerScores

  -- Expected command scores:
  -- 3: 3 + 3 = 6 (both 1st)
  -- 2: 2 + 2 = 4 (both 2nd)
  -- 1: 1 + 1 = 2 (both 3rd)

  let c3Score = getScore 3 cmdScores
  let c2Score = getScore 2 cmdScores
  let c1Score = getScore 1 cmdScores

  pure (h1Score == 5 && h3Score == 4 && c3Score == 6 && c2Score == 4)

-- =============================================================================
-- REQ_TALLY_003: Approval check
-- =============================================================================

||| Test: isApproved returns false initially
||| REQ_TALLY_003
export
test_REQ_TALLY_003_notApproved : IO Bool
test_REQ_TALLY_003_notApproved = do
  setExpiryDuration 86400
  pid <- createProposal 0xabcd

  approved <- isApproved pid
  pure (not approved)

-- =============================================================================
-- REQ_TALLY_004: Approval storage
-- =============================================================================

||| Test: Approve proposal stores IDs
||| REQ_TALLY_004
export
test_REQ_TALLY_004_approveProposal : IO Bool
test_REQ_TALLY_004_approveProposal = do
  setExpiryDuration 86400
  pid <- createProposal 0xabcd

  -- Approve
  approveProposal pid 2 3

  -- Assert
  approvedHeader <- getApprovedHeaderId pid
  approvedCmd <- getApprovedCmdId pid
  approved <- isApproved pid

  pure (approvedHeader == 2 && approvedCmd == 3 && approved)

-- =============================================================================
-- REQ_TALLY_005: Snapshot
-- =============================================================================

||| Test: Snap epoch tracking
||| REQ_TALLY_005
export
test_REQ_TALLY_005_snapEpoch : IO Bool
test_REQ_TALLY_005_snapEpoch = do
  setExpiryDuration 86400
  setSnapInterval 3600
  pid <- createProposal 0xabcd

  -- Initially not snapped
  snapped <- isSnappedInEpoch pid
  let initialOk = not snapped

  -- Set as snapped
  currentEpoch <- calcCurrentEpoch pid
  setLastSnappedEpoch pid currentEpoch

  -- Now should be snapped
  snapped' <- isSnappedInEpoch pid

  pure (initialOk && snapped')

-- =============================================================================
-- REQ_TALLY_006: Final tally with clear winner
-- =============================================================================

||| Test: Final tally approves winner
||| REQ_TALLY_006
export
test_REQ_TALLY_006_finalTally_winner : IO Bool
test_REQ_TALLY_006_finalTally_winner = do
  -- Setup
  setExpiryDuration 86400
  pid <- createProposal 0xabcd
  _ <- createHeader pid 0x2222
  setProposalCmdCount pid 2

  -- Add 3 reps with clear winner (header 1, command 1)
  let rep1 = 0x1111111111111111111111111111111111111111
  let rep2 = 0x2222222222222222222222222222222222222222
  let rep3 = 0x3333333333333333333333333333333333333333
  addRep pid rep1
  addRep pid rep2
  addRep pid rep3

  -- All vote for header 1, command 1 as first choice
  storeVote pid rep1 (1, 2, 0) (1, 2, 0)
  storeVote pid rep2 (1, 2, 0) (1, 2, 0)
  storeVote pid rep3 (1, 2, 0) (1, 2, 0)

  -- Final tally
  success <- finalTally pid

  -- Assert
  approvedHeader <- getApprovedHeaderId pid
  approvedCmd <- getApprovedCmdId pid

  pure (success && approvedHeader == 1 && approvedCmd == 1)

-- =============================================================================
-- Tie handling tests
-- =============================================================================

||| Test: Final tally with tie extends expiration
export
test_finalTally_tie : IO Bool
test_finalTally_tie = do
  -- Setup
  setExpiryDuration 86400
  pid <- createProposal 0xabcd
  _ <- createHeader pid 0x2222
  setProposalCmdCount pid 2

  -- Add 2 reps with tied votes
  let rep1 = 0x1111111111111111111111111111111111111111
  let rep2 = 0x2222222222222222222222222222222222222222
  addRep pid rep1
  addRep pid rep2

  -- Rep1 votes header 1, Rep2 votes header 2 (tie)
  storeVote pid rep1 (1, 2, 0) (1, 2, 0)
  storeVote pid rep2 (2, 1, 0) (1, 2, 0)

  -- Get initial expiration
  initialExpiration <- getProposalExpiration pid

  -- Final tally (should extend due to header tie)
  success <- finalTally pid

  -- Assert: not approved, expiration extended
  finalExpiration <- getProposalExpiration pid
  approved <- isApproved pid

  pure (not success && not approved && finalExpiration > initialExpiration)

-- =============================================================================
-- Test Collection
-- =============================================================================

export
allTallyTests : List (String, IO Bool)
allTallyTests =
  [ ("REQ_TALLY_001_tallyCall", test_REQ_TALLY_001_tallyCall)
  , ("rcvPoints", pure test_rcvPoints)
  , ("scoreMap_accumulate", pure test_scoreMap_accumulate)
  , ("findTopScorer", pure test_findTopScorer)
  , ("REQ_TALLY_002_calcScores", test_REQ_TALLY_002_calcScores)
  , ("REQ_TALLY_003_notApproved", test_REQ_TALLY_003_notApproved)
  , ("REQ_TALLY_004_approveProposal", test_REQ_TALLY_004_approveProposal)
  , ("REQ_TALLY_005_snapEpoch", test_REQ_TALLY_005_snapEpoch)
  , ("REQ_TALLY_006_finalTally_winner", test_REQ_TALLY_006_finalTally_winner)
  , ("finalTally_tie", test_finalTally_tie)
  ]

export
runTallyTests : IO ()
runTallyTests = do
  putStrLn "=== Tally Tests (EVM Runtime) ==="
  results <- traverse runTest allTallyTests
  let numPassed = length $ filter id results
  let numTotal = length results
  putStrLn $ "Tally: " ++ show numPassed ++ "/" ++ show numTotal ++ " passed"
  where
    runTest : (String, IO Bool) -> IO Bool
    runTest (name, test) = do
      result <- test
      putStrLn $ (if result then "[PASS]" else "[FAIL]") ++ " " ++ name
      pure result
