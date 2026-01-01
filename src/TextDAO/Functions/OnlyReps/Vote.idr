||| TextDAO Vote Function
||| REQ_VOTE_001: Representatives can vote on proposals using RCV
module TextDAO.Functions.OnlyReps.Vote

import TextDAO.Storages.Schema

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

timestamp : IO Integer
timestamp = primIO prim__timestamp

caller : IO Integer
caller = primIO prim__caller

evmRevert : Integer -> Integer -> IO ()
evmRevert off len = primIO (prim__revert off len)

%foreign "evm:calldataload"
prim__calldataload : Integer -> PrimIO Integer

%foreign "evm:return"
prim__return : Integer -> Integer -> PrimIO ()

calldataload : Integer -> IO Integer
calldataload off = primIO (prim__calldataload off)

evmReturn : Integer -> Integer -> IO ()
evmReturn off len = primIO (prim__return off len)

-- =============================================================================
-- Function Selectors
-- =============================================================================

||| vote(uint256,uint256[3],uint256[3]) -> 0x34567890
SEL_VOTE : Integer
SEL_VOTE = 0x34567890

||| isRep(uint256,address) -> 0x56789012
SEL_IS_REP : Integer
SEL_IS_REP = 0x56789012

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

||| Return a boolean value
returnBool : Bool -> IO ()
returnBool b = returnUint (if b then 1 else 0)

-- =============================================================================
-- Vote Storage Layout
-- =============================================================================

||| Vote struct offsets (6 slots total)
||| rankedHeaderIds[3] at offsets 0, 1, 2
||| rankedCommandIds[3] at offsets 3, 4, 5
VOTE_OFFSET_HEADER_0 : Integer
VOTE_OFFSET_HEADER_0 = 0

VOTE_OFFSET_HEADER_1 : Integer
VOTE_OFFSET_HEADER_1 = 1

VOTE_OFFSET_HEADER_2 : Integer
VOTE_OFFSET_HEADER_2 = 2

VOTE_OFFSET_CMD_0 : Integer
VOTE_OFFSET_CMD_0 = 3

VOTE_OFFSET_CMD_1 : Integer
VOTE_OFFSET_CMD_1 = 4

VOTE_OFFSET_CMD_2 : Integer
VOTE_OFFSET_CMD_2 = 5

-- =============================================================================
-- Representative Storage
-- =============================================================================

||| Get representative slot by index
||| Reps are stored in proposal meta at offset 0x40
export
getRepSlot : ProposalId -> Integer -> IO Integer
getRepSlot pid index = do
  metaSlot <- getProposalMetaSlot pid
  let repsBaseSlot = metaSlot + 0x40
  mstore 0 index
  mstore 32 repsBaseSlot
  keccak256 0 64

||| Get representative count
export
getRepCount : ProposalId -> IO Integer
getRepCount pid = do
  metaSlot <- getProposalMetaSlot pid
  sload (metaSlot + 0x40)

||| Set representative count
export
setRepCount : ProposalId -> Integer -> IO ()
setRepCount pid count = do
  metaSlot <- getProposalMetaSlot pid
  sstore (metaSlot + 0x40) count

||| Get representative address by index
export
getRepAddr : ProposalId -> Integer -> IO Address
getRepAddr pid index = do
  slot <- getRepSlot pid index
  sload slot

||| Add representative to proposal
export
addRep : ProposalId -> Address -> IO ()
addRep pid addr = do
  count <- getRepCount pid
  slot <- getRepSlot pid count
  sstore slot addr
  setRepCount pid (count + 1)

||| Check if address is a representative for proposal
||| REQ_VOTE_002
export
isRep : ProposalId -> Address -> IO Bool
isRep pid addr = do
  count <- getRepCount pid
  checkRep addr 0 count
  where
    checkRep : Address -> Integer -> Integer -> IO Bool
    checkRep target idx cnt =
      if idx >= cnt
        then pure False
        else do
          repAddr <- getRepAddr pid idx
          if repAddr == target
            then pure True
            else checkRep target (idx + 1) cnt

-- =============================================================================
-- Vote Storage
-- =============================================================================

||| Store a vote
||| REQ_VOTE_003
export
storeVote : ProposalId -> Address -> (Integer, Integer, Integer) -> (Integer, Integer, Integer) -> IO ()
storeVote pid voter (h0, h1, h2) (c0, c1, c2) = do
  slot <- getVoteSlot pid voter
  sstore (slot + VOTE_OFFSET_HEADER_0) h0
  sstore (slot + VOTE_OFFSET_HEADER_1) h1
  sstore (slot + VOTE_OFFSET_HEADER_2) h2
  sstore (slot + VOTE_OFFSET_CMD_0) c0
  sstore (slot + VOTE_OFFSET_CMD_1) c1
  sstore (slot + VOTE_OFFSET_CMD_2) c2

||| Read a vote
export
readVote : ProposalId -> Address -> IO ((Integer, Integer, Integer), (Integer, Integer, Integer))
readVote pid voter = do
  slot <- getVoteSlot pid voter
  h0 <- sload (slot + VOTE_OFFSET_HEADER_0)
  h1 <- sload (slot + VOTE_OFFSET_HEADER_1)
  h2 <- sload (slot + VOTE_OFFSET_HEADER_2)
  c0 <- sload (slot + VOTE_OFFSET_CMD_0)
  c1 <- sload (slot + VOTE_OFFSET_CMD_1)
  c2 <- sload (slot + VOTE_OFFSET_CMD_2)
  pure ((h0, h1, h2), (c0, c1, c2))

-- =============================================================================
-- Vote Validation
-- =============================================================================

||| Check if proposal is expired
||| REQ_VOTE_004
export
isProposalExpired : ProposalId -> IO Bool
isProposalExpired pid = do
  expiration <- getProposalExpiration pid
  now <- timestamp
  pure (now >= expiration)

||| Validate header ID is within bounds
export
validateHeaderId : ProposalId -> HeaderId -> IO Bool
validateHeaderId pid hid = do
  headerCount <- getProposalHeaderCount pid
  pure (hid >= 0 && hid <= headerCount)

||| Validate command ID is within bounds
export
validateCommandId : ProposalId -> CommandId -> IO Bool
validateCommandId pid cid = do
  cmdCount <- getProposalCmdCount pid
  pure (cid >= 0 && cid <= cmdCount)

-- =============================================================================
-- Entry Point
-- =============================================================================

||| Vote on a proposal (RCV: Ranked Choice Voting)
||| REQ_VOTE_001: Representatives can cast ranked votes
export
vote : ProposalId -> (Integer, Integer, Integer) -> (Integer, Integer, Integer) -> IO Bool
vote pid rankedHeaders rankedCommands = do
  -- Access control: onlyReps
  callerAddr <- caller
  rep <- isRep pid callerAddr

  if not rep
    then do
      -- Revert: YouAreNotTheRep
      evmRevert 0 0
      pure False
    else do
      -- Check proposal not expired
      expired <- isProposalExpired pid
      if expired
        then do
          -- Revert: ProposalAlreadyExpired
          evmRevert 0 0
          pure False
        else do
          -- Validate header IDs
          let (h0, h1, h2) = rankedHeaders
          validH0 <- validateHeaderId pid h0
          validH1 <- validateHeaderId pid h1
          validH2 <- validateHeaderId pid h2

          -- Validate command IDs
          let (c0, c1, c2) = rankedCommands
          validC0 <- validateCommandId pid c0
          validC1 <- validateCommandId pid c1
          validC2 <- validateCommandId pid c2

          if not (validH0 && validH1 && validH2 && validC0 && validC1 && validC2)
            then do
              -- Revert: InvalidId
              evmRevert 0 0
              pure False
            else do
              -- Store vote
              storeVote pid callerAddr rankedHeaders rankedCommands
              pure True

-- =============================================================================
-- Main Entry Point
-- =============================================================================

||| Main entry point for Vote contract
export
main : IO ()
main = do
  selector <- getSelector

  if selector == SEL_VOTE
    then do
      pid <- calldataload 4
      h0 <- calldataload 36
      h1 <- calldataload 68
      h2 <- calldataload 100
      c0 <- calldataload 132
      c1 <- calldataload 164
      c2 <- calldataload 196
      success <- vote pid (h0, h1, h2) (c0, c1, c2)
      returnBool success

    else if selector == SEL_IS_REP
    then do
      pid <- calldataload 4
      addr <- calldataload 36
      rep <- isRep pid addr
      returnBool rep

    else evmRevert 0 0
