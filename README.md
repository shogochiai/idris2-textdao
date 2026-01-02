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

## Running Tests

The test suite runs on EVM:

```bash
# Build with Yul backend
idris2-yul --cg yul --build idris2-textdao.ipkg

# Deploy and run (requires anvil)
anvil --code-size-limit 100000 &
BYTECODE=$(solc --strict-assembly --bin build/exec/textdao-tests.yul | tail -1)
cast send --create "0x$BYTECODE" --rpc-url http://localhost:8545
```

## Coverage

Function-level coverage is available via `idris2-evm-coverage`:

```
Total TextDAO Functions/Storages: 81
Coverage breakdown:
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
