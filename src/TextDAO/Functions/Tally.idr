||| TextDAO Tally Function
||| REQ_TALLY_001: RCV vote counting and proposal approval
module TextDAO.Functions.Tally

import TextDAO.Storages.Schema
import TextDAO.Functions.OnlyReps.Vote

import Data.List

%default covering

-- =============================================================================
-- EVM Primitives
-- =============================================================================

%foreign "evm:timestamp"
prim__timestamp : PrimIO Integer

%foreign "evm:revert"
prim__revert : Integer -> Integer -> PrimIO ()

timestamp : IO Integer
timestamp = primIO prim__timestamp

evmRevert : Integer -> Integer -> IO ()
evmRevert off len = primIO (prim__revert off len)

%foreign "evm:calldataload"
prim__calldataload : Integer -> PrimIO Integer

%foreign "evm:return"
prim__return : Integer -> Integer -> PrimIO ()

calldataload : Integer -> IO Integer
calldataload off = primIO (prim__calldataload off)

evmReturn : Integer -> Integer -> IO ()
evmReturn off len = primIO (prim__return off len)

-- =============================================================================
-- Function Selectors
-- =============================================================================

||| tally(uint256) -> 0x67890123
SEL_TALLY : Integer
SEL_TALLY = 0x67890123

||| snap(uint256) -> 0x78901234
SEL_SNAP : Integer
SEL_SNAP = 0x78901234

||| isApproved(uint256) -> 0x89012345
SEL_IS_APPROVED : Integer
SEL_IS_APPROVED = 0x89012345

-- =============================================================================
-- Entry Point Helpers
-- =============================================================================

||| Extract function selector from calldata (first 4 bytes)
getSelector : IO Integer
getSelector = do
  data_ <- calldataload 0
  pure (data_ `div` 0x100000000000000000000000000000000000000000000000000000000)

||| Return a uint256 value
returnUint : Integer -> IO ()
returnUint val = do
  mstore 0 val
  evmReturn 0 32

||| Return a boolean value
returnBool : Bool -> IO ()
returnBool b = returnUint (if b then 1 else 0)

-- =============================================================================
-- RCV Score Calculation
-- =============================================================================

||| RCV points: 1st choice = 3, 2nd = 2, 3rd = 1
public export
rcvPoints : Integer -> Integer
rcvPoints 0 = 3  -- 1st choice
rcvPoints 1 = 2  -- 2nd choice
rcvPoints 2 = 1  -- 3rd choice
rcvPoints _ = 0

||| Score accumulator for headers/commands
||| Maps ID -> Score
public export
record ScoreMap where
  constructor MkScoreMap
  scores : List (Integer, Integer)

export
emptyScoreMap : ScoreMap
emptyScoreMap = MkScoreMap []

export
addScore : Integer -> Integer -> ScoreMap -> ScoreMap
addScore id points (MkScoreMap scores) =
  MkScoreMap (updateOrInsert id points scores)
  where
    updateOrInsert : Integer -> Integer -> List (Integer, Integer) -> List (Integer, Integer)
    updateOrInsert i p [] = [(i, p)]
    updateOrInsert i p ((k, v) :: rest) =
      if k == i
        then (k, v + p) :: rest
        else (k, v) :: updateOrInsert i p rest

export
getScore : Integer -> ScoreMap -> Integer
getScore id (MkScoreMap scores) =
  case find (\(k, _) => k == id) scores of
    Just (_, v) => v
    Nothing => 0

export
findTopScorer : ScoreMap -> List Integer
findTopScorer (MkScoreMap []) = []
findTopScorer (MkScoreMap scores) =
  let maxScore = foldl max 0 (map snd scores)
  in if maxScore == 0
       then []
       else map fst (filter (\(_, v) => v == maxScore) scores)

-- =============================================================================
-- Vote Aggregation
-- =============================================================================

||| Accumulate votes from a single representative
export
accumulateVote : ProposalId -> Address -> (ScoreMap, ScoreMap) -> IO (ScoreMap, ScoreMap)
accumulateVote pid voter (headerScores, cmdScores) = do
  ((h0, h1, h2), (c0, c1, c2)) <- readVote pid voter

  -- Add header scores (skip 0 = no vote)
  let headerScores' = if h0 > 0 then addScore h0 (rcvPoints 0) headerScores else headerScores
  let headerScores'' = if h1 > 0 then addScore h1 (rcvPoints 1) headerScores' else headerScores'
  let headerScores''' = if h2 > 0 then addScore h2 (rcvPoints 2) headerScores'' else headerScores''

  -- Add command scores
  let cmdScores' = if c0 > 0 then addScore c0 (rcvPoints 0) cmdScores else cmdScores
  let cmdScores'' = if c1 > 0 then addScore c1 (rcvPoints 1) cmdScores' else cmdScores'
  let cmdScores''' = if c2 > 0 then addScore c2 (rcvPoints 2) cmdScores'' else cmdScores''

  pure (headerScores''', cmdScores''')

||| Calculate RCV scores for all representatives
||| REQ_TALLY_002
export
calcRCVScores : ProposalId -> IO (ScoreMap, ScoreMap)
calcRCVScores pid = do
  repCount <- getRepCount pid
  accumulateAll pid 0 repCount (emptyScoreMap, emptyScoreMap)
  where
    accumulateAll : ProposalId -> Integer -> Integer -> (ScoreMap, ScoreMap) -> IO (ScoreMap, ScoreMap)
    accumulateAll pid idx cnt acc =
      if idx >= cnt
        then pure acc
        else do
          repAddr <- getRepAddr pid idx
          acc' <- accumulateVote pid repAddr acc
          accumulateAll pid (idx + 1) cnt acc'

-- =============================================================================
-- Proposal State Checks
-- =============================================================================

||| Check if proposal is already approved
||| REQ_TALLY_003
export
isApproved : ProposalId -> IO Bool
isApproved pid = do
  approvedHeader <- getApprovedHeaderId pid
  pure (approvedHeader > 0)

||| Approve header and command
||| REQ_TALLY_004
export
approveProposal : ProposalId -> HeaderId -> CommandId -> IO ()
approveProposal pid headerId cmdId = do
  setApprovedHeaderId pid headerId
  setApprovedCmdId pid cmdId

-- =============================================================================
-- Snap (Periodic Snapshot)
-- =============================================================================

||| Snap slot offset within proposal meta
SNAP_EPOCH_SLOT_OFFSET : Integer
SNAP_EPOCH_SLOT_OFFSET = 0x50

||| Get last snapped epoch
export
getLastSnappedEpoch : ProposalId -> IO Integer
getLastSnappedEpoch pid = do
  metaSlot <- getProposalMetaSlot pid
  sload (metaSlot + SNAP_EPOCH_SLOT_OFFSET)

||| Set last snapped epoch
export
setLastSnappedEpoch : ProposalId -> Integer -> IO ()
setLastSnappedEpoch pid epoch = do
  metaSlot <- getProposalMetaSlot pid
  sstore (metaSlot + SNAP_EPOCH_SLOT_OFFSET) epoch

||| Calculate current epoch (timestamp / snapInterval)
export
calcCurrentEpoch : ProposalId -> IO Integer
calcCurrentEpoch pid = do
  snapInterval <- getSnapInterval
  now <- timestamp
  pure (if snapInterval == 0 then 0 else now `div` snapInterval)

||| Check if already snapped in current epoch
export
isSnappedInEpoch : ProposalId -> IO Bool
isSnappedInEpoch pid = do
  lastEpoch <- getLastSnappedEpoch pid
  currentEpoch <- calcCurrentEpoch pid
  pure (lastEpoch >= currentEpoch)

||| Take snapshot of current voting state
||| REQ_TALLY_005
export
snap : ProposalId -> IO ()
snap pid = do
  -- Check not already snapped
  snapped <- isSnappedInEpoch pid
  if snapped
    then evmRevert 0 0  -- AlreadySnapped
    else do
      -- Calculate scores
      (headerScores, cmdScores) <- calcRCVScores pid

      -- Mark as snapped
      currentEpoch <- calcCurrentEpoch pid
      setLastSnappedEpoch pid currentEpoch

      -- (In real implementation, would emit ProposalSnapped event)
      pure ()

-- =============================================================================
-- Final Tally
-- =============================================================================

||| Perform final tally when proposal expires
||| REQ_TALLY_006
export
finalTally : ProposalId -> IO Bool
finalTally pid = do
  -- Check not already approved
  approved <- isApproved pid
  if approved
    then do
      evmRevert 0 0  -- ProposalAlreadyApproved
      pure False
    else do
      -- Calculate final scores
      (headerScores, cmdScores) <- calcRCVScores pid

      -- Find winners
      let topHeaders = findTopScorer headerScores
      let topCommands = findTopScorer cmdScores

      case (topHeaders, topCommands) of
        -- Single winner for both
        ([winnerId], [winnerCmd]) => do
          approveProposal pid winnerId winnerCmd
          pure True

        -- Tie or no votes: extend expiration
        _ => do
          expiryDuration <- getExpiryDuration
          currentExpiration <- getProposalExpiration pid
          setProposalExpiration pid (currentExpiration + expiryDuration)
          pure False

-- =============================================================================
-- Entry Point
-- =============================================================================

||| Tally function (entry point)
||| REQ_TALLY_001: Anyone can call tally to count votes
export
tally : ProposalId -> IO ()
tally pid = do
  expired <- isProposalExpired pid

  if expired
    then do
      _ <- finalTally pid
      pure ()
    else do
      snap pid

-- =============================================================================
-- Main Entry Point
-- =============================================================================

||| Main entry point for Tally contract
export
main : IO ()
main = do
  selector <- getSelector

  if selector == SEL_TALLY
    then do
      pid <- calldataload 4
      tally pid
      evmReturn 0 0

    else if selector == SEL_SNAP
    then do
      pid <- calldataload 4
      snap pid
      evmReturn 0 0

    else if selector == SEL_IS_APPROVED
    then do
      pid <- calldataload 4
      approved <- isApproved pid
      returnBool approved

    else evmRevert 0 0
