||| TextDAO Storage Schema
||| Idris2 port of textdao-monorepo/packages/contracts/src/textdao/storages/Schema.sol
|||
||| Defines core data structures for deliberation, proposals, voting, and members
module TextDAO.Storages.Schema

-- =============================================================================
-- EVM Primitives (FFI)
-- =============================================================================

%foreign "evm:sload"
prim__sload : Integer -> PrimIO Integer

%foreign "evm:sstore"
prim__sstore : Integer -> Integer -> PrimIO ()

%foreign "evm:mstore"
prim__mstore : Integer -> Integer -> PrimIO ()

%foreign "evm:keccak256"
prim__keccak256 : Integer -> Integer -> PrimIO Integer

-- =============================================================================
-- Wrapped Primitives
-- =============================================================================

export
sload : Integer -> IO Integer
sload slot = primIO (prim__sload slot)

export
sstore : Integer -> Integer -> IO ()
sstore slot val = primIO (prim__sstore slot val)

export
mstore : Integer -> Integer -> IO ()
mstore off val = primIO (prim__mstore off val)

export
keccak256 : Integer -> Integer -> IO Integer
keccak256 off len = primIO (prim__keccak256 off len)

-- =============================================================================
-- Type Aliases
-- =============================================================================

||| IPFS Content Identifier (stored as keccak256 hash of CID string)
public export
MetadataCid : Type
MetadataCid = Integer

||| Ethereum address (20 bytes, stored as Integer)
public export
Address : Type
Address = Integer

||| Proposal ID
public export
ProposalId : Type
ProposalId = Integer

||| Header ID within a proposal
public export
HeaderId : Type
HeaderId = Integer

||| Command ID within a proposal
public export
CommandId : Type
CommandId = Integer

||| Tag ID
public export
TagId : Type
TagId = Integer

||| Timestamp (Unix epoch seconds)
public export
Timestamp : Type
Timestamp = Integer

-- =============================================================================
-- Action Status Enum
-- =============================================================================

||| Status of an action within a command
public export
data ActionStatus = Pending | Executed | Failed

export
actionStatusToInt : ActionStatus -> Integer
actionStatusToInt Pending = 0
actionStatusToInt Executed = 1
actionStatusToInt Failed = 2

export
intToActionStatus : Integer -> ActionStatus
intToActionStatus 1 = Executed
intToActionStatus 2 = Failed
intToActionStatus _ = Pending

-- =============================================================================
-- Storage Slot Layout (ERC-7201 Namespaced)
-- =============================================================================

||| Base storage slot for Deliberation
||| keccak256("textdao.deliberation") - 1
export
SLOT_DELIBERATION : Integer
SLOT_DELIBERATION = 0x1000

||| Base storage slot for Texts
export
SLOT_TEXTS : Integer
SLOT_TEXTS = 0x2000

||| Base storage slot for Members
export
SLOT_MEMBERS : Integer
SLOT_MEMBERS = 0x3000

||| Base storage slot for Tags
export
SLOT_TAGS : Integer
SLOT_TAGS = 0x4000

||| Base storage slot for Admins
export
SLOT_ADMINS : Integer
SLOT_ADMINS = 0x5000

||| Storage slot for proposal count
export
SLOT_PROPOSAL_COUNT : Integer
SLOT_PROPOSAL_COUNT = 0x1001

||| Storage slot for member count
export
SLOT_MEMBER_COUNT : Integer
SLOT_MEMBER_COUNT = 0x3001

||| Storage slot for text count
export
SLOT_TEXT_COUNT : Integer
SLOT_TEXT_COUNT = 0x2001

-- =============================================================================
-- DeliberationConfig Storage Layout
-- =============================================================================

||| Slot offsets within DeliberationConfig
||| Config is stored at SLOT_DELIBERATION + 0x100
export
SLOT_CONFIG_EXPIRY_DURATION : Integer
SLOT_CONFIG_EXPIRY_DURATION = 0x1100

export
SLOT_CONFIG_SNAP_INTERVAL : Integer
SLOT_CONFIG_SNAP_INTERVAL = 0x1101

export
SLOT_CONFIG_REPS_NUM : Integer
SLOT_CONFIG_REPS_NUM = 0x1102

export
SLOT_CONFIG_QUORUM_SCORE : Integer
SLOT_CONFIG_QUORUM_SCORE = 0x1103

-- =============================================================================
-- Storage Slot Calculation Helpers
-- =============================================================================

||| Calculate storage slot for proposal by ID
||| slot = keccak256(pid . SLOT_DELIBERATION)
export
getProposalSlot : ProposalId -> IO Integer
getProposalSlot pid = do
  mstore 0 pid
  mstore 32 SLOT_DELIBERATION
  keccak256 0 64

||| Calculate storage slot for proposal's header array
||| slot = keccak256(pid . SLOT_DELIBERATION) + 0x10
export
getProposalHeadersSlot : ProposalId -> IO Integer
getProposalHeadersSlot pid = do
  baseSlot <- getProposalSlot pid
  pure (baseSlot + 0x10)

||| Calculate storage slot for specific header
||| slot = keccak256(headerId . getProposalHeadersSlot(pid))
export
getHeaderSlot : ProposalId -> HeaderId -> IO Integer
getHeaderSlot pid hid = do
  headersSlot <- getProposalHeadersSlot pid
  mstore 0 hid
  mstore 32 headersSlot
  keccak256 0 64

||| Calculate storage slot for proposal's command array
||| slot = keccak256(pid . SLOT_DELIBERATION) + 0x20
export
getProposalCommandsSlot : ProposalId -> IO Integer
getProposalCommandsSlot pid = do
  baseSlot <- getProposalSlot pid
  pure (baseSlot + 0x20)

||| Calculate storage slot for proposal's meta
||| slot = keccak256(pid . SLOT_DELIBERATION) + 0x30
export
getProposalMetaSlot : ProposalId -> IO Integer
getProposalMetaSlot pid = do
  baseSlot <- getProposalSlot pid
  pure (baseSlot + 0x30)

||| Calculate storage slot for a vote by representative address
||| slot = keccak256(repAddr . getProposalMetaSlot(pid) + 0x10)
export
getVoteSlot : ProposalId -> Address -> IO Integer
getVoteSlot pid repAddr = do
  metaSlot <- getProposalMetaSlot pid
  let votesBaseSlot = metaSlot + 0x10
  mstore 0 repAddr
  mstore 32 votesBaseSlot
  keccak256 0 64

||| Calculate storage slot for member by index
||| slot = keccak256(index . SLOT_MEMBERS)
export
getMemberSlot : Integer -> IO Integer
getMemberSlot index = do
  mstore 0 index
  mstore 32 SLOT_MEMBERS
  keccak256 0 64

||| Calculate storage slot for text by index
||| slot = keccak256(index . SLOT_TEXTS)
export
getTextSlot : Integer -> IO Integer
getTextSlot index = do
  mstore 0 index
  mstore 32 SLOT_TEXTS
  keccak256 0 64

-- =============================================================================
-- Storage Read/Write Helpers
-- =============================================================================

||| Get proposal count
export
getProposalCount : IO Integer
getProposalCount = sload SLOT_PROPOSAL_COUNT

||| Set proposal count
export
setProposalCount : Integer -> IO ()
setProposalCount = sstore SLOT_PROPOSAL_COUNT

||| Get member count
export
getMemberCount : IO Integer
getMemberCount = sload SLOT_MEMBER_COUNT

||| Set member count
export
setMemberCount : Integer -> IO ()
setMemberCount = sstore SLOT_MEMBER_COUNT

||| Get text count
export
getTextCount : IO Integer
getTextCount = sload SLOT_TEXT_COUNT

||| Set text count
export
setTextCount : Integer -> IO ()
setTextCount = sstore SLOT_TEXT_COUNT

-- =============================================================================
-- Deliberation Config Read/Write
-- =============================================================================

||| Get expiry duration (seconds)
export
getExpiryDuration : IO Integer
getExpiryDuration = sload SLOT_CONFIG_EXPIRY_DURATION

||| Set expiry duration
export
setExpiryDuration : Integer -> IO ()
setExpiryDuration = sstore SLOT_CONFIG_EXPIRY_DURATION

||| Get snapshot interval
export
getSnapInterval : IO Integer
getSnapInterval = sload SLOT_CONFIG_SNAP_INTERVAL

||| Set snapshot interval
export
setSnapInterval : Integer -> IO ()
setSnapInterval = sstore SLOT_CONFIG_SNAP_INTERVAL

||| Get number of representatives
export
getRepsNum : IO Integer
getRepsNum = sload SLOT_CONFIG_REPS_NUM

||| Set number of representatives
export
setRepsNum : Integer -> IO ()
setRepsNum = sstore SLOT_CONFIG_REPS_NUM

||| Get quorum score
export
getQuorumScore : IO Integer
getQuorumScore = sload SLOT_CONFIG_QUORUM_SCORE

||| Set quorum score
export
setQuorumScore : Integer -> IO ()
setQuorumScore = sstore SLOT_CONFIG_QUORUM_SCORE

-- =============================================================================
-- Proposal Meta Field Offsets
-- =============================================================================

||| Offset for createdAt within proposal meta
export
META_OFFSET_CREATED_AT : Integer
META_OFFSET_CREATED_AT = 0

||| Offset for expirationTime
export
META_OFFSET_EXPIRATION : Integer
META_OFFSET_EXPIRATION = 1

||| Offset for snapInterval
export
META_OFFSET_SNAP_INTERVAL : Integer
META_OFFSET_SNAP_INTERVAL = 2

||| Offset for headerCount
export
META_OFFSET_HEADER_COUNT : Integer
META_OFFSET_HEADER_COUNT = 3

||| Offset for commandCount
export
META_OFFSET_CMD_COUNT : Integer
META_OFFSET_CMD_COUNT = 4

||| Offset for approvedHeaderId
export
META_OFFSET_APPROVED_HEADER : Integer
META_OFFSET_APPROVED_HEADER = 5

||| Offset for approvedCommandId
export
META_OFFSET_APPROVED_CMD : Integer
META_OFFSET_APPROVED_CMD = 6

||| Offset for fullyExecuted flag
export
META_OFFSET_EXECUTED : Integer
META_OFFSET_EXECUTED = 7

-- =============================================================================
-- Proposal Meta Read/Write
-- =============================================================================

||| Get proposal creation timestamp
export
getProposalCreatedAt : ProposalId -> IO Timestamp
getProposalCreatedAt pid = do
  metaSlot <- getProposalMetaSlot pid
  sload (metaSlot + META_OFFSET_CREATED_AT)

||| Set proposal creation timestamp
export
setProposalCreatedAt : ProposalId -> Timestamp -> IO ()
setProposalCreatedAt pid ts = do
  metaSlot <- getProposalMetaSlot pid
  sstore (metaSlot + META_OFFSET_CREATED_AT) ts

||| Get proposal expiration time
export
getProposalExpiration : ProposalId -> IO Timestamp
getProposalExpiration pid = do
  metaSlot <- getProposalMetaSlot pid
  sload (metaSlot + META_OFFSET_EXPIRATION)

||| Set proposal expiration time
export
setProposalExpiration : ProposalId -> Timestamp -> IO ()
setProposalExpiration pid ts = do
  metaSlot <- getProposalMetaSlot pid
  sstore (metaSlot + META_OFFSET_EXPIRATION) ts

||| Get header count for proposal
export
getProposalHeaderCount : ProposalId -> IO Integer
getProposalHeaderCount pid = do
  metaSlot <- getProposalMetaSlot pid
  sload (metaSlot + META_OFFSET_HEADER_COUNT)

||| Set header count for proposal
export
setProposalHeaderCount : ProposalId -> Integer -> IO ()
setProposalHeaderCount pid count = do
  metaSlot <- getProposalMetaSlot pid
  sstore (metaSlot + META_OFFSET_HEADER_COUNT) count

||| Get command count for proposal
export
getProposalCmdCount : ProposalId -> IO Integer
getProposalCmdCount pid = do
  metaSlot <- getProposalMetaSlot pid
  sload (metaSlot + META_OFFSET_CMD_COUNT)

||| Set command count for proposal
export
setProposalCmdCount : ProposalId -> Integer -> IO ()
setProposalCmdCount pid count = do
  metaSlot <- getProposalMetaSlot pid
  sstore (metaSlot + META_OFFSET_CMD_COUNT) count

||| Get approved header ID
export
getApprovedHeaderId : ProposalId -> IO HeaderId
getApprovedHeaderId pid = do
  metaSlot <- getProposalMetaSlot pid
  sload (metaSlot + META_OFFSET_APPROVED_HEADER)

||| Set approved header ID
export
setApprovedHeaderId : ProposalId -> HeaderId -> IO ()
setApprovedHeaderId pid hid = do
  metaSlot <- getProposalMetaSlot pid
  sstore (metaSlot + META_OFFSET_APPROVED_HEADER) hid

||| Get approved command ID
export
getApprovedCmdId : ProposalId -> IO CommandId
getApprovedCmdId pid = do
  metaSlot <- getProposalMetaSlot pid
  sload (metaSlot + META_OFFSET_APPROVED_CMD)

||| Set approved command ID
export
setApprovedCmdId : ProposalId -> CommandId -> IO ()
setApprovedCmdId pid cid = do
  metaSlot <- getProposalMetaSlot pid
  sstore (metaSlot + META_OFFSET_APPROVED_CMD) cid

||| Check if proposal is fully executed
export
isFullyExecuted : ProposalId -> IO Bool
isFullyExecuted pid = do
  metaSlot <- getProposalMetaSlot pid
  val <- sload (metaSlot + META_OFFSET_EXECUTED)
  pure (val == 1)

||| Set fully executed flag
export
setFullyExecuted : ProposalId -> Bool -> IO ()
setFullyExecuted pid executed = do
  metaSlot <- getProposalMetaSlot pid
  sstore (metaSlot + META_OFFSET_EXECUTED) (if executed then 1 else 0)
