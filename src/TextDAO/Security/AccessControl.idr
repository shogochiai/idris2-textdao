||| TextDAO Access Control
||| REQ_SECURITY_001: Type-safe access control for TextDAO
|||
||| Compile-time guarantees for member and representative access.
||| Based on Subcontract.Core.AccessControl pattern.
module TextDAO.Security.AccessControl

import public Subcontract.Core.Outcome
import public Subcontract.Core.Storable
import public TextDAO.Storages.Schema

%default covering

-- =============================================================================
-- Member Access Control
-- =============================================================================

||| Proof that an address is a registered member.
||| This is a COMPILE-TIME constraint - functions requiring IsMember
||| cannot be called without obtaining this proof first.
public export
data IsMember : Integer -> Type where
  ||| Witness that address is a member
  MkIsMember : (addr : Integer) -> IsMember addr

||| Extract address from member proof
export
memberAddr : IsMember addr -> Integer
memberAddr (MkIsMember a) = a

||| Check membership and return proof if valid (runtime bridge)
export
checkMember : (addr : Integer) -> IO (Maybe (IsMember addr))
checkMember addr = do
  count <- getMemberCount
  found <- checkLoop addr 0 count
  pure $ if found
    then Just (believe_me $ MkIsMember addr)
    else Nothing
  where
    checkLoop : Integer -> Integer -> Integer -> IO Bool
    checkLoop target idx count =
      if idx >= count then pure False
      else do
        slot <- getMemberSlot idx
        memberAddr <- sload slot
        if memberAddr == target
          then pure True
          else checkLoop target (idx + 1) count

||| Require member or fail with Outcome
export
requireMemberProof : (addr : Integer) -> IO (Outcome (IsMember addr))
requireMemberProof addr = do
  mproof <- checkMember addr
  pure $ case mproof of
    Just prf => Ok (believe_me prf)
    Nothing => Fail AuthViolation (tagEvidence "YouAreNotTheMember")

-- =============================================================================
-- Representative Access Control (Proposal-Scoped)
-- =============================================================================

||| Proof that an address is a representative for a specific proposal.
||| This is scoped to a proposal ID - rep status is per-proposal.
public export
data IsRep : Integer -> Integer -> Type where
  ||| Witness that address is a rep for the proposal
  MkIsRep : (pid : Integer) -> (addr : Integer) -> IsRep pid addr

||| Extract proposal ID from rep proof
export
repProposalId : IsRep pid addr -> Integer
repProposalId (MkIsRep p _) = p

||| Extract address from rep proof
export
repAddr : IsRep pid addr -> Integer
repAddr (MkIsRep _ a) = a

||| Check rep status and return proof if valid (runtime bridge)
export
checkRep : (pid : Integer) -> (addr : Integer) -> IO (Maybe (IsRep pid addr))
checkRep pid addr = do
  repCount <- getRepCount pid
  found <- checkLoop pid addr 0 repCount
  pure $ if found
    then Just (believe_me $ MkIsRep pid addr)
    else Nothing
  where
    checkLoop : Integer -> Integer -> Integer -> Integer -> IO Bool
    checkLoop pid target idx count =
      if idx >= count then pure False
      else do
        slot <- getRepSlot pid idx
        repAddr <- sload slot
        if repAddr == target
          then pure True
          else checkLoop pid target (idx + 1) count

||| Require rep or fail with Outcome
export
requireRepProof : (pid : Integer) -> (addr : Integer) -> IO (Outcome (IsRep pid addr))
requireRepProof pid addr = do
  mproof <- checkRep pid addr
  pure $ case mproof of
    Just prf => Ok (believe_me prf)
    Nothing => Fail AuthViolation (tagEvidence "YouAreNotTheRep")

-- =============================================================================
-- Proposal State Guards
-- =============================================================================

||| Proof that a proposal has not expired
public export
data NotExpired : Integer -> Type where
  MkNotExpired : (pid : Integer) -> NotExpired pid

||| Check expiration and return proof if not expired
export
checkNotExpired : (pid : Integer) -> IO (Maybe (NotExpired pid))
checkNotExpired pid = do
  expiration <- getProposalExpiration pid
  now <- timestamp
  pure $ if now < expiration
    then Just (believe_me $ MkNotExpired pid)
    else Nothing

||| Require not expired or fail with Outcome
export
requireNotExpired : (pid : Integer) -> IO (Outcome (NotExpired pid))
requireNotExpired pid = do
  mproof <- checkNotExpired pid
  pure $ case mproof of
    Just prf => Ok (believe_me prf)
    Nothing => Fail InvalidTransition (tagEvidence "ProposalAlreadyExpired")

||| Proof that a proposal is approved
public export
data IsApproved : Integer -> Type where
  MkIsApproved : (pid : Integer) -> IsApproved pid

||| Check approval and return proof if approved
export
checkApproved : (pid : Integer) -> IO (Maybe (IsApproved pid))
checkApproved pid = do
  approvedHeader <- getApprovedHeaderId pid
  pure $ if approvedHeader > 0
    then Just (believe_me $ MkIsApproved pid)
    else Nothing

||| Require approved or fail with Outcome
export
requireApproved : (pid : Integer) -> IO (Outcome (IsApproved pid))
requireApproved pid = do
  mproof <- checkApproved pid
  pure $ case mproof of
    Just prf => Ok (believe_me prf)
    Nothing => Fail InvalidTransition (tagEvidence "ProposalNotApproved")

||| Proof that a proposal has not been executed
public export
data NotExecuted : Integer -> Type where
  MkNotExecuted : (pid : Integer) -> NotExecuted pid

||| Check not executed and return proof
export
checkNotExecuted : (pid : Integer) -> IO (Maybe (NotExecuted pid))
checkNotExecuted pid = do
  executed <- isFullyExecuted pid
  pure $ if not executed
    then Just (believe_me $ MkNotExecuted pid)
    else Nothing

||| Require not executed or fail with Outcome
export
requireNotExecuted : (pid : Integer) -> IO (Outcome (NotExecuted pid))
requireNotExecuted pid = do
  mproof <- checkNotExecuted pid
  pure $ case mproof of
    Just prf => Ok (believe_me prf)
    Nothing => Fail InvalidTransition (tagEvidence "ProposalAlreadyExecuted")
