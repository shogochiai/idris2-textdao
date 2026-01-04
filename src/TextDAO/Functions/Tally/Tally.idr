||| TextDAO Tally Function
||| REQ_TALLY_001: RCV vote counting and proposal approval
module TextDAO.Functions.Tally.Tally

import public Subcontract.Core.Entry
import Subcontract.Core.ABI.Decoder
import public Subcontract.Core.Outcome
import TextDAO.Storages.Schema
import TextDAO.Functions.Vote.Vote

import Data.List

-- Note: EVM primitives now come from TextDAO.Storages.Schema via Subcontract.Core.Storable

%default covering

-- =============================================================================
-- Function Signatures
-- =============================================================================

||| tally(uint256) -> void
public export
tallySig : Sig
tallySig = MkSig "tally" [TUint256] []

public export
tallySel : Sel tallySig
tallySel = MkSel 0x67890123

||| snap(uint256) -> void
public export
snapSig : Sig
snapSig = MkSig "snap" [TUint256] []

public export
snapSel : Sel snapSig
snapSel = MkSel 0x78901234

||| isApproved(uint256) -> bool
public export
isApprovedSig : Sig
isApprovedSig = MkSig "isApproved" [TUint256] [TBool]

public export
isApprovedSel : Sel isApprovedSig
isApprovedSel = MkSel 0x89012345

||| tallyAndExecute(uint256) -> bool
public export
tallyAndExecuteSig : Sig
tallyAndExecuteSig = MkSig "tallyAndExecute" [TUint256] [TBool]

public export
tallyAndExecuteSel : Sel tallyAndExecuteSig
tallyAndExecuteSel = MkSel 0x90123456

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
accumulateVote : ProposalId -> EvmAddr -> (ScoreMap, ScoreMap) -> IO (ScoreMap, ScoreMap)
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
snap : ProposalId -> IO (Outcome ())
snap pid = do
  -- Check not already snapped
  snapped <- isSnappedInEpoch pid
  if snapped
    then pure (Fail EpochMismatch (tagEvidence "AlreadySnapped"))
    else do
      -- Calculate scores
      (headerScores, cmdScores) <- calcRCVScores pid

      -- Mark as snapped
      currentEpoch <- calcCurrentEpoch pid
      setLastSnappedEpoch pid currentEpoch

      pure (Ok ())

-- =============================================================================
-- Final Tally
-- =============================================================================

||| Perform final tally when proposal expires
||| REQ_TALLY_006
export
finalTally : ProposalId -> IO (Outcome Bool)
finalTally pid = do
  -- Check not already approved
  approved <- isApproved pid
  if approved
    then pure (Fail InvalidTransition (tagEvidence "ProposalAlreadyApproved"))
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
          pure (Ok True)

        -- Tie or no votes: extend expiration
        _ => do
          expiryDuration <- getExpiryDuration
          currentExpiration <- getProposalExpiration pid
          setProposalExpiration pid (currentExpiration + expiryDuration)
          pure (Ok False)

-- =============================================================================
-- Tally and Execute
-- =============================================================================

||| Execute the approved command (simplified)
||| REQ_EXECUTE_001: Execute approved proposals
executeApproved : ProposalId -> IO Bool
executeApproved pid = do
  -- Check if already executed
  executed <- isFullyExecuted pid
  if executed
    then pure False
    else do
      setFullyExecuted pid True
      pure True

||| Tally and immediately execute if approved
||| REQ_TALLY_007: Combined tally and execute for efficiency
export
tallyAndExecute : ProposalId -> IO (Outcome Bool)
tallyAndExecute pid = do
  expired <- isProposalExpired pid

  if not expired
    then pure (Fail InvalidTransition (tagEvidence "ProposalNotExpired"))
    else do
      result <- finalTally pid
      case result of
        Ok True => do
          executed <- executeApproved pid
          pure (Ok executed)
        Ok False => pure (Ok False)
        Fail c e => pure (Fail c e)

-- =============================================================================
-- Tally Core Logic
-- =============================================================================

||| Tally function (core logic)
||| REQ_TALLY_001: Anyone can call tally to count votes
export
tally : ProposalId -> IO (Outcome ())
tally pid = do
  expired <- isProposalExpired pid

  if expired
    then do
      result <- finalTally pid
      case result of
        Ok _ => pure (Ok ())
        Fail c e => pure (Fail c e)
    else snap pid

-- =============================================================================
-- Entry Points
-- =============================================================================

||| Entry: tally(uint256)
export
tallyEntry : Entry tallySig
tallyEntry = MkEntry tallySel $ do
  pid <- runDecoder decodeUint256
  result <- tally (uint256Value pid)
  case result of
    Ok () => evmReturn 0 0
    Fail _ _ => evmRevert 0 0

||| Entry: snap(uint256)
export
snapEntry : Entry snapSig
snapEntry = MkEntry snapSel $ do
  pid <- runDecoder decodeUint256
  result <- snap (uint256Value pid)
  case result of
    Ok () => evmReturn 0 0
    Fail _ _ => evmRevert 0 0

||| Entry: isApproved(uint256) -> bool
export
isApprovedEntry : Entry isApprovedSig
isApprovedEntry = MkEntry isApprovedSel $ do
  pid <- runDecoder decodeUint256
  approved <- isApproved (uint256Value pid)
  returnBool approved

||| Entry: tallyAndExecute(uint256) -> bool
export
tallyAndExecuteEntry : Entry tallyAndExecuteSig
tallyAndExecuteEntry = MkEntry tallyAndExecuteSel $ do
  pid <- runDecoder decodeUint256
  result <- tallyAndExecute (uint256Value pid)
  case result of
    Ok success => returnBool success
    Fail _ _ => evmRevert 0 0
