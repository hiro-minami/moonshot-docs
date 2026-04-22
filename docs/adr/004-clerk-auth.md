---
layout: default
title: "ADR 004: Clerk による認証基盤の採用"
---

# ADR 004: Clerk による認証基盤の採用

- Status: Accepted
- Date: 2026-04-17
- Deciders: Lead Engineer

## Context

Vercel(フロント)と AWS(API)が分離したハイブリッド構成において、セキュアかつ
開発体験の高い認証基盤を選定する必要があった。認証画面の構築やマルチデバイス対応の
工数を削減し、コア機能(OKR 管理)の開発に注力したかった。

## Decision

認証およびユーザーセッション管理に **Clerk** を採用する。Next.js 側のコンポーネント
提供に加え、Hono 側の公式ミドルウェアによるセッション検証を活用し、開発コストを
最小化する。

## Alternatives Considered

- **NextAuth.js (Auth.js):**
  無料で DB にデータを完全に保持できるが、マルチデバイス対応やパスワードレス実装の
  自前工数が大きく、開発スピードが劣後するため却下

- **AWS Cognito:**
  AWS インフラとの親和性は高いが、UI コンポーネントのカスタマイズ性やフロント
  エンドの DX が Clerk に大きく劣るため却下

- **Supabase Auth:**
  DB 込みで安価だが、今回はバックエンド DB に AWS Aurora Serverless を採用する
  インフラ一元化方針(ADR 003)と競合するため却下

## Consequences

### Positive

- サインイン画面やセッション管理の実装工数がほぼゼロになり、コア機能(OKR 管理)
  の開発に注力できる
- Hono 公式の認証ミドルウェアが提供されており結合が容易
- パスワードレス認証やマルチデバイス対応が標準機能として提供される

### Negative

- ベンダーロックインが発生する(ADR 007 の独自 UUID 採用で影響を緩和)
- MAU が 10,000 を超えた段階でコストが跳ね上がる(Pro プラン $25 + 超過分 MAU 課金)
- Clerk の障害が直接サービス停止に繋がる(公称 SLA 99.99% だが実測は別)
- ユーザーマスターが Aurora 外(Clerk 側)に存在するため、Webhook 等でのデータ
  同期アーキテクチャが必要(ADR 007 で扱う)
