||| TextDAO Text Function
||| REQ_TEXT_001: Create and manage texts from approved proposals
module TextDAO.Functions.Text.Text

import public Subcontract.Core.Entry
import Subcontract.Core.ABI.Decoder
import public Subcontract.Core.Outcome
import TextDAO.Storages.Schema

-- Note: EVM primitives now come from TextDAO.Storages.Schema via Subcontract.Core.Storable

%default covering

-- =============================================================================
-- Function Signatures
-- =============================================================================

||| createText(uint256,bytes32) -> uint256
public export
createTextSig : Sig
createTextSig = MkSig "createText" [TUint256, TBytes32] [TUint256]

public export
createTextSel : Sel createTextSig
createTextSel = MkSel 0xc0123456

||| getText(uint256) -> bytes32
public export
getTextSig : Sig
getTextSig = MkSig "getText" [TUint256] [TBytes32]

public export
getTextSel : Sel getTextSig
getTextSel = MkSel 0xc1234567

||| getTextCount() -> uint256
public export
getTextCountSig : Sig
getTextCountSig = MkSig "getTextCount" [] [TUint256]

public export
getTextCountSel : Sel getTextCountSig
getTextCountSel = MkSel 0xc2345678

-- =============================================================================
-- Event Topics
-- =============================================================================

||| TextCreated(uint256 textId, uint256 pid) event signature
EVENT_TEXT_CREATED : Integer
EVENT_TEXT_CREATED = 0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890

-- =============================================================================
-- Text Storage Layout
-- =============================================================================

||| Text struct offsets
TEXT_OFFSET_METADATA : Integer
TEXT_OFFSET_METADATA = 0

TEXT_OFFSET_PROPOSAL_ID : Integer
TEXT_OFFSET_PROPOSAL_ID = 1

TEXT_OFFSET_HEADER_ID : Integer
TEXT_OFFSET_HEADER_ID = 2

-- =============================================================================
-- Text Storage Functions
-- =============================================================================

||| Store text metadata
export
storeTextMetadata : Integer -> MetadataCid -> IO ()
storeTextMetadata textId metadata = do
  slot <- getTextSlot textId
  sstore (slot + TEXT_OFFSET_METADATA) metadata

||| Get text metadata
export
getTextMetadata : Integer -> IO MetadataCid
getTextMetadata textId = do
  slot <- getTextSlot textId
  sload (slot + TEXT_OFFSET_METADATA)

||| Store text's proposal ID
export
storeTextProposalId : Integer -> ProposalId -> IO ()
storeTextProposalId textId pid = do
  slot <- getTextSlot textId
  sstore (slot + TEXT_OFFSET_PROPOSAL_ID) pid

||| Get text's proposal ID
export
getTextProposalId : Integer -> IO ProposalId
getTextProposalId textId = do
  slot <- getTextSlot textId
  sload (slot + TEXT_OFFSET_PROPOSAL_ID)

||| Store text's header ID
export
storeTextHeaderId : Integer -> HeaderId -> IO ()
storeTextHeaderId textId hid = do
  slot <- getTextSlot textId
  sstore (slot + TEXT_OFFSET_HEADER_ID) hid

||| Get text's header ID
export
getTextHeaderId : Integer -> IO HeaderId
getTextHeaderId textId = do
  slot <- getTextSlot textId
  sload (slot + TEXT_OFFSET_HEADER_ID)

-- =============================================================================
-- Create Text Core Logic
-- =============================================================================

||| Check if proposal is approved
isProposalApproved : ProposalId -> IO Bool
isProposalApproved pid = do
  approvedHeader <- getApprovedHeaderId pid
  pure (approvedHeader > 0)

||| Create text from approved proposal
||| REQ_TEXT_001: Create text after proposal is approved
export
createText : ProposalId -> MetadataCid -> IO (Outcome Integer)
createText pid metadataCid = do
  -- Check proposal is approved
  approved <- isProposalApproved pid
  if not approved
    then pure (Fail InvalidTransition (tagEvidence "ProposalNotApproved"))
    else do
      -- Get next text ID
      textCount <- getTextCount
      let textId = textCount

      -- Get approved header ID
      approvedHeader <- getApprovedHeaderId pid

      -- Store text data
      storeTextMetadata textId metadataCid
      storeTextProposalId textId pid
      storeTextHeaderId textId approvedHeader

      -- Increment text count
      setTextCount (textCount + 1)

      -- Emit TextCreated event
      mstore 0 textId
      log2 0 32 EVENT_TEXT_CREATED pid

      pure (Ok textId)

-- =============================================================================
-- Entry Points
-- =============================================================================

||| Entry: createText(uint256,bytes32) -> uint256
export
createTextEntry : Entry createTextSig
createTextEntry = MkEntry createTextSel $ do
  pid <- runDecoder decodeUint256
  metadataCid <- runDecoder decodeBytes32
  result <- createText (uint256Value pid) (bytes32Value metadataCid)
  case result of
    Ok textId => returnUint textId
    Fail _ _ => evmRevert 0 0

||| Entry: getText(uint256) -> bytes32
export
getTextEntry : Entry getTextSig
getTextEntry = MkEntry getTextSel $ do
  textId <- runDecoder decodeUint256
  metadata <- getTextMetadata (uint256Value textId)
  returnUint metadata

||| Entry: getTextCount() -> uint256
export
getTextCountEntry : Entry getTextCountSig
getTextCountEntry = MkEntry getTextCountSel $ do
  count <- getTextCount
  returnUint count
