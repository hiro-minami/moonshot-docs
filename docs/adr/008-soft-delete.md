# ADR 008: 論理削除戦略 (Read 時カスケード)

- Status: Accepted
- Date: 2026-04-17
- Deciders: Lead Engineer

## Context

楽観的 UI での「削除 → 取り消し」を実現するため、物理削除ではなく論理削除が必須
だった。親子関係(Objective → Key Result → Task)での削除伝搬方式を決定する必要が
あった。

## Decision

- 全テーブル(`users` / `objectives` / `key_results` / `tasks`)に `deleted_at`
  列(Nullable)を持たせる
- `deleted_at` は「**ユーザーが直接削除したエンティティ**」にのみ立てる
- Read 時に親の削除状態を参照して子をフィルタする(**Read 時カスケード**)
- Drizzle Repository 層に `withSoftDelete()` ヘルパ関数を共通化し、クエリ肥大化と
  規約逸脱バグを防ぐ
- 30 日経過した `deleted_at` レコードは `pg_cron` による定期バッチで物理削除する

## Alternatives Considered

- **Write 時カスケード(親削除時に子も `deleted_at` 更新):**
  復元時に「親と一緒に削除された子」と「元々個別に削除されていた子」の区別が
  つかず、本来消えたままにすべきタスクまで復元されてしまうバグが発生するため却下

- **物理削除 + バックアップからの復元:**
  UX 悪化(復元に数分〜数時間)、短期的な「削除取り消し」に不向きなため却下

- **ステータス列による表現(`status = 'deleted'`):**
  既存の `tasks.status` と意味が衝突する、復元時の前ステータス保持が必要になる等、
  設計複雑化するため却下

## Consequences

### Positive

- 復元操作が安全: 子エンティティの個別削除状態を保持したまま親のみ復元可能
- 楽観的 UI での即時「取り消し」操作が自然に実現できる
- `deleted_at` 列だけで済むため、スキーマがシンプル

### Negative

- Read クエリで毎回親の `deleted_at` 参照が必要、JOIN 条件が複雑化する
- Repository 層のヘルパ整備で緩和するが、規約逸脱時(ヘルパを使わず直接クエリを
  書く等)にバグ混入リスクがある
- 物理削除バッチ(`pg_cron`)の運用が追加で必要
- 論理削除レコードがインデックスを膨張させるため、複合インデックスに
  `deleted_at` を含める設計が必要

## 実装メモ

- インデックス方針(Design Doc §6.3 と合わせる):
  - `objectives (user_id, deleted_at, end_date DESC)` 複合
  - `key_results (objective_id, deleted_at)`
  - `tasks (key_result_id, status, deleted_at)`
- Repository ヘルパ例:

  ```ts
  // すべての SELECT は必ずこのヘルパ経由で実行する
  function withSoftDelete(table) {
    return { where: isNull(table.deleted_at) };
  }
  ```
