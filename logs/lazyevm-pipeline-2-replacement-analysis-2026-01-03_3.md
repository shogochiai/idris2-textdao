# Pipeline 2 Trace 出力統合 - リサーチクエスチョンツリー

**日付**: 2026-01-03
**目的**: idris2-evm の Interpreter.idr に trace 出力オプションを追加し、lazy evm で anvil なしに trace.csv を生成可能にする

---

## 1. 現状分析

### 1.1 Pipeline 2 が期待する trace.csv フォーマット

**場所**: `/Users/bob/code/idris2-evm-coverage/src/EvmCoverage/TraceParser.idr`

```
CSV Header: step,pc,opcode,name,stack_depth
例: 0,0,96,PUSH1,0
    1,2,96,PUSH1,1
    2,4,1,ADD,2
```

**TraceEntry レコード**:
```idris
record TraceEntry where
  constructor MkTraceEntry
  step : Nat
  pc : Nat
  opcode : Nat
  opcodeName : String
  stackDepth : Nat
```

### 1.2 idris2-evm 既存の trace 機能

**場所**: `/Users/bob/code/idris2-evm/src/EVM/Interpreter.idr` (391-436行)

既に `runWithTrace` と `executeWithTrace` 関数が存在:

```idris
record TraceEntry where
  constructor MkTraceEntry
  stepNum : Nat
  pc : Nat
  opcode : Bits8
  opcodeName : String
  stackDepth : Nat

Show TraceEntry where
  show e = show e.stepNum ++ "," ++ show e.pc ++ "," ++
           show e.opcode ++ "," ++ e.opcodeName ++ "," ++ show e.stackDepth
```

**Main.idr のオプション** (46-47, 72-74行):
```idris
trace : Bool
traceFile : Maybe String
parseArgs ("--trace" :: rest) opts = parseArgs rest ({ trace := True } opts)
parseArgs ("--trace-file" :: f :: rest) opts = parseArgs rest ({ trace := True, traceFile := Just f } opts)
```

### 1.3 ギャップ分析

| 項目 | Pipeline 2 期待 | idris2-evm 現状 | ギャップ |
|------|-----------------|-----------------|----------|
| CSV フォーマット | step,pc,opcode,name,stack_depth | step,pc,opcode,name,stack_depth | **なし** (完全一致) |
| opcode 型 | Nat | Bits8 | 微小 (cast で解決) |
| trace 出力機能 | 必要 | `--trace-file` で対応済み | **なし** |
| lazy evm 統合 | 必要 | 未統合 | **あり** |

**発見**: idris2-evm は既に Pipeline 2 互換の trace 出力を持っている！

---

## 2. リサーチクエスチョンツリー

### Q1: idris2-evm の trace 機能は Pipeline 2 と互換性があるか？

```
Q1: trace 互換性
├── Q1.1: フォーマットは一致するか？ → ✅ 一致 (step,pc,opcode,name,stack_depth)
├── Q1.2: 必要なデータは揃っているか？ → ✅ すべて揃っている
└── Q1.3: 追加実装は必要か？ → ❌ 不要
```

**結論**: idris2-evm の `--trace-file` 出力は既に Pipeline 2 互換

### Q2: lazy evm から idris2-evm を呼び出す方法は？

```
Q2: 統合方法
├── Q2.1: サブプロセスとして呼び出すか？
│   ├── メリット: 実装簡単、既存コード再利用
│   └── デメリット: プロセス起動オーバーヘッド
├── Q2.2: ライブラリとしてリンクするか？
│   ├── メリット: 高速、型安全
│   └── デメリット: 依存関係増加、ビルド複雑化
└── Q2.3: 推奨: サブプロセス方式
    └── 理由: STI Parity 哲学に適合 (各ツールが独立)
```

### Q3: 必要な実行フローは？

```
Q3: 実行フロー
├── Q3.1: bytecode.hex はどこにあるか？
│   └── idris2-textdao/src/build/exec/*.bin (Yul コンパイル結果)
├── Q3.2: calldata はどこから取得するか？
│   ├── テストシナリオから (e.g., propose, vote)
│   └── または SPEC.toml の要件から
├── Q3.3: 複数コントラクト対応は必要か？
│   ├── TextDAO: Proxy → Dictionary → Implementation パターン
│   └── idris2-evm: --contract オプションで対応済み
└── Q3.4: World State は必要か？
    └── はい: storage 状態を読み込んで実行する必要あり
```

### Q4: lazy evm ask への統合ポイントは？

```
Q4: 統合ポイント
├── Q4.1: どのステップで trace を生成するか？
│   └── Step 4 の前 (Pipeline 2 実行前)
├── Q4.2: どこに trace.csv を保存するか？
│   └── projectDir/trace.csv (findTraceFile で検出可能な場所)
├── Q4.3: 失敗時のフォールバックは？
│   └── Pipeline 2 スキップ (現状と同じ)
└── Q4.4: キャッシュ戦略は？
    └── bytecode/calldata が変わったら再生成
```

---

## 3. 実装計画

### Phase 1: idris2-evm テスト実行 (検証)

```bash
# TextDAO bytecode で trace 生成をテスト
cd /Users/bob/code/idris2-textdao
idris2-evm-run --trace-file trace.csv \
  --bytecode $(cat src/build/exec/TextDAO.bin) \
  --calldata 0x371303c0  # propose()
```

**確認事項**:
- [ ] trace.csv が生成されるか
- [ ] フォーマットが Pipeline 2 互換か
- [ ] PC 値が asm.json と対応するか

### Phase 2: lazy evm 統合

**変更ファイル**: `/Users/bob/code/lazy/pkgs/LazyEvm/src/Evm/Ask/Ask.idr`

```idris
-- 新規追加: idris2-evm で trace を生成
generateTrace : String -> String -> String -> IO (Either String String)
generateTrace projectDir bytecodeHex calldataHex = do
  let tracePath = projectDir ++ "/trace.csv"
  -- idris2-evm-run を呼び出し
  result <- system $ "idris2-evm-run --trace-file " ++ tracePath ++
                     " --bytecode " ++ bytecodeHex ++
                     " --calldata " ++ calldataHex
  if result == 0
    then pure $ Right tracePath
    else pure $ Left "idris2-evm-run failed"
```

### Phase 3: 複数コントラクト対応

TextDAO は Proxy パターンを使用:
1. Proxy (0x1000)
2. Dictionary (0x2000)
3. Members, Propose, Vote, Tally (0x3000-0x6000)

```idris
-- 複数コントラクト実行
generateMultiContractTrace : String -> List (String, String, Maybe String) -> String -> IO (Either String String)
generateMultiContractTrace projectDir contracts calldata = do
  let contractArgs = concatMap (\(a,c,s) => " --contract " ++ a ++ ":" ++ c ++
                                            maybe "" (":" ++) s) contracts
  -- idris2-evm-run --contract ... --call 0x1000 --trace-file trace.csv
  ...
```

---

## 4. 技術的判断

### なぜ idris2-evm アプローチが優れているか

| 基準 | anvil 方式 | idris2-evm 方式 |
|------|------------|-----------------|
| **依存関係** | Rust (foundry) | なし (pure Idris2) |
| **ポータビリティ** | 低 (anvil 必要) | 高 (Idris2 のみ) |
| **STI Parity 適合** | 低 | 高 (自己完結) |
| **デバッグ容易性** | 低 | 高 (同じ言語) |
| **保守性** | 外部依存 | 内部制御可能 |

**結論**: idris2-evm 方式を採用

---

## 5. 次のアクション

1. **Phase 1**: idris2-evm --trace-file の動作確認
   - TextDAO bytecode で実行テスト
   - trace.csv フォーマット検証

2. **Phase 2**: lazy evm 統合
   - `generateTrace` 関数追加
   - `runStepWithOpts` で trace 生成呼び出し

3. **Phase 3**: 複数コントラクト対応
   - TextDAO の Proxy パターン対応
   - World State 永続化

---

## 6. 関連ファイル参照

- idris2-evm Interpreter: `/Users/bob/code/idris2-evm/src/EVM/Interpreter.idr`
- idris2-evm Main: `/Users/bob/code/idris2-evm/src/Main.idr`
- TraceParser: `/Users/bob/code/idris2-evm-coverage/src/EvmCoverage/TraceParser.idr`
- YulCoverage: `/Users/bob/code/idris2-evm-coverage/src/EvmCoverage/YulCoverage.idr`
- LazyEvm Ask: `/Users/bob/code/lazy/pkgs/LazyEvm/src/Evm/Ask/Ask.idr`
