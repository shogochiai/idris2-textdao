# LazyEvm Binary Cache Solution - 2026-01-03 Session 3

## 目標

`make install` 一発で、キャッシュに苦しむことなく最新のコードが `lazy` コマンドに確実に反映されるビルドパイプラインを構築する。

---

## キャッシュ問題の根本原因（復習）

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Idris2 + pack ビルドにおけるキャッシュ層                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Layer 1: Idris2 TTC キャッシュ                                              │
│  └── 場所: pkgs/*/build/ttc/                                                │
│  └── 問題: ソースタイムスタンプで判定、依存パッケージ変更を見逃す             │
│                                                                             │
│  Layer 2: pack インストールキャッシュ                                         │
│  └── 場所: ~/.local/state/pack/install/<idris2-version>/                    │
│  └── 問題: local パッケージでも古いインストール済みを参照する場合がある       │
│                                                                             │
│  Layer 3: Scheme ソース (.ss)                                                │
│  └── 場所: pkgs/LazyCli/build/exec/lazy_app/lazy.ss                         │
│  └── 問題: TTC が更新されても再生成されないことがある                         │
│                                                                             │
│  Layer 4: Chez コンパイル済みバイナリ (.so)                                   │
│  └── 場所: pkgs/LazyCli/build/exec/lazy_app/lazy.so                         │
│  └── 問題: .ss が同一なら .so も更新されない（正常動作）                      │
│                                                                             │
│  Layer 5: インストール先                                                      │
│  └── 場所: ~/.local/bin/lazy, ~/.local/bin/lazy_app/                        │
│  └── 問題: ビルドが更新されてもインストールを忘れる                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 解決策: キャッシュフリービルドパイプライン

### 設計原則

1. **全キャッシュを明示的に削除**: 暗黙のキャッシュ参照を防ぐ
2. **依存パッケージから順番にビルド**: ボトムアップで確実にリビルド
3. **pack を使わず idris2 直接呼び出し**: pack のキャッシュ問題を回避
4. **検証ステップ内蔵**: ビルド後に文字列検索で反映を確認

### ディレクトリ構造

```
/Users/bob/code/lazy/
├── Makefile              ← 既存（拡張する）
├── pkgs/
│   ├── LazyShared/       ← 共有型定義
│   ├── LazyCore/         ← コアライブラリ
│   ├── LazyPr/           ← PRパイプライン
│   ├── LazyDepGraph/     ← 依存グラフ
│   ├── LazyEvm/          ← EVM/Yul ツールキット ★ここを主に変更
│   └── LazyCli/          ← 実行可能バイナリ
└── bin/                  ← ローカルビルド出力
```

---

## 新しい Makefile ターゲット

### 追加するターゲット

```makefile
# === Cache-Free Build (確実にキャッシュを無効化) ===

# 全キャッシュクリア
clean-all: clean
	@echo "Clearing pack install cache..."
	rm -rf ~/.local/state/pack/install/*/lazyshared
	rm -rf ~/.local/state/pack/install/*/lazycore
	rm -rf ~/.local/state/pack/install/*/lazypr
	rm -rf ~/.local/state/pack/install/*/lazydepgraph
	rm -rf ~/.local/state/pack/install/*/lazyevm
	rm -rf ~/.local/state/pack/install/*/lazycli
	@echo "Cache cleared."

# キャッシュフリービルド（確実にリビルド）
build-fresh: clean-all
	@echo "=== Fresh Build (cache-free) ==="
	@echo "[1/6] Building LazyShared..."
	cd pkgs/LazyShared && $(IDRIS) --build lazyshared.ipkg
	cd pkgs/LazyShared && $(IDRIS) --install lazyshared.ipkg
	@echo "[2/6] Building LazyCore..."
	cd pkgs/LazyCore && $(IDRIS) --build lazycore.ipkg
	cd pkgs/LazyCore && $(IDRIS) --install lazycore.ipkg
	@echo "[3/6] Building LazyPr..."
	cd pkgs/LazyPr && $(IDRIS) --build lazypr.ipkg
	cd pkgs/LazyPr && $(IDRIS) --install lazypr.ipkg
	@echo "[4/6] Building LazyDepGraph..."
	cd pkgs/LazyDepGraph && $(IDRIS) --build lazydepgraph.ipkg
	cd pkgs/LazyDepGraph && $(IDRIS) --install lazydepgraph.ipkg
	@echo "[5/6] Building LazyEvm..."
	cd pkgs/LazyEvm && $(IDRIS) --build lazyevm.ipkg
	cd pkgs/LazyEvm && $(IDRIS) --install lazyevm.ipkg
	@echo "[6/6] Building LazyCli..."
	cd pkgs/LazyCli && $(IDRIS) --build lazycli.ipkg
	@mkdir -p bin
	@cp pkgs/LazyCli/build/exec/lazy bin/
	@cp -r pkgs/LazyCli/build/exec/lazy_app bin/ 2>/dev/null || true
	@ln -sf $(ONNX_SHIM_PATH)/$(ONNX_SHIM_LIB) bin/lazy_app/$(ONNX_SHIM_LIB) 2>/dev/null || true
	@echo "=== Build Complete ==="

# キャッシュフリーインストール
install-fresh: build-fresh
	@echo "=== Installing to $(INSTALL_DIR) ==="
	@rm -rf $(INSTALL_DIR)/lazy $(INSTALL_DIR)/lazy_app
	@mkdir -p $(INSTALL_DIR)
	@cp bin/lazy $(INSTALL_DIR)/
	@cp -r bin/lazy_app $(INSTALL_DIR)/
	@ln -sf $(ONNX_SHIM_PATH)/$(ONNX_SHIM_LIB) $(INSTALL_DIR)/lazy_app/$(ONNX_SHIM_LIB) 2>/dev/null || true
	@echo "Installed lazy to $(INSTALL_DIR)"
	@echo ""
	@echo "=== Verification ==="
	@$(INSTALL_DIR)/lazy --version 2>/dev/null || $(INSTALL_DIR)/lazy --help | head -5
	@echo ""
	@echo "Binary timestamp:"
	@ls -la $(INSTALL_DIR)/lazy_app/lazy.so

# LazyEvm のみリビルド（高速版）
evm-fresh:
	@echo "=== Rebuilding LazyEvm only ==="
	rm -rf pkgs/LazyEvm/build
	rm -rf ~/.local/state/pack/install/*/lazyevm
	cd pkgs/LazyEvm && $(IDRIS) --build lazyevm.ipkg
	cd pkgs/LazyEvm && $(IDRIS) --install lazyevm.ipkg
	@echo "=== Rebuilding LazyCli ==="
	rm -rf pkgs/LazyCli/build
	cd pkgs/LazyCli && $(IDRIS) --build lazycli.ipkg
	@mkdir -p bin
	@cp pkgs/LazyCli/build/exec/lazy bin/
	@cp -r pkgs/LazyCli/build/exec/lazy_app bin/ 2>/dev/null || true
	@echo "=== LazyEvm rebuild complete ==="

# LazyEvm のみリビルド + インストール
install-evm: evm-fresh
	@rm -rf $(INSTALL_DIR)/lazy $(INSTALL_DIR)/lazy_app
	@cp bin/lazy $(INSTALL_DIR)/
	@cp -r bin/lazy_app $(INSTALL_DIR)/
	@ln -sf $(ONNX_SHIM_PATH)/$(ONNX_SHIM_LIB) $(INSTALL_DIR)/lazy_app/$(ONNX_SHIM_LIB) 2>/dev/null || true
	@echo "Installed lazy to $(INSTALL_DIR)"

# ビルド検証（特定の文字列がバイナリに含まれているか確認）
verify:
	@echo "=== Build Verification ==="
	@echo "Checking lazy.ss for Pipeline 2..."
	@grep -l "Pipeline 2" pkgs/LazyCli/build/exec/lazy_app/lazy.ss && echo "  ✓ Found in lazy.ss" || echo "  ✗ NOT found in lazy.ss"
	@echo ""
	@echo "Checking installed binary..."
	@strings $(INSTALL_DIR)/lazy_app/lazy.so | grep -q "Pipeline 2" && echo "  ✓ Found in installed lazy.so" || echo "  ✗ NOT found in installed lazy.so"
```

---

## 使い方

### 基本コマンド

```bash
cd /Users/bob/code/lazy

# 完全クリーンビルド + インストール（推奨）
make install-fresh

# LazyEvm のみ変更した場合（高速）
make install-evm

# ビルド検証（特定文字列がバイナリに含まれているか）
make verify
```

### ワークフロー

```
開発者の編集
     │
     ▼
LazyEvm/src/Evm/Ask/Ask.idr を編集
     │
     ▼
make install-evm  ← LazyEvm と LazyCli のみリビルド
     │
     ▼
make verify       ← "Pipeline 2" 等の文字列が含まれるか確認
     │
     ▼
lazy evm ask ...  ← 最新コードで実行
```

---

## diff: Makefile への追加

以下を `/Users/bob/code/lazy/Makefile` の末尾に追加:

```makefile
# =============================================================================
# Cache-Free Build Targets
# =============================================================================

# 全キャッシュクリア（pack インストールキャッシュ含む）
clean-all: clean
	@echo "Clearing pack install cache for lazy packages..."
	rm -rf ~/.local/state/pack/install/*/lazyshared
	rm -rf ~/.local/state/pack/install/*/lazycore
	rm -rf ~/.local/state/pack/install/*/lazypr
	rm -rf ~/.local/state/pack/install/*/lazydepgraph
	rm -rf ~/.local/state/pack/install/*/lazyevm
	rm -rf ~/.local/state/pack/install/*/lazycli
	@echo "All caches cleared."

# キャッシュフリービルド
build-fresh: clean-all
	@echo "=== Fresh Build (all caches cleared) ==="
	@echo "[1/6] Building LazyShared..."
	cd pkgs/LazyShared && $(IDRIS) --build lazyshared.ipkg
	cd pkgs/LazyShared && $(IDRIS) --install lazyshared.ipkg
	@echo "[2/6] Building LazyCore..."
	cd pkgs/LazyCore && $(IDRIS) --build lazycore.ipkg
	cd pkgs/LazyCore && $(IDRIS) --install lazycore.ipkg
	@echo "[3/6] Building LazyPr..."
	cd pkgs/LazyPr && $(IDRIS) --build lazypr.ipkg
	cd pkgs/LazyPr && $(IDRIS) --install lazypr.ipkg
	@echo "[4/6] Building LazyDepGraph..."
	cd pkgs/LazyDepGraph && $(IDRIS) --build lazydepgraph.ipkg
	cd pkgs/LazyDepGraph && $(IDRIS) --install lazydepgraph.ipkg
	@echo "[5/6] Building LazyEvm..."
	cd pkgs/LazyEvm && $(IDRIS) --build lazyevm.ipkg
	cd pkgs/LazyEvm && $(IDRIS) --install lazyevm.ipkg
	@echo "[6/6] Building LazyCli..."
	cd pkgs/LazyCli && $(IDRIS) --build lazycli.ipkg
	@mkdir -p bin
	@cp pkgs/LazyCli/build/exec/lazy bin/
	@cp -r pkgs/LazyCli/build/exec/lazy_app bin/ 2>/dev/null || true
	@ln -sf $(ONNX_SHIM_PATH)/$(ONNX_SHIM_LIB) bin/lazy_app/$(ONNX_SHIM_LIB) 2>/dev/null || true
	@echo "=== Fresh Build Complete ==="

# キャッシュフリーインストール（推奨）
install-fresh: build-fresh
	@echo "=== Installing to $(INSTALL_DIR) ==="
	@rm -rf $(INSTALL_DIR)/lazy $(INSTALL_DIR)/lazy_app
	@mkdir -p $(INSTALL_DIR)
	@cp bin/lazy $(INSTALL_DIR)/
	@cp -r bin/lazy_app $(INSTALL_DIR)/
	@ln -sf $(ONNX_SHIM_PATH)/$(ONNX_SHIM_LIB) $(INSTALL_DIR)/lazy_app/$(ONNX_SHIM_LIB) 2>/dev/null || true
	@echo ""
	@echo "=== Installed ==="
	@echo "Binary: $(INSTALL_DIR)/lazy"
	@ls -la $(INSTALL_DIR)/lazy_app/lazy.so
	@echo ""

# LazyEvm のみリビルド（高速版）
evm-fresh:
	@echo "=== Rebuilding LazyEvm + LazyCli ==="
	rm -rf pkgs/LazyEvm/build
	rm -rf pkgs/LazyCli/build
	rm -rf ~/.local/state/pack/install/*/lazyevm
	cd pkgs/LazyEvm && $(IDRIS) --build lazyevm.ipkg
	cd pkgs/LazyEvm && $(IDRIS) --install lazyevm.ipkg
	cd pkgs/LazyCli && $(IDRIS) --build lazycli.ipkg
	@mkdir -p bin
	@cp pkgs/LazyCli/build/exec/lazy bin/
	@cp -r pkgs/LazyCli/build/exec/lazy_app bin/ 2>/dev/null || true
	@ln -sf $(ONNX_SHIM_PATH)/$(ONNX_SHIM_LIB) bin/lazy_app/$(ONNX_SHIM_LIB) 2>/dev/null || true
	@echo "=== LazyEvm Rebuild Complete ==="

# LazyEvm のみリビルド + インストール
install-evm: evm-fresh
	@rm -rf $(INSTALL_DIR)/lazy $(INSTALL_DIR)/lazy_app
	@mkdir -p $(INSTALL_DIR)
	@cp bin/lazy $(INSTALL_DIR)/
	@cp -r bin/lazy_app $(INSTALL_DIR)/
	@ln -sf $(ONNX_SHIM_PATH)/$(ONNX_SHIM_LIB) $(INSTALL_DIR)/lazy_app/$(ONNX_SHIM_LIB) 2>/dev/null || true
	@echo "Installed lazy to $(INSTALL_DIR)"
	@ls -la $(INSTALL_DIR)/lazy_app/lazy.so

# ビルド検証
verify:
	@echo "=== Build Verification ==="
	@echo "Build output:"
	@ls -la pkgs/LazyCli/build/exec/lazy_app/lazy.so 2>/dev/null || echo "  (not built)"
	@echo ""
	@echo "Installed binary:"
	@ls -la $(INSTALL_DIR)/lazy_app/lazy.so 2>/dev/null || echo "  (not installed)"
	@echo ""
	@echo "String search in lazy.ss:"
	@grep -c "Pipeline 2" pkgs/LazyCli/build/exec/lazy_app/lazy.ss 2>/dev/null && echo "  ✓ 'Pipeline 2' found" || echo "  ✗ 'Pipeline 2' NOT found"
```

---

## なぜこれで解決するか

### 問題と対策の対応

| 問題 | 対策 |
|------|------|
| TTC キャッシュが古い | `rm -rf pkgs/*/build` で強制削除 |
| pack インストールキャッシュ | `rm -rf ~/.local/state/pack/install/*/lazy*` |
| .ss が再生成されない | ビルドディレクトリごと削除して強制再生成 |
| インストール先が古い | `rm -rf $(INSTALL_DIR)/lazy*` で削除後コピー |
| pack の依存解決問題 | pack を使わず `idris2 --build` 直接使用 |

### ビルド順序の保証

```
LazyShared (依存なし)
     ↓
LazyCore (LazyShared に依存)
     ↓
LazyPr, LazyDepGraph (LazyShared, LazyCore に依存)
     ↓
LazyEvm (LazyCore に依存)
     ↓
LazyCli (全パッケージに依存)
```

各ステップで `--install` を実行し、次のパッケージが最新の TTC を参照できるようにする。

---

## トラブルシューティング

### Q: ビルドに失敗する

```bash
# 依存関係を確認
make clean-all
make build-fresh
```

### Q: "Pipeline 2" がバイナリに含まれない

```bash
# 検証
make verify

# 含まれていない場合
grep "Pipeline 2" pkgs/LazyEvm/src/Evm/Ask/Ask.idr
# → ソースに存在するか確認

strings pkgs/LazyEvm/build/ttc/*/Evm/Ask/Ask.ttc | grep "Pipeline 2"
# → TTC に存在するか確認

grep "Pipeline 2" pkgs/LazyCli/build/exec/lazy_app/lazy.ss
# → Scheme ソースに存在するか確認
```

### Q: 外部ライブラリ (idris2-coverage 等) を更新した

```bash
# 外部ライブラリも含めて完全リビルド
rm -rf ~/.local/state/pack/install/*/idris2-coverage
rm -rf ~/.local/state/pack/install/*/idris2-yul-coverage
rm -rf ~/.local/state/pack/install/*/idris2-evm-coverage
make install-fresh
```

---

## まとめ

| コマンド | 用途 | 所要時間 |
|----------|------|----------|
| `make install-fresh` | 完全クリーンビルド + インストール | 〜5分 |
| `make install-evm` | LazyEvm のみ変更時 | 〜1分 |
| `make verify` | ビルド検証 | 即時 |
| `make clean-all` | 全キャッシュ削除のみ | 即時 |

**推奨**: LazyEvm を変更したら `make install-evm && make verify` を実行。

---

## 動作確認結果 (2026-01-03 09:20)

### `make install-evm` 実行ログ

```
=== Rebuilding LazyEvm + LazyCli ===
rm -rf pkgs/LazyEvm/build
rm -rf pkgs/LazyCli/build
rm -rf ~/.local/state/pack/install/*/lazyevm
cd pkgs/LazyEvm && idris2 --build lazyevm.ipkg
 1/16: Building Integration.Tests.AllTests
 ...
16/16: Building EvmKit.EvmKit
cd pkgs/LazyEvm && idris2 --install lazyevm.ipkg
Installing ... to ~/.local/state/pack/install/.../lazyevm-0/
cd pkgs/LazyCli && idris2 --build lazycli.ipkg
1/2: Building LazyCli.PolicyBundle
2/2: Building LazyCli.Main
Now compiling the executable: lazy
=== LazyEvm Rebuild Complete ===
Installed lazy to /Users/bob/.local/bin
-rwxr-xr-x  1 bob  staff  679597 Jan  3 09:20 /Users/bob/.local/bin/lazy_app/lazy.so
```

### `make verify` 実行結果

```
=== Build Verification ===
Build output:
-rwxr-xr-x  1 bob  staff  679597 Jan  3 09:20 pkgs/LazyCli/build/exec/lazy_app/lazy.so

Installed binary:
-rwxr-xr-x  1 bob  staff  679597 Jan  3 09:20 /Users/bob/.local/bin/lazy_app/lazy.so

String search in lazy.ss:
3
  ✓ 'Pipeline 2' found
```

### 結論

- `make install-evm` によりキャッシュを確実にクリアしてリビルド成功
- `make verify` により "Pipeline 2" 文字列が lazy.ss に含まれていることを確認
- キャッシュフリービルドパイプラインが正常に動作

### 追加修正 (2026-01-03 09:48)

`libvocab_db.dylib` の依存が不足していた問題を修正:

```
Exception: (while loading libvocab_db.dylib) dlopen(libvocab_db.dylib, 0x0002): tried: ...
```

**修正内容**:
- Makefile に `VOCAB_DB_PATH` と `VOCAB_DB_LIB` 変数を追加
- `install`, `install-fresh`, `install-evm` ターゲットに `libvocab_db.dylib` のシンボリックリンクを追加

**Pipeline 2 動作確認**:
```
[Pipeline 2] Debug: yulPath = Just "/Users/bob/code/idris2-textdao/src/build/exec/textdao-tests.yul"
[Pipeline 2] Debug: asmJsonPath = Just "/Users/bob/code/idris2-textdao/src/build/exec/textdao-tests-asm.json"
[Pipeline 2] Debug: tracePath = Nothing
[Pipeline 2] Running Yul coverage with: ...
```
