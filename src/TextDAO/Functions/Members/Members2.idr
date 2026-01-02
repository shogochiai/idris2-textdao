||| TextDAO Members Function (Refactored with StorageCap)
|||
||| REQ_MEMBERS_001: Member registration and lookup
|||
||| This version uses StorageCap to enforce "DO NOT USE STORAGE DIRECTLY"
||| at the type level. All storage access is visible in function signatures:
||| - Functions taking StorageCap can access storage
||| - Functions without it cannot (enforced by module boundary)
|||
module TextDAO.Functions.Members.Members2

import TextDAO.Storages.Schema
import Subcontract.Core.Entry
import Subcontract.Core.StorageCap

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
-- Member Read Functions (Require StorageCap)
-- =============================================================================

||| Get member address by index
||| REQ_MEMBERS_002
||| NOTE: Takes StorageCap - this function accesses storage
export
getMemberAddr : StorageCap -> Integer -> IO Integer
getMemberAddr cap index = do
  slot <- getMemberSlotCap (mstoreCap cap) (keccak256Cap cap) index
  sloadCap cap (slot + MEMBER_OFFSET_ADDR)

||| Get member metadata by index
||| NOTE: Takes StorageCap - this function accesses storage
export
getMemberMetadata : StorageCap -> Integer -> IO Integer
getMemberMetadata cap index = do
  slot <- getMemberSlotCap (mstoreCap cap) (keccak256Cap cap) index
  sloadCap cap (slot + MEMBER_OFFSET_METADATA)

mutual
  ||| Check if address is a member (linear search)
  ||| REQ_MEMBERS_003
  ||| NOTE: Takes StorageCap - this function accesses storage
  export
  isMemberImpl : StorageCap -> Integer -> IO Bool
  isMemberImpl cap addr = do
    count <- getMemberCountCap (sloadCap cap)
    checkMemberLoop cap addr 0 count

  ||| Helper function for member lookup loop
  checkMemberLoop : StorageCap -> Integer -> Integer -> Integer -> IO Bool
  checkMemberLoop cap target idx count =
    if idx >= count
      then pure False
      else getMemberAddr cap idx >>= \memberAddr =>
        if memberAddr == target
          then pure True
          else checkMemberLoop cap target (idx + 1) count

-- =============================================================================
-- Member Write Functions (Require StorageCap)
-- =============================================================================

||| Add a new member
||| REQ_MEMBERS_004
||| NOTE: Takes StorageCap - this function accesses storage
export
addMemberImpl : StorageCap -> Integer -> Integer -> IO Integer
addMemberImpl cap addr metadata = do
  count <- getMemberCountCap (sloadCap cap)
  slot <- getMemberSlotCap (mstoreCap cap) (keccak256Cap cap) count
  sstoreCap cap (slot + MEMBER_OFFSET_ADDR) addr
  sstoreCap cap (slot + MEMBER_OFFSET_METADATA) metadata
  setMemberCountCap (sstoreCap cap) (count + 1)
  pure count

-- =============================================================================
-- Handlers (Receive StorageCap from Framework)
-- =============================================================================

||| addMember handler: Decodes (address, bytes32), returns uint256
||| Handler type ensures storage access is explicit
addMemberHandler : Handler ()
addMemberHandler cap = do
  -- Type-safe decoding: no manual offset calculation
  (addr, meta) <- runDecoder $ do
    a <- decodeAddress
    m <- decodeBytes32
    pure (a, m)
  idx <- addMemberImpl cap (addrValue addr) (bytes32Value meta)
  returnUint idx

||| getMember handler: Decodes uint256, returns address
getMemberHandler : Handler ()
getMemberHandler cap = do
  idx <- runDecoder decodeUint256
  addr <- getMemberAddr cap (uint256Value idx)
  returnUint addr

||| getMemberCount handler: No params, returns uint256
getMemberCountHandler : Handler ()
getMemberCountHandler cap = do
  count <- getMemberCountCap (sloadCap cap)
  returnUint count

||| isMember handler: Decodes address, returns bool
isMemberHandler : Handler ()
isMemberHandler cap = do
  addr <- runDecoder decodeAddress
  member <- isMemberImpl cap (addrValue addr)
  returnBool member

-- =============================================================================
-- Entry Points (Type-Safe, Using runHandler)
-- =============================================================================

||| addMember entry: wraps handler with selector binding
addMemberEntry : Entry Members2.addMemberSig
addMemberEntry = MkEntry addMemberSel (runHandler addMemberHandler)

||| getMember entry: wraps handler with selector binding
getMemberEntry : Entry Members2.getMemberSig
getMemberEntry = MkEntry getMemberSel (runHandler getMemberHandler)

||| getMemberCount entry: wraps handler with selector binding
getMemberCountEntry : Entry Members2.getMemberCountSig
getMemberCountEntry = MkEntry getMemberCountSel (runHandler getMemberCountHandler)

||| isMember entry: wraps handler with selector binding
isMemberEntry : Entry Members2.isMemberSig
isMemberEntry = MkEntry isMemberSel (runHandler isMemberHandler)

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
