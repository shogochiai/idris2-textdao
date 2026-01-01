||| TextDAO Propose Function
||| REQ_PROPOSE_001: Proposal creation with header and commands
module TextDAO.Functions.OnlyMember.Propose

import TextDAO.Storages.Schema
import TextDAO.Functions.Members

%default covering

-- =============================================================================
-- EVM Primitives
-- =============================================================================

%foreign "evm:timestamp"
prim__timestamp : PrimIO Integer

%foreign "evm:caller"
prim__caller : PrimIO Integer

%foreign "evm:revert"
prim__revert : Integer -> Integer -> PrimIO ()

%foreign "evm:calldataload"
prim__calldataload : Integer -> PrimIO Integer

%foreign "evm:return"
prim__return : Integer -> Integer -> PrimIO ()

timestamp : IO Integer
timestamp = primIO prim__timestamp

caller : IO Integer
caller = primIO prim__caller

evmRevert : Integer -> Integer -> IO ()
evmRevert off len = primIO (prim__revert off len)

proposeCalldataload : Integer -> IO Integer
proposeCalldataload off = primIO (prim__calldataload off)

evmReturn : Integer -> Integer -> IO ()
evmReturn off len = primIO (prim__return off len)

-- =============================================================================
-- Function Selectors
-- =============================================================================

||| propose(bytes32) -> 0x01234567
SEL_PROPOSE : Integer
SEL_PROPOSE = 0x01234567

||| getHeader(uint256,uint256) -> 0x12345678
SEL_GET_HEADER : Integer
SEL_GET_HEADER = 0x12345678

||| getProposalCount() -> 0x23456789
SEL_GET_PROPOSAL_COUNT : Integer
SEL_GET_PROPOSAL_COUNT = 0x23456789

-- =============================================================================
-- Entry Point Helpers
-- =============================================================================

||| Extract function selector from calldata (first 4 bytes)
getSelector : IO Integer
getSelector = do
  data_ <- proposeCalldataload 0
  pure (data_ `div` 0x100000000000000000000000000000000000000000000000000000000)

||| Return a uint256 value
returnUint : Integer -> IO ()
returnUint val = do
  mstore 0 val
  evmReturn 0 32

-- =============================================================================
-- Header Storage
-- =============================================================================

||| Offset for header metadataCid within header struct
HEADER_OFFSET_METADATA : Integer
HEADER_OFFSET_METADATA = 0

||| Store header metadata CID
||| REQ_PROPOSE_002
export
storeHeader : ProposalId -> HeaderId -> MetadataCid -> IO ()
storeHeader pid hid metadata = do
  slot <- getHeaderSlot pid hid
  sstore (slot + HEADER_OFFSET_METADATA) metadata

||| Get header metadata CID
export
getHeaderMetadata : ProposalId -> HeaderId -> IO MetadataCid
getHeaderMetadata pid hid = do
  slot <- getHeaderSlot pid hid
  sload (slot + HEADER_OFFSET_METADATA)

-- =============================================================================
-- Command Storage
-- =============================================================================

||| Get command slot for proposal
export
getCommandSlot : ProposalId -> CommandId -> IO Integer
getCommandSlot pid cid = do
  cmdsSlot <- getProposalCommandsSlot pid
  mstore 0 cid
  mstore 32 cmdsSlot
  keccak256 0 64

-- =============================================================================
-- Proposal Creation
-- =============================================================================

||| Initialize proposal metadata
||| REQ_PROPOSE_003
export
initProposalMeta : ProposalId -> IO ()
initProposalMeta pid = do
  now <- timestamp
  expiryDuration <- getExpiryDuration

  setProposalCreatedAt pid now
  setProposalExpiration pid (now + expiryDuration)
  setProposalHeaderCount pid 0
  setProposalCmdCount pid 0
  setApprovedHeaderId pid 0
  setApprovedCmdId pid 0
  setFullyExecuted pid False

||| Create header in proposal
||| REQ_PROPOSE_004
export
createHeader : ProposalId -> MetadataCid -> IO HeaderId
createHeader pid metadata = do
  headerCount <- getProposalHeaderCount pid
  let headerId = headerCount + 1  -- 0 is reserved/unused
  storeHeader pid headerId metadata
  setProposalHeaderCount pid headerId
  pure headerId

||| Create a new proposal with initial header
||| REQ_PROPOSE_005
export
createProposal : MetadataCid -> IO ProposalId
createProposal headerMetadata = do
  -- Get next proposal ID
  pid <- getProposalCount

  -- Initialize proposal meta
  initProposalMeta pid

  -- Create first header
  _ <- createHeader pid headerMetadata

  -- Increment proposal count
  setProposalCount (pid + 1)

  pure pid

-- =============================================================================
-- Entry Point
-- =============================================================================

||| Propose function (entry point)
||| REQ_PROPOSE_001: Members can create proposals with header metadata
export
propose : MetadataCid -> IO ProposalId
propose headerMetadata = do
  -- Access control: onlyMember
  callerAddr <- caller
  member <- isMember callerAddr

  if not member
    then do
      -- Revert: YouAreNotTheMember
      evmRevert 0 0
      pure 0
    else do
      createProposal headerMetadata

-- =============================================================================
-- Main Entry Point
-- =============================================================================

||| Main entry point for Propose contract
export
main : IO ()
main = do
  selector <- getSelector

  if selector == SEL_PROPOSE
    then do
      headerMetadata <- proposeCalldataload 4
      pid <- propose headerMetadata
      returnUint pid

    else if selector == SEL_GET_HEADER
    then do
      pid <- proposeCalldataload 4
      hid <- proposeCalldataload 36
      metadata <- getHeaderMetadata pid hid
      returnUint metadata

    else if selector == SEL_GET_PROPOSAL_COUNT
    then do
      count <- getProposalCount
      returnUint count

    else evmRevert 0 0
