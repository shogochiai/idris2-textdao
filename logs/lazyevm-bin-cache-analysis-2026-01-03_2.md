# LazyEvm Binary Cache Analysis - 2026-01-03 Session 2

## 課題解決ツリー

```
Q9: Pipeline 2 自動検出機能を追加
├── Q9.1: resolveYulPath/resolveAsmJsonPath/resolveTracePath 関数追加 [COMPLETED]
│   └── 実装: Ask.idr lines 695-760
│       ├── findYulFile: src/build/exec/*.yul を検索
│       ├── findAsmJsonFile: foo.yul → foo-asm.json を導出
│       ├── findTraceFile: trace.csv を検索
│       └── resolve*Path: 明示指定 > 自動検出 の優先順位
│
├── Q9.2: runStepWithOptsで自動検出を使用 [COMPLETED]
│   └── 実装: Ask.idr lines 793-809
│       ├── yulPath <- resolveYulPath opts.path opts.yulPath
│       ├── asmJsonPath <- resolveAsmJsonPath yulPath opts.asmJsonPath
│       └── case (yulPath, asmJsonPath) of ... → runStep4YulCoverage
│
└── Q9.3: ビルド・テスト [IN PROGRESS - BLOCKED]
    │
    ├── 問題1: fromMaybe 未定義エラー [SOLVED]
    │   ├── 原因: Data.Maybe の fromMaybe がスコープにない
    │   └── 解決: case 式に変更
    │       let tracePath = case mTracePath of
    │         Just t => t
    │         Nothing => ""
    │
    ├── 問題2: Pipeline 2 デバッグ出力が表示されない [INVESTIGATING]
    │   │
    │   ├── 調査1: ビルドキャッシュ問題
    │   │   ├── idris2 --build で LazyEvm/LazyCli を個別ビルド
    │   │   ├── バイナリタイムスタンプ確認: 08:38 → 08:40 に更新
    │   │   └── 結果: まだデバッグ出力が表示されない
    │   │
    │   ├── 調査2: 文字列がバイナリに含まれているか
    │   │   ├── strings ~/.local/bin/lazy_app/*.so | grep "Pipeline 2"
    │   │   │   └── 結果: 見つからない ❌
    │   │   ├── grep "Pipeline 2" .../LazyCli/build/exec/lazy_app/lazy.ss
    │   │   │   └── 結果: 見つからない ❌
    │   │   └── strings .../LazyEvm/build/ttc/*/Evm/Ask/Ask.ttc
    │   │       └── 結果: "Run Step 4 Pipeline 2..." 見つかった ✓
    │   │
    │   ├── 調査3: pack ビルドシステムの問題
    │   │   ├── 発見: LazyCli/pack.toml に local package 定義あり
    │   │   │   [custom.all.lazyevm]
    │   │   │   type = "local"
    │   │   │   path = "../LazyEvm"
    │   │   │   ipkg = "lazyevm.ipkg"
    │   │   │
    │   │   ├── pack --no-prompt build lazycli 実行
    │   │   │   └── lazyevm を再ビルドした出力あり
    │   │   │
    │   │   └── しかし: 最終バイナリに "Pipeline 2" が含まれない
    │   │
    │   └── 根本原因の仮説
    │       ├── 仮説A: pack がインストール済み lazyevm を優先使用
    │       │   └── ~/.local/state/pack/install/... 内のキャッシュ
    │       │
    │       ├── 仮説B: Chez Scheme コンパイルでの別のキャッシュ
    │       │   └── .so ファイル生成時に古い .ss を参照
    │       │
    │       └── 仮説C: TTC → Scheme 変換時のリンク問題
    │           └── LazyEvm の TTC は新しいが、
    │               LazyCli の Scheme 生成時に古い定義を参照
    │
    └── 次のステップ
        ├── [ ] pack install --with-src lazyevm で強制再インストール
        ├── [ ] ~/.local/state/pack 内の lazyevm キャッシュを削除
        └── [ ] pack の verbose モードでリンク先を確認
```

## 技術詳細

### ファイル配置
```
/Users/bob/code/lazy/
├── pkgs/
│   ├── LazyEvm/
│   │   ├── lazyevm.ipkg
│   │   ├── pack.toml
│   │   ├── src/Evm/Ask/Ask.idr  ← Pipeline 2 実装
│   │   └── build/
│   │       └── ttc/.../Ask.ttc  ← "Pipeline 2" 含む ✓
│   │
│   └── LazyCli/
│       ├── lazycli.ipkg
│       ├── pack.toml  ← lazyevm を local として参照
│       └── build/exec/
│           ├── lazy
│           └── lazy_app/
│               ├── lazy.ss   ← "Pipeline 2" 含まない ❌
│               └── lazy.so   ← "Pipeline 2" 含まない ❌
│
~/.local/bin/
├── lazy
└── lazy_app/
    └── lazy.so  ← 最終バイナリ、"Pipeline 2" 含まない ❌
```

### Yul ファイル配置（自動検出対象）
```
/Users/bob/code/idris2-textdao/
└── src/build/exec/
    ├── textdao-tests.yul        ← 174KB (2026-01-01)
    └── textdao-tests-asm.json   ← 1MB (2026-01-03)
```

### 期待される出力（Pipeline 2 動作時）
```
Running EVM STI Parity analysis...
Target: /Users/bob/code/idris2-textdao
Steps: ["testandcoverage"]

  [Step 4] EVM interpreter coverage (Pipeline 1)... Result: hasGap
    Coverage: 14745/53682 (27%)
    ...

  [Pipeline 2] Debug: yulPath = Just "/Users/bob/.../textdao-tests.yul"
  [Pipeline 2] Debug: asmJsonPath = Just "/Users/bob/.../textdao-tests-asm.json"
  [Pipeline 2] Debug: tracePath = Nothing
  [Pipeline 2] Running Yul coverage with: /Users/bob/.../textdao-tests.yul
  [Step 4] TextDAO source coverage (Pipeline 2)... Result: ...
```

### 実際の出力（現在）
```
Running EVM STI Parity analysis...
Target: /Users/bob/code/idris2-textdao
Steps: ["testandcoverage"]

  [Step 4] EVM interpreter coverage (Pipeline 1)... Result: hasGap
    Coverage: 14745/53682 (27%)
    ...

=== Summary ===
  testandcoverage: hasGap (10 gaps)
```
→ Pipeline 2 関連の出力が一切なし

## 結論

**問題**: Idris2 pack ビルドシステムのキャッシュにより、LazyEvm の最新コードが LazyCli の最終バイナリに反映されていない

**証拠**:
1. LazyEvm の TTC ファイルには "Pipeline 2" 文字列が存在する
2. LazyCli の Scheme ソース (.ss) には "Pipeline 2" 文字列が存在しない
3. 最終バイナリ (.so) にも "Pipeline 2" 文字列が存在しない

**原因の可能性**:
- pack がローカルパッケージの更新を検出できていない
- または pack install 済みの古いバージョンが優先されている

---

## lazy コマンドのアーキテクチャ

### コンパイルパイプライン概要

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Idris2 Chez Scheme Backend Pipeline                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌───────────┐ │
│  │ Idris2 Source│ => │     TTC      │ => │ Scheme (.ss) │ => │ Binary    │ │
│  │   (.idr)     │    │  (type-check)│    │  (code gen)  │    │   (.so)   │ │
│  └──────────────┘    └──────────────┘    └──────────────┘    └───────────┘ │
│         │                   │                   │                   │       │
│         ▼                   ▼                   ▼                   ▼       │
│  [キャッシュ1]         [キャッシュ2]       [キャッシュ3]       [キャッシュ4] │
│   ソース変更検出        build/ttc/         build/exec/*.ss    build/exec/*.so│
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 各ステージの詳細

#### Stage 1: Idris2 ソース → TTC
- **入力**: `*.idr` ファイル
- **出力**: `build/ttc/**/*.ttc` (Type-Checked Tree)
- **キャッシュ**: ファイルタイムスタンプベース
- **問題点**: 依存パッケージの変更が検出されにくい

#### Stage 2: TTC → Scheme
- **入力**: `*.ttc` ファイル群
- **出力**: `build/exec/lazy_app/lazy.ss` (単一の Scheme ファイル)
- **特徴**: 全モジュールが1つの .ss ファイルにインライン化
- **キャッシュ**: 依存 TTC のハッシュ比較
- **問題点**: ローカルパッケージの TTC 更新が伝播しないことがある

#### Stage 3: Scheme → Native Binary
- **入力**: `lazy.ss`
- **出力**: `lazy.so` (Chez Scheme コンパイル済みバイナリ)
- **コンパイル**: `compileChez` ファイルで定義
  ```scheme
  (parameterize ([optimize-level 3] [compile-file-message #f])
    (compile-program "lazy.ss"))
  ```
- **キャッシュ**: .ss のタイムスタンプ
- **問題点**: .ss が更新されていれば正しく再コンパイルされる

### 最終バイナリの構成

```
~/.local/bin/
├── lazy                  ← シェルラッパースクリプト
└── lazy_app/
    ├── lazy.so           ← Chez Scheme ネイティブバイナリ (651KB)
    ├── lazy.ss           ← Scheme ソース (814KB、デバッグ用)
    ├── libidris2_support.dylib
    ├── libonnx_shim.dylib
    └── libvocab_db.dylib
```

#### シェルラッパー (`lazy`) の内容

```sh
#!/bin/sh
# @generated by Idris 0.8.0-95333b3ad, Chez backend

set -e # exit on any error

if [ "$(uname)" = Darwin ]; then
  DIR=$(zsh -c 'printf %s "$0:A:h"' "$0")
else
  DIR=$(dirname "$(readlink -f -- "$0")")
fi
export LD_LIBRARY_PATH="$DIR/lazy_app:$LD_LIBRARY_PATH"
export DYLD_LIBRARY_PATH="$DIR/lazy_app:$DYLD_LIBRARY_PATH"
export IDRIS2_INC_SRC="$DIR/lazy_app"

"$DIR/lazy_app/lazy.so" "$@"
```

**役割**:
1. 実行ディレクトリを解決
2. 動的ライブラリパスを設定 (LD_LIBRARY_PATH / DYLD_LIBRARY_PATH)
3. Idris2 インクルードパスを設定
4. 引数をそのまま lazy.so に渡して実行

### サブコマンド統合アーキテクチャ

```
┌─────────────────────────────────────────────────────────────────┐
│                      LazyCli/Main.idr                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  main : IO ()                                                   │
│  main = do                                                      │
│    args <- getArgs                                              │
│    dispatch (parseArgs args)                                    │
│                                                                 │
│  dispatch : LazyCommand -> IO ()                                │
│  dispatch (CmdCore args)     = CoreCli.dispatch args            │
│  dispatch (CmdEvm args)      = EvmCli.dispatchEvm args   ◄──────┼── lazyevm パッケージ
│  dispatch (CmdPr args)       = PrCli.dispatch args              │
│  dispatch (CmdDepgraph args) = DepgraphCli.dispatch args        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ import
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    LazyEvm/Evm/Cli/Main.idr                     │
├─────────────────────────────────────────────────────────────────┤
│  dispatchEvm : EvmCommand -> IO ()                              │
│  dispatchEvm EvmCmdHelp      = printEvmHelp                     │
│  dispatchEvm (EvmCmdAsk o)   = runAsk o                         │
│  dispatchEvm (EvmCmdInit o)  = runInit o                        │
│  dispatchEvm (EvmCmdRelease o) = runRelease o                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ import
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    LazyEvm/Evm/Ask/Ask.idr                      │
├─────────────────────────────────────────────────────────────────┤
│  runAsk : AskOpts -> IO ()                                      │
│  runStepWithOpts : ...                                          │
│  ← Pipeline 2 実装はここ                                         │
└─────────────────────────────────────────────────────────────────┘
```

### pack パッケージ管理

#### LazyCli/pack.toml でのローカルパッケージ定義

```toml
[custom.all.lazyevm]
type = "local"
path = "../LazyEvm"
ipkg = "lazyevm.ipkg"
```

**動作原理**:
1. `pack build lazycli` 実行時
2. pack は `../LazyEvm` を参照
3. LazyEvm をビルドして TTC を生成
4. LazyCli が LazyEvm の TTC を参照してビルド

### キャッシュ問題の発生ポイント

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    キャッシュ問題マップ                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  [問題点1] LazyEvm のソース変更                                              │
│      │                                                                      │
│      ▼                                                                      │
│  LazyEvm/build/ttc/*.ttc  ← 更新される ✓                                    │
│      │                                                                      │
│      ▼                                                                      │
│  [問題点2] ★ここで断絶 ★                                                    │
│  │  - pack が LazyEvm TTC の更新を検出しない                                │
│  │  - ~/.local/state/pack/install/lazyevm が優先される可能性                │
│  │  - idris2 が古い TTC をリンク                                            │
│      │                                                                      │
│      ▼                                                                      │
│  LazyCli/build/exec/lazy.ss  ← 古い LazyEvm コードが含まれる ❌              │
│      │                                                                      │
│      ▼                                                                      │
│  LazyCli/build/exec/lazy.so  ← 古い LazyEvm コードのまま ❌                  │
│      │                                                                      │
│      ▼                                                                      │
│  ~/.local/bin/lazy_app/lazy.so  ← インストール時にコピー ❌                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 解決策と対処法

#### 1. 完全キャッシュクリア（確実だが時間がかかる）

```bash
# LazyEvm のビルドキャッシュを削除
rm -rf /Users/bob/code/lazy/pkgs/LazyEvm/build

# LazyCli のビルドキャッシュを削除
rm -rf /Users/bob/code/lazy/pkgs/LazyCli/build

# pack のインストールキャッシュを削除
rm -rf ~/.local/state/pack/install/lazyevm

# 再ビルド
cd /Users/bob/code/lazy/pkgs/LazyCli
pack --no-prompt build lazycli

# インストール
pack --no-prompt install lazycli
```

#### 2. 強制再インストール

```bash
pack --no-prompt install --with-src lazyevm
pack --no-prompt build lazycli
pack --no-prompt install lazycli
```

#### 3. 手動バイナリ更新（開発中のワークアラウンド）

```bash
# ビルドディレクトリから直接コピー
rm -rf ~/.local/bin/lazy ~/.local/bin/lazy_app
cp /Users/bob/code/lazy/pkgs/LazyCli/build/exec/lazy ~/.local/bin/
cp -r /Users/bob/code/lazy/pkgs/LazyCli/build/exec/lazy_app ~/.local/bin/
```

#### 4. デバッグ確認方法

```bash
# 文字列がバイナリに含まれているか確認
strings ~/.local/bin/lazy_app/lazy.so | grep "Pipeline 2"
grep "Pipeline 2" ~/.local/bin/lazy_app/lazy.ss

# TTC に含まれているか確認
strings /Users/bob/code/lazy/pkgs/LazyEvm/build/ttc/*/Evm/Ask/Ask.ttc | grep "Pipeline 2"
```

### 根本原因の分析

**なぜキャッシュ問題が頻発するか**:

1. **多段キャッシュ**: Idris2 + Chez Scheme の組み合わせで4段階のキャッシュが存在
2. **パッケージ間依存**: LazyCli → LazyEvm の依存関係でキャッシュ無効化が伝播しにくい
3. **pack の local パッケージ処理**: タイムスタンプベースの比較が不完全な場合がある
4. **インストールキャッシュ**: `~/.local/state/pack/install/` に古いバージョンが残る
5. **Scheme コンパイル**: `.ss` → `.so` の変換でインクリメンタルビルドが効かない

**推奨ワークフロー**:

開発中は以下のコマンドで確実にリビルド:
```bash
cd /Users/bob/code/lazy/pkgs/LazyEvm && rm -rf build
cd /Users/bob/code/lazy/pkgs/LazyCli && rm -rf build
pack --no-prompt build lazycli
# インストールせず直接実行
/Users/bob/code/lazy/pkgs/LazyCli/build/exec/lazy evm ask ...
```