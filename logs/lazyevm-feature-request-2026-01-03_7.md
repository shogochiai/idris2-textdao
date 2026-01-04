# lazy evm ask Feature Request: Branch Coverage

**Date**: 2026-01-03
**Status**: Feature Request

---

## 1. Per-Function Branch Coverage

### Current State

現在の `lazy evm ask --steps=4` は関数レベルのカバレッジのみ計測:

```
Coverage: 34/114 (30%)
```

除外パターン (`idris2-evm-coverage/exclusions/base.txt`):
- `*_Tests_*`, `*_Test_*` - テストモジュール
- `*#0` ~ `*#9` - コンパイラ生成クロージャ
- `Prelude_*`, `Data_*` 等 - 標準ライブラリ

- 関数が1回でも実行されたら "covered"
- 分岐 (if/else, switch/case) の網羅性は未計測

### Requested Feature

各関数の分岐カバレッジを計測:

```
Coverage: 75/223 functions (34%)

Per-function branch coverage:
  TextDAO_Functions_Members_u_addMember:
    branches: 3/5 (60%)
    - if memberExists: covered
    - if memberCount >= maxMembers: NOT covered
    - switch role: 2/3 cases covered

  TextDAO_Functions_Vote_u_vote:
    branches: 4/4 (100%)
    - if hasVoted: covered
    - if proposalExists: covered
    - ...
```

### Implementation Approach

1. **Yul AST解析**: `switch`, `if` 文の位置を特定
2. **Source Map拡張**: 分岐点のPC範囲を記録
3. **トレース分析**: 各分岐のPC実行有無を確認

### Data Structure

```idris
record BranchCoverage where
  constructor MkBranchCoverage
  funcName : String
  totalBranches : Nat
  coveredBranches : Nat
  branches : List BranchInfo

record BranchInfo where
  constructor MkBranchInfo
  branchType : BranchType  -- If, Switch, Case
  location : (Nat, Nat)    -- start/end offset in Yul
  covered : Bool
  hitCount : Nat           -- 何回実行されたか
```

---

## 2. Severity Levels for Coverage Gaps

### Current State

全ての未カバー関数が同じ `[warning]` で表示:

```
[warning] TextDAO_Functions_Members_u_addMember: Source function not covered
[warning] TextDAO_Storages_Schema_u_getVoteSlot: Source function not covered
```

### Requested Feature

重要度に応じた severity 分類:

```
[critical] TextDAO_Functions_Members_u_addMember: Core function not covered (0 branches hit)
[high]     TextDAO_Functions_Vote_u_vote: Partial coverage (2/5 branches)
[medium]   TextDAO_Storages_Schema_u_getVoteSlot: Utility function not covered
[low]      TextDAO_Tests_*: Test helper not covered (expected)
```

### Severity Criteria

| Severity | Criteria |
|----------|----------|
| Critical | Production関数で0%カバレッジ |
| High | Production関数で50%未満カバレッジ |
| Medium | Production関数で50-80%カバレッジ |
| Low | テスト/ヘルパー関数、または80%+カバレッジ |

### Implementation

```idris
data CoverageSeverity = Critical | High | Medium | Low

calculateSeverity : FuncCoverage -> CoverageSeverity
calculateSeverity fc =
  if isTestFunc fc.name then Low
  else if fc.branchPercent == 0.0 then Critical
  else if fc.branchPercent < 50.0 then High
  else if fc.branchPercent < 80.0 then Medium
  else Low
```

---

## 3. Output Format Enhancement

### Current

```
Coverage: 75/223 (34%)
```

### Proposed

```
=== EVM Coverage Analysis ===

Function Coverage: 75/223 (34%)
Branch Coverage: 142/380 (37%)

By Severity:
  Critical: 12 functions (0% branch coverage)
  High: 45 functions (<50% branch coverage)
  Medium: 30 functions (50-80% branch coverage)
  Low: 136 functions (80%+ or test functions)

Top Critical Gaps:
  [critical] TextDAO_Functions_Members_u_addMember
    - branches: 0/5
    - missing: if memberExists, if maxMembers, switch role

  [critical] TextDAO_Functions_Propose_u_propose
    - branches: 0/8
    - missing: all branches untested
```

---

## Related Files

- `/Users/bob/code/idris2-evm-coverage/src/EvmCoverage/SolcSourceMap.idr`
- `/Users/bob/code/lazy/pkgs/LazyEvm/src/Evm/Ask/Ask.idr`
- `/Users/bob/code/idris2-yul/src/Compiler/EVM/Solc.idr`

---

## Priority

- Function coverage: ✅ Implemented (2026-01-03)
- Branch coverage: 🔜 Next priority
- Severity levels: 🔜 After branch coverage
