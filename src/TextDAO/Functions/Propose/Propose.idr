||| TextDAO Propose Function
||| REQ_PROPOSE_001: Proposal creation with header and commands
module TextDAO.Functions.Propose.Propose

import public Subcontract.Core.Entry
import Subcontract.Core.ABI.Decoder
import public Subcontract.Core.Outcome
import TextDAO.Storages.Schema
import TextDAO.Functions.Members.Members
import public TextDAO.Security.AccessControl

-- Note: EVM primitives now come from TextDAO.Storages.Schema via Subcontract.Core.Storable

%default covering

-- =============================================================================
-- Function Signatures
-- =============================================================================

||| propose(bytes32) -> uint256
public export
proposeSig : Sig
proposeSig = MkSig "propose" [TBytes32] [TUint256]

public export
proposeSel : Sel proposeSig
proposeSel = MkSel 0x01234567

||| getHeader(uint256,uint256) -> bytes32
public export
getHeaderSig : Sig
getHeaderSig = MkSig "getHeader" [TUint256, TUint256] [TBytes32]

public export
getHeaderSel : Sel getHeaderSig
getHeaderSel = MkSel 0x12345678

||| getProposalCount() -> uint256
public export
getProposalCountSig : Sig
getProposalCountSig = MkSig "getProposalCount" [] [TUint256]

public export
getProposalCountSel : Sel getProposalCountSig
getProposalCountSel = MkSel 0x23456789

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
-- Proposal Creation (Core Logic)
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

||| Propose function with compile-time member proof
||| REQ_PROPOSE_001: Members can create proposals with header metadata
||| Type-safe version: caller must provide proof of membership
export
proposeWithProof : IsMember callerAddr -> MetadataCid -> IO ProposalId
proposeWithProof _ headerMetadata = createProposal headerMetadata

||| Propose function (runtime checked version for entry points)
||| REQ_PROPOSE_001: Members can create proposals with header metadata
export
propose : MetadataCid -> IO (Outcome ProposalId)
propose headerMetadata = do
  callerAddr <- caller
  proofResult <- requireMemberProof callerAddr
  case proofResult of
    Fail c e => pure (Fail c e)
    Ok _ => do
      -- Proof verified, proceed with proposal creation
      pid <- createProposal headerMetadata
      pure (Ok pid)

-- =============================================================================
-- Entry Points
-- =============================================================================

||| Entry: propose(bytes32) -> uint256
export
proposeEntry : Entry proposeSig
proposeEntry = MkEntry proposeSel $ do
  headerMetadata <- runDecoder decodeBytes32
  result <- propose (bytes32Value headerMetadata)
  case result of
    Ok pid => returnUint pid
    Fail _ _ => evmRevert 0 0

||| Entry: getHeader(uint256,uint256) -> bytes32
export
getHeaderEntry : Entry getHeaderSig
getHeaderEntry = MkEntry getHeaderSel $ do
  pid <- runDecoder decodeUint256
  hid <- runDecoder decodeUint256
  metadata <- getHeaderMetadata (uint256Value pid) (uint256Value hid)
  returnUint metadata

||| Entry: getProposalCount() -> uint256
export
getProposalCountEntry : Entry getProposalCountSig
getProposalCountEntry = MkEntry getProposalCountSel $ do
  count <- getProposalCount
  returnUint count
