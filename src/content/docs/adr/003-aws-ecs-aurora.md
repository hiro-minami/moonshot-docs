---
title: "ADR 003: インフラストラクチャの AWS 一元管理 (ECS Fargate + Aurora)"
---


- Status: Accepted
- Date: 2026-04-17
- Deciders: Lead Engineer

## Context

Vercel にホストされる Next.js からのリクエストを処理するバックエンド (Hono) および
DB のデプロイ先を選定する必要があった。

「フロントエンドのプレビュー環境との連動(DX)」を優先するか、「ネットワークの
堅牢性とインフラの統制(Governance)」を優先するかでトレードオフが存在した。

## Decision

バックエンド API を **AWS ECS Fargate**、データベースを **Amazon Aurora Serverless v2
(PostgreSQL 互換)** とする構成を採用し、Terraform (IaC) を用いてネットワーク (VPC)
から一元管理する。

## Alternatives Considered

- **Neon (外部 SaaS) + App Runner:**
  Vercel のプレビュー環境ごとに DB を自動ブランチングできる機能は DX として最強
  だが、以下の理由で却下:
  - App Runner の新規受付停止(非推奨化)の動向
  - ビジネスデータが AWS 外(Neon)に流出するコンプライアンス上の懸念
  - インフラ管理の分散

- **AWS Lambda + API Gateway:**
  サーバーレスの恩恵は大きいが、VPC 内の RDS (Aurora) へ接続する際の ENI
  コールドスタート問題や、Hono の常駐パフォーマンスの安定性を考慮し、コンテナ
  (ECS) に劣後すると判断し却下

## Consequences

### Positive

- AWS のプライベートネットワーク (VPC) 内で ECS から Aurora への通信が完結する
  ため、セキュリティ水準が極めて高い
- Terraform による IaC 管理でインフラの再現性が担保される
- Aurora Serverless v2 の無段階スケールにより、DB の負荷スパイクに対しても
  システムが落ちない耐障害性を得られる

### Negative

- 運用コストおよびランニングコストが高い。Aurora Serverless v2 はアイドル時でも
  最小 0.5 ACU が起動し続けるため、アクセスゼロでも DB だけで月額約 $45〜50 の
  固定費が発生する
- Vercel の Pull Request ごとのプレビュー環境に対して、動的に独立した DB を
  用意するような「モダンな DX」の構築が Neon に比べて困難(泥臭い CI/CD の
  スクリプトが必要)になる
- Cold Start による p95 レイテンシ目標(300ms)への影響を PoC で実測する必要が
  ある(Design Doc の Pre-mortem シナリオ B 参照)

## 実装メモ(追記)

- PostgreSQL バージョン: Aurora Serverless v2 対応の最新安定版を採用
- 2026年4月時点: PostgreSQL 17.7 (17.7.1 パッチ適用版)
- PostgreSQL 18.1 は RDS Preview 環境のみで提供されており、Serverless v2 非対応のため採用不可
- Aurora 18 本番 GA 後に 17→18 へのメジャーバージョンアップグレードを検討
- ローカル DevContainer は `postgres:17-alpine` で本番とメジャーバージョンを揃える

## 関連 ADR

- [ADR 021](./021-ecs-image-tag-strategy.md): ECS タスク定義のイメージタグ管理戦略（ECR IMMUTABLE タグと CI/CD の責任分離）
