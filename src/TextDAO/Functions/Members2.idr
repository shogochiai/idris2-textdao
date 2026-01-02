||| TextDAO Members Function (Refactored with Subcontract API)
|||
||| REQ_MEMBERS_001: Member registration and lookup
|||
||| This version uses the type-safe Subcontract API to eliminate:
||| - Manual calldataload offset calculations (4, 36, 68, ...)
||| - Hardcoded selector values without signature binding
||| - Boilerplate selector dispatch
|||
module TextDAO.Functions.Members2

import TextDAO.Storages.Schema
import Subcontract.Core.Entry

%default covering

-- =============================================================================
-- Function Signatures (Type-Level Documentation)
-- =============================================================================

||| addMember(address,bytes32) -> uint256
||| Registers a new member with their metadata CID
addMemberSig : Sig
addMemberSig = MkSig "addMember" [TAddress, TBytes32] [TUint256]

||| getMember(uint256) -> address
||| Returns member address by index
getMemberSig : Sig
getMemberSig = MkSig "getMember" [TUint256] [TAddress]

||| getMemberCount() -> uint256
||| Returns total number of members
getMemberCountSig : Sig
getMemberCountSig = MkSig "getMemberCount" [] [TUint256]

||| isMember(address) -> bool
||| Checks if address is a registered member
isMemberSig : Sig
isMemberSig = MkSig "isMember" [TAddress] [TBool]

-- =============================================================================
-- Selectors (Bound to Signatures)
-- =============================================================================

||| Selector for addMember: keccak256("addMember(address,bytes32)")[:4]
addMemberSel : Sel Members2.addMemberSig
addMemberSel = MkSel 0xca6d56dc

||| Selector for getMember: keccak256("getMember(uint256)")[:4]
getMemberSel : Sel Members2.getMemberSig
getMemberSel = MkSel 0x9c0a0cd2

||| Selector for getMemberCount: keccak256("getMemberCount()")[:4]
getMemberCountSel : Sel Members2.getMemberCountSig
getMemberCountSel = MkSel 0x997072f7

||| Selector for isMember: keccak256("isMember(address)")[:4]
isMemberSel : Sel Members2.isMemberSig
isMemberSel = MkSel 0xa230c524

-- =============================================================================
-- Member Storage Layout
-- =============================================================================

||| Offset for member address within member struct
MEMBER_OFFSET_ADDR : Integer
MEMBER_OFFSET_ADDR = 0

||| Offset for member metadata CID within member struct
MEMBER_OFFSET_METADATA : Integer
MEMBER_OFFSET_METADATA = 1

||| Member struct size (2 slots: addr + metadata)
MEMBER_SIZE : Integer
MEMBER_SIZE = 2

-- =============================================================================
-- Member Read Functions
-- =============================================================================

||| Get member address by index
||| REQ_MEMBERS_002
export
getMemberAddr : Integer -> IO Integer
getMemberAddr index = do
  slot <- getMemberSlot index
  sload (slot + MEMBER_OFFSET_ADDR)

||| Get member metadata by index
export
getMemberMetadata : Integer -> IO Integer
getMemberMetadata index = do
  slot <- getMemberSlot index
  sload (slot + MEMBER_OFFSET_METADATA)

mutual
  ||| Check if address is a member (linear search)
  ||| REQ_MEMBERS_003
  export
  isMemberImpl : Integer -> IO Bool
  isMemberImpl addr = do
    count <- getMemberCount
    checkMemberLoop addr 0 count

  ||| Helper function for member lookup loop
  checkMemberLoop : Integer -> Integer -> Integer -> IO Bool
  checkMemberLoop target idx count =
    if idx >= count
      then pure False
      else getMemberAddr idx >>= \memberAddr =>
        if memberAddr == target
          then pure True
          else checkMemberLoop target (idx + 1) count

-- =============================================================================
-- Member Write Functions
-- =============================================================================

||| Add a new member
||| REQ_MEMBERS_004
export
addMemberImpl : Integer -> Integer -> IO Integer
addMemberImpl addr metadata = do
  count <- getMemberCount
  slot <- getMemberSlot count
  sstore (slot + MEMBER_OFFSET_ADDR) addr
  sstore (slot + MEMBER_OFFSET_METADATA) metadata
  setMemberCount (count + 1)
  pure count

-- =============================================================================
-- Entry Points (Type-Safe)
-- =============================================================================

||| addMember entry: Decodes (address, bytes32), returns uint256
addMemberEntry : Entry Members2.addMemberSig
addMemberEntry = MkEntry addMemberSel $ do
  -- Type-safe decoding: no manual offset calculation
  (addr, meta) <- runDecoder $ do
    a <- decodeAddress
    m <- decodeBytes32
    pure (a, m)
  idx <- addMemberImpl (addrValue addr) (bytes32Value meta)
  returnUint idx

||| getMember entry: Decodes uint256, returns address
getMemberEntry : Entry Members2.getMemberSig
getMemberEntry = MkEntry getMemberSel $ do
  idx <- runDecoder decodeUint256
  addr <- getMemberAddr (uint256Value idx)
  returnUint addr

||| getMemberCount entry: No params, returns uint256
getMemberCountEntry : Entry Members2.getMemberCountSig
getMemberCountEntry = MkEntry getMemberCountSel $ do
  count <- getMemberCount
  returnUint count

||| isMember entry: Decodes address, returns bool
isMemberEntry : Entry Members2.isMemberSig
isMemberEntry = MkEntry isMemberSel $ do
  addr <- runDecoder decodeAddress
  member <- isMemberImpl (addrValue addr)
  returnBool member

-- =============================================================================
-- Main Entry Point (Using Dispatch)
-- =============================================================================

||| Main entry point for Members contract
||| Uses type-safe dispatch instead of manual if-else chain
export
main : IO ()
main = dispatch
  [ entry addMemberEntry
  , entry getMemberEntry
  , entry getMemberCountEntry
  , entry isMemberEntry
  ]
