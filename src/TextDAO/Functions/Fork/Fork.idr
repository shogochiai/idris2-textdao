||| TextDAO Fork Function
||| REQ_FORK_001: Representatives can fork proposals with new headers/commands
module TextDAO.Functions.Fork.Fork

import public Subcontract.Core.Entry
import Subcontract.Core.ABI.Decoder
import public Subcontract.Core.Outcome
import TextDAO.Storages.Schema
import TextDAO.Functions.Vote.Vote
import TextDAO.Functions.Propose.Propose
import public TextDAO.Security.AccessControl

-- Note: EVM primitives now come from TextDAO.Storages.Schema via Subcontract.Core.Storable

%default covering

-- =============================================================================
-- Function Signatures
-- =============================================================================

||| fork(uint256,bytes32,bytes32) -> uint256
public export
forkSig : Sig
forkSig = MkSig "fork" [TUint256, TBytes32, TBytes32] [TUint256]

public export
forkSel : Sel forkSig
forkSel = MkSel 0xf0123456

||| forkHeader(uint256,bytes32) -> uint256
public export
forkHeaderSig : Sig
forkHeaderSig = MkSig "forkHeader" [TUint256, TBytes32] [TUint256]

public export
forkHeaderSel : Sel forkHeaderSig
forkHeaderSel = MkSel 0xf1234567

||| forkCommand(uint256,bytes32) -> uint256
public export
forkCommandSig : Sig
forkCommandSig = MkSig "forkCommand" [TUint256, TBytes32] [TUint256]

public export
forkCommandSel : Sel forkCommandSig
forkCommandSel = MkSel 0xf2345678

-- =============================================================================
-- Command Storage
-- =============================================================================

||| Command struct offsets
CMD_OFFSET_ACTION_DATA : Integer
CMD_OFFSET_ACTION_DATA = 0

||| Store command action data
export
storeCommand : ProposalId -> CommandId -> Integer -> IO ()
storeCommand pid cid actionData = do
  slot <- getCommandSlot pid cid
  sstore (slot + CMD_OFFSET_ACTION_DATA) actionData

||| Get command action data
export
getCommandActionData : ProposalId -> CommandId -> IO Integer
getCommandActionData pid cid = do
  slot <- getCommandSlot pid cid
  sload (slot + CMD_OFFSET_ACTION_DATA)

||| Create new command in proposal
export
createCommand : ProposalId -> Integer -> IO CommandId
createCommand pid actionData = do
  cmdCount <- getProposalCmdCount pid
  let cmdId = cmdCount + 1  -- 0 is reserved/unused
  storeCommand pid cmdId actionData
  setProposalCmdCount pid cmdId
  pure cmdId

-- =============================================================================
-- Fork Core Logic
-- =============================================================================

||| Fork header with compile-time proofs
||| REQ_FORK_002: Reps can add alternative headers
export
forkHeaderWithProof : IsRep pid callerAddr -> NotExpired pid -> ProposalId -> MetadataCid -> IO HeaderId
forkHeaderWithProof _ _ pid headerMetadata = createHeader pid headerMetadata

||| Fork header only - add a new header to existing proposal
||| REQ_FORK_002: Reps can add alternative headers
||| Runtime checked version for entry points
export
forkHeader : ProposalId -> MetadataCid -> IO (Outcome HeaderId)
forkHeader pid headerMetadata = do
  callerAddr <- caller
  repResult <- requireRepProof pid callerAddr
  case repResult of
    Fail c e => pure (Fail c e)
    Ok repProof => do
      expResult <- requireNotExpired pid
      case expResult of
        Fail c e => pure (Fail c e)
        Ok notExpiredProof => do
          hid <- forkHeaderWithProof repProof notExpiredProof pid headerMetadata
          pure (Ok hid)

||| Fork command with compile-time proofs
||| REQ_FORK_003: Reps can add alternative commands
export
forkCommandWithProof : IsRep pid callerAddr -> NotExpired pid -> ProposalId -> Integer -> IO CommandId
forkCommandWithProof _ _ pid actionData = createCommand pid actionData

||| Fork command only - add a new command to existing proposal
||| REQ_FORK_003: Reps can add alternative commands
||| Runtime checked version for entry points
export
forkCommand : ProposalId -> Integer -> IO (Outcome CommandId)
forkCommand pid actionData = do
  callerAddr <- caller
  repResult <- requireRepProof pid callerAddr
  case repResult of
    Fail c e => pure (Fail c e)
    Ok repProof => do
      expResult <- requireNotExpired pid
      case expResult of
        Fail c e => pure (Fail c e)
        Ok notExpiredProof => do
          cid <- forkCommandWithProof repProof notExpiredProof pid actionData
          pure (Ok cid)

||| Fork with compile-time proofs
||| REQ_FORK_001: Reps can fork proposals with new alternatives
export
forkWithProof : IsRep pid callerAddr -> NotExpired pid -> ProposalId -> MetadataCid -> Integer -> IO (HeaderId, CommandId)
forkWithProof _ _ pid headerMetadata actionData = do
  headerId <- createHeader pid headerMetadata
  cmdId <- createCommand pid actionData
  pure (headerId, cmdId)

||| Fork - add both header and command to existing proposal
||| REQ_FORK_001: Reps can fork proposals with new alternatives
||| Runtime checked version for entry points
export
fork : ProposalId -> MetadataCid -> Integer -> IO (Outcome (HeaderId, CommandId))
fork pid headerMetadata actionData = do
  callerAddr <- caller
  repResult <- requireRepProof pid callerAddr
  case repResult of
    Fail c e => pure (Fail c e)
    Ok repProof => do
      expResult <- requireNotExpired pid
      case expResult of
        Fail c e => pure (Fail c e)
        Ok notExpiredProof => do
          result <- forkWithProof repProof notExpiredProof pid headerMetadata actionData
          pure (Ok result)

-- =============================================================================
-- Entry Points
-- =============================================================================

||| Entry: fork(uint256,bytes32,bytes32) -> uint256
export
forkEntry : Entry forkSig
forkEntry = MkEntry forkSel $ do
  pid <- runDecoder decodeUint256
  headerMetadata <- runDecoder decodeBytes32
  actionData <- runDecoder decodeBytes32
  result <- fork (uint256Value pid) (bytes32Value headerMetadata) (bytes32Value actionData)
  case result of
    Ok (hid, _) => returnUint hid
    Fail _ _ => evmRevert 0 0

||| Entry: forkHeader(uint256,bytes32) -> uint256
export
forkHeaderEntry : Entry forkHeaderSig
forkHeaderEntry = MkEntry forkHeaderSel $ do
  pid <- runDecoder decodeUint256
  headerMetadata <- runDecoder decodeBytes32
  result <- forkHeader (uint256Value pid) (bytes32Value headerMetadata)
  case result of
    Ok hid => returnUint hid
    Fail _ _ => evmRevert 0 0

||| Entry: forkCommand(uint256,bytes32) -> uint256
export
forkCommandEntry : Entry forkCommandSig
forkCommandEntry = MkEntry forkCommandSel $ do
  pid <- runDecoder decodeUint256
  actionData <- runDecoder decodeBytes32
  result <- forkCommand (uint256Value pid) (bytes32Value actionData)
  case result of
    Ok cid => returnUint cid
    Fail _ _ => evmRevert 0 0
