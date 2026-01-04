# idris2-evm-coverage 分子問題分析

**日時**: 2026-01-03
**問題**: Coverage 0/54 (0%) - 4980トレースエントリがあるのに分子が0

## 現状

```
Coverage: 0/54 (0%)
├── 分母: 54 ✓ 正しい (TextDAOソース関数数)
├── 分子: 0  ✗ おかしい (トレースからマッピングされた関数)
└── トレースエントリ: 4980 (存在するが使われていない)
```

## 問題の構造

```
分子が0になる原因
│
├── 仮説A: トレースの内容が間違っている
│   ├── A1: トレースがTextDAOバイトコードではなくidris2-evm内部の実行を記録
│   │   └── 現状: idris2-evmインタプリタ自身のステップを記録している可能性
│   │
│   ├── A2: トレースフォーマットがYulCoverageの期待と異なる
│   │   └── 調査必要: trace.csvのフォーマット vs YulCoverage.parseTrace
│   │
│   └── A3: トレースにPC (Program Counter) 情報が含まれていない
│       └── 調査必要: トレースエントリの中身を確認
│
├── 仮説B: ソースマップが欠落/不正
│   ├── B1: asm.jsonが生成されていない
│   │   └── 確認: ./src/build/exec/textdao-tests-asm.json の存在と内容
│   │
│   ├── B2: asm.jsonのPC→関数名マッピングが不完全
│   │   └── 調査必要: asm.jsonのsourceName/begin/end情報
│   │
│   └── B3: Yul関数名とIdris2ソース関数名の対応が取れていない
│       └── 例: TextDAO_Functions_Members_u_addMember vs addMember
│
├── 仮説C: マッピングロジックのバグ
│   ├── C1: YulCoverage.idrのparseTrace実装の問題
│   │   └── 調査: idris2-evm-coverage/src/EvmCoverage/YulCoverage.idr
│   │
│   ├── C2: PC範囲マッチングのoff-by-oneエラー
│   │   └── 調査: begin <= pc < end vs begin <= pc <= end
│   │
│   └── C3: 関数名正規化の不一致
│       └── 調査: ソース関数名 vs Yul関数名の変換ルール
│
└── 仮説D: パイプライン接続の問題
    ├── D1: lazy evm askがトレースファイルを正しく読んでいない
    │   └── 調査: lazyがどのファイルをトレースとして使用しているか
    │
    ├── D2: テスト実行とトレース生成が別々のバイトコードを対象にしている
    │   └── 調査: binPathとトレース生成時のバイトコードパスの一致
    │
    └── D3: トレースが古い/キャッシュされている
        └── 調査: トレースファイルのタイムスタンプ
```

---

## 確定した原因: A1

**トレースがidris2-evm内部実行ではなく、空のcalldataでの実行を記録**

```
lazy/pkgs/LazyEvm/src/Evm/Ask/Ask.idr:316-322
│
└── generateTrace bytecodeHex = do
      let (_, evmTrace) = EvmInterp.executeWithTrace bytecode [] 100000 EvmStorage.empty
                                                            ^^              ^^^^^
                                                     空のcalldata      空のstorage
```

4980トレースは:
- コントラクトのディスパッチコード（関数セレクタ読み取り）
- calldataが空でrevertするパス
- TextDAO関数本体（addMember, isMember等）は一度も実行されていない

---

## 解決策: Option A - Library API修正

### 必要な変更

```
1. lazy/Ask.idr の generateTrace を修正
│
├── Before:
│   generateTrace : String -> IO (Either String (List EvmTrace.TraceEntry))
│   generateTrace bytecodeHex = ...executeWithTrace bytecode [] 100000 empty
│
└── After:
    generateTrace : String -> List TestScenario -> IO (Either String (List EvmTrace.TraceEntry))
    generateTrace bytecodeHex scenarios =
      -- 各シナリオでexecuteWithTrace
      -- トレースを結合して返す

2. TestScenario レコードを定義
│
├── record TestScenario where
│     constructor MkTestScenario
│     name : String
│     calldata : String           -- 0xSELECTOR + args
│     initialStorage : Storage    -- cheat code: 事前設定するスロット
│
└── 例:
    MkTestScenario "addMember"
      "0xca6d56dc000...00deadbeef000...001234"  -- selector + addr + metadata
      (sstore MEMBER_COUNT_SLOT 0 empty)        -- memberCount = 0 から開始

3. テストシナリオをTextDAOから収集
│
├── EvmRunner.idr の selectors を使用
│   SEL_ADD_MEMBER = 0xca6d56dc
│   SEL_GET_MEMBER_COUNT = 0x997072f7
│
└── 各テストケースに対応するシナリオを生成
    - test_REQ_MEMBERS_001 → addMember calldata + empty storage
    - test_REQ_MEMBERS_002 → getMemberAddr calldata + storage with 3 members
    - etc.
```

### 実装ステップ

```
Step 1: idris2-evm に依存関係なしで実装可能
│
├── Storage.sstore : StorageKey -> StorageValue -> Storage -> Storage
│   └── 既に存在、cheat codeとして使える
│
└── executeWithTrace : Bytecode -> List Bits8 -> Nat -> Storage -> (Result, List TraceEntry)
    └── 既にStorage引数を受け付ける

Step 2: lazy の Ask.idr を修正
│
├── TestScenario 型を追加
├── generateTrace を複数シナリオ対応に
├── トレースを結合するロジック追加
│
└── discoverScenarios : String -> IO (List TestScenario)
    └── プロジェクトからテストシナリオを検出

Step 3: TextDAO にシナリオ定義ファイルを追加
│
├── scenarios.json または TestScenarios.idr
└── 各テストケースの (calldata, initialStorage) を定義
```

---

## 追加調査結果 (2026-01-03 12:30)

### 発見1: textdao-tests-runtime.bin はテストランナー

```yul
mstore(64, 128)
pop(TextDAO_Tests_AllTests_u_main(0))  ← 無条件でテストを実行
```

- calldataを見ていない
- getMemberCountセレクタを渡しても無視される
- テストランナーが直接 `main()` を呼び出す

### 発見2: asm.json の source が全て -1

```
16733 "source":-1
```

- solcがYulコンパイル時にソースマッピングを生成していない
- `begin/end` オフセットはYulソースファイルと一致しない
- PCからYul関数へのマッピングが壊れている

### 発見3: オフセット不一致

```
asm.json: "begin":247,"end":250,"name":"PUSH"
Yulファイル offset 247: "tion mk_closure(func" (関数名の途中)
→ 一致しない！
```

### 結論: 現在のパイプラインでは分子計算が不可能

```
問題の連鎖
│
├── 1. テストランナーはcalldata無視
│   └── getMemberCount等の関数を直接呼び出しできない
│
├── 2. asm.jsonにソースマッピングがない
│   └── PCからYul関数を特定できない
│
└── 3. オフセットが一致しない
    └── begin/endはYulソースのバイト位置ではない
```

---

## 調査優先順位

```
優先度High (まず確認)
│
├── 1. トレースエントリの中身を確認
│   └── コマンド: head -20 [trace file path]
│   └── 期待: PC, opcode, gas等の情報
│
├── 2. asm.jsonの存在と内容を確認
│   └── ファイル: ./src/build/exec/textdao-tests-asm.json
│   └── 期待: .code[].begin, .code[].end, .code[].name
│
└── 3. lazyがどのファイルをトレースソースにしているか確認
    └── コード: ~/code/lazy のEVM coverage実装を確認

優先度Medium (上記で解決しない場合)
│
├── 4. YulCoverage.idrのparseTrace実装レビュー
│
├── 5. PC→関数名マッピングロジックのデバッグ
│
└── 6. 関数名正規化ルールの確認

優先度Low (根本的な再設計が必要な場合)
│
├── 7. idris2-evmのトレース出力フォーマット変更
│
├── 8. Yul関数境界情報の別途生成
│
└── 9. ソースレベルカバレッジへの切り替え
```

## 次のアクション

```
即座に実行すべき調査
│
├── [ ] トレースファイルのパスと内容を特定
│   └── lazy evm askが使用しているトレースソースを追跡
│
├── [ ] 4980エントリの実際の中身をサンプリング
│   └── PC情報が含まれているか？TextDAO関数呼び出しか？
│
└── [ ] asm.jsonのPC範囲情報を確認
    └── Yul関数ごとのbegin/end PCが正しく記録されているか？
```

## 技術的背景

```
正しいパイプライン (期待)
│
├── 1. TextDAO.idr → idris2-yul → textdao.yul
├── 2. textdao.yul → solc --asm-json → textdao-asm.json (PC→関数マップ)
├── 3. textdao.yul → solc → textdao.bin (バイトコード)
├── 4. idris2-evm --trace textdao.bin calldata → trace.csv (実行PC列)
└── 5. YulCoverage.analyze(asm.json, trace.csv) → 分子/分母

現状の疑い
│
├── ステップ4のトレースがidris2-evm自身の実行を記録している
│   └── TextDAOバイトコードのPC列ではなくインタプリタの内部状態
│
└── または、ステップ5のマッピングロジックに問題がある
    └── PC範囲チェックや関数名マッチングのバグ
```
