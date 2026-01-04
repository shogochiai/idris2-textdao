||| TextDAO Text Function
||| REQ_TEXT_001: Create and manage texts from approved proposals
module TextDAO.Functions.Text.Text

import TextDAO.Storages.Schema

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

%foreign "evm:log2"
prim__log2 : Integer -> Integer -> Integer -> Integer -> PrimIO ()

caller : IO Integer
caller = primIO prim__caller

evmRevert : Integer -> Integer -> IO ()
evmRevert off len = primIO (prim__revert off len)

calldataload : Integer -> IO Integer
calldataload off = primIO (prim__calldataload off)

evmReturn : Integer -> Integer -> IO ()
evmReturn off len = primIO (prim__return off len)

evmLog2 : Integer -> Integer -> Integer -> Integer -> IO ()
evmLog2 off len topic1 topic2 = primIO (prim__log2 off len topic1 topic2)

-- =============================================================================
-- Function Selectors
-- =============================================================================

||| createText(uint256,bytes32) -> 0xc0123456
SEL_CREATE_TEXT : Integer
SEL_CREATE_TEXT = 0xc0123456

||| getText(uint256) -> 0xc1234567
SEL_GET_TEXT : Integer
SEL_GET_TEXT = 0xc1234567

||| getTextCount() -> 0xc2345678
SEL_GET_TEXT_COUNT : Integer
SEL_GET_TEXT_COUNT = 0xc2345678

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
-- Create Text Function
-- =============================================================================

||| Check if proposal is approved
isProposalApproved : ProposalId -> IO Bool
isProposalApproved pid = do
  approvedHeader <- getApprovedHeaderId pid
  pure (approvedHeader > 0)

||| Create text from approved proposal
||| REQ_TEXT_001: Create text after proposal is approved
export
createText : ProposalId -> MetadataCid -> IO Integer
createText pid metadataCid = do
  -- Check proposal is approved
  approved <- isProposalApproved pid
  if not approved
    then do
      evmRevert 0 0  -- ProposalNotApproved
      pure 0
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
      evmLog2 0 32 EVENT_TEXT_CREATED pid

      pure textId

-- =============================================================================
-- Main Entry Point
-- =============================================================================

||| Main entry point for Text contract
export
main : IO ()
main = do
  selector <- getSelector

  if selector == SEL_CREATE_TEXT
    then do
      pid <- calldataload 4
      metadataCid <- calldataload 36
      textId <- createText pid metadataCid
      returnUint textId

    else if selector == SEL_GET_TEXT
    then do
      textId <- calldataload 4
      metadata <- getTextMetadata textId
      returnUint metadata

    else if selector == SEL_GET_TEXT_COUNT
    then do
      count <- getTextCount
      returnUint count

    else evmRevert 0 0
