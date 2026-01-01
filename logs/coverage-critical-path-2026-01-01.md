# Coverage Critical Path - 2026-01-01

## Goal
`lazy evm ask --steps=4` で idris2-textdao の EVM カバレッジを計測する

---

## Critical Path (直列依存チェーン)

各ステップは前のステップが成功しないと意味がない。

```
Q1 ─────▶ Q2 ─────▶ Q3 ─────▶ Q4 ─────▶ Q5 ─────▶ Q6
Chez       .ss.html  .ss.html   dumpcases  coverage   lazy
profile    生成      解析可能   対応       計算       統合
動作       確認      確認       確認       確認       確認

Status:   ✅         ✅         ✅         ✅         ✅         ⏳
```

---

## Q1: Idris2 --profile で Chez profiler が動作するか？

**Status**: ✅ PASSED

**検証結果** (2026-01-01):

### --dumpcases (静的分岐解析): ✅ 動作
```bash
$ idris2 --dumpcases /tmp/dump.txt --build Test.ipkg
Dumping case trees to /tmp/dump.txt

$ cat /tmp/dump.txt
Test.main = [{ext:0}]: (Prelude.IO.prim__putStr ["hello\n", !{ext:0}])
Prelude.EqOrd.compare = [...]: (%case ... [(%constcase 1 0), (%constcase 0 ...)] ...)
```
**Note**: `--dumpcases` は `--help` に表示されない undocumented flag

### --coverage: ❌ 存在しない
```bash
$ idris2 --cg chez --coverage Test.idr
Error: Unknown flag --coverage
```

### --profile: ✅ 動作確認済み
```bash
$ idris2 --profile --build Test.ipkg
$ ./build/exec/test-exe
hello

$ ls *.html
profile.html      test-exe.ss.html

$ grep -o 'title="[^"]*"' test-exe.ss.html | head -5
title="line 5 char 1 count 1"
title="line 5 char 7 count 1"
title="line 10 char 62 count 1"
```

**発見**:
- `--profile` でビルド → 実行時に `.ss.html` と `profile.html` が自動生成
- `.ss.html` に `line X char Y count Z` 形式でヒットカウント記録
- idris2-coverage の ProfileParser.idr でパース可能な形式

**Q1 結論: ✅ PASSED - 両方の基盤技術が動作**
- `--dumpcases`: 静的分岐解析 (denominator)
- `--profile` + `.ss.html`: 動的ヒット計測 (numerator)

---

## Q2: idris2-evm を --profile でビルド → 実行 → .ss.html 生成されるか？

**Status**: ✅ PASSED

**検証結果** (2026-01-01):
```bash
$ cd /Users/bob/code/idris2-evm
$ idris2 --profile --dumpcases /tmp/idris2-evm-dump.txt --build idris2-evm.ipkg
Dumping case trees to /tmp/idris2-evm-dump.txt

$ ./build/exec/idris2-evm-run --bytecode 0x6001600055 --calldata 0x
Result: SUCCESS

$ ls *.html
profile.html  idris2-evm-run.ss.html

$ grep -c 'count [1-9]' idris2-evm-run.ss.html
9922   # 約10,000行が実行された
```

**発見**:
- dumpcases: 684行 (EVM opcodes含む)
- .ss.html: 約55,000行中9,922行が実行 (約18% expression coverage)

---

## Q3: .ss.html ファイルは解析可能な形式か？

**Status**: ✅ PASSED

**検証結果** (2026-01-01):
```bash
$ grep -o '<span class=pc[0-9]* title="[^"]*">[^<]*</span>' idris2-evm-run.ss.html | head -3
<span class=pc2 title="line 5 char 1 count 1">(case </span>
<span class=pc2 title="line 5 char 7 count 1">(</span>
<span class=pc2 title="line 5 char 8 count 1">machine-type</span>
```

**形式確認**:
- `<span class=pcN title="line L char C count N">...</span>` 形式
- ProfileParser.idr の `parseSpan` で解析可能
- 行番号、文字位置、実行回数が正確に抽出可能

---

## Q4: dumpcases 出力から canonical branches を抽出できるか？

**Status**: ✅ PASSED

**検証結果** (2026-01-01):
```bash
$ grep 'EVM.MultiInterpreter.executeSimple' /tmp/idris2-evm-dump.txt | head -1
EVM.MultiInterpreter.executeSimple = [...]: (%case !{arg:0} [
  (%concase EVM.Opcodes.ADD Just 1 [] ...),
  (%concase EVM.Opcodes.MUL Just 2 [] ...),
  ...80+ opcode cases...
])
```

**形式確認**:
- `%case !{arg} [(%concase Name ...)]` 形式
- DumpcasesParser.idr で解析可能
- 統計: 299 %case, 134 %constcase, 216 %concase
- idris2-coverage実行結果: 1544 canonical branches for idris2-evm

---

## Q5: coverage = hits / canonical が計算できるか？

**Status**: ✅ PASSED

**検証結果** (2026-01-01):
```bash
$ cd /Users/bob/code/idris2-coverage
$ pack run idris2-coverage.ipkg -- /Users/bob/code/idris2-evm
# Coverage Report
canonical:          1544   # reachable branches in main binary
excluded_void:      0
bugs:               0
## Excluded from Denominator:
  standard_library:   465

$ pack run idris2-coverage.ipkg -- /Users/bob/code/idris2-coverage --json
Running 94 tests...
[PASS] ... (94 tests passed)
{
  "summary": { "total_canonical": 462, ... },
  "high_impact_targets": [
    { "kind": "untested_canonical", "funcName": "...", "severity": "Inf" },
    ...
  ]
}
```

**確認事項**:
- 静的解析: dumpcases → canonical branches カウント
- 動的解析: .ss.html → executed count
- 結合: TestCoverage レコードで計算
- JSON出力: high_impact_targets で優先度付きレポート

---

## Q6: lazy evm ask --steps=4 から呼び出せるか？

**Status**: ⏳ PENDING (次のアクション)

**Key Finding (Q5で発見)**:
idris2-textdao は `%foreign "evm:sstore"` FFI を使用しているため、
標準の Chez backend でビルドできない。

**2つのアプローチ**:

### A: idris2-evm インタプリタの分岐カバレッジ (推奨)
```
idris2-evm --profile --bytecode <TextDAO.bin> --calldata <test>
→ .ss.html に EVM Interpreter の分岐カバレッジが記録される
→ "どの EVM オペコードがテストされたか" を計測
```

### B: idris2-textdao の Idris コードカバレッジ
```
idris2-yul --coverage で TextDAO → Yul → bytecode
→ Yul レベルでの分岐カバレッジ (idris2-yul側の実装が必要)
```

**推奨次アクション**:
1. LazyEvm の Ask.idr を確認
2. idris2-coverage の API を呼び出す統合コードを実装
3. idris2-evm の .ss.html パースと組み合わせ

**依存**: Q5 成功 ✅

**検証方法**:
```bash
cd /Users/bob/code/lazy/pkgs/LazyEvm
# Check current Ask.idr implementation
# Integrate idris2-coverage API
```

**現在の状態** (2026-01-01):
- ✅ LazyEvm/src/Evm/Ask/Ask.idr に統合コード実装済み
- ✅ idris2-evm-coverage library が存在 (/Users/bob/code/idris2-evm-coverage)
- ✅ pack.toml に依存関係設定済み
- ⚠️ LazyCli に pack.toml が未設定 (全パッケージのローカル依存解決が必要)

**残タスク**:
1. LazyCli用のpack.toml作成 (すべてのローカル依存をマッピング)
2. `pack run lazycli.ipkg -- evm ask --steps=4` でテスト実行

---

## 検証順序と所要時間見積

| Step | 質問 | 依存 | 見積時間 | Blocker度 |
|------|------|------|----------|-----------|
| 1 | Q1: Chez profiler | なし | 10min | ★★★★★ |
| 2 | Q4: dumpcases | なし | 15min | ★★★★☆ |
| 3 | Q2: idris2-evm coverage build | Q1 | 20min | ★★★★☆ |
| 4 | Q3: .ssi 形式確認 | Q2 | 10min | ★★★☆☆ |
| 5 | Q5: coverage 計算 | Q3,Q4 | 30min | ★★★☆☆ |
| 6 | Q6: lazy 統合 | Q5 | 30min | ★★☆☆☆ |

**推奨**: Q1 と Q4 を並行実行（両方独立）

---

## Decision Tree

```
Q1: Chez profiler 動作?
├── NO → Idris2 バージョン確認 / 別 backend 検討
└── YES
    │
    Q2: idris2-evm --coverage ビルド?
    ├── NO → pack vs idris2 直接ビルド比較
    └── YES
        │
        Q3: .ssi 解析可能?
        ├── NO → Chez 出力形式調査 / ProfileParser 修正
        └── YES
            │
            Q4: dumpcases 解析可能? (並行実行可)
            ├── NO → dumpcases 形式調査 / DumpcasesParser 修正
            └── YES
                │
                Q5: coverage 計算OK?
                ├── NO → SchemeMapper / Aggregator 修正
                └── YES
                    │
                    Q6: lazy 統合OK?
                    ├── NO → Ask.idr 修正
                    └── YES → ✅ 完了
```

---

## Immediate Action

**今すぐ実行**: Q1 (最もクリティカル、10分で判明)

```bash
echo 'main : IO ()
main = putStrLn "hello"' > /tmp/Test.idr

idris2 --cg chez --coverage /tmp/Test.idr -o test-cov
./build/exec/test-cov
find ~/.idris2 -name "*.ssi" -mmin -1
```
