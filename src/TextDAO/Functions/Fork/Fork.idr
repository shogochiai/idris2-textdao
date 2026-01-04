||| TextDAO Fork Function
||| REQ_FORK_001: Representatives can fork proposals with new headers/commands
module TextDAO.Functions.Fork.Fork

import TextDAO.Storages.Schema
import TextDAO.Functions.Vote.Vote
import TextDAO.Functions.Propose.Propose

%default covering

-- =============================================================================
-- EVM Primitives
-- =============================================================================

%foreign "evm:caller"
prim__caller : PrimIO Integer

%foreign "evm:revert"
prim__revert : Integer -> Integer -> PrimIO ()

%foreign "evm:calldataload"
prim__calldataload : Integer -> PrimIO Integer

%foreign "evm:return"
prim__return : Integer -> Integer -> PrimIO ()

caller : IO Integer
caller = primIO prim__caller

evmRevert : Integer -> Integer -> IO ()
evmRevert off len = primIO (prim__revert off len)

calldataload : Integer -> IO Integer
calldataload off = primIO (prim__calldataload off)

evmReturn : Integer -> Integer -> IO ()
evmReturn off len = primIO (prim__return off len)

-- =============================================================================
-- Function Selectors
-- =============================================================================

||| fork(uint256,bytes32,bytes32) -> 0xf0123456
SEL_FORK : Integer
SEL_FORK = 0xf0123456

||| forkHeader(uint256,bytes32) -> 0xf1234567
SEL_FORK_HEADER : Integer
SEL_FORK_HEADER = 0xf1234567

||| forkCommand(uint256,bytes32) -> 0xf2345678
SEL_FORK_COMMAND : Integer
SEL_FORK_COMMAND = 0xf2345678

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
-- Fork Functions
-- =============================================================================

||| Fork header only - add a new header to existing proposal
||| REQ_FORK_002: Reps can add alternative headers
export
forkHeader : ProposalId -> MetadataCid -> IO HeaderId
forkHeader pid headerMetadata = do
  -- Access control: onlyReps
  callerAddr <- caller
  rep <- isRep pid callerAddr

  if not rep
    then do
      evmRevert 0 0  -- YouAreNotTheRep
      pure 0
    else do
      -- Check proposal not expired
      expired <- isProposalExpired pid
      if expired
        then do
          evmRevert 0 0  -- ProposalAlreadyExpired
          pure 0
        else createHeader pid headerMetadata

||| Fork command only - add a new command to existing proposal
||| REQ_FORK_003: Reps can add alternative commands
export
forkCommand : ProposalId -> Integer -> IO CommandId
forkCommand pid actionData = do
  -- Access control: onlyReps
  callerAddr <- caller
  rep <- isRep pid callerAddr

  if not rep
    then do
      evmRevert 0 0  -- YouAreNotTheRep
      pure 0
    else do
      -- Check proposal not expired
      expired <- isProposalExpired pid
      if expired
        then do
          evmRevert 0 0  -- ProposalAlreadyExpired
          pure 0
        else createCommand pid actionData

||| Fork - add both header and command to existing proposal
||| REQ_FORK_001: Reps can fork proposals with new alternatives
export
fork : ProposalId -> MetadataCid -> Integer -> IO (HeaderId, CommandId)
fork pid headerMetadata actionData = do
  -- Access control: onlyReps
  callerAddr <- caller
  rep <- isRep pid callerAddr

  if not rep
    then do
      evmRevert 0 0  -- YouAreNotTheRep
      pure (0, 0)
    else do
      -- Check proposal not expired
      expired <- isProposalExpired pid
      if expired
        then do
          evmRevert 0 0  -- ProposalAlreadyExpired
          pure (0, 0)
        else do
          headerId <- createHeader pid headerMetadata
          cmdId <- createCommand pid actionData
          pure (headerId, cmdId)

-- =============================================================================
-- Main Entry Point
-- =============================================================================

||| Main entry point for Fork contract
export
main : IO ()
main = do
  selector <- getSelector

  if selector == SEL_FORK
    then do
      pid <- calldataload 4
      headerMetadata <- calldataload 36
      actionData <- calldataload 68
      (hid, cid) <- fork pid headerMetadata actionData
      -- Return header ID (could also encode both)
      returnUint hid

    else if selector == SEL_FORK_HEADER
    then do
      pid <- calldataload 4
      headerMetadata <- calldataload 36
      hid <- forkHeader pid headerMetadata
      returnUint hid

    else if selector == SEL_FORK_COMMAND
    then do
      pid <- calldataload 4
      actionData <- calldataload 36
      cid <- forkCommand pid actionData
      returnUint cid

    else evmRevert 0 0
