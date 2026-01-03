# Cheat Code Coverage Map

Mapping of uncovered functions to required cheat codes for testing.

## Summary

| Cheat Code | Purpose | Required By |
|------------|---------|-------------|
| `prank` | Set msg.sender | Members, Propose, Vote |
| `store` | Direct storage write | Schema, Members setup |
| `load` | Direct storage read | Schema, verification |
| `warp` | Set block.timestamp | Vote (expiration) |
| `deal` | Set ETH balance | (future: payable functions) |
| `snapshot` | Save state | Test isolation |
| `expectRevert` | Assert reverts | Access control tests |

## Uncovered Functions → Cheat Codes

### Members Module (6 branches in checkMemberLoop)

| Function | Cheat Codes Needed | Test Setup |
|----------|-------------------|------------|
| `isMember` | `setupMember`, `prank` | Add member, then check |
| `getMemberMetadata` | `setupMember` | Pre-populate storage |
| `getMemberAddr` | `setupMember` | Pre-populate storage |
| `checkMemberLoop` | `setupMembers` | Multiple members for loop testing |
| `addMember` | `prank` | Set caller as authorized |
| `MEMBER_OFFSET_*` | (constants, no cheat needed) | - |

```idris
-- Example: Test isMember with cheat codes
testIsMember : IO Bool
testIsMember = do
  -- Setup: add alice as member
  setupMember 0 alice 0xMETA1

  -- Act & Assert
  result <- isMember alice
  pure result  -- Should be True
```

### Schema Module

| Function | Cheat Codes Needed | Test Setup |
|----------|-------------------|------------|
| `sstore` | - (primitive, test via effects) | - |
| `sload` | `store` | Pre-write value to slot |
| `setSnapInterval` | `load` | Verify after call |
| Config getters/setters | `store`, `load` | Direct slot manipulation |

```idris
-- Example: Test sload/sstore round-trip
testStorage : IO Bool
testStorage = do
  store 0x1234 42
  val <- load 0x1234
  pure (val == 42)
```

### Vote Module

| Function | Cheat Codes Needed | Test Setup |
|----------|-------------------|------------|
| `vote` | `prank`, `warp`, `setupRep`, `setupProposalMeta` | Full proposal setup |
| `isRep` | `setupRep` | Add rep to proposal |
| `isProposalExpired` | `warp` | Set timestamp before/after expiration |
| `storeVote` | `setupProposalMeta` | Proposal must exist |

```idris
-- Example: Test vote with time manipulation
testVoteNotExpired : IO Bool
testVoteNotExpired = do
  -- Setup proposal expiring at t=1000
  setupProposalMeta 0 0 1000 100
  setupRep 0 0 alice

  -- Warp to before expiration
  let ctx = warp 500 initBlockContext

  -- Prank as rep
  let st = prank alice initPrankState

  -- Vote should succeed
  result <- vote 0 (1, 2, 3) (1, 2, 3)
  pure result

-- Example: Test vote expired
testVoteExpired : IO Bool
testVoteExpired = do
  setupProposalMeta 0 0 1000 100
  setupRep 0 0 alice

  -- Warp to after expiration
  let ctx = warp 2000 initBlockContext
  let st = expectRevert initExpectState

  -- Vote should revert
  _ <- vote 0 (1, 2, 3) (1, 2, 3)
  pure (checkRevertExpectation st)
```

### Propose Module

| Function | Cheat Codes Needed | Test Setup |
|----------|-------------------|------------|
| `propose` | `prank`, `setupMember`, `setupConfig` | Caller must be member |
| `createProposal` | `setupConfig` | Config for expiry calculation |
| `initProposalMeta` | `warp` | Timestamp for createdAt |
| `createHeader` | (via propose) | - |

```idris
-- Example: Test propose as member
testProposeAsMember : IO Bool
testProposeAsMember = do
  -- Setup: alice is a member
  setupMember 0 alice 0xMETA
  setupConfig 86400 3600 5 3  -- 1 day expiry

  -- Prank as alice
  let st = prank alice initPrankState

  -- Propose should succeed
  pid <- propose 0xHEADER_META
  pure (pid >= 0)

-- Example: Test propose as non-member (should revert)
testProposeAsNonMember : IO Bool
testProposeAsNonMember = do
  -- No members setup
  setupConfig 86400 3600 5 3

  let st = prank bob initPrankState
  let expect = expectRevert initExpectState

  -- Should revert
  _ <- propose 0xHEADER_META
  pure (checkRevertExpectation expect)
```

## Branch Coverage Details

### checkMemberLoop (6 branches)

```
Branch 1: idx >= count (empty loop, return False)
Branch 2: idx < count (enter loop)
Branch 3: memberAddr == target (found, return True)
Branch 4: memberAddr /= target (continue loop)
Branch 5: Loop iteration (recursive call)
Branch 6: Final iteration before exit
```

Test cases:
1. Empty member list → Branch 1
2. Single member, match → Branches 2, 3
3. Single member, no match → Branches 2, 4, 1
4. Multiple members, match in middle → Branches 2, 4, 5, 3
5. Multiple members, no match → Branches 2, 4, 5, 4, 5, 1

### updateOrInsert (8 branches in Tally)

Already covered (hits: 24), but for reference:
- Insert new entry
- Update existing entry
- Loop through existing entries
- Match found vs. not found

## Test Execution Flow

```
1. Initialize VM state
   vmState = initVMState

2. Setup storage state
   setupMembers [...]
   setupConfig ...
   setupProposalMeta ...

3. Apply cheat codes
   vmState' = { prankSt := prank alice vmState.prankSt }
   vmState'' = { blockCtx := warp 1000 vmState'.blockCtx }

4. Execute function under test
   result <- functionUnderTest args

5. Verify expectations
   assert (checkRevertExpectation vmState''.expectSt)
   assert (result == expectedValue)

6. (Optional) Restore state
   revertTo snapshotId
```

## Implementation Priority

1. **High Priority** (blocks most tests):
   - `setupMember` ✅
   - `prank` ✅
   - `store`/`load` ✅

2. **Medium Priority** (time-dependent tests):
   - `warp` ✅
   - `setupProposalMeta` ✅
   - `setupRep` ✅

3. **Lower Priority** (convenience):
   - `snapshot`/`revertTo` ✅
   - `expectRevert` ✅
   - `deal` ✅
