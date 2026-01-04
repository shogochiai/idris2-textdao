||| TextDAO Execute Function
||| REQ_EXECUTE_001: Execute approved proposals
module TextDAO.Functions.Execute.Execute

import public Subcontract.Core.Entry
import Subcontract.Core.ABI.Decoder
import public Subcontract.Core.Outcome
import TextDAO.Storages.Schema
import TextDAO.Functions.Fork.Fork
import public TextDAO.Security.AccessControl
import public TextDAO.Security.Reentrancy

-- Note: EVM primitives now come from TextDAO.Storages.Schema via Subcontract.Core.Storable

%default covering

-- =============================================================================
-- Function Signatures
-- =============================================================================

||| execute(uint256) -> bool
public export
executeSig : Sig
executeSig = MkSig "execute" [TUint256] [TBool]

public export
executeSel : Sel executeSig
executeSel = MkSel 0xe0123456

||| isExecuted(uint256) -> bool
public export
isExecutedSig : Sig
isExecutedSig = MkSig "isExecuted" [TUint256] [TBool]

public export
isExecutedSel : Sel isExecutedSig
isExecutedSel = MkSel 0xe1234567

-- =============================================================================
-- Event Topics
-- =============================================================================

||| ProposalExecuted(uint256 pid) event signature
EVENT_PROPOSAL_EXECUTED : Integer
EVENT_PROPOSAL_EXECUTED = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef

-- =============================================================================
-- Execute Core Logic
-- =============================================================================

||| Check if proposal has been approved
export
isProposalApproved : ProposalId -> IO Bool
isProposalApproved pid = do
  approvedHeader <- getApprovedHeaderId pid
  pure (approvedHeader > 0)

||| Execute with compile-time proofs and reentrancy protection
||| REQ_EXECUTE_001: Execute approved proposals
||| Type-safe version: requires proof of approval, not-executed, and lock
export
executeWithProof : ExecuteLock Locked
                -> IsApproved pid
                -> NotExecuted pid
                -> ProposalId
                -> IO Bool
executeWithProof _ _ _ pid = do
  -- Get approved command
  approvedCmdId <- getApprovedCmdId pid
  actionData <- getCommandActionData pid approvedCmdId

  -- Execute the action (simplified: just mark as executed)
  -- CEI pattern: Checks done via proofs, Effects before Interactions
  setFullyExecuted pid True

  -- Emit ProposalExecuted event
  mstore 0 pid
  log1 0 32 EVENT_PROPOSAL_EXECUTED

  -- External interaction would happen here (protected by lock)
  -- In real implementation, would decode and execute action

  pure True

||| Execute the approved command
||| REQ_EXECUTE_001: Execute approved proposals
||| Runtime checked version with reentrancy protection
export
execute : ProposalId -> IO (Outcome Bool)
execute pid = do
  -- Try to acquire reentrancy lock
  mlock <- tryGetUnlocked
  case mlock of
    Nothing => pure (Fail Reentrancy (tagEvidence "ReentrancyDetected"))
    Just unlocked => do
      -- Check if proposal is approved
      approvedResult <- requireApproved pid
      case approvedResult of
        Fail c e => pure (Fail c e)
        Ok approvedProof => do
          -- Check if already executed
          notExecResult <- requireNotExecuted pid
          case notExecResult of
            Fail c e => pure (Fail c e)
            Ok notExecProof => do
              -- Execute with lock held
              (success, _) <- withExecuteLock unlocked $ \locked => do
                executeWithProof locked approvedProof notExecProof pid
              pure (Ok success)

||| Execute action by calling target contract (with reentrancy protection)
||| Note: Simplified version - real implementation would parse action struct
||| The lock parameter ensures this can only be called when lock is held
export
executeAction : ExecuteLock Locked -> Integer -> Integer -> Integer -> IO Bool
executeAction _ target value callData = do
  -- Store calldata in memory
  mstore 0 callData

  -- Call target contract (safe: lock is held)
  result <- call 100000 target value 0 32 32 32

  pure (result == 1)

-- =============================================================================
-- Entry Points
-- =============================================================================

||| Entry: execute(uint256) -> bool
export
executeEntry : Entry executeSig
executeEntry = MkEntry executeSel $ do
  pid <- runDecoder decodeUint256
  result <- execute (uint256Value pid)
  case result of
    Ok success => returnBool success
    Fail _ _ => evmRevert 0 0

||| Entry: isExecuted(uint256) -> bool
export
isExecutedEntry : Entry isExecutedSig
isExecutedEntry = MkEntry isExecutedSel $ do
  pid <- runDecoder decodeUint256
  executed <- isFullyExecuted (uint256Value pid)
  returnBool executed
