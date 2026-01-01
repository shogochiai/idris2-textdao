# Coverage Integration Tree - 2026-01-01

## Root Question
**`lazy evm ask --steps=4` でidris2-textdaoのEVMカバレッジを計測するには？**

---

## 現状アーキテクチャ

```
lazy evm ask --steps=4
      │
      ▼
┌─────────────────────────────────────────────────────────────┐
│ LazyEvm/src/Evm/Ask/Ask.idr                                 │
│   runEvmCoverage : String -> IO CoverageResult              │
│                                                             │
│   imports:                                                  │
│     - EvmCoverage.EvmCoverage (idris2-evm-coverage)         │
│     - EvmCoverage.Types                                     │
│     - EvmCoverage.DumpcasesParser                           │
│     - EvmCoverage.ProfileParser                             │
│     - EvmCoverage.SchemeMapper                              │
│     - EvmCoverage.Aggregator                                │
│     - EvmCoverage.Report                                    │
└─────────────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│ idris2-evm-coverage (Library API)                           │
│   EvmCov.analyzeCoverage : EvmCoverageConfig -> IO Result   │
│                                                             │
│   Pipeline:                                                 │
│     1. idris2 --dumpcases → 静的分岐解析 (denominator)      │
│     2. idris2 --coverage → Chez profiler 実行              │
│     3. .ssi ファイル解析 → 実行回数 (numerator)            │
│     4. coverage = hits / canonical                          │
└─────────────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│ idris2-evm (インタプリタ)                                   │
│   --coverage フラグでビルド時に Chez が分岐追跡             │
│                                                             │
│   executeOp ADD vm = ...    ← 実行回数記録                  │
│   executeOp SSTORE vm = ... ← 実行回数記録                  │
└─────────────────────────────────────────────────────────────┘
```

---

## Level 1: 統合の根本課題

### Q1.1 [UNKNOWN] idris2-evm-coverage は LazyEvm から呼び出せるか？
- **Status**: ❓ 未検証
- **Blocker**: LazyEvmのpack.toml依存にidris2-evm-coverageがあるか確認必要
- **Next**: `pack build` して import エラーがないか確認

### Q1.2 [UNKNOWN] idris2-evm を --coverage でビルドできるか？
- **Status**: ❓ 未検証
- **Dependency**: Idris2 の --coverage フラグが Chez backend で動作すること
- **Next**: `idris2 --cg chez --coverage` でビルドテスト

### Q1.3 [UNKNOWN] .ssi ファイルのパスはどこに生成されるか？
- **Status**: ❓ 未検証
- **Dependency**: Chez Scheme profiler の出力先
- **Next**: テストビルド後にファイル探索

---

## Level 2: idris2-evm-coverage 課題

### Q2.1 [UNKNOWN] DumpcasesParser は動作するか？
- **Purpose**: `idris2 --dumpcases` 出力から静的分岐数を抽出
- **Input**: Idris2 の dumpcases 形式
- **Output**: canonical branch count (denominator)

### Q2.2 [UNKNOWN] ProfileParser は .ssi を正しく解析するか？
- **Purpose**: Chez Scheme profiler 出力から実行回数を抽出
- **Input**: `.ssi` ファイル
- **Output**: hit count per branch (numerator)

### Q2.3 [UNKNOWN] SchemeMapper は EVM オペコードにマップできるか？
- **Purpose**: Idris2 ソース行 → EVM オペコード対応
- **Challenge**: Interpreter.idr の `executeOp` パターンマッチを認識

### Q2.4 [UNKNOWN] Aggregator は正しくカバレッジ計算するか？
- **Formula**: `coverage = canonicalHit / canonicalTotal`
- **Edge cases**: 0 division, negative counts

---

## Level 3: idris2-textdao 統合課題

### Q3.1 [UNKNOWN] idris2-textdao のテストはどう実行されるか？
- **Current**: `src/TextDAO/Tests/AllTests.idr` が存在
- **Question**: pack test で実行可能か？

### Q3.2 [UNKNOWN] テスト実行時に idris2-evm が呼ばれるか？
- **Current**: テストが EVM バイトコード実行を含むか？
- **Question**: 純粋 Idris2 テストのみか、EVM 実行テストか？

### Q3.3 [UNKNOWN] カバレッジ対象は何か？
- **Option A**: idris2-textdao の Idris2 コード自体
- **Option B**: idris2-evm インタプリタの分岐 (EVM オペコード実行)
- **Option C**: 両方

---

## Level 4: 実装タスク

### T4.1 [TODO] LazyEvm pack.toml に idris2-evm-coverage 依存追加
```toml
[deps]
idris2-evm-coverage = { path = "../idris2-evm-coverage" }
```

### T4.2 [TODO] idris2-evm を --coverage でビルドするスクリプト
```bash
cd idris2-evm
idris2 --cg chez --coverage src/Main.idr -o idris2-evm-coverage
```

### T4.3 [TODO] テスト実行 → .ssi 生成 → 解析 パイプライン実装
```
1. pack test idris2-textdao
2. find .ssi files
3. EvmCov.analyzeCoverage
4. Report generation
```

### T4.4 [TODO] CLI 統合
```bash
lazy evm ask --steps=4 --path=/Users/bob/code/idris2-textdao
```

---

## 依存関係図

```
┌──────────────┐     ┌──────────────────┐     ┌─────────────┐
│ lazy         │────▶│ idris2-evm-      │────▶│ idris2-evm  │
│ (LazyEvm)    │     │ coverage         │     │ (--coverage)│
└──────────────┘     └──────────────────┘     └─────────────┘
       │                     │                       │
       │                     ▼                       ▼
       │              ┌──────────────┐        ┌───────────┐
       │              │ Chez Scheme  │        │ .ssi      │
       │              │ profiler     │───────▶│ files     │
       │              └──────────────┘        └───────────┘
       │
       ▼
┌──────────────────┐
│ idris2-textdao   │
│ (target project) │
└──────────────────┘
```

---

## Immediate Next Actions

1. **Q1.1 検証**: LazyEvm が idris2-evm-coverage を import できるか確認
2. **Q1.2 検証**: idris2-evm を --coverage でビルド
3. **Q3.1 検証**: idris2-textdao の現在のテスト構造を確認
4. **プロトタイプ**: 手動で coverage パイプラインを実行

---

## Notes

- Step 4 は「Test and Coverage」で、テスト実行 + カバレッジ計測の両方を含む
- Steps 5-6 は Step 4 の結果に依存（Fuzzing, Drift）
- LazyCore の Steps 1-3 は既に動作想定（Spec-Test Parity, Orphans, Semantic）
