# lazy evm ask --steps=4 統合 Research Question Tree - 2026-01-01

## Goal
`lazy evm ask --steps=4` で idris2-textdao の EVM カバレッジを自動計測する

---

## 前提条件 (検証済み)

| Question | Status | Result |
|----------|--------|--------|
| Q1: idris2-evm --profile ビルド | ✅ | 動作確認済み |
| Q2: TextDAO テスト実行 | ✅ | 4テスト成功 |
| Q3: .ss.html パース | ✅ | 動作確認済み |
| Q4: Exclusion ルール | ✅ | idris2-coverage ロジック流用 |
| Q5: Coverage 計算 | ✅ | EVM.* only: 26.3% |

---

## Architecture

```
lazy evm ask --steps=4 --path=/path/to/idris2-textdao
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ LazyEvm/src/Evm/Ask/Ask.idr                                 │
│   runEvmAsk : AskOptions -> IO (List Gap)                   │
│                                                             │
│   steps 1-3: delegate to LazyCore                           │
│   step 4:    call idris2-evm-coverage                       │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ idris2-evm-coverage (Library)                               │
│                                                             │
│   Pipeline:                                                 │
│     1. Build idris2-evm with --profile                      │
│     2. Build TextDAO contracts (idris2-yul)                 │
│     3. Run tests: idris2-evm --bytecode <X> --calldata <Y>  │
│     4. Collect .ss.html                                     │
│     5. Parse + Exclusion + Calculate coverage               │
│     6. Return CoverageResult                                │
└─────────────────────────────────────────────────────────────┘
```

---

## Critical Path

```
Q6.1 ──▶ Q6.2 ──▶ Q6.3 ──▶ Q6.4 ──▶ Q6.5
LazyCli  Ask.idr  テスト    Coverage  Gap
pack.toml 確認    定義発見  API呼出   生成
```

---

## Q6.1: LazyCli の pack.toml でビルドできるか？

**Status**: ✅ RESOLVED

**問題**: LazyCli に pack.toml がない → ローカル依存解決失敗

**検証方法**:
```bash
ls /Users/bob/code/lazy/pkgs/LazyCli/pack.toml
# → File does not exist

cd /Users/bob/code/lazy/pkgs/LazyCli
pack run lazycli.ipkg -- evm ask --steps=4
# → [fatal] Unknown package: lazycore
```

**解決策**: LazyCli 用 pack.toml を作成

```toml
# /Users/bob/code/lazy/pkgs/LazyCli/pack.toml

[custom.all.lazycore]
type = "local"
path = "../LazyCore"
ipkg = "lazycore.ipkg"

[custom.all.lazyevm]
type = "local"
path = "../LazyEvm"
ipkg = "lazyevm.ipkg"

[custom.all.lazypr]
type = "local"
path = "../LazyPr"
ipkg = "lazypr.ipkg"

[custom.all.lazydepgraph]
type = "local"
path = "../LazyDepGraph"
ipkg = "lazydepgraph.ipkg"

[custom.all.lazyshared]
type = "local"
path = "../LazyShared"
ipkg = "lazyshared.ipkg"

[custom.all.idris2-coverage]
type = "local"
path = "/Users/bob/code/idris2-coverage"
ipkg = "idris2-coverage.ipkg"

[custom.all.idris2-evm-coverage]
type = "local"
path = "/Users/bob/code/idris2-evm-coverage"
ipkg = "idris2-evm-coverage.ipkg"

[custom.all.idris2-yul-coverage]
type = "local"
path = "/Users/bob/code/idris2-yul-coverage"
ipkg = "idris2-yul-coverage.ipkg"

[install]
libs = ["lazycli"]
```

**成功条件**:
- `pack build lazycli.ipkg` 成功
- `lazy evm --help` 表示

---

## Q6.2: Ask.idr の step 4 実装を確認

**Status**: ⚠️ NEEDS MODIFICATION

**依存**: Q6.1 成功 ✅

**確認結果** (2026-01-01):

現在の `Ask.idr` step 4 実装:
```idris
runEvmCoverage : String -> IO CoverageResult
runEvmCoverage targetPath = do
  let config = EvmCov.MkEvmCoverageConfig targetPath ...
  result <- EvmCov.analyzeCoverage config  -- ← 問題
  ...
```

**問題**: `EvmCov.analyzeCoverage` は純粋 Idris2 プロジェクト用
- dumpcases + Chez profiler で Idris2 コードのカバレッジを計測
- TextDAO は `%foreign "evm:*"` FFI を使っているため Chez で実行不可

**必要な変更**: EVM bytecode 実行ベースのパイプラインに変更

```idris
-- 新しい step 4 パイプライン
runEvmCoverage : String -> IO CoverageResult
runEvmCoverage targetPath = do
  -- 1. SPEC.toml からテスト定義読み込み
  tests <- loadEvmTests (targetPath ++ "/SPEC.toml")

  -- 2. idris2-yul で bytecode 生成 (既にある場合はスキップ)
  bytecodes <- buildContracts targetPath

  -- 3. idris2-evm (--profile) でテスト実行
  runProfiledEvmTests bytecodes tests

  -- 4. .ss.html からカバレッジ収集
  coverage <- collectCoverageFromSsHtml evmPath

  pure coverage
```

---

## Q6.3: テスト定義の発見方法

**Status**: ✅ RESOLVED - **選択肢 B: *Test.idr ファイルから発見**

**依存**: Q6.2 確認

**確認結果** (2026-01-01):

SPEC.toml には `[[evm.tests]]` セクションがない。
テストは `*Test.idr` ファイル内の `allXxxTests : List (String, IO Bool)` として定義。

**テストファイル一覧**:
```
src/TextDAO/Tests/
├── AllTests.idr      # 全テスト実行エントリポイント
├── SchemaTest.idr    # 4 tests (pure)
├── MembersTest.idr   # 7 tests (EVM runtime)
├── ProposeTest.idr   # ? tests (EVM runtime)
├── VoteTest.idr      # ? tests (EVM runtime)
├── TallyTest.idr     # ? tests (EVM runtime)
└── EvmTest.idr       # 4 tests (EVM integration)
```

**テスト発見パターン**:
```idris
export allXxxTests : List (String, IO Bool)
export runXxxTests : IO ()
```

**統合方法**:
1. `AllTests.idr` をビルド (`%foreign "evm:*"` → idris2-yul でバイトコード生成)
2. idris2-evm --profile で実行
3. .ss.html 収集

---

## Q6.4: Coverage API 呼び出し

**Status**: ✅ CLARIFIED - idris2-evm-coverage に `analyzeEvmBytecode` API を追加する

**依存**: Q6.3 解決 ✅

**整理** (2026-01-01):

### 正しい理解

カバレッジ計測対象は **idris2-evm インタプリタ自体**:
- idris2-evm を `--profile` でビルド
- TextDAO バイトコードを実行
- idris2-evm の EVM.* 関数がどれだけ実行されたかを計測

**既に Q1-Q5 で成功している**: EVM.* only: 26.3%

### 必要な API

```idris
-- idris2-evm-coverage に追加
record EvmInterpreterCoverageConfig where
  constructor MkEvmInterpreterCoverageConfig
  evmPath       : String   -- idris2-evm プロジェクトパス
  ssHtmlPath    : String   -- .ss.html ファイルパス (テスト実行後)
  exclusions    : List String  -- 除外パターン (Prelude.*, etc.)

-- .ss.html を解析して EVM.* 関数のカバレッジを計算
analyzeEvmInterpreterCoverage : EvmInterpreterCoverageConfig -> IO (Either String AggregatedCoverage)
```

### パイプライン

```
1. idris2-evm を --profile でビルド (事前準備)
2. idris2-yul で TextDAO → bytecode (事前準備)
3. テスト実行: idris2-evm --bytecode X --calldata Y
4. .ss.html 収集 (idris2-evm/build/exec/*.ss.html)
5. analyzeEvmInterpreterCoverage で解析
   - EVM.* 関数のみ抽出 (Exclusion)
   - hit/canonical 計算
6. Gap 生成
```

### 実装方針

**idris2-evm-coverage に追加**:
1. `EvmInterpreterCoverage.idr` モジュール新規作成
2. 既存の `ProfileParser.extractSpans` を再利用
3. 既存の `DumpcasesParser.shouldExcludeFunction` を再利用
4. EVM.* 関数の行範囲マッピング (SchemeMapper)

---

## Q6.5: Gap 生成

**Status**: ✅ ALREADY IMPLEMENTED (Ask.idr に実装済み)

**依存**: Q6.4 成功

**確認結果** (2026-01-01):

Ask.idr に既に Gap 変換ロジックが実装されている:

```idris
-- Ask.idr:74-108
convertEvmCovGaps : List EvmCov.CoverageGap -> List SharedGap.Gap
convertEvmCovGaps = map toSharedGap
  where
    toSeverity : Nat -> SharedGap.GapSeverity
    toSeverity p = if p >= 8 then SharedGap.Error
                   else if p >= 4 then SharedGap.Warning
                   else SharedGap.Info

convertHighImpactTarget : EvmCov.HighImpactTarget -> SharedGap.Gap
convertHighImpactTarget t =
  let sev = case t.severityLevel of
              EvmCov.Error => SharedGap.Error
              EvmCov.Warning => SharedGap.Warning
              EvmCov.Info => SharedGap.Info
  in MkGap
       { gapId = t.funcName
       , pass = "testandcoverage"
       , location = emptyModulePath
       , message = t.note ++ " (severity=" ++ EvmCov.showSeverity t.severity ++ ")"
       , severity = sev
       , counterExample = Nothing
       , propTestGap = Nothing
       }
```

**結論**: Gap 生成は Q6.4 の API 修正が完了すれば動作する

---

## 検証順序

| Step | Question | 状態 | 作業内容 |
|------|----------|------|----------|
| 1 | Q6.1 | ✅ | LazyCli pack.toml 作成 |
| 2 | Q6.2 | ✅ | Ask.idr step 4 確認済み (API差し替えで対応) |
| 3 | Q6.3 | ✅ | テスト定義: *Test.idr パターン |
| 4 | Q6.4 | ✅ | Coverage API 設計確定 (EvmInterpreterCoverage) |
| 5 | Q6.5 | ✅ | Gap 生成 - 実装済み |

**残作業**: idris2-evm-coverage に `EvmInterpreterCoverage.idr` 実装

---

## 既存コードの確認ポイント

1. **LazyEvm/src/Evm/Ask/Ask.idr**
   - step 4 の現在の実装状態
   - idris2-evm-coverage import の有無

2. **idris2-evm-coverage/src/EvmCoverage/EvmCoverage.idr**
   - API インターフェース
   - 必要な入力パラメータ

3. **idris2-textdao/SPEC.toml**
   - テスト定義の有無
   - [[evm.tests]] セクション

4. **idris2-textdao/src/TextDAO/Tests/**
   - 既存テストファイル
   - テストケース定義形式

---

## Immediate Next Action

**次のステップ**: idris2-evm-coverage に `EvmInterpreterCoverage.idr` を実装

### 実装タスク

1. **idris2-evm-coverage/src/EvmCoverage/EvmInterpreterCoverage.idr** 新規作成
   ```idris
   record EvmInterpreterCoverageConfig where
     constructor MkEvmInterpreterCoverageConfig
     ssHtmlPath    : String
     ssPath        : String   -- .ss ファイル (関数→行マッピング用)

   analyzeEvmInterpreterCoverage : EvmInterpreterCoverageConfig
                                 -> IO (Either String AggregatedCoverage)
   ```

2. **再利用する既存コード**:
   - `ProfileParser.extractSpans` - .ss.html パース
   - `SchemeMapper.parseSchemeDefs` - 関数→行範囲マッピング
   - `DumpcasesParser.shouldExcludeFunction` - Exclusion ルール

3. **LazyEvm Ask.idr 修正**:
   - `runEvmCoverage` を `analyzeEvmInterpreterCoverage` に差し替え

### コマンド

```bash
cd /Users/bob/code/idris2-evm-coverage
# 1. EvmInterpreterCoverage.idr 作成
# 2. ipkg に追加
# 3. ビルド確認
pack build idris2-evm-coverage.ipkg
```
