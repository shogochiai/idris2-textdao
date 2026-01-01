# Multi-Contract EVM Environment Design

## Problem Statement

ERC-7546 UCS pattern requires:
1. **Proxy Contract** - forwards calls via DELEGATECALL
2. **Dictionary Contract** - maps selector → implementation (STATICCALL lookup)
3. **Implementation Contracts** - actual logic (DELEGATECALL execution)

Current idris2-evm limitations:
- Single Storage per execution
- No CALL/DELEGATECALL/STATICCALL support (stubs only)
- No multi-contract address space

## Required Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        World State                                   │
├─────────────────────────────────────────────────────────────────────┤
│  Address → (Code, Storage)                                          │
│  ─────────────────────────                                          │
│  0x1000 (Proxy)      → (proxy.bin,    {0: 0x2000})                 │
│  0x2000 (Dictionary) → (dict.bin,     {0: owner, keccak: impl})    │
│  0x3000 (Members)    → (members.bin,  {})                           │
│  0x4000 (Propose)    → (propose.bin,  {})                           │
└─────────────────────────────────────────────────────────────────────┘
```

## Implementation Plan

### Phase 1: World State Model

```idris
-- New WorldState module
record Account where
  constructor MkAccount
  code : Bytecode
  storage : Storage
  balance : Word256

record WorldState where
  constructor MkWorldState
  accounts : SortedMap Word256 Account

-- Operations
getAccount : Word256 -> WorldState -> Maybe Account
setAccount : Word256 -> Account -> WorldState -> WorldState
getStorage : Word256 -> Word256 -> WorldState -> Word256
setStorage : Word256 -> Word256 -> Word256 -> WorldState -> WorldState
```

### Phase 2: Call Opcodes

```idris
-- CALL: Execute code at address with separate storage context
-- call(gas, address, value, argsOffset, argsSize, retOffset, retSize)
executeCall : VM -> WorldState -> (VM, WorldState)

-- DELEGATECALL: Execute code at address with CALLER's storage context
-- delegatecall(gas, address, argsOffset, argsSize, retOffset, retSize)
executeDelegateCall : VM -> WorldState -> (VM, WorldState)

-- STATICCALL: Read-only CALL (reverts on state modification)
-- staticcall(gas, address, argsOffset, argsSize, retOffset, retSize)
executeStaticCall : VM -> WorldState -> (VM, WorldState)
```

### Phase 3: Execution Context

```idris
record ExecutionContext where
  constructor MkExecCtx
  currentAddress : Word256      -- Address being executed
  storageAddress : Word256      -- Address whose storage to use (different for DELEGATECALL)
  caller : Word256
  origin : Word256
  callDepth : Nat
  isStatic : Bool               -- True during STATICCALL
```

### Phase 4: CLI Changes

```bash
# Load multiple contracts
idris2-evm \
  --contract 0x1000:proxy.bin:proxy_storage.json \
  --contract 0x2000:dict.bin:dict_storage.json \
  --contract 0x3000:members.bin \
  --call 0x1000 \
  --calldata 0x997072f7 \
  --save-world world_state.json
```

## JSON World State Format

```json
{
  "accounts": {
    "0x1000": {
      "code": "0x6080...",
      "storage": {"0x0": "0x2000"},
      "balance": "0x0"
    },
    "0x2000": {
      "code": "0x6080...",
      "storage": {
        "0x0": "0xowner",
        "0xabc123": "0x3000"
      },
      "balance": "0x0"
    }
  }
}
```

## Test Scenario: Members.addMember via Proxy

```
1. User calls Proxy(0x1000) with selector 0xca6d56dc (addMember)

2. Proxy:
   - SLOAD slot 0 → gets Dictionary address (0x2000)
   - DELEGATECALL to Dictionary with calldata

3. Dictionary (via DELEGATECALL, but we need STATICCALL logic):
   - Extract selector from calldata
   - Calculate keccak256(selector, 2) → storage slot
   - SLOAD → gets Implementation address (0x3000)
   - Return implementation address

4. Proxy receives implementation address
   - DELEGATECALL to Implementation(0x3000)

5. Members Implementation:
   - Runs in Proxy's storage context
   - SSTORE to Proxy's storage slots (0x3000, 0x3001, etc.)

6. Return to user
```

## Simplification for MVP

Instead of full multi-contract support, we can test individual contracts:

### Option A: Test Implementation Directly
- Skip Proxy/Dictionary layer
- Call Members.bin directly with appropriate calldata
- Verify storage changes

### Option B: Hardcoded Dictionary Lookup
- Precompute implementation addresses
- Mock DELEGATECALL by switching code

### Option C: Scripted Multi-Execution
```bash
# Step 1: Set implementation in Dictionary
idris2-evm --contract dict.bin \
  --calldata 0x2c3c3e4e000000...ca6d56dc...0x3000 \
  --save-storage dict_storage.json

# Step 2: Call Proxy (simulated)
# Since we can't do real DELEGATECALL, test implementation directly
idris2-evm --contract members.bin \
  --load-storage proxy_storage.json \
  --calldata 0xca6d56dc... \
  --save-storage proxy_storage.json
```

## Priority

1. **[HIGH]** Fix function dispatch bug in idris2-yul first
2. **[MEDIUM]** Implement basic CALL opcodes
3. **[LOW]** Full WorldState with multiple contracts

## Current Blocker

Before implementing multi-contract support, we need to fix:
- **idris2-yul function dispatch** - selector extraction/comparison not working
- Without this, even single-contract tests fail

## Workaround for Now

Test contracts in isolation:
1. Build each contract separately
2. Extract runtime bytecode
3. Test with direct calldata (not through Proxy)
4. Use storage persistence for sequential tests

This validates:
- Contract logic correctness
- Storage operations
- Individual function behavior

Does NOT validate:
- DELEGATECALL behavior
- Multi-contract interaction
- Proxy pattern
