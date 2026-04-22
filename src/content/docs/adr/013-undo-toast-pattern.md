---
title: "ADR 013: 破壊的操作における Undo トーストパターンの採用"
---


- Status: Accepted
- Date: 2026-04-19
- Deciders: @hiro-minami

## Context

OKR ツリーは Objective → Key Result → Task の親子階層を持ち、Objective の削除は配下の全 KR・Task をカスケード削除する。楽観的更新により UI 上も即座に消えるため、誤操作時に失うデータ量が大きい。

破壊的操作に対する UX パターンとして、ユーザーの意図を確認しつつフロー（操作の流れ）を妨げない手段が求められる。

## Decision

Objective の削除において、`window.confirm()` ではなく **Undo トースト（遅延実行 + 取り消し）パターン** を採用する。

### フロー

1. ✕ ボタンクリック → キャッシュから即座に除外（楽観的更新）
2. プログレスバー付きトースト表示（5 秒カウントダウン）
3. 「元に戻す」クリック → キャッシュ復元、API 未呼出
4. タイムアウト → 実際に DELETE API を呼び出す

### 実装構成

- `useUndoableDeleteObjective`: 遅延削除スケジューリング + キャッシュ操作 + undo ロジック
- `UndoToast`: プログレスバー付き汎用トーストコンポーネント（`shared/components/`）
- `ObjectiveList` がトースト表示を管理し、`ObjectiveCard` には `onDelete` コールバックを渡す

### 適用範囲

- **Objective 削除**: カスケード削除の影響が大きいため必須
- **Key Result / Task 削除**: 影響範囲が限定的なため即時削除（楽観的更新 + ロールバック）を維持

## Alternatives Considered

### window.confirm() によるブロッキング確認

ブラウザネイティブの確認ダイアログ。実装は最小限だが、モーダルがフローを中断し UX が悪い。スタイリングのカスタマイズ不可。最初に採用したが、undo パターンに移行した。

### カスタムモーダルダイアログ

shadcn/ui の AlertDialog 等でカスタム確認 UI を表示する方式。スタイリングは統一できるが、依然としてフローを中断する点は同じ。操作の取り消しができない（確定後は不可逆）。

## Consequences

### Positive

- 操作フローを中断しない（ノンブロッキング）
- 誤操作から 5 秒以内であれば完全に復元できる（API 未呼出のため副作用なし）
- プログレスバーで残り時間を視覚的にフィードバック
- `UndoToast` は汎用コンポーネントとして他の破壊的操作にも再利用可能

### Negative

- 5 秒経過後は取り消し不可（サーバー側に soft-delete があるため管理者レベルでは復元可能）
- タイマー管理が必要で、`confirm()` より実装が複雑
- ページ遷移やブラウザ閉じ時に pending な削除が失われる可能性がある（未保存の操作はキャンセル扱い）

---

## Addendum (2026-04-21)

Dogfooding の結果、KR / Task の即時削除も誤操作リスクが無視できないと判断し、Undo トーストの適用範囲を**全エンティティ（Objective / Key Result / Task）**に拡大した。

各 feature に `useUndoableDelete{Entity}` フックを配置し、`UndoToast` コンポーネントを共有する構成は変更なし。元の ADR で「影響範囲が限定的なため即時削除を維持」としていた KR / Task にも同じパターンを適用した。
