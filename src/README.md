# TextDAO - Idris2 Implementation

TextDAO smart contracts written in Idris2, targeting EVM deployment via `idris2-yul` compiler.

## Architecture

```
                    ERC-7546 Architecture

    User tx ───────▶ PROXY ───────▶ Dictionary ───────▶ DELEGATECALL
                       │              (selector           │
                       │               lookup)            │
                       ▼                                  ▼
                    Storage                        Implementation
                    (lives here)                   (stateless code)
```

**Key Points:**
- Users call **PROXY**, not implementation
- All storage lives in the Proxy contract
- Implementation contracts are stateless - executed via DELEGATECALL
- Dictionary maps selectors → implementation addresses
- Upgrades only touch Dictionary, Proxy address stays the same

## Directory Structure

```
src/TextDAO/
├── Storages/
│   └── Schema.idr              # ERC-7201 storage layout
├── Functions/
│   ├── Members/
│   │   ├── Members.idr         # Member registration
│   │   └── Tests/
│   │       └── MembersTest.idr
│   ├── Propose/
│   │   ├── Propose.idr         # Proposal creation
│   │   └── Tests/
│   ├── Fork/
│   │   ├── Fork.idr            # Proposal forking
│   │   └── Tests/
│   ├── Vote/
│   │   ├── Vote.idr            # RCV voting
│   │   └── Tests/
│   ├── Tally/
│   │   ├── Tally.idr           # Vote counting
│   │   └── Tests/
│   ├── Execute/
│   │   ├── Execute.idr         # Proposal execution
│   │   └── Tests/
│   └── Text/
│       ├── Text.idr            # Text management
│       └── Tests/
└── Tests/
    ├── AllTests.idr            # Test aggregator
    └── CheatCodes.idr          # Foundry-style test utilities
```

## Function Selectors

| Function | Selector | Module |
|----------|----------|--------|
| `addMember(address,bytes32)` | `0xca6d56dc` | Members |
| `getMember(uint256)` | `0x9c0a0cd2` | Members |
| `getMemberCount()` | `0x997072f7` | Members |
| `isMember(address)` | `0xa230c524` | Members |
| `propose(bytes32)` | `0x01234567` | Propose |
| `getHeader(uint256,uint256)` | `0x12345678` | Propose |
| `getProposalCount()` | `0x23456789` | Propose |
| `vote(uint256,uint256[3],uint256[3])` | `0x34567890` | Vote |
| `isRep(uint256,address)` | `0x56789012` | Vote |
| `tally(uint256)` | `0x67890123` | Tally |
| `snap(uint256)` | `0x78901234` | Tally |
| `isApproved(uint256)` | `0x89012345` | Tally |
| `tallyAndExecute(uint256)` | `0x90123456` | Tally |
| `fork(uint256,bytes32,bytes32)` | `0xf0123456` | Fork |
| `forkHeader(uint256,bytes32)` | `0xf1234567` | Fork |
| `forkCommand(uint256,bytes32)` | `0xf2345678` | Fork |
| `execute(uint256)` | `0xe0123456` | Execute |
| `isExecuted(uint256)` | `0xe1234567` | Execute |
| `createText(uint256,bytes32)` | `0xc0123456` | Text |
| `getText(uint256)` | `0xc1234567` | Text |
| `getTextCount()` | `0xc2345678` | Text |

## Entry Pattern

Each function module exports `*Entry : Entry *Sig` values:

```idris
-- 1. Define signature (type-safe)
proposeSig : Sig
proposeSig = MkSig "propose" [TBytes32] [TUint256]

-- 2. Define selector (keccak256 hash)
proposeSel : Sel proposeSig
proposeSel = MkSel 0x01234567

-- 3. Core logic (pure business logic)
propose : MetadataCid -> IO ProposalId

-- 4. Entry point (ABI decode/encode + core logic)
proposeEntry : Entry proposeSig
proposeEntry = MkEntry proposeSel $ do
  headerMetadata <- runDecoder decodeBytes32
  pid <- propose (bytes32Value headerMetadata)
  returnUint pid
```

## Storage Schema (ERC-7201)

```idris
-- Namespace: textdao.deliberation.v1
SLOT_DELIBERATION = 0x...

-- Field layout:
-- +0: proposalCount
-- +1: memberCount
-- +2: textCount
-- +3: expiryDuration
-- +4: snapInterval
-- +5: repsNum
-- +6: quorumScore
```

## Deliberation Flow

```
1. Member calls propose(headerMetadata)
   └─▶ Creates proposal with initial header

2. VRF selects representatives
   └─▶ Random reps stored in proposal meta

3. Reps call fork(pid, header, command)
   └─▶ Add alternative headers/commands

4. Reps call vote(pid, rankedHeaders, rankedCommands)
   └─▶ RCV votes stored per rep

5. Anyone calls tally(pid) after expiration
   └─▶ Borda scoring, winner approval

6. Anyone calls execute(pid)
   └─▶ Execute approved command
```

## Build & Test

```bash
# Build via idris2-yul
cd ~/code/idris2-yul
./scripts/build-contract.sh ~/code/idris2-textdao/src/TextDAO/Functions/Members/Members.idr

# Run tests via idris2-evm
pack run idris2-evm -- \
  --contract 0x1000:build/output/Members.bin \
  --call 0x1000 \
  --calldata 0x997072f7  # getMemberCount

# Check coverage
lazy evm ask ~/code/idris2-textdao --steps=4
```

## Dependencies

- `idris2-yul`: Idris2 → Yul compiler (handles `evm:*` FFI)
- `idris2-subcontract`: Subcontract framework (Entry, Sig, Sel, Schema)
- `idris2-evm`: Pure Idris2 EVM interpreter for testing

## Related

- [TextDAO Spec](docs/textdao.txt) - Reference implementation
- [idris2-subcontract](../idris2-subcontract) - Framework patterns
