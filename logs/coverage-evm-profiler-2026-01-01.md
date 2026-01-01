# EVM Profiler Coverage Research Question Tree - 2026-01-01

## Goal
idris2-evm インタプリタを --profile でビルドし、TextDAO テスト実行時の
EVM オペコード分岐カバレッジを計測する

---

## Architecture

```
TextDAO Tests (bytecode + calldata)
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ idris2-evm --profile                                        │
│                                                             │
│   executeOp ADD vm = ...     ← Chez profiler が記録        │
│   executeOp SSTORE vm = ...  ← Chez profiler が記録        │
│   executeOp CALL vm = ...    ← Chez profiler が記録        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ .ss.html                                                    │
│   line 150 count=42  (ADD branch hit 42 times)              │
│   line 155 count=0   (SELFDESTRUCT branch never hit)        │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ --dumpcases から canonical branches                         │
│   EVM.MultiInterpreter.executeOp: 80+ opcode branches       │
│   - Canonical: ADD, SUB, SSTORE, CALL, ...                  │
│   - Excluded: SELFDESTRUCT (deprecated), CREATE2 (unused)   │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
    Coverage = hit_opcodes / canonical_opcodes
```

---

## Critical Path

```
Q1 ──────▶ Q2 ──────▶ Q3 ──────▶ Q4 ──────▶ Q5
Profile    テスト     .ss.html   dumpcases   Coverage
ビルド     実行       解析       Exclusion   計算
```

---

## Q1: idris2-evm を --profile でビルドできるか？

**Status**: ✅ PASSED (前回検証済み)

```bash
cd /Users/bob/code/idris2-evm
idris2 --profile --dumpcases /tmp/idris2-evm-dump.txt --build idris2-evm.ipkg
```

**結果**:
- ビルド成功
- dumpcases: 684行 (EVM opcodes 含む)

---

## Q2: TextDAO テストを idris2-evm で実行し .ss.html を生成できるか？

**Status**: ❓ UNKNOWN

**依存**: Q1 成功

**検証方法**:
```bash
# Step 1: TextDAO bytecode を生成
cd /Users/bob/code/idris2-yul
./scripts/build-contract.sh /path/to/TextDAO/Members.idr

# Step 2: 各テストケースを実行
cd /Users/bob/code/idris2-evm
./build/exec/idris2-evm-run \
  --bytecode <Members.bin> \
  --calldata 0x997072f7  # getMemberCount()

# Step 3: .ss.html 確認
ls *.ss.html
grep 'EVM.MultiInterpreter.executeOp' idris2-evm-run.ss.html
```

**成功条件**:
- 各 TextDAO 関数のテスト実行成功
- .ss.html に executeOp の各分岐のヒットカウントが記録

**課題**:
- 複数テストケースの .ss.html をどうマージするか？
- テストスクリプトの自動化

---

## Q3: .ss.html から EVM オペコード別ヒット数を抽出できるか？

**Status**: ❓ UNKNOWN

**依存**: Q2 成功

**検証方法**:
```bash
# executeOp の各 concase をパース
grep -o 'EVM.Opcodes.[A-Z0-9]*' idris2-evm-run.ss.html | sort | uniq -c

# または ProfileParser を拡張して opcode 別集計
```

**期待する出力**:
```
Opcode      Hit Count
ADD         42
SUB         15
SSTORE      8
SLOAD       23
CALL        3
DELEGATECALL 1
SELFDESTRUCT 0  ← 未カバー
```

**成功条件**:
- オペコード別のヒット数を正確に抽出
- 0 ヒットのオペコードを特定

---

## Q4: dumpcases から Canonical/Excluded オペコードを分類できるか？

**Status**: ✅ RESOLVED (idris2-coverage の既存ロジックで対応)

**依存**: 独立 (Q1-Q3 と並行可能)

**発見**: idris2-coverage/src/Coverage/DumpcasesParser.idr に exclusion ロジック実装済み

### 既存の Exclusion ルール (shouldExcludeFunction)

```idris
-- Excluded (分母から除外):
isPrefixOf "{" name           -- {csegen:*} コンパイラ生成
isPrefixOf "_builtin." name   -- Builtin constructors
isPrefixOf "prim__" name      -- Primitive operations
isPrefixOf "Prelude." name    -- Standard library
isPrefixOf "Data." name
isPrefixOf "System." name
isPrefixOf "Control." name
isSuffixOf "." name           -- Type constructors
isInfixOf ".Tests." name      -- Test code
```

### EVM 用の適用

```
EVM.MultiInterpreter.executeOp      ← Canonical (カウント対象)
EVM.MultiInterpreter.executeSimple  ← Canonical (カウント対象)
EVM.Stack.push                      ← Canonical (カウント対象)
Prelude.Types.List.length           ← Excluded (stdlib)
{csegen:143}                        ← Excluded (compiler-generated)
```

**結論**: 既存の exclusion ロジックをそのまま使用可能。
`EVM.*` 名前空間の関数のみが Canonical としてカウントされる。

---

## Q5: Coverage = hit / canonical を計算できるか？

**Status**: ⚠️ PARTIAL - Exclusion の適用方法に課題

**依存**: Q3 成功 AND Q4 成功

### 現在の結果 (2026-01-01)

| Metric | Value | 問題点 |
|--------|-------|--------|
| Total expressions (.ss.html) | 54,766 | stdlib 含む |
| Executed (count > 0) | 16,243 | |
| Not executed (count = 0) | 38,523 | |
| **Raw expression coverage** | **29.6%** | Exclusion 未適用 |

### 問題: Exclusion が .ss.html に適用されていない

```
dumpcases (関数名ベース)          .ss.html (行番号ベース)
─────────────────────────        ─────────────────────────
EVM.MultiInterpreter.executeOp   line 991 count=35
Prelude.Types.List.length        line 123 count=100  ← 除外されるべき
{csegen:143}                     line 45 count=50    ← 除外されるべき
```

**課題**:
1. .ss.html は Scheme ソースの行番号のみ記録
2. 関数名との対応が必要 (Scheme ソースをパースして関数→行範囲をマップ)
3. idris2-coverage の Collector.idr がこれを行っている

### 解決策: idris2-coverage の Collector.idr ロジック

```
1. parseSchemeDefs(".ss")      → [(schemeFunc, startLine), ...]
2. dumpcases → CompiledFunction → canonical 関数のみ抽出
3. parseAnnotatedHtml(".ss.html") → ExprCoverage(line, char, count)
4. matchAllFunctionsWithCoverage() → 関数レベルカバレッジ
```

**次のアクション**:
- Q5.1: .ss ファイルから EVM.* 関数の行範囲を抽出 ✅
- Q5.2: .ss.html から EVM.* 関数のみの expression coverage を計算 ✅
- Q5.3: Exclusion 適用後の正確なカバレッジを算出 ✅

### Q5 最終結果 (2026-01-01)

| Metric | Raw (全体) | EVM.* Only |
|--------|-----------|------------|
| Total expressions | 54,766 | 42,521 |
| Executed (count > 0) | 16,243 | 11,218 |
| Not executed (count = 0) | 38,523 | 31,303 |
| **Expression Coverage** | 29.6% | **26.3%** |

**EVM 関数の行範囲**: lines 758-1150 (206 関数、約 390 行)

**Exclusion 効果**:
- Prelude.*, Data.*, System.* などの stdlib 関数が除外
- compiler-generated ({csegen:*}) が除外
- EVM.Word256, EVM.Stack, EVM.Memory, EVM.MultiInterpreter のみカウント

---

## Implementation Tasks

### T1: テストランナースクリプト作成
```bash
#!/bin/bash
# run-textdao-tests.sh

cd /Users/bob/code/idris2-evm

# Build with profiling
idris2 --profile --build idris2-evm.ipkg

# Run each test case
for test in "${TEXTDAO_TESTS[@]}"; do
  ./build/exec/idris2-evm-run --bytecode "$BYTECODE" --calldata "$test"
done

# Collect .ss.html
```

### T2: Opcode Hit Extractor 実装
```idris
-- Extract opcode hits from .ss.html
extractOpcodeHits : String -> List (String, Nat)
```

### T3: Exclusion Config 作成
```toml
# textdao-coverage.toml
[exclusions]
deprecated = ["SELFDESTRUCT"]
unimplemented = ["CREATE2", "EXTCODEHASH"]
environment = ["BLOCKHASH", "DIFFICULTY", "PREVRANDAO"]
```

### T4: Coverage Calculator 実装
```idris
-- Calculate coverage with exclusions
calculateEvmCoverage : List (String, Nat) -> ExclusionConfig -> CoverageResult
```

---

## Questions to Resolve

1. **複数テストの .ss.html マージ**:
   - 同じ executable を複数回実行すると .ss.html は上書き？追記？
   - テストごとに別ディレクトリで実行してマージが必要？

2. **Exclusion 基準**:
   - TextDAO 固有の exclusion と汎用の exclusion を分けるか？
   - idris2-coverage の exclusions/ と同様の仕組みを使うか？

3. **ソース行との対応**:
   - .ss.html の行番号は Scheme ソースの行
   - Idris2 ソース (MultiInterpreter.idr) との対応は可能か？

---

## Immediate Next Action

**Q2 検証**: TextDAO テストを 1 つ実行して .ss.html を確認

```bash
# Members.idr の getMemberCount() テスト
cd /Users/bob/code/idris2-yul
./scripts/build-contract.sh examples/TextDAO/Members.idr

cd /Users/bob/code/idris2-evm
./build/exec/idris2-evm-run \
  --bytecode <runtime_bytecode> \
  --calldata 0x997072f7

# 結果確認
grep -c 'executeOp' *.ss.html
```
