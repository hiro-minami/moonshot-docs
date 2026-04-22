---
layout: default
title: "ADR 020: Feature 間コンポーネント合成のパターン"
---

# ADR 020: Feature 間コンポーネント合成のパターン

- Status: Accepted
- Date: 2026-04-21
- Deciders: Lead Engineer

## Context

ADR 001 で採用した Feature-Sliced Design (FSD) では `features/xxx/` から
`features/yyy/` を直接 import することを禁止している。しかし PoC 実装の過程で
以下の 2 箇所に feature 間の直接 import が生じていた。

1. `features/objectives/components/objective-card.tsx` → `features/key-results/components/key-result-list.tsx`
2. `features/key-results/components/key-result-item.tsx` → `features/tasks/components/task-list.tsx`

いずれも親エンティティの UI が子エンティティの一覧を内部に表示する必要があり、
「ドメイン的に正しいがモジュール境界を侵害する」構造であった。

## Decision

**ページ層（`app/`）から render prop / children で依存を注入するパターン**を
標準とする。

### 仕組み

1. 子を表示する feature コンポーネントは `children` または `render*` prop で
   スロットを公開する
2. `app/` のページコンポーネント（全 feature を知ってよい最上位層）が
   render prop 経由で子 feature のコンポーネントを注入する
3. feature コンポーネント同士は互いの存在を知らない

### コード例

```tsx
// app/dashboard/page.tsx（最上位層 — 全 feature を知ってよい）
import { ObjectiveList } from "@/features/objectives/components/objective-list";
import { KeyResultList } from "@/features/key-results/components/key-result-list";
import { TaskList } from "@/features/tasks/components/task-list";

export default function DashboardPage() {
  return (
    <ObjectiveList
      renderKeyResults={(objectiveId) => (
        <KeyResultList
          objectiveId={objectiveId}
          renderTasks={(keyResultId) => <TaskList keyResultId={keyResultId} />}
        />
      )}
    />
  );
}
```

```tsx
// features/objectives/components/objective-card.tsx
// ❌ import { KeyResultList } from "@/features/key-results/..."; ← 禁止
export function ObjectiveCard({ objective, onDelete, children }: {
  objective: Objective;
  onDelete: (...) => void;
  children?: React.ReactNode;  // ← KR リストはここに注入される
}) {
  return (
    <Card>
      <CardHeader>...</CardHeader>
      <CardContent>{children}</CardContent>
    </Card>
  );
}
```

### render prop 内でのコンポーネント定義禁止

render prop のコールバック内で**新しいコンポーネントを定義して返す**ことは
禁止する。毎レンダーで新しい関数参照が生まれ、React の reconciliation が
「別のコンポーネント型」と判断してアンマウント → リマウントを繰り返すため、
state のリセットや不要な API 再フェッチが発生する。

```tsx
// ❌ NG: 毎レンダーで新しいコンポーネント型が生まれる → state が毎回リセット
renderKeyResults={(id) => {
  const WrappedList = () => <KeyResultList objectiveId={id} />;
  return <WrappedList />;
}}

// ✅ OK: 既存コンポーネントの JSX をそのまま返す → 型が安定し差分更新される
renderKeyResults={(id) => <KeyResultList objectiveId={id} />}
```

React は仮想 DOM の差分比較時に**コンポーネントの関数参照**を型の同一性判定に
使う。render 内で定義した関数は毎回新しいオブジェクトになるため
`旧関数 !== 新関数` → 完全な再マウントとなる。一方、モジュールスコープで定義
された `KeyResultList` は常に同じ参照なので、props の差分のみが評価される。

## Alternatives Considered

- **children のみ（render prop なし）で合成**:
  `ObjectiveCard` に `children` を渡すだけなら簡潔だが、`ObjectiveList` 内で
  `KeyResultList` を import する必要があり、feature 間の直接 import が
  `ObjectiveCard` → `ObjectiveList` に移動するだけで根本解決にならない。却下

- **shared/ への移動**:
  `KeyResultList` を `shared/components/` に昇格する案。しかし `KeyResultList` は
  `useKeyResults`、`useUndoableDeleteKeyResult`、`CreateKeyResultForm` 等の
  KR ドメイン専用ロジックに依存しており、それらを全て shared に移動すると
  FSD のカプセル化が崩壊する。却下

## Consequences

### Positive

- `features/` 間の直接 import が完全に排除され、ADR 001 の原則が守られる
- 各 feature が独立してテスト・削除可能になる
- 合成の責務が `app/` に集約されるため、依存関係の全体像がページ単位で見える

### Negative

- ページコンポーネントの記述量が増える（render prop のネストが深くなり得る）
- コンポーネントの props に `render*` / `children` が増え、型定義が冗長になる
- ネストが 3 階層以上になった場合、可読性が低下する可能性がある
  （その場合は Context や Compound Component パターンへの移行を検討する）
