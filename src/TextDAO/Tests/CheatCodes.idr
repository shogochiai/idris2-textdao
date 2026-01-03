||| TextDAO Cheat Codes
||| Foundry-compatible EVM state manipulation for testing
|||
||| Required for testing uncovered functions:
||| - Members: isMember, addMember, checkMemberLoop
||| - Vote: vote, isRep, isProposalExpired
||| - Propose: propose, createProposal
||| - Schema: sload, sstore, setSnapInterval
module TextDAO.Tests.CheatCodes

import TextDAO.Storages.Schema

%default covering

-- =============================================================================
-- Cheat Code Interface
-- =============================================================================

||| Foundry VM address (magic address for cheat codes)
||| 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
public export
VM_ADDRESS : Integer
VM_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D

-- =============================================================================
-- Caller Manipulation (prank, startPrank, stopPrank)
-- =============================================================================

||| Set msg.sender for the next call only
||| Usage: Test addMember, propose (onlyMember modifier)
public export
record PrankState where
  constructor MkPrankState
  prankedAddress : Maybe Address
  isPersistent : Bool

||| Initialize prank state
export
initPrankState : PrankState
initPrankState = MkPrankState Nothing False

||| Prank: set msg.sender for next call
||| vm.prank(address) in Foundry
export
prank : Address -> PrankState -> PrankState
prank addr st = { prankedAddress := Just addr, isPersistent := False } st

||| StartPrank: set msg.sender until stopPrank
||| vm.startPrank(address) in Foundry
export
startPrank : Address -> PrankState -> PrankState
startPrank addr st = { prankedAddress := Just addr, isPersistent := True } st

||| StopPrank: clear persistent prank
export
stopPrank : PrankState -> PrankState
stopPrank st = { prankedAddress := Nothing, isPersistent := False } st

||| Get effective caller (pranked or real)
export
getEffectiveCaller : PrankState -> Address -> Address
getEffectiveCaller st realCaller =
  case st.prankedAddress of
    Nothing => realCaller
    Just pranked => pranked

-- =============================================================================
-- Balance Manipulation (deal, hoax)
-- =============================================================================

||| Deal: set ETH balance for address
||| vm.deal(address, amount) in Foundry
||| Storage slot: keccak256(addr) in balance mapping (simplified)
export
deal : Address -> Integer -> IO ()
deal addr amount = do
  -- In real EVM, balance is in state trie, not storage
  -- For testing, we simulate by storing in a reserved slot
  let balanceSlot = 0xBALA  -- Reserved slot for test balances
  mstore 0 addr
  mstore 32 balanceSlot
  slot <- keccak256 0 64
  sstore slot amount

||| Hoax: deal + prank combined
||| vm.hoax(address, amount) in Foundry
export
hoax : Address -> Integer -> PrankState -> IO PrankState
hoax addr amount st = do
  deal addr amount
  pure (prank addr st)

-- =============================================================================
-- Time Manipulation (warp, roll, skip)
-- =============================================================================

||| Block context for time manipulation
public export
record BlockContext where
  constructor MkBlockContext
  mockTimestamp : Maybe Integer
  mockBlockNumber : Maybe Integer

||| Initialize block context
export
initBlockContext : BlockContext
initBlockContext = MkBlockContext Nothing Nothing

||| Warp: set block.timestamp
||| vm.warp(timestamp) in Foundry
||| Usage: Test isProposalExpired, vote expiration checks
export
warp : Integer -> BlockContext -> BlockContext
warp ts ctx = { mockTimestamp := Just ts } ctx

||| Roll: set block.number
||| vm.roll(blockNumber) in Foundry
export
roll : Integer -> BlockContext -> BlockContext
roll bn ctx = { mockBlockNumber := Just bn } ctx

||| Skip: advance time by duration
||| vm.skip(duration) in Foundry
export
skip : Integer -> BlockContext -> BlockContext
skip duration ctx =
  let current = fromMaybe 0 ctx.mockTimestamp
  in { mockTimestamp := Just (current + duration) } ctx
  where
    fromMaybe : a -> Maybe a -> a
    fromMaybe def Nothing = def
    fromMaybe _ (Just x) = x

||| Get effective timestamp
export
getEffectiveTimestamp : BlockContext -> Integer -> Integer
getEffectiveTimestamp ctx realTs =
  case ctx.mockTimestamp of
    Nothing => realTs
    Just mock => mock

-- =============================================================================
-- Storage Manipulation (store, load)
-- =============================================================================

||| Store: write directly to storage slot
||| vm.store(address, slot, value) in Foundry
||| Usage: Setup member storage, proposal meta, config
export
store : Integer -> Integer -> IO ()
store slot value = sstore slot value

||| Load: read directly from storage slot
||| vm.load(address, slot) in Foundry
export
load : Integer -> IO Integer
load slot = sload slot

-- =============================================================================
-- State Snapshots (snapshot, revertTo)
-- =============================================================================

||| Snapshot ID counter (stored in reserved slot)
SNAPSHOT_COUNTER_SLOT : Integer
SNAPSHOT_COUNTER_SLOT = 0x5AAAA

||| Snapshot: save current state
||| vm.snapshot() in Foundry
||| Returns snapshot ID
export
snapshot : IO Integer
snapshot = do
  counter <- sload SNAPSHOT_COUNTER_SLOT
  let newId = counter + 1
  sstore SNAPSHOT_COUNTER_SLOT newId
  -- In real impl, would save full state tree
  -- For now, just return ID
  pure newId

||| RevertTo: restore state to snapshot
||| vm.revertTo(snapshotId) in Foundry
export
revertTo : Integer -> IO Bool
revertTo snapshotId = do
  counter <- sload SNAPSHOT_COUNTER_SLOT
  if snapshotId <= counter
    then do
      -- In real impl, would restore full state tree
      pure True
    else pure False

-- =============================================================================
-- Expectation Helpers (expectRevert, expectEmit)
-- =============================================================================

||| Expect state for revert checking
public export
record ExpectState where
  constructor MkExpectState
  expectingRevert : Bool
  expectedSelector : Maybe Integer
  lastReverted : Bool

||| Initialize expect state
export
initExpectState : ExpectState
initExpectState = MkExpectState False Nothing False

||| ExpectRevert: expect next call to revert
||| vm.expectRevert() in Foundry
export
expectRevert : ExpectState -> ExpectState
expectRevert st = { expectingRevert := True, expectedSelector := Nothing } st

||| ExpectRevert with selector: expect specific revert reason
||| vm.expectRevert(selector) in Foundry
export
expectRevertSelector : Integer -> ExpectState -> ExpectState
expectRevertSelector sel st = { expectingRevert := True, expectedSelector := Just sel } st

||| Record that a revert occurred
export
recordRevert : ExpectState -> ExpectState
recordRevert st = { lastReverted := True } st

||| Check if revert expectation was met
export
checkRevertExpectation : ExpectState -> Bool
checkRevertExpectation st =
  if st.expectingRevert then st.lastReverted else True

-- =============================================================================
-- TextDAO-Specific Test Setup Helpers
-- =============================================================================

||| Setup a member in storage (for testing isMember, checkMemberLoop)
||| Sets: memberCount, member[index].addr, member[index].metadata
export
setupMember : Integer -> Address -> MetadataCid -> IO ()
setupMember index addr metadata = do
  -- Get current count and increment
  count <- sload SLOT_MEMBER_COUNT
  let newCount = max count (index + 1)
  sstore SLOT_MEMBER_COUNT newCount

  -- Calculate member slot
  slot <- getMemberSlot index
  sstore slot addr           -- MEMBER_OFFSET_ADDR = 0
  sstore (slot + 1) metadata -- MEMBER_OFFSET_METADATA = 1
  where
    max : Integer -> Integer -> Integer
    max a b = if a > b then a else b

||| Setup multiple members
export
setupMembers : List (Address, MetadataCid) -> IO ()
setupMembers members = go 0 members
  where
    go : Integer -> List (Address, MetadataCid) -> IO ()
    go _ [] = pure ()
    go idx ((addr, meta) :: rest) = do
      setupMember idx addr meta
      go (idx + 1) rest

||| Setup proposal meta (for testing vote, isRep)
export
setupProposalMeta : ProposalId -> Integer -> Integer -> Integer -> IO ()
setupProposalMeta pid createdAt expiration snapInterval = do
  metaSlot <- getProposalMetaSlot pid
  sstore (metaSlot + META_OFFSET_CREATED_AT) createdAt
  sstore (metaSlot + META_OFFSET_EXPIRATION) expiration
  sstore (metaSlot + META_OFFSET_SNAP_INTERVAL) snapInterval
  sstore (metaSlot + META_OFFSET_HEADER_COUNT) 0
  sstore (metaSlot + META_OFFSET_CMD_COUNT) 0
  sstore (metaSlot + META_OFFSET_APPROVED_HEADER) 0
  sstore (metaSlot + META_OFFSET_APPROVED_CMD) 0
  sstore (metaSlot + META_OFFSET_EXECUTED) 0

||| Setup representative for proposal (for testing vote, isRep)
export
setupRep : ProposalId -> Integer -> Address -> IO ()
setupRep pid index addr = do
  metaSlot <- getProposalMetaSlot pid
  let repsCountSlot = metaSlot + 0x40

  -- Update rep count
  count <- sload repsCountSlot
  let newCount = max count (index + 1)
  sstore repsCountSlot newCount

  -- Store rep address
  mstore 0 index
  mstore 32 (metaSlot + 0x40)
  repSlot <- keccak256 0 64
  sstore repSlot addr
  where
    max : Integer -> Integer -> Integer
    max a b = if a > b then a else b

||| Setup deliberation config (for testing propose, vote)
export
setupConfig : Integer -> Integer -> Integer -> Integer -> IO ()
setupConfig expiryDuration snapInterval repsNum quorumScore = do
  sstore SLOT_CONFIG_EXPIRY_DURATION expiryDuration
  sstore SLOT_CONFIG_SNAP_INTERVAL snapInterval
  sstore SLOT_CONFIG_REPS_NUM repsNum
  sstore SLOT_CONFIG_QUORUM_SCORE quorumScore

-- =============================================================================
-- Combined VM State
-- =============================================================================

||| Full VM cheat code state
public export
record VMState where
  constructor MkVMState
  prankSt : PrankState
  blockCtx : BlockContext
  expectSt : ExpectState

||| Initialize full VM state
export
initVMState : VMState
initVMState = MkVMState initPrankState initBlockContext initExpectState

-- =============================================================================
-- Cheat Code Selectors (Foundry-compatible function selectors)
-- =============================================================================

||| vm.prank(address) selector
SEL_PRANK : Integer
SEL_PRANK = 0xca669fa7

||| vm.startPrank(address) selector
SEL_START_PRANK : Integer
SEL_START_PRANK = 0x06447d56

||| vm.stopPrank() selector
SEL_STOP_PRANK : Integer
SEL_STOP_PRANK = 0x90c5013b

||| vm.deal(address,uint256) selector
SEL_DEAL : Integer
SEL_DEAL = 0xc88a5e6d

||| vm.warp(uint256) selector
SEL_WARP : Integer
SEL_WARP = 0xe5d6bf02

||| vm.roll(uint256) selector
SEL_ROLL : Integer
SEL_ROLL = 0x1f7b4f30

||| vm.store(address,bytes32,bytes32) selector
SEL_STORE : Integer
SEL_STORE = 0x70ca10bb

||| vm.load(address,bytes32) selector
SEL_LOAD : Integer
SEL_LOAD = 0x667f9d70

||| vm.expectRevert() selector
SEL_EXPECT_REVERT : Integer
SEL_EXPECT_REVERT = 0xf4844814

||| vm.snapshot() selector
SEL_SNAPSHOT : Integer
SEL_SNAPSHOT = 0x9711715a

||| vm.revertTo(uint256) selector
SEL_REVERT_TO : Integer
SEL_REVERT_TO = 0x44d7f0a4
