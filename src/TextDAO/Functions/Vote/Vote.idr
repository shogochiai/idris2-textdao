||| TextDAO Vote Function
||| REQ_VOTE_001: Representatives can vote on proposals using RCV
module TextDAO.Functions.Vote.Vote

import public Subcontract.Core.Entry
import Subcontract.Core.ABI.Decoder
import public Subcontract.Core.Outcome
import TextDAO.Storages.Schema
import public TextDAO.Security.AccessControl

-- Note: EVM primitives now come from TextDAO.Storages.Schema via Subcontract.Core.Storable

%default covering

-- =============================================================================
-- Function Signatures
-- =============================================================================

||| vote(uint256,uint256[3],uint256[3]) -> bool
||| Note: Arrays are decoded as 6 consecutive uint256s
public export
voteSig : Sig
voteSig = MkSig "vote" [TUint256, TUint256, TUint256, TUint256, TUint256, TUint256, TUint256] [TBool]

public export
voteSel : Sel voteSig
voteSel = MkSel 0x34567890

||| isRep(uint256,address) -> bool
public export
isRepSig : Sig
isRepSig = MkSig "isRep" [TUint256, TAddress] [TBool]

public export
isRepSel : Sel isRepSig
isRepSel = MkSel 0x56789012

-- =============================================================================
-- Vote Storage Layout
-- =============================================================================

||| Vote struct offsets (6 slots total)
||| rankedHeaderIds[3] at offsets 0, 1, 2
||| rankedCommandIds[3] at offsets 3, 4, 5
VOTE_OFFSET_HEADER_0 : Integer
VOTE_OFFSET_HEADER_0 = 0

VOTE_OFFSET_HEADER_1 : Integer
VOTE_OFFSET_HEADER_1 = 1

VOTE_OFFSET_HEADER_2 : Integer
VOTE_OFFSET_HEADER_2 = 2

VOTE_OFFSET_CMD_0 : Integer
VOTE_OFFSET_CMD_0 = 3

VOTE_OFFSET_CMD_1 : Integer
VOTE_OFFSET_CMD_1 = 4

VOTE_OFFSET_CMD_2 : Integer
VOTE_OFFSET_CMD_2 = 5

-- =============================================================================
-- Representative Storage (now in Schema.idr, re-exported via import)
-- =============================================================================

||| Check if address is a representative for proposal
||| REQ_VOTE_002
export
isRep : ProposalId -> EvmAddr -> IO Bool
isRep pid addr = do
  count <- getRepCount pid
  checkRep addr 0 count
  where
    checkRep : EvmAddr -> Integer -> Integer -> IO Bool
    checkRep target idx cnt =
      if idx >= cnt
        then pure False
        else do
          repAddr <- getRepAddr pid idx
          if repAddr == target
            then pure True
            else checkRep target (idx + 1) cnt

-- =============================================================================
-- Vote Storage
-- =============================================================================

||| Store a vote
||| REQ_VOTE_003
export
storeVote : ProposalId -> EvmAddr -> (Integer, Integer, Integer) -> (Integer, Integer, Integer) -> IO ()
storeVote pid voter (h0, h1, h2) (c0, c1, c2) = do
  slot <- getVoteSlot pid voter
  sstore (slot + VOTE_OFFSET_HEADER_0) h0
  sstore (slot + VOTE_OFFSET_HEADER_1) h1
  sstore (slot + VOTE_OFFSET_HEADER_2) h2
  sstore (slot + VOTE_OFFSET_CMD_0) c0
  sstore (slot + VOTE_OFFSET_CMD_1) c1
  sstore (slot + VOTE_OFFSET_CMD_2) c2

||| Store a vote with explicit arguments (workaround for tuple compilation issues)
||| Takes 6 individual Integers instead of 2 tuples
export
storeVoteDirect : ProposalId -> EvmAddr -> Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> IO ()
storeVoteDirect pid voter h0 h1 h2 c0 c1 c2 = do
  slot <- getVoteSlot pid voter
  sstore (slot + VOTE_OFFSET_HEADER_0) h0
  sstore (slot + VOTE_OFFSET_HEADER_1) h1
  sstore (slot + VOTE_OFFSET_HEADER_2) h2
  sstore (slot + VOTE_OFFSET_CMD_0) c0
  sstore (slot + VOTE_OFFSET_CMD_1) c1
  sstore (slot + VOTE_OFFSET_CMD_2) c2

||| Read a vote
export
readVote : ProposalId -> EvmAddr -> IO ((Integer, Integer, Integer), (Integer, Integer, Integer))
readVote pid voter = do
  slot <- getVoteSlot pid voter
  h0 <- sload (slot + VOTE_OFFSET_HEADER_0)
  h1 <- sload (slot + VOTE_OFFSET_HEADER_1)
  h2 <- sload (slot + VOTE_OFFSET_HEADER_2)
  c0 <- sload (slot + VOTE_OFFSET_CMD_0)
  c1 <- sload (slot + VOTE_OFFSET_CMD_1)
  c2 <- sload (slot + VOTE_OFFSET_CMD_2)
  pure ((h0, h1, h2), (c0, c1, c2))

||| Read vote header at specific rank (workaround for tuple compilation issues)
export
readVoteHeader : ProposalId -> EvmAddr -> Integer -> IO Integer
readVoteHeader pid voter rank = do
  slot <- getVoteSlot pid voter
  sload (slot + rank)

||| Read vote command at specific rank (workaround for tuple compilation issues)
export
readVoteCommand : ProposalId -> EvmAddr -> Integer -> IO Integer
readVoteCommand pid voter rank = do
  slot <- getVoteSlot pid voter
  sload (slot + VOTE_OFFSET_CMD_0 + rank)

-- =============================================================================
-- Vote Validation
-- =============================================================================

||| Check if proposal is expired
||| REQ_VOTE_004
export
isProposalExpired : ProposalId -> IO Bool
isProposalExpired pid = do
  expiration <- getProposalExpiration pid
  now <- timestamp
  pure (now >= expiration)

||| Validate header ID is within bounds
export
validateHeaderId : ProposalId -> HeaderId -> IO Bool
validateHeaderId pid hid = do
  headerCount <- getProposalHeaderCount pid
  pure (hid >= 0 && hid <= headerCount)

||| Validate command ID is within bounds
export
validateCommandId : ProposalId -> CommandId -> IO Bool
validateCommandId pid cid = do
  cmdCount <- getProposalCmdCount pid
  pure (cid >= 0 && cid <= cmdCount)

-- =============================================================================
-- Vote Core Logic
-- =============================================================================

||| Vote on a proposal with compile-time proofs
||| REQ_VOTE_001: Representatives can cast ranked votes
||| Type-safe version: requires proof of rep status and not expired
export
voteWithProof : IsRep pid callerAddr
             -> NotExpired pid
             -> ProposalId
             -> (Integer, Integer, Integer)
             -> (Integer, Integer, Integer)
             -> IO (Outcome Bool)
voteWithProof repProof _ pid rankedHeaders rankedCommands = do
  let voterAddr = repAddr repProof
  -- Validate header IDs
  let (h0, h1, h2) = rankedHeaders
  validH0 <- validateHeaderId pid h0
  validH1 <- validateHeaderId pid h1
  validH2 <- validateHeaderId pid h2

  -- Validate command IDs
  let (c0, c1, c2) = rankedCommands
  validC0 <- validateCommandId pid c0
  validC1 <- validateCommandId pid c1
  validC2 <- validateCommandId pid c2

  if not (validH0 && validH1 && validH2 && validC0 && validC1 && validC2)
    then pure (Fail InvariantViolation (tagEvidence "InvalidId"))
    else do
      -- Store vote
      storeVote pid voterAddr rankedHeaders rankedCommands
      pure (Ok True)

||| Vote on a proposal (RCV: Ranked Choice Voting)
||| REQ_VOTE_001: Representatives can cast ranked votes
||| Runtime checked version for entry points
export
vote : ProposalId -> (Integer, Integer, Integer) -> (Integer, Integer, Integer) -> IO (Outcome Bool)
vote pid rankedHeaders rankedCommands = do
  callerAddr <- caller
  -- Check rep status
  repResult <- requireRepProof pid callerAddr
  case repResult of
    Fail c e => pure (Fail c e)
    Ok repProof => do
      -- Check not expired
      expResult <- requireNotExpired pid
      case expResult of
        Fail c e => pure (Fail c e)
        Ok notExpiredProof =>
          voteWithProof repProof notExpiredProof pid rankedHeaders rankedCommands

-- =============================================================================
-- Entry Points
-- =============================================================================

||| Entry: vote(uint256,uint256[3],uint256[3]) -> bool
export
voteEntry : Entry voteSig
voteEntry = MkEntry voteSel $ do
  pid <- runDecoder decodeUint256
  h0 <- runDecoder decodeUint256
  h1 <- runDecoder decodeUint256
  h2 <- runDecoder decodeUint256
  c0 <- runDecoder decodeUint256
  c1 <- runDecoder decodeUint256
  c2 <- runDecoder decodeUint256
  result <- vote (uint256Value pid)
                 (uint256Value h0, uint256Value h1, uint256Value h2)
                 (uint256Value c0, uint256Value c1, uint256Value c2)
  case result of
    Ok success => returnBool success
    Fail _ _ => evmRevert 0 0

||| Entry: isRep(uint256,address) -> bool
export
isRepEntry : Entry isRepSig
isRepEntry = MkEntry isRepSel $ do
  pid <- runDecoder decodeUint256
  addr <- runDecoder decodeAddress
  rep <- isRep (uint256Value pid) (addrValue addr)
  returnBool rep
