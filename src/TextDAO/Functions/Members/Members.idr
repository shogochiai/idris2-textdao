||| TextDAO Members Function
||| REQ_MEMBERS_001: Member registration and lookup
module TextDAO.Functions.Members.Members

import public Subcontract.Core.Entry
import Subcontract.Core.ABI.Decoder
import public Subcontract.Core.Outcome
import public TextDAO.Storages.Schema

-- Note: EVM primitives now come from TextDAO.Storages.Schema via Subcontract.Core.Storable

%default covering

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
-- Function Signatures
-- =============================================================================

||| addMember(address,bytes32) -> uint256
public export
addMemberSig : Sig
addMemberSig = MkSig "addMember" [TAddress, TBytes32] [TUint256]

public export
addMemberSel : Sel addMemberSig
addMemberSel = MkSel 0xca6d56dc

||| getMember(uint256) -> address
public export
getMemberSig : Sig
getMemberSig = MkSig "getMember" [TUint256] [TAddress]

public export
getMemberSel : Sel getMemberSig
getMemberSel = MkSel 0x9c0a0cd2

||| getMemberCount() -> uint256
public export
getMemberCountSig : Sig
getMemberCountSig = MkSig "getMemberCount" [] [TUint256]

public export
getMemberCountSel : Sel getMemberCountSig
getMemberCountSel = MkSel 0x997072f7

||| isMember(address) -> bool
public export
isMemberSig : Sig
isMemberSig = MkSig "isMember" [TAddress] [TBool]

public export
isMemberSel : Sel isMemberSig
isMemberSel = MkSel 0xa230c524

-- =============================================================================
-- Member Read Functions (Core Logic)
-- =============================================================================

||| Get member address by index
||| REQ_MEMBERS_002
export
getMemberAddr : Integer -> IO EvmAddr
getMemberAddr index = do
  slot <- getMemberSlot index
  sload (slot + MEMBER_OFFSET_ADDR)

||| Get member metadata by index
export
getMemberMetadata : Integer -> IO MetadataCid
getMemberMetadata index = do
  slot <- getMemberSlot index
  sload (slot + MEMBER_OFFSET_METADATA)

mutual
  ||| Check if address is a member (linear search)
  ||| REQ_MEMBERS_003
  export
  isMember : EvmAddr -> IO Bool
  isMember addr = do
    count <- getMemberCount
    checkMemberLoop addr 0 count

  ||| Helper function for member lookup loop
  checkMemberLoop : EvmAddr -> Integer -> Integer -> IO Bool
  checkMemberLoop target idx count =
    if idx >= count
      then pure False
      else getMemberAddr idx >>= \memberAddr =>
        if memberAddr == target
          then pure True
          else checkMemberLoop target (idx + 1) count

-- =============================================================================
-- Member Write Functions (Core Logic)
-- =============================================================================

||| Add a new member
||| REQ_MEMBERS_004
export
addMember : EvmAddr -> MetadataCid -> IO Integer
addMember addr metadata = do
  count <- getMemberCount
  slot <- getMemberSlot count
  sstore (slot + MEMBER_OFFSET_ADDR) addr
  sstore (slot + MEMBER_OFFSET_METADATA) metadata
  setMemberCount (count + 1)
  pure count

-- =============================================================================
-- Access Control Modifier
-- =============================================================================

||| Revert if caller is not a member
||| REQ_MEMBERS_005
export
requireMember : EvmAddr -> IO (Outcome ())
requireMember callerAddr = do
  member <- isMember callerAddr
  if member
    then pure (Ok ())
    else pure (Fail AuthViolation (tagEvidence "YouAreNotTheMember"))

-- =============================================================================
-- Entry Points
-- =============================================================================

||| Entry: addMember(address,bytes32) -> uint256
export
addMemberEntry : Entry addMemberSig
addMemberEntry = MkEntry addMemberSel $ do
  addr <- runDecoder decodeAddress
  meta <- runDecoder decodeBytes32
  idx <- addMember (addrValue addr) (bytes32Value meta)
  returnUint idx

||| Entry: getMember(uint256) -> address
export
getMemberEntry : Entry getMemberSig
getMemberEntry = MkEntry getMemberSel $ do
  index <- runDecoder decodeUint256
  addr <- getMemberAddr (uint256Value index)
  returnUint addr

||| Entry: getMemberCount() -> uint256
export
getMemberCountEntry : Entry getMemberCountSig
getMemberCountEntry = MkEntry getMemberCountSel $ do
  count <- getMemberCount
  returnUint count

||| Entry: isMember(address) -> bool
export
isMemberEntry : Entry isMemberSig
isMemberEntry = MkEntry isMemberSel $ do
  addr <- runDecoder decodeAddress
  member <- isMember (addrValue addr)
  returnBool member
