# Pipeline 2 Library API 統合方針

**日付**: 2026-01-03
**目的**: idris2-evm を Library API として統合し、anvil 依存を完全排除

---

## 1. 方針決定

### 1.1 ユーザー要件

1. **No fallback, fail fast**: Pipeline 1 を完全削除
2. **Library API 統合**: サブプロセスではなくライブラリとして idris2-evm を利用
3. **型安全性**: ファイルシステム依存を排除
4. **CLI 簡素化**: `--steps=4` 関連の引数を削除、`--modules` は維持

### 1.2 アーキテクチャ決定

```
Before (サブプロセス方式):
lazy evm ask
  └── system("idris2-evm-run --trace-file trace.csv ...")
        └── trace.csv (ファイル I/O)
              └── TraceParser.parseTraceFile

After (Library API 方式):
lazy evm ask
  └── EVM.Interpreter.executeWithTrace (直接呼び出し)
        └── List TraceEntry (メモリ内)
              └── TraceEntry 変換 (型安全)
```

---

## 2. 技術詳細

### 2.1 idris2-evm Library API

**場所**: `/Users/bob/code/idris2-evm/src/EVM/Interpreter.idr`

```idris
-- 利用する関数
executeWithTrace : Bytecode -> List Bits8 -> Nat -> Storage -> (Result, List TraceEntry)

-- TraceEntry 型
record TraceEntry where
  constructor MkTraceEntry
  stepNum : Nat
  pc : Nat
  opcode : Bits8
  opcodeName : String
  stackDepth : Nat
```

### 2.2 TraceEntry 変換

idris2-evm の TraceEntry → idris2-evm-coverage の TraceEntry:

```idris
-- idris2-evm (ソース)
EVM.Interpreter.TraceEntry:
  opcode : Bits8

-- idris2-evm-coverage (ターゲット)
EvmCoverage.TraceParser.TraceEntry:
  opcode : Nat

-- 変換
convertEntry : EVM.Interpreter.TraceEntry -> EvmCoverage.TraceParser.TraceEntry
convertEntry e = MkTraceEntry
  e.stepNum
  e.pc
  (cast e.opcode)  -- Bits8 → Nat
  e.opcodeName
  e.stackDepth
```

### 2.3 パッケージ依存

```
lazyevm.ipkg:
  depends = base, contrib, idris2-coverage, lazycore,
            idris2-yul-coverage, idris2-evm-coverage, idris2-evm
                                                      ^^^^^^^^^ 追加
```

---

## 3. CLI 変更

### 3.1 削除するオプション

| オプション | 理由 |
|-----------|------|
| `--ss-html=` | Pipeline 1 専用 |
| `--yul=` | 自動解決に移行済み |
| `--asm-json=` | 自動解決に移行済み |
| `--trace=` | Library API で不要 |

### 3.2 維持するオプション

| オプション | 用途 |
|-----------|------|
| `--steps=` | 実行ステップ選択 |
| `--format=` | 出力形式 |
| `--modules=` | テストモジュール指定 |

### 3.3 AskOpts 最終形

```idris
record AskOpts where
  constructor MkAskOpts
  path : String
  steps : List Nat
  format : String
  modules : List String
```

---

## 4. Ask.idr 変更計画

### 4.1 削除するコード

- Pipeline 1 関連のすべてのコード
- `findTraceFile` (ファイル検索不要)
- trace.csv 読み込みロジック
- fallback 処理

### 4.2 追加するコード

```idris
import EVM.Interpreter as EVM
import EVM.Bytecode

-- bytecode から直接 trace を生成
generateTrace : String -> List Bits8 -> IO (Either String (List EvmCoverage.TraceParser.TraceEntry))
generateTrace bytecodeHex calldata = do
  let bytecode = parseBytecode bytecodeHex
  let (result, traces) = EVM.executeWithTrace bytecode calldata 10000 emptyStorage
  pure $ Right $ map convertEntry traces
```

### 4.3 エラー処理 (fail fast)

```idris
runStep4 : AskOpts -> IO (Either String CoverageResult)
runStep4 opts = do
  bytecode <- resolveBytecode opts.path
  case bytecode of
    Nothing => pure $ Left "ERROR: bytecode not found (fail fast)"
    Just bc => do
      traces <- generateTrace bc []
      -- coverage 計算続行
```

---

## 5. 実装ステップ

1. ✅ lazyevm.ipkg に idris2-evm 依存追加
2. ✅ Options.idr 簡素化 (modules 維持)
3. ⏳ Ask.idr 修正
   - Pipeline 1 コード削除
   - Library API import
   - generateTrace 実装
   - fail fast エラー処理
4. ⏳ ビルド・テスト

---

## 6. 利点

| 項目 | Before | After |
|------|--------|-------|
| 型安全性 | 低 (String) | 高 (TraceEntry 型) |
| ファイル依存 | あり (trace.csv) | なし |
| エラー処理 | fallback | fail fast |
| パフォーマンス | プロセス起動 | 直接呼び出し |
| デバッグ | 困難 | 容易 (同一言語) |
