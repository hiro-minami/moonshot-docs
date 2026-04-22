---
layout: default
title: "ADR 017: GitHub Actions CI パイプラインの採用"
---

# ADR 017: GitHub Actions CI パイプラインの採用

- Status: Accepted
- Date: 2026-04-20
- Deciders: hiro-minami

## Context

Moonshot の PoC 機能実装が完了し、E2E テスト (ADR 016) も整備された。現状、lint・typecheck・ビルド・E2E テストはすべてローカル実行に依存しており、以下の問題がある:

- PR マージ前の品質チェックが手動で、見落としが発生しうる
- 複数人開発への移行時にレビュー負荷が増大する
- E2E テストの実行を忘れるリスクがある

## Decision

**GitHub Actions** で 7 つのワークフローを構成する。

### CI ワークフロー（PR・main push 時）

各ステップを独立したワークフローに分割し、並列実行による高速フィードバックを実現する。

| ワークフロー         | トリガー                | 内容                         |
| -------------------- | ----------------------- | ---------------------------- |
| `format.yml`         | PR / main push          | Prettier フォーマット        |
| `lint.yml`           | PR / main push          | ESLint                       |
| `typecheck.yml`      | PR / main push          | TypeScript 型チェック        |
| `build.yml`          | PR / main push          | Next.js + API ビルド         |
| `e2e.yml`            | PR のみ                 | Playwright E2E テスト        |
| `terraform-plan.yml` | PR（infra/\*\* 変更時） | Terraform plan + PR コメント |

### デプロイワークフロー（main push 時）

| ワークフロー       | トリガー                                  | 内容                                            |
| ------------------ | ----------------------------------------- | ----------------------------------------------- |
| `deploy-api.yml`   | main push（apps/api, packages/db 変更時） | Docker ビルド → ECR push → ECS Fargate デプロイ |
| `deploy-infra.yml` | main push（infra/\*\* 変更時）            | Terraform apply                                 |

### E2E ワークフロー (`e2e.yml`)

PR 作成時のみ実行。PostgreSQL サービスコンテナ + Playwright で統合テストを行う。

- PostgreSQL 17 サービスコンテナで DB を起動
- `drizzle-kit migrate` でマイグレーションを適用
- Playwright Chromium で E2E テスト実行
- テストレポートとトレースをアーティファクトとしてアップロード（14 日保持）

### アクションのバージョン固定

すべてのサードパーティ Actions はコミットハッシュで固定する（タグの改ざんリスク回避）。バージョンタグはインラインコメントで記載する。

```yaml
- uses: actions/checkout@de0fac2e...dd # v6.0.2
```

### シークレット管理

以下を GitHub Secrets に登録する:

| Secret                    | 用途                               |
| ------------------------- | ---------------------------------- |
| `CLERK_SECRET_KEY`        | Clerk API 認証（ビルド・テスト用） |
| `CLERK_PUBLISHABLE_KEY`   | Clerk フロントエンド設定           |
| `E2E_CLERK_USER_EMAIL`    | E2E テストユーザーのメールアドレス |
| `E2E_CLERK_USER_PASSWORD` | E2E テストユーザーのパスワード     |
| `AWS_ACCESS_KEY_ID`       | AWS API アクセスキー（デプロイ用） |
| `AWS_SECRET_ACCESS_KEY`   | AWS シークレットキー（デプロイ用） |

### 並行性制御

- CI ワークフロー: `cancel-in-progress: true`（古い実行を自動キャンセル）
- デプロイワークフロー: `cancel-in-progress: false`（進行中のデプロイはキャンセルしない）

## Alternatives Considered

### 単一ワークフローに統合

- lint + typecheck + build + E2E を 1 ジョブで実行
- 却下理由: E2E は DB 起動 + Playwright インストールで遅い（約 5 分）。lint/typecheck のフィードバックが遅延する

### CI ステップを 1 つの yml にまとめる

- format + lint + typecheck + build を 1 ワークフロー内の 1 ジョブで直列実行
- 却下理由: 並列実行できず、1 つのステップが失敗すると後続が実行されない。個別のステータスバッジも付けられない

### CircleCI / GitLab CI

- 却下理由: リポジトリが GitHub にあり、GitHub Actions がネイティブ統合で最もシンプル。追加の SaaS 契約が不要

### OIDC による AWS 認証

- GitHub Actions OIDC と IAM ロールの信頼関係でアクセスキー不要にできる
- 現段階ではアクセスキー方式を採用し、将来的に OIDC へ移行可能

## Consequences

### Positive

- PR マージ前に lint・型・ビルド・E2E・Terraform plan が自動チェックされる
- 各 CI ステップが独立ワークフローのため並列実行・個別ステータス表示が可能
- main push 時に API・インフラが自動デプロイされる
- Terraform plan の結果が PR コメントに投稿され、レビューが容易
- アクションのコミットハッシュ固定によるサプライチェーン攻撃リスクの低減
- アーティファクトにより E2E 失敗時のデバッグが容易（レポート + トレース）
- `concurrency` でリソース浪費を防止

### Negative

- GitHub Secrets に Clerk キー・AWS キー・テストユーザー情報を登録する初期セットアップが必要
- E2E ワークフローは約 5〜10 分かかり、GitHub Actions の無料枠を消費する
- Clerk Development Keys の rate limit に注意が必要（CI 実行頻度が高い場合）
- コミットハッシュ固定は可読性が低く、アップデート時に手動確認が必要
