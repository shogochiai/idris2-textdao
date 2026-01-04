# TextDAO Coverage Gap Analysis - 2026-01-03

## 堂々巡りの発見

過去のログで同じ問題が2度発生していた：

| ログファイル | Q2ステータス | 実際 |
|------------|-------------|------|
| coverage-evm-profiler-2026-01-01.md | ❓ UNKNOWN | 未完了 |
| coverage-lazy-integration-2026-01-01.md | ✅ 検証済み | 誤り |
| coverage-gap-analysis-2026-01-02.md | 問題発見 | 正確 |

## 根本問題

### 問題1: Chez Scheme Profilerの測定対象

```
測定されるもの:
  idris2-evm の EVM.Interpreter.executeOp, step, run など
  (Idris2→Scheme にコンパイルされた関数)

測定すべきもの:
  TextDAO.Functions.propose, vote, tally など
  (TextDAOのソースコード関数)
```

Chez Scheme ProfilerはIdris2コードがSchemeにコンパイルされた関数を測定する。
TextDAOはYul→バイトコードとしてEVM上で実行されるため、Schemeレベルでは見えない。

### 問題2: .ss.htmlファイルの混同

`/Users/bob/code/idris2-evm/idris2-evm-run.ss.html` は：
- idris2-evmインタプリタ自体のプロファイル出力
- TextDAOバイトコード実行時にidris2-evmのどの関数が呼ばれたかを記録
- TextDAOソースコードのカバレッジではない

## 解決アプローチ

### アプローチA: --trace オプション (有望)

```bash
# idris2-evm-run --trace でオペコードトレース取得
idris2-evm-run --trace textdao-tests-runtime.bin

# 出力例:
step,pc,opcode,name,stack_depth
0,0,96,PUSH1,0
1,2,96,PUSH1,1
...
```

### アプローチB: solc --asm-json でソースマップ生成

```bash
solc --strict-assembly --asm-json textdao-tests.yul
```

出力にはYulソースオフセット (`begin`, `end`) が含まれる。
これでPC → Yulソース位置 → Yul関数名 → TextDAOモジュールのマッピングが可能。

### アプローチC: Yul関数名からの逆引き

Yul関数名がIdris2モジュール構造を保持している：
```
TextDAO_Tests_AllTests_u_main
TextDAO_Tests_EvmTest_u_test_REQ_EVM_001_selector_dispatch
TextDAO_Functions_Propose_u_propose
```

アンダースコアをドットに変換：`TextDAO.Tests.AllTests.main`

---

## 課題解決ツリー

```
Goal: TextDAOソースコードのカバレッジを計測する

Q1: --traceで実行トレースを取得できるか？ ✅ PASSED
    - CSV形式でPC/opcode/name出力確認済み

Q2: solc --asm-jsonでPC→Yulソースマップを生成できるか？ ✅ PASSED
    - begin/end オフセットがYulソースに対応
    - tagでJUMPDEST位置を特定可能

Q3: Yul関数→TextDAOモジュールのマッピングができるか？ ❓ IN PROGRESS
    - Yul関数名パターン: TextDAO_Module_u_funcname
    - アンダースコア→ドット変換でモジュールパス復元可能

Q4: トレース + ソースマップ → 関数レベルカバレッジ計算 ⏳ PENDING
    依存: Q2, Q3

Q5: lazy evm ask --steps=4 に統合 ⏳ PENDING
    依存: Q4
```

---

## 発見 (2026-01-03)

### Yul関数の数

```
TextDAO関数: 223個
- TextDAO_Tests_* (テスト)
- TextDAO_Functions_Members_* (Membersモジュール)
- TextDAO_Functions_Propose_* (Proposeモジュール)
- TextDAO_Functions_Vote_* (Voteモジュール)
- TextDAO_Functions_Tally_* (Tallyモジュール)
- TextDAO_Storages_Schema_* (Schemaモジュール)
```

### 関数名パターン

Yul関数名からIdris2モジュール構造を復元可能:
```
TextDAO_Functions_Members_u_addMember → TextDAO.Functions.Members.addMember
TextDAO_Tests_EvmTest_u_test_REQ_EVM_001 → TextDAO.Tests.EvmTest.test_REQ_EVM_001
```

`_u_` はユーザー定義関数、`_m_` はパターンマッチの分岐、`_n_` は名前マングリング

## 次のアクション

1. ~~solc --asm-json出力をファイルに保存~~ ✅
2. ~~PC→Yul関数マッピングを構築~~ ✅
3. ~~--trace出力からヒットしたPCを抽出~~ ✅
4. ~~PC→関数→モジュール でカバレッジ計算~~ ✅
5. idris2-evm-coverage/src/EvmCoverage/YulMapper.idr 実装

---

## 計測結果 (2026-01-03)

### TextDAOソースコードカバレッジ

| メトリック | 値 |
|-----------|-----|
| TextDAO関数数 | 223 |
| ヒット関数数 | 35 |
| **カバレッジ** | **15.7%** |

### ヒット関数 Top 10

| ヒット数 | 関数 |
|---------|------|
| 252 | TextDAO_Tests_AllTests_u_runAllTests |
| 224 | TextDAO_Tests_TallyTest_u_test_finalTally_tie |
| 180 | TextDAO_Tests_TallyTest_m_allTallyTests_3 |
| 134 | TextDAO_Tests_TallyTest_u_test_REQ_TALLY_006_finalTally_winner |
| 108 | TextDAO_Tests_AllTests_m_runAllTests_0 |
| 54 | TextDAO_Tests_TallyTest_u_test_REQ_TALLY_002_calcScores |
| 32 | TextDAO_Tests_EvmTest_u_test_REQ_EVM_003_return_encoding |
| 32 | TextDAO_Tests_TallyTest_m_allTallyTests_2 |
| 26 | TextDAO_Functions_Tally_n_3445_2616_u_updateOrInsert |
| 21 | TextDAO_Tests_EvmTest_u_test_REQ_EVM_004_revert_unauthorized |

### 未ヒット関数の例

- TextDAO_Functions_Members_u_isMember
- TextDAO_Functions_Members_u_addMember
- TextDAO_Functions_Propose_u_propose
- TextDAO_Functions_Vote_u_vote

### 比較

| 測定対象 | カバレッジ |
|---------|-----------|
| idris2-evmインタプリタ (EVM.*) | 26.3% |
| TextDAOソースコード | 15.7% |

**重要**: 26.3%はidris2-evmインタプリタのカバレッジ、15.7%がTextDAO自体のカバレッジ

---

## Phase 2: lazy evm ask 統合

### Goal

`lazy evm ask /path/to/textdao --steps=4` でTextDAOソースコードカバレッジを自動計測

### Research Question Tree

```
Q7: YulMapper.idr の実装
├── Q7.1: Yulソース解析 (オフセット→関数名)
│   ├── 入力: textdao-tests.yul
│   ├── 出力: List (Nat, Nat, String) = [(start, end, funcName)]
│   └── 依存: なし
│
├── Q7.2: asm-json解析 (PC→Yulオフセット)
│   ├── 入力: textdao-tests-asm.json
│   ├── 出力: SortedMap Nat (Nat, Nat) = PC → (begin, end)
│   └── 依存: solc --asm-json 実行
│
├── Q7.3: トレース解析 (PCヒットカウント)
│   ├── 入力: idris2-evm-run --trace 出力
│   ├── 出力: SortedMap Nat Nat = PC → hitCount
│   └── 依存: idris2-evm-run --trace 実行
│
└── Q7.4: カバレッジ計算
    ├── 入力: Q7.1 + Q7.2 + Q7.3
    ├── 出力: CoverageResult (関数レベル)
    └── 依存: Q7.1, Q7.2, Q7.3

Q8: lazy evm ask Step 4 統合
├── Q8.1: 既存のrunStep4EvmInterpreterを置換
├── Q8.2: Yul/asm-json/trace パス検出
└── Q8.3: Gap生成 (未ヒット関数 → Gap)
```

### Critical Path

```
Q7.1 ──┬──▶ Q7.4 ──▶ Q8
Q7.2 ──┤
Q7.3 ──┘
```

### 実装計画

#### Phase 2.1: YulMapper.idr 作成

```idris
-- idris2-evm-coverage/src/EvmCoverage/YulMapper.idr

||| Yul関数定義
record YulFunc where
  constructor MkYulFunc
  name : String
  startOffset : Nat
  endOffset : Nat

||| Yulソースから関数定義を抽出
parseYulFunctions : String -> List YulFunc

||| オフセットから関数名を検索
lookupFuncByOffset : List YulFunc -> Nat -> Maybe String
```

#### Phase 2.2: AsmJsonParser.idr 作成

```idris
-- idris2-evm-coverage/src/EvmCoverage/AsmJsonParser.idr

||| PC→Yulオフセットマッピング
record PcMapping where
  constructor MkPcMapping
  pc : Nat
  beginOffset : Nat
  endOffset : Nat

||| asm-jsonをパースしてPCマッピングを抽出
parseAsmJson : String -> Either String (List PcMapping)
```

#### Phase 2.3: 統合API

```idris
-- idris2-evm-coverage/src/EvmCoverage/YulCoverage.idr

||| Yulベースカバレッジ設定
record YulCoverageConfig where
  constructor MkYulCoverageConfig
  yulPath : String      -- textdao-tests.yul
  asmJsonPath : String  -- textdao-tests-asm.json
  tracePath : String    -- trace CSV出力
  prefix : String       -- "TextDAO_" でフィルタ

||| Yulベースカバレッジ計算
analyzeYulCoverage : YulCoverageConfig -> IO (Either String YulCoverageResult)
```

---

## 関連ファイル

| ファイル | 用途 |
|---------|------|
| /Users/bob/code/idris2-textdao/src/build/exec/textdao-tests.yul | Yulソース |
| /Users/bob/code/idris2-textdao/src/build/exec/textdao-tests-runtime.bin | ランタイムバイトコード |
| /Users/bob/code/idris2-evm-coverage/src/EvmCoverage/SourceMap.idr | 既存SourceMap実装 |
| /Users/bob/code/idris2-evm-coverage/src/EvmCoverage/TraceParser.idr | トレースパーサー |

---

## 実装進捗 (2026-01-03 更新)

### Q7.1: YulMapper.idr 実装 ✅ COMPLETED

**ファイル**: `/Users/bob/code/idris2-evm-coverage/src/EvmCoverage/YulMapper.idr`

**実装内容**:

```idris
-- 型定義
record YulFunc where
  constructor MkYulFunc
  name : String
  startOffset : Nat
  endOffset : Nat

record IdrisFunc where
  constructor MkIdrisFunc
  modulePath : String
  funcName : String
  variant : Maybe String

-- 主要関数
parseYulFuncName : String -> Maybe IdrisFunc
  -- TextDAO_Module_u_funcName → TextDAO.Module.funcName

parseYulFunctions : String -> List YulFunc
  -- Yulソースから関数定義を抽出

filterByPrefix : String -> List YulFunc -> List YulFunc
  -- プレフィックスでフィルタリング

readYulFile : String -> IO (Either String (List YulFunc))
  -- ファイル読み込み
```

**発見: Idris2パーサーの罠**

変数名 `prefix` を使うとパースエラーが発生:

```
Error: Couldn't parse declaration.
filterByPrefix prefix funcs = ...
               ^^^^^^
```

`pfx` に変更することで解決。`prefix` はIdris2で予約語または特殊な意味を持つ可能性がある。

### Q7.2: AsmJsonParser.idr ✅ COMPLETED

**ファイル**: `/Users/bob/code/idris2-evm-coverage/src/EvmCoverage/AsmJsonParser.idr`

**実装内容**:

```idris
-- 型定義
record AsmInstr where
  constructor MkAsmInstr
  pc : Nat              -- Program counter (bytecode offset)
  beginOff : Int        -- Yul source begin offset
  endOff : Int          -- Yul source end offset
  opName : String       -- Opcode name (PUSH, JUMP, etc.)
  opValue : Maybe String

record PcToYul where
  constructor MkPcToYul
  pc : Nat
  yulBegin : Int
  yulEnd : Int

-- 主要関数
parseAsmJson : String -> List AsmInstr
  -- asm.jsonをパースしてPC→Yulオフセットマッピング

buildPcMap : List AsmInstr -> SortedMap Nat PcToYul
  -- PCからYulオフセットを高速検索
```

**技術的発見**:
- asm.jsonはテキストヘッダー行の後にJSONが続く形式
- `.data["0"].code` にランタイムコードの命令列がある
- 各命令に `begin`, `end` (Yulソースオフセット) が含まれる

### Q7.3: トレース解析 ✅ COMPLETED

**ファイル**: `/Users/bob/code/idris2-evm-coverage/src/EvmCoverage/TraceParser.idr` (既存)

CSV形式のトレース解析は既に実装済み:
- `parseTraceCSV : String -> List TraceEntry`
- `readTraceFile : String -> IO (Either String (List TraceEntry))`

### Q7.4: YulCoverage.idr ✅ COMPLETED

**ファイル**: `/Users/bob/code/idris2-evm-coverage/src/EvmCoverage/YulCoverage.idr`

**実装内容**:

```idris
-- 統合カバレッジ計算
record YulCoverageResult where
  constructor MkYulCoverageResult
  yulFuncCount : Nat
  idrisFuncCount : Nat
  coveredCount : Nat
  coveragePercent : Double
  coveredFuncs : List FuncCoverage
  uncoveredFuncs : List FuncCoverage

-- Pipeline:
--   1. Parse Yul source → function definitions with byte offsets
--   2. Parse asm.json → PC to Yul offset mapping
--   3. Parse trace → executed PCs
--   4. Map executed PCs → Yul offsets → Yul functions → Idris functions
--   5. Calculate coverage

analyzeFromFiles : (yulPath : String) ->
                   (asmJsonPath : String) ->
                   (tracePath : String) ->
                   (moduleFilter : Maybe String) ->
                   IO (Either String YulCoverageResult)

coverageSummary : YulCoverageResult -> String
  -- テキストレポート生成

moduleBreakdown : YulCoverageResult -> String
  -- モジュール別カバレッジ
```

### Q8: lazy evm ask 統合 ⏳ IN PROGRESS

Step 4に組み込み予定。YulCoverage.idr APIを使用。

---

## 課題解決ツリー (更新版)

```
Goal: TextDAOソースコードのカバレッジを計測する

Phase 1: 調査・検証
├── Q1: --traceで実行トレースを取得できるか？ ✅ PASSED
│   └── CSV形式でPC/opcode/name出力確認済み
│
├── Q2: solc --asm-jsonでPC→Yulソースマップを生成できるか？ ✅ PASSED
│   └── begin/end オフセットがYulソースに対応
│
├── Q3: Yul関数→TextDAOモジュールのマッピングができるか？ ✅ PASSED
│   └── _u_, _m_, _n_ マーカーで関数種別を識別
│
├── Q4: トレース + ソースマップ → 関数レベルカバレッジ計算 ✅ PASSED
│   └── 15.7% (35/223関数) を計測
│
├── Q5: lazy evm ask --steps=4 に統合 ⏳ IN PROGRESS
│   └── Q7, Q8で実装中
│
└── Q6: (欠番)

Phase 2: 実装
├── Q7: YulMapper.idr の実装 ✅ COMPLETED
│   ├── Q7.1: Yulソース解析 ✅ COMPLETED
│   │   └── parseYulFunctions, parseYulFuncName 実装完了
│   │
│   ├── Q7.2: asm-json解析 ✅ COMPLETED
│   │   └── AsmJsonParser.idr - PC→Yulオフセットマッピング
│   │
│   ├── Q7.3: トレース解析 ✅ COMPLETED
│   │   └── TraceParser.idr (既存) - PCヒットカウント
│   │
│   └── Q7.4: カバレッジ計算 ✅ COMPLETED
│       └── YulCoverage.idr - Q7.1 + Q7.2 + Q7.3 の統合
│
└── Q8: lazy evm ask Step 4 統合 ✅ COMPLETED
    ├── Q8.1: YulCoverage imports追加 ✅
    ├── Q8.2: runStep4YulCoverage関数作成 ✅
    ├── Q8.3: AskOptsに--yul/--asm-json/--trace オプション追加 ✅
    ├── Q8.4: runStepWithOptsで両パイプライン実行 ✅
    └── Q8.5: ビルド成功 ✅
```

---

## 技術的発見

### 1. Yul関数名のマングリング規則

| パターン | 意味 | 例 |
|---------|------|-----|
| `_u_` | ユーザー定義関数 | `TextDAO_Functions_Vote_u_vote` |
| `_m_N` | パターンマッチ分岐N | `TextDAO_Tests_TallyTest_m_allTallyTests_3` |
| `_n_XXXX_YYYY_` | ネスト関数 (行/列) | `TextDAO_Functions_Tally_n_3445_2616_u_updateOrInsert` |

### 2. Idris2の変数名制約

`prefix` という変数名はIdris2で特殊な扱いを受ける。パースエラーを避けるため `pfx` などの代替名を使用する必要がある。

### 3. カバレッジの二重性

| 対象 | 計測方法 | カバレッジ |
|-----|---------|-----------|
| idris2-evmインタプリタ | Chez Scheme Profiler (.ss.html) | 26.3% |
| TextDAOソースコード | EVM trace + Yulマッピング | 15.7% |

両者は異なる抽象度のカバレッジを測定している。

---

## 教訓

1. **Q2のUNKNOWNステータスを見落とした** → 依存タスクの前提条件を明示的に確認
2. **測定対象の混同** → Chez ProfilerはIdris2コード、EVMトレースはバイトコード
3. **.ss.htmlファイルの正体不明** → ファイルヘッダーのタイトルを必ず確認
4. **変数名の罠** → Idris2では `prefix` が使えない場合がある
