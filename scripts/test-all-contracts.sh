#!/bin/bash
# Test all TextDAO and Praddictfun contracts with idris2-evm
# Usage: ./scripts/test-all-contracts.sh [--steps=N]

set -e

STEPS=${1:-4}  # Default 4 steps per contract
YUL_DIR="/Users/bob/code/idris2-yul"
EVM_DIR="/Users/bob/code/idris2-evm"
PRADICT_DIR="/Users/bob/code/praddictfun"
LOG_DIR="/Users/bob/code/idris2-textdao/logs"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/evm-test-$TIMESTAMP.md"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "# EVM Contract Test Results - $TIMESTAMP" > "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Function to extract runtime bytecode
extract_runtime() {
    local full_bytecode="$1"
    echo "$full_bytecode" | sed 's/.*f3fe//'
}

# Function to build and test a contract
test_contract() {
    local name="$1"
    local source="$2"
    local selectors="$3"  # space-separated: "selector1:name1 selector2:name2"

    echo -e "${YELLOW}=== Testing $name ===${NC}"
    echo "## $name" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    # Build
    echo "Building..."
    if ! cd "$YUL_DIR" && ./scripts/build-contract.sh "$source" > /dev/null 2>&1; then
        echo -e "${RED}  Build FAILED${NC}"
        echo "- Build: **FAILED**" >> "$LOG_FILE"
        return 1
    fi
    echo -e "${GREEN}  Build OK${NC}"
    echo "- Build: **OK**" >> "$LOG_FILE"

    # Extract basename for output files
    local basename=$(basename "$source" .idr)
    local binfile="$YUL_DIR/build/output/$basename.bin"

    if [ ! -f "$binfile" ]; then
        echo -e "${RED}  Bytecode not found${NC}"
        echo "- Bytecode: **NOT FOUND**" >> "$LOG_FILE"
        return 1
    fi

    # Extract runtime
    local full=$(cat "$binfile")
    local runtime=$(extract_runtime "$full")
    local runtime_file="/tmp/${basename}-runtime.bin"
    echo "$runtime" > "$runtime_file"
    echo "- Bytecode size: ${#runtime} chars" >> "$LOG_FILE"

    # Test each selector
    echo "### Function Tests" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    local pass=0
    local fail=0

    for entry in $selectors; do
        local sel=$(echo "$entry" | cut -d: -f1)
        local fname=$(echo "$entry" | cut -d: -f2)

        echo "  Testing $fname ($sel)..."

        local result=$(cd "$EVM_DIR" && pack run idris2-evm -- \
            --contract "0x1000:$runtime_file" \
            --call 0x1000 \
            --calldata "0x$sel" 2>&1)

        if echo "$result" | grep -q "SUCCESS"; then
            echo -e "${GREEN}    $fname: PASS${NC}"
            echo "- \`$fname\` ($sel): **PASS**" >> "$LOG_FILE"
            ((pass++))
        else
            echo -e "${RED}    $fname: FAIL${NC}"
            local error=$(echo "$result" | grep -E "(REVERT|ERROR|STACK)" | head -1)
            echo "- \`$fname\` ($sel): **FAIL** - $error" >> "$LOG_FILE"
            ((fail++))
        fi
    done

    echo "" >> "$LOG_FILE"
    echo "**Results: $pass passed, $fail failed**" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    return 0
}

echo "Starting EVM Contract Tests..."
echo ""

# TextDAO Contracts
echo "## TextDAO Contracts" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

test_contract "TextDAO_Members" "examples/TextDAO_Members.idr" \
    "997072f7:getMemberCount a230c524:isMember"

test_contract "TextDAO_Propose" "examples/TextDAO_Propose.idr" \
    "013cf08b:getProposalCount"

test_contract "TextDAO_Vote" "examples/TextDAO_Vote.idr" \
    "9f2b2833:getVoteCount"

test_contract "TextDAO_Tally" "examples/TextDAO_Tally.idr" \
    "6d4ce63c:get"

echo ""
echo "## Praddictfun Contracts" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Check if praddictfun contracts exist
if [ -d "$PRADICT_DIR" ]; then
    # List available contracts
    for contract in "$YUL_DIR/examples/"PPM_*.idr "$YUL_DIR/examples/"IdeoCoin_*.idr; do
        if [ -f "$contract" ]; then
            name=$(basename "$contract" .idr)
            echo "Found: $name"
            # Basic test - just try to execute with empty calldata
            test_contract "$name" "examples/$name.idr" "00000000:fallback" || true
        fi
    done
fi

echo ""
echo "=== Test Summary ==="
echo "Log file: $LOG_FILE"
cat "$LOG_FILE"
