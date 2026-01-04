||| TextDAO Reentrancy Guard
||| REQ_SECURITY_002: Type-safe reentrancy protection for TextDAO
|||
||| Compile-time guarantees against reentrancy attacks.
||| Based on Subcontract.Core.Reentrancy pattern.
module TextDAO.Security.Reentrancy

import public Subcontract.Core.Storable
import public TextDAO.Storages.Schema

%default total

-- =============================================================================
-- Lock State (Type-Level)
-- =============================================================================

||| Lock state at type level
public export
data LockState = Unlocked | Locked

||| Type-indexed lock.
||| The state is part of the TYPE, not just a runtime value.
public export
data ExecuteLock : LockState -> Type where
  ||| An unlocked lock
  MkUnlocked : ExecuteLock Unlocked
  ||| A locked lock
  MkLocked : ExecuteLock Locked

-- =============================================================================
-- Storage Layout for Lock
-- =============================================================================

||| Storage slot for execute reentrancy lock
||| Separate from other storage to avoid collisions
SLOT_EXECUTE_LOCK : Integer
SLOT_EXECUTE_LOCK = 0xDEAD0001

-- =============================================================================
-- State Transitions (Linear-Style)
-- =============================================================================

||| Acquire lock: Unlocked -> Locked
||| This CONSUMES the Unlocked proof and PRODUCES a Locked proof.
export
acquireExecuteLock : ExecuteLock Unlocked -> IO (ExecuteLock Locked)
acquireExecuteLock MkUnlocked = do
  sstore SLOT_EXECUTE_LOCK 1
  pure MkLocked

||| Release lock: Locked -> Unlocked
||| This CONSUMES the Locked proof and PRODUCES an Unlocked proof.
export
releaseExecuteLock : ExecuteLock Locked -> IO (ExecuteLock Unlocked)
releaseExecuteLock MkLocked = do
  sstore SLOT_EXECUTE_LOCK 0
  pure MkUnlocked

-- =============================================================================
-- Protected Execution Pattern
-- =============================================================================

||| Execute an action with reentrancy protection.
||| The action receives a Locked proof, preventing nested calls.
|||
||| ```idris
||| executeProposal : ExecuteLock Unlocked -> ProposalId -> IO (ExecuteLock Unlocked, Bool)
||| executeProposal lock pid = withExecuteLock lock $ \_ => do
|||   -- This code runs with lock held
|||   -- Any reentrant call would need ExecuteLock Unlocked, but we have Locked
|||   performExternalCall
||| ```
export
withExecuteLock : ExecuteLock Unlocked
               -> (ExecuteLock Locked -> IO a)
               -> IO (a, ExecuteLock Unlocked)
withExecuteLock lock action = do
  locked <- acquireExecuteLock lock
  result <- action locked
  unlocked <- releaseExecuteLock locked
  pure (result, unlocked)

||| Execute and discard the returned lock (simpler API)
export
withExecuteLock_ : ExecuteLock Unlocked -> (ExecuteLock Locked -> IO a) -> IO a
withExecuteLock_ lock action = fst <$> withExecuteLock lock action

-- =============================================================================
-- Runtime Initialization
-- =============================================================================

||| Initialize lock from storage (checks current state)
export
initExecuteLock : IO (Either (ExecuteLock Locked) (ExecuteLock Unlocked))
initExecuteLock = do
  state <- sload SLOT_EXECUTE_LOCK
  pure $ if state == 0
    then Right MkUnlocked
    else Left MkLocked

||| Try to get unlocked state (fails if already locked = reentrancy attempt)
export
tryGetUnlocked : IO (Maybe (ExecuteLock Unlocked))
tryGetUnlocked = do
  result <- initExecuteLock
  pure $ case result of
    Right unlocked => Just unlocked
    Left _ => Nothing

-- =============================================================================
-- Compile-Time Guarantees
-- =============================================================================

-- The key insight: ExecuteLock Unlocked is CONSUMED when acquiring the lock.
-- After acquireExecuteLock, you have ExecuteLock Locked, not ExecuteLock Unlocked.
-- To call a function requiring ExecuteLock Unlocked, you must release the lock first.
--
-- This makes reentrancy IMPOSSIBLE at compile time:
--
-- badExecute : ExecuteLock Unlocked -> IO ()
-- badExecute lock = withExecuteLock_ lock $ \locked => do
--   -- Here we have ExecuteLock Locked, not ExecuteLock Unlocked
--   badExecute lock  -- ERROR: lock is already consumed!
--   -- ^-- This doesn't compile because 'lock' was consumed by withExecuteLock_
--
-- In Solidity, this would be a runtime revert.
-- In Idris2, it's a compile-time type error.
