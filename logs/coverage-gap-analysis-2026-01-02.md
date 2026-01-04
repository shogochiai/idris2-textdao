# Coverage Gap Analysis - 2026-01-02

## 発見されたギャップ

Q2（TextDAOテスト実行）が実際には完了していないにもかかわらず、完了済みとしてマークされていた。

## 考古学的ツリー

```
coverage-evm-profiler-2026-01-01.md (研究ログ)
├── Q1: Chez Scheme Profiler機構 ✅
├── Q2: TextDAOテスト実行 → idris2-evm-run --profile ❓ UNKNOWN ← ここが問題
├── Q3: .ss.html収集 ✅ (但しidris2-evm自身のテストから)
├── Q4: Parse & Analysis ✅
└── Q5: Coverage結果 26.3% ⚠️ (TextDAOではなくidris2-evmのテストの結果)

coverage-lazy-integration-2026-01-01.md (統合ログ)
├── 前提条件として Q1-Q5 を「✅ 検証済み」としてマーク ← 不正確
├── Q6.1-Q6.5 lazy統合タスク
└── 全て完了済みとしてマーク

実際の状態:
├── idris2-evm-run.ss.html = idris2-evm自身のテストスイートからのプロファイル出力
├── TextDAOバイトコードは一度もidris2-evm-run --profileで実行されていない
└── 26.3%のカバレッジはTextDAOとは無関係
```

## ステータス伝播の流れ

```
Q2 "❓ UNKNOWN" (evm-profiler.md)
       ↓
  別のドキュメントで前提条件として参照
       ↓
Q2 "✅ 検証済み" (lazy-integration.md) ← ギャップ発生
       ↓
  後続タスク全て「完了」としてマーク
       ↓
  実際は未完了のQ2に依存している
```

## 根本原因

1. Q2の調査時に「具体的なコマンド例が見つからない」状態でUNKNOWNとした
2. 別の統合作業でQ1-Q5を前提条件として扱う際、詳細確認せず「検証済み」とマーク
3. 後続の作業はこの誤った前提で進行

## 現在の.ss.htmlの正体

- ファイル: `/Users/bob/code/idris2-evm/idris2-evm-run.ss.html`
- 内容: idris2-evmプロジェクト自身のテストスイート実行結果
- カバレッジ: 26.3% (EVM.* functions)
- TextDAOとの関係: **なし**

## Q2を完了するために必要なこと

1. TextDAOのバイトコードを取得（idris2-yulでコンパイル済み）
2. idris2-evm-runを`--profile`フラグ付きでビルド
3. TextDAOバイトコードをidris2-evm-runで実行
4. 生成された.ss.htmlを収集
5. `lazy evm ask --steps=4`で分析

## 教訓

- 「UNKNOWN」ステータスは明示的に「未完了」として扱う
- 前提条件を参照する際は、オリジナルドキュメントのステータスを確認
- ステータスの伝播時に変換（UNKNOWN→検証済み）しない
