---
layout: default
title: "ADR 009: Idempotency-Key の保存先 (PostgreSQL UNLOGGED TABLE)"
---

# ADR 009: Idempotency-Key の保存先 (PostgreSQL UNLOGGED TABLE)

- Status: Accepted
- Date: 2026-04-17
- Deciders: Lead Engineer

## Context

楽観的 UI + ネットワーク不安定時のリトライにより、同一リクエストが二重送信される
ケースは必ず発生する。たとえば「タスクを作成 → 通信エラーと見なして自動リトライ
→ 実は初回リクエストも成功していて二重登録」のような状況を防ぐため、Stripe API 流の
**Idempotency-Key** の保存機構が必要。

保存先の候補として「追加インフラ不要」と「高速 I/O」を両立する選択肢を検討した。

## Decision

Aurora 内に **UNLOGGED TABLE** として `idempotency_keys` テーブルを作成する。
期限切れレコードは **`pg_cron` 拡張**で定期パージする。

テーブル定義:

```
idempotency_keys (UNLOGGED)
  key           TEXT PRIMARY KEY       -- クライアント生成 UUID v4
  user_id       UUID NOT NULL          -- 認証済みユーザー ID
  request_hash  TEXT NOT NULL          -- リクエストボディのハッシュ
  response_body JSONB NOT NULL         -- 初回レスポンスボディ
  status_code   INTEGER NOT NULL       -- 初回レスポンスステータス
  created_at    TIMESTAMP NOT NULL
  expires_at    TIMESTAMP NOT NULL     -- INDEX, 24時間後
```

## Alternatives Considered

- **ElastiCache (Redis):**
  最速だが最小構成でも月額固定コスト(~$15/mo〜)が追加発生、Terraform 管理対象
  増加、VPC / SG の構成複雑化を招くため MVP / PoC 段階では過剰投資と判断し却下

- **通常テーブル(LOGGED):**
  WAL(先行書き込みログ)の書き込みコストがレイテンシに影響、パフォーマンス面で
  UNLOGGED に劣後するため却下

- **アプリケーションメモリ(Map 等):**
  ECS Fargate のスケーリングでタスクが複数ある場合、タスク間でキーが共有されず
  冪等性が担保できないため却下

## Consequences

### Positive

- 追加インフラゼロ、コスト増加なし
- WAL スキップによりメモリ速度に近い I/O パフォーマンス
- `pg_cron` で DB 内完結、アプリ側バッチ不要
- Aurora の既存バックアップ・監視体系にそのまま乗る

### Negative

- DB クラッシュ時にデータ消失する
  (許容: 冪等性キーの寿命は24時間であり、万が一消失しても「リトライ時にエラーまたは
  二重登録が一時的に発生」だけで済む)
- Aurora リードレプリカに UNLOGGED テーブルはレプリケートされない
  (書き込み系 API でのみ利用するため実用上は影響なし、writer endpoint 経由で
  アクセスする必要がある点に注意)
- 将来スケール時(10,000 MAU+)は、DB 負荷や高可用性要件に応じて ElastiCache
  移行を再評価する

## 実装メモ

- クライアント側: すべての POST / PATCH / DELETE リクエストで `Idempotency-Key`
  ヘッダ(UUID v4)を必須とする
- サーバー側: ミドルウェアで以下を実行
  1. `Idempotency-Key` ヘッダ存在チェック(なければ 400)
  2. `idempotency_keys` テーブル検索
  3. 存在すれば `response_body` をそのまま返却(初回レスポンス再生)
  4. 存在しなければ処理実行後に結果を INSERT
- `pg_cron` 設定例: `SELECT cron.schedule('purge-idempotency', '0 * * * *', 'DELETE FROM idempotency_keys WHERE expires_at < NOW()');`
- Aurora PostgreSQL で `pg_cron` 拡張は 12.5+ で利用可能(Aurora Serverless v2 は
  PostgreSQL 13+ 対応のため問題なし)
