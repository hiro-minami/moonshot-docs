---
layout: default
title: "ADR 007: ユーザーID設計と Clerk → Aurora 同期方式"
---

# ADR 007: ユーザーID設計と Clerk → Aurora 同期方式

- Status: Accepted
- Date: 2026-04-17
- Deciders: Lead Engineer
- Related: ADR 004 (Clerk)

## Context

Clerk ユーザー情報を Aurora 側のビジネスロジックとどう連携するかを決定する必要が
あった。以下の選択肢が検討対象となった:

- Clerk ID を全テーブルの外部キー(FK)として直接使う案
- Aurora 独自 UUID を発行して Clerk ID と紐付ける案

また、Clerk → Aurora へのデータ同期方式(Webhook 中心か、API アクセス時の Lazy
Create 中心か)も同時に決定する必要があった。

## Decision

- Aurora に独自 UUID を発行する `users` テーブルを設けて Clerk ID (`clerk_user_id`)
  と紐付ける
- 同期は **Clerk Webhook**(`user.created` / `user.updated` / `user.deleted`)を
  ECS 上の受信エンドポイントで受け、**Svix 署名を検証した上で**Aurora へ反映する
- Webhook 遅延・失敗時の補完として、API 初回アクセス時に JWT `sub` クレームから
  Aurora `users` を参照、不在なら Lazy Create するフォールバックを実装する
  (Webhook が primary、Lazy Create が fallback)

## Alternatives Considered

- **Clerk ID を直接 FK として全テーブルに持たせる:**
  シンプルだが、将来の認証基盤移行時(例: Clerk → Auth0 / 自前認証)に全 FK の
  書き換えが必要となり、マイグレーションコストが過大。また、ユーザープロフィール
  設定(ダークモードトグル等)の受け皿テーブルも別途必要になり二重管理となるため却下

- **Webhook のみ (Lazy Create なし):**
  Webhook は非同期のため、ユーザーが Clerk 登録直後の数秒間 Aurora に users が
  存在せず API 利用不可となり UX 劣化。Webhook 欠損時の復旧手段もなくなるため却下

- **Lazy Create のみ (Webhook なし):**
  最もシンプルだが、`user.updated`(メール変更)や `user.deleted`(退会)の
  イベントが Aurora に反映されず、整合性が取れなくなるため却下

## Consequences

### Positive

- ベンダーロックイン緩和: 将来 Auth0 等へ移行時、`users.clerk_user_id` 列のみ
  差し替えれば済み、全テーブルの FK 書き換えは不要
- ユーザープロフィール拡張の受け皿を確保(ダークモード設定、通知設定等)
- Webhook + Lazy Create の二重化により、同期欠損に強い
- Svix 署名検証により、偽 Webhook による攻撃を防御

### Negative

- Webhook 受信エンドポイントの実装・運用負担が発生する
  (Svix 署名検証、リトライ、冪等性)
- ユーザー作成時、Webhook 到着までの整合性窓(数秒〜数分)が存在する
  (Lazy Create で補完)
- Webhook 欠損時の `user.updated` / `user.deleted` イベントの整合性回復方法は
  未決(Design Doc Open Question Q1)

## 実装メモ

- Webhook 受信エンドポイントは PoC 段階では ECS 上の同一 Hono サービス内に
  `/webhooks/clerk` として配置。将来分離が必要になれば別 ECS サービスまたは
  Lambda へ切り出す
- Webhook ハンドリング対象イベント: `user.created` / `user.updated` /
  `user.deleted` の3種類
