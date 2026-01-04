# lazy evm ask PC→関数マッピング分析

**日時**: 2026-01-03
**状態**: Solc FFI実装完了、source map生成成功

## 進捗 (2026-01-03 更新)

### 実装完了: Compiler.EVM.Solc モジュール

**ファイル**: `/Users/bob/code/idris2-yul/src/Compiler/EVM/Solc.idr`

機能:
- `compileYulWithSourceMap` - Yulをコンパイルしてsource map付きで返す
- `parseSourceMap` - solc source mapフォーマットを解析
- `pcToSourceOffset` - PC indexからソースオフセットを取得

テスト結果:
```
Bytecode length: 46688
Parsed 14964 source map entries
Entries with offset > 40000: 9901 (TextDAO関数領域)
```

---

---

## 課題解決ツリー

```
Goal: lazy evm ask --steps=4 で正しいカバレッジを計測する

現状: Coverage 0/54 (0%)
├── 分母: 54 ✅ 正しい (TextDAO.Functions.* の関数数)
├── 分子: 0  ✗ おかしい
└── トレースエントリ: 4980 (存在するがマッピングされない)

Q1: トレースは正しく生成されているか？ ✅ PASSED
├── 4980エントリ存在
├── PC値: 0, 2, 4, 5, 7, ... (連続的)
└── executeWithTrace は動作している

Q2: asm.json のPC計算は正しいか？ ✅ FIXED
├── 問題: opcodeSize が全PUSH を33バイトと計算
├── 修正: opcodeSizeWithValue で value長から計算
│   ├── PUSH [tag] → 3 bytes
│   ├── PUSH #[$], PUSH [$] → 33 bytes
│   └── PUSH value → 1 + len(value)/2 bytes
└── 結果: PC=0,2,4,5... がトレースと一致

Q3: YulMapper のオフセット計算は正しいか？ ✅ FIXED
├── 問題: lineNum * 80 という概算
├── 修正: zipWithByteOffset で累積バイトオフセット計算
│   └── offset + length(line) + 1 (改行)
└── 結果: 実際のファイルバイト位置と一致

Q4: PC→Yulオフセット→関数 のマッピングは動作するか？ ✗ FAILED
├── トレースPC (0-100): begin offset 236-3199 にマップ
├── Production関数: begin offset 43557+ から開始
└── ギャップ: 40000+ バイトの差

Q5: なぜトレースがProduction関数に到達しないか？ ⏳ ROOT CAUSE
├── 仮説A: テストランナーがProduction関数を呼んでいない
│   └── textdao-tests-runtime.yul は main() を直接呼び出し
│       └── calldataを無視して AllTests.main を実行
│
├── 仮説B: Production関数はインライン化されている
│   └── Yul最適化でコードが埋め込まれた可能性
│
└── 仮説C: asm.json の begin/end がYulソースと対応していない
    ├── source: -1 (全16733命令)
    └── solc がソースマッピングを生成していない

Q6: 過去に解決したソースマッピングはどこか？ ❓ UNKNOWN
└── ユーザー曰く「過去に一度解決した記憶がある」
    └── 検索中...
```

---

## デバッグ出力の分析

### トレースPC vs ASMマッピング

```
Hit instructions (PC 0-100): 79個
Begin offset range: 236 - 3199

Sample mappings:
  PC=0  → begin=247
  PC=2  → begin=243
  PC=4  → begin=88
  PC=5  → begin=88
  ...
  PC=100 → begin=3199
```

### Yul関数のオフセット範囲

```
Infrastructure (低オフセット):
  mk_closure [226..5226]
  require [3456..8456]
  ...

Production関数 (高オフセット):
  TextDAO_Functions_Members_u_addMember [43557..48557]
  TextDAO_Functions_Members_u_isMember [44123..49123]
  TextDAO_Functions_Propose_u_propose [52340..57340]
  ...
```

### 問題の図解

```
Yul Source File (bytes):
0                    43557              100000+
|--------------------|--------------------|
   Infrastructure       Production
   (mk_closure等)       (TextDAO.Functions.*)

Trace PCs map to:
0        3199
|--------|
  ここだけ

→ Production関数領域に到達していない
```

---

## 修正済みコード

### AsmJsonParser.idr - PC計算修正

```idris
divNat : Nat -> Nat -> Nat
divNat _ Z = Z
divNat n m = go n m Z
  where
    go : Nat -> Nat -> Nat -> Nat
    go Z _ acc = acc
    go n m acc = if n < m then acc else go (n `minus` m) m (S acc)

opcodeSizeWithValue : String -> Maybe String -> Nat
opcodeSizeWithValue name mValue =
  if isPrefixOf "PUSH" name
    then case name of
           "PUSH [tag]" => 3
           "PUSH #[$]" => 33
           "PUSH [$]" => 33
           _ => case mValue of
                  Just val => 1 + divNat (length val) 2
                  Nothing => 1
    else if name == "tag" || name == "JUMPDEST"
           then 1
           else 1
```

### YulMapper.idr - バイトオフセット修正

```idris
zipWithByteOffset : Nat -> List String -> List (Nat, String)
zipWithByteOffset _ [] = []
zipWithByteOffset offset (x :: xs) =
  (offset, x) :: zipWithByteOffset (offset + length x + 1) xs

parseYulLine : (Nat, String) -> Maybe YulFunc
parseYulLine (byteOffset, line) =
  case extractFuncName (trim line) of
    Nothing => Nothing
    Just funcName =>
      let startOff = byteOffset
          endOff = byteOffset + 5000
      in Just $ MkYulFunc funcName startOff endOff
```

### Ask.idr - calldata追加 (PoC)

```idris
generateTrace : String -> IO (Either String (List EvmTrace.TraceEntry))
generateTrace bytecodeHex = do
  case EvmBytecode.fromHex bytecodeHex of
    Nothing => pure $ Left "Invalid bytecode hex"
    Just bytecode =>
      let calldata = [0x99, 0x70, 0x72, 0xf7]  -- getMemberCount selector
          (_, evmTrace) = EvmInterp.executeWithTrace bytecode calldata 100000 EvmStorage.empty
      in pure $ Right $ convertTraceEntries evmTrace
```

---

## 次のアクション候補

### Option A: solcにソースマップを生成させる

```bash
# 現状
solc --strict-assembly --bin textdao-tests.yul

# 必要
solc --strict-assembly --bin --combined-json srcmap textdao-tests.yul
# または
solc --strict-assembly --bin --asm-json --debug-info location textdao-tests.yul
```

問題: source: -1 は「ソース情報なし」を意味する

### Option B: Yulソースから直接関数境界を計算

現在のアプローチを改良:
1. `function TextDAO_...` の開始位置を正確に取得 ✅ 済
2. 対応する `}` で終了位置を計算 ⏳ 未実装
3. begin/end ではなくYul関数名でマッチング

### Option C: テストランナーの構造を変更

textdao-tests-runtime.yul が calldata を使うように:
```yul
// Before
pop(TextDAO_Tests_AllTests_u_main(0))

// After
switch selector()
case 0x12345678 { pop(TextDAO_Functions_Members_u_addMember(...)) }
case 0xabcdef01 { pop(TextDAO_Functions_Propose_u_propose(...)) }
...
```

### Option D: asm.json の begin/end を信頼せず、PC範囲で直接マッチ

1. トレースから実行されたPC範囲を取得
2. asm.json から各関数の開始PC (JUMPDEST) を特定
3. 関数の終了PC (次のJUMPDESTまたはSTOP) を特定
4. PC範囲でカバレッジ計算

---

## 関連ファイル

| ファイル | 役割 |
|---------|------|
| `/Users/bob/code/lazy/pkgs/LazyEvm/src/Evm/Ask/Ask.idr` | lazy evm ask 実装 |
| `/Users/bob/code/idris2-evm-coverage/src/EvmCoverage/YulMapper.idr` | Yul→Idris関数マッピング |
| `/Users/bob/code/idris2-evm-coverage/src/EvmCoverage/AsmJsonParser.idr` | asm.json→PCマッピング |
| `/Users/bob/code/idris2-evm-coverage/src/EvmCoverage/YulCoverage.idr` | カバレッジ計算統合 |
| `/Users/bob/code/idris2-textdao/src/build/exec/textdao-tests.yul` | Yulソース |
| `/Users/bob/code/idris2-textdao/src/build/exec/textdao-tests-asm.json` | ASMマッピング |

---

## 過去ログ参照

- `idris2-evm-coverage-numerator-analysis-2026-01-03_5.md` - 分子問題の初期分析
- `coverage-gap-analysis-2026-01-03.md` - Phase 1-2 実装記録
- `lazyevm-pipeline-2-replacement-analysis-2026-01-03_3.md` - パイプライン分析
