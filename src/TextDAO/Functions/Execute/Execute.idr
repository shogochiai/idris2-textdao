||| TextDAO Execute Function
||| REQ_EXECUTE_001: Execute approved proposals
module TextDAO.Functions.Execute.Execute

import TextDAO.Storages.Schema
import TextDAO.Functions.Fork.Fork

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

%foreign "evm:call"
prim__call : Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> PrimIO Integer

%foreign "evm:log1"
prim__log1 : Integer -> Integer -> Integer -> PrimIO ()

caller : IO Integer
caller = primIO prim__caller

evmRevert : Integer -> Integer -> IO ()
evmRevert off len = primIO (prim__revert off len)

calldataload : Integer -> IO Integer
calldataload off = primIO (prim__calldataload off)

evmReturn : Integer -> Integer -> IO ()
evmReturn off len = primIO (prim__return off len)

evmCall : Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> IO Integer
evmCall gas addr value argsOffset argsSize retOffset retSize =
  primIO (prim__call gas addr value argsOffset argsSize retOffset retSize)

evmLog1 : Integer -> Integer -> Integer -> IO ()
evmLog1 off len topic = primIO (prim__log1 off len topic)

-- =============================================================================
-- Function Selectors
-- =============================================================================

||| execute(uint256) -> 0xe0123456
SEL_EXECUTE : Integer
SEL_EXECUTE = 0xe0123456

||| isExecuted(uint256) -> 0xe1234567
SEL_IS_EXECUTED : Integer
SEL_IS_EXECUTED = 0xe1234567

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
-- Event Topics
-- =============================================================================

||| ProposalExecuted(uint256 pid) event signature
EVENT_PROPOSAL_EXECUTED : Integer
EVENT_PROPOSAL_EXECUTED = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef

-- =============================================================================
-- Execute Functions
-- =============================================================================

||| Check if proposal has been approved
export
isProposalApproved : ProposalId -> IO Bool
isProposalApproved pid = do
  approvedHeader <- getApprovedHeaderId pid
  pure (approvedHeader > 0)

||| Execute the approved command
||| REQ_EXECUTE_001: Execute approved proposals
export
execute : ProposalId -> IO Bool
execute pid = do
  -- Check if proposal is approved
  approved <- isProposalApproved pid
  if not approved
    then do
      evmRevert 0 0  -- ProposalNotApproved
      pure False
    else do
      -- Check if already executed
      executed <- isFullyExecuted pid
      if executed
        then do
          evmRevert 0 0  -- ProposalAlreadyExecuted
          pure False
        else do
          -- Get approved command
          approvedCmdId <- getApprovedCmdId pid
          actionData <- getCommandActionData pid approvedCmdId

          -- Execute the action (simplified: just mark as executed)
          -- In real implementation, would decode and execute action
          -- For now, we just mark the proposal as executed
          setFullyExecuted pid True

          -- Emit ProposalExecuted event
          mstore 0 pid
          evmLog1 0 32 EVENT_PROPOSAL_EXECUTED

          pure True

||| Execute action by calling target contract
||| Note: Simplified version - real implementation would parse action struct
export
executeAction : Integer -> Integer -> Integer -> IO Bool
executeAction target value callData = do
  -- Store calldata in memory
  mstore 0 callData

  -- Call target contract
  result <- evmCall 100000 target value 0 32 32 32

  pure (result == 1)

-- =============================================================================
-- Main Entry Point
-- =============================================================================

||| Main entry point for Execute contract
export
main : IO ()
main = do
  selector <- getSelector

  if selector == SEL_EXECUTE
    then do
      pid <- calldataload 4
      success <- execute pid
      returnBool success

    else if selector == SEL_IS_EXECUTED
    then do
      pid <- calldataload 4
      executed <- isFullyExecuted pid
      returnBool executed

    else evmRevert 0 0
