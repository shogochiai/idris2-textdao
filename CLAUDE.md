# CLAUDE.md - idris2-textdao Project Guide

## Project Overview

TextDAO smart contracts written in Idris2, targeting EVM deployment via `idris2-yul` compiler.

## Critical Architecture Understanding

### Why Standard Build Fails

This project uses `%foreign "evm:sload"`, `%foreign "evm:sstore"`, etc. in `src/TextDAO/Storages/Schema.idr`. These FFI specifiers are **NOT supported by standard Idris2 Chez Scheme backend**.

```idris
-- This CANNOT be built with `idris2 --build` or `pack build`
%foreign "evm:sload"
prim__sload : Integer -> PrimIO Integer
```

### Correct Build Pipeline

```
1. idris2-yul/examples/TextDAO_*.idr  ← Mirrored sources
   ↓ ./scripts/build-contract.sh
2. Yul code
   ↓ solc --strict-assembly
3. EVM bytecode (.bin files)
   ↓ idris2-evm-run (pack run idris2-evm --)
4. Execution with profiler → .ss.html
```

### Related Repositories

| Repo | Purpose | Location |
|------|---------|----------|
| `idris2-yul` | Idris2→Yul compiler (handles evm:* FFI) | `~/code/idris2-yul` |
| `idris2-evm` | Pure Idris2 EVM interpreter | `~/code/idris2-evm` |
| `idris2-evm-coverage` | Coverage analysis tools | `~/code/idris2-evm-coverage` |
| `lazy` | STI Parity analysis CLI | `~/code/lazy` |

## Test Execution

### Option 1: Test Script (Recommended)

```bash
cd ~/code/idris2-textdao
./scripts/test-all-contracts.sh
```

This script:
1. Builds each contract via `idris2-yul/scripts/build-contract.sh`
2. Extracts runtime bytecode
3. Runs with `pack run idris2-evm -- --contract 0x1000:file.bin --calldata 0xSELECTOR`
4. Generates profiler output

### Option 2: Manual Execution

```bash
# Build a single contract
cd ~/code/idris2-yul
./scripts/build-contract.sh examples/TextDAO_Members.idr

# Run with idris2-evm
pack run idris2-evm -- \
  --contract 0x1000:build/output/TextDAO_Members.bin \
  --call 0x1000 \
  --calldata 0x997072f7  # getMemberCount selector
```

## Coverage Analysis

### Run Coverage Check

```bash
lazy evm ask ~/code/idris2-textdao --steps=4
```

Expected output:
```
[Step 4] EVM interpreter coverage... Result: hasGap
Coverage: 12760/49800 (25.62%)
```

### Profiler Output Location

The EVM interpreter profiler output is at:
```
~/code/idris2-evm/idris2-evm-run.ss.html
```

If this file doesn't exist, run `./scripts/test-all-contracts.sh` first.

## File Structure

```
src/TextDAO/
├── Storages/
│   └── Schema.idr       # %foreign "evm:*" primitives, storage slots
├── Functions/
│   ├── Members.idr      # Member management
│   ├── OnlyMember/
│   │   └── Propose.idr  # Proposal creation
│   ├── OnlyReps/
│   │   └── Vote.idr     # Voting logic
│   └── Tally.idr        # Vote counting, RCV
└── Tests/
    ├── AllTests.idr     # Test aggregator
    ├── *Test.idr        # Individual test modules
```

## Common Issues

### "evm:sstore specifier not accepted by any backend"
- **Cause**: Using standard `idris2` instead of `idris2-yul`
- **Fix**: Use the pipeline via `idris2-yul/examples/`

### "No test executable found"
- **Cause**: Trying to build Tests directly
- **Fix**: Tests use `%foreign "evm:*"` too; run via `test-all-contracts.sh`

### Coverage shows 0%
- **Cause**: Profiler output not generated
- **Fix**: Run tests with `idris2-evm` built with `--profile` flag

## Development Workflow

1. Edit source in `src/TextDAO/`
2. Mirror changes to `~/code/idris2-yul/examples/TextDAO_*.idr`
3. Run `./scripts/test-all-contracts.sh`
4. Check coverage with `lazy evm ask --steps=4`
