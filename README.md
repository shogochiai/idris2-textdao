# idris2-textdao

TextDAO implementation in Idris2 for EVM deployment.

## Overview

TextDAO is a decentralized autonomous organization (DAO) for collaborative text editing and governance. This implementation uses Idris2's dependent types for safety guarantees and compiles to EVM bytecode via `idris2-yul`.

## Features

- **Member Management**: Add/check members with metadata
- **Proposal System**: Create headers and proposals with timestamps
- **Representative Voting**: Only reps can vote, with ranked choice support
- **Tally & Approval**: RCV score calculation and proposal finalization
- **Type-Safe Storage**: ERC-7201 namespaced storage slots

## Architecture

```
src/TextDAO/
├── Storages/
│   └── Schema.idr       # Storage layout, slots, metadata
├── Functions/
│   ├── Members.idr      # Member management (6 functions)
│   ├── OnlyMember/
│   │   └── Propose.idr  # Proposal creation (8 functions)
│   ├── OnlyReps/
│   │   └── Vote.idr     # Voting (10 functions)
│   └── Tally.idr        # Vote counting, RCV (20 functions)
└── Tests/
    ├── AllTests.idr     # Test runner
    ├── MembersTest.idr
    ├── ProposeTest.idr
    ├── VoteTest.idr
    └── TallyTest.idr
```

## Building

```bash
# Requires idris2-yul compiler
pack build idris2-textdao

# Or with idris2-yul directly
idris2-yul --cg yul --build idris2-textdao.ipkg
```

## Build & Test Pipeline

**Important**: This project uses `%foreign "evm:*"` FFI directives which require special handling.

### Architecture

```
idris2-textdao/src/TextDAO/*.idr  (uses %foreign "evm:sload", "evm:sstore", etc.)
        ↓
        │  Cannot build directly with standard idris2
        │  (evm:* FFI is not supported by Chez backend)
        ↓
idris2-yul/examples/TextDAO_*.idr  (mirrored contract sources)
        ↓  ./scripts/build-contract.sh
idris2-yul → Yul → solc → .bin (EVM bytecode)
        ↓
idris2-evm-run (built with --profile)  ← Pure Idris2 EVM interpreter
        ↓
~/code/idris2-evm/idris2-evm-run.ss.html  (Chez profiler output)
        ↓
lazy evm ask --steps=4  ← Coverage analysis
```

### Running Tests

```bash
# Option 1: Use the test script (recommended)
./scripts/test-all-contracts.sh

# This script:
# 1. Builds contracts via idris2-yul/scripts/build-contract.sh
# 2. Runs them through idris2-evm-run (pack run idris2-evm -- ...)
# 3. Generates profiler output at ~/code/idris2-evm/idris2-evm-run.ss.html
```

### Coverage Analysis

```bash
# Run STI Parity coverage analysis (Step 4)
lazy evm ask /path/to/idris2-textdao --steps=4

# Output example:
#   [Step 4] EVM interpreter coverage... Result: hasGap
#   Coverage: 12760/49800 (25.62%)
```

The coverage tool automatically finds the profiler output at the known location.
If not found, it provides instructions for manual setup.

## Coverage Metrics

Function-level coverage via `idris2-evm-coverage`:

```
Total TextDAO Functions/Storages: 81
  TextDAO.Functions.Members:    6 functions
  TextDAO.Functions.OnlyMember: 8 functions
  TextDAO.Functions.OnlyReps:  10 functions
  TextDAO.Functions.Tally:     20 functions
  TextDAO.Storages.Schema:     37 functions
```

## Storage Layout

Uses ERC-7201 namespaced storage:

| Namespace | Slot | Description |
|-----------|------|-------------|
| `MEMBER`  | keccak256("textdao.member") | Member data |
| `HEADER`  | keccak256("textdao.header") | Proposal headers |
| `VOTE`    | keccak256("textdao.vote")   | Vote records |
| `META`    | keccak256("textdao.meta")   | Metadata |
| `SLOT`    | keccak256("textdao.slot")   | Generic slots |

## Dependencies

- [idris2-yul](https://github.com/shogochiai/idris2-yul) - EVM backend
- Solidity compiler (solc) for Yul→bytecode
- Foundry (anvil/cast) for testing

## Related

- [TextDAO Solidity](https://github.com/shogochiai/TextDAO) - Original Solidity implementation
- [idris2-evm-coverage](https://github.com/shogochiai/idris2-evm-coverage) - Coverage tools

## License

MIT
