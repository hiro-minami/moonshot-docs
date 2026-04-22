# Architecture Decision Records (ADR)

このディレクトリは Moonshot プロジェクトの設計判断を記録する ADR 集です。

## ADR 一覧

| #                                              | タイトル                                                     | Status   |
| ---------------------------------------------- | ------------------------------------------------------------ | -------- |
| [001](./001-frontend-feature-sliced-design.md) | フロントエンドへの Feature-Sliced Design (機能別分割) の採用 | Accepted |
| [002](./002-hono-clean-architecture.md)        | Hono と Clean Architecture (手動DI) の採用                   | Accepted |
| [003](./003-aws-ecs-aurora.md)                 | インフラストラクチャの AWS 一元管理 (ECS Fargate + Aurora)   | Accepted |
| [004](./004-clerk-auth.md)                     | Clerk による認証基盤の採用                                   | Accepted |
| [005](./005-tanstack-query.md)                 | TanStack Query (v5) による状態管理と楽観的UI                 | Accepted |
| [006](./006-shadcn-ui.md)                      | shadcn/ui + Tailwind CSS v4 による UI 基盤                   | Accepted |
| [007](./007-user-id-sync.md)                   | ユーザーID設計と Clerk → Aurora 同期方式                     | Accepted |
| [008](./008-soft-delete.md)                    | 論理削除戦略 (Read 時カスケード)                             | Accepted |
| [009](./009-idempotency-key.md)                | Idempotency-Key の保存先 (UNLOGGED TABLE)                    | Accepted |
| [010](./010-design-tokens.md)                  | デザイントークンと CSS 変数を用いたテーマ管理                | Accepted |
| [011](./011-env-var-access-pattern.md)         | 環境変数アクセスパターン                                     | Proposed |
| [012](./012-esbuild-api-bundling.md)           | esbuild による API バンドルビルド                            | Accepted |
| [013](./013-undo-toast-pattern.md)             | 破壊的操作における Undo トーストパターンの採用               | Accepted |
| [014](./014-hono-rpc-client.md)                | Hono RPC クライアントによる型安全な API 呼び出し             | Accepted |
| [015](./015-view-transitions.md)               | View Transitions API によるページ遷移アニメーション          | Accepted |
| [016](./016-e2e-playwright.md)                 | Playwright による E2E テストの採用                           | Accepted |
| [017](./017-github-actions-ci.md)              | GitHub Actions CI パイプラインの採用                         | Accepted |
| [018](./018-github-actions-oidc-aws.md)        | GitHub Actions OIDC による AWS 認証                          | Accepted |
| [019](./019-deploy-role-least-privilege.md)    | Deploy ロールの最小権限化戦略                                | Proposed |
| [020](./020-cross-feature-composition.md)      | Feature 間コンポーネント合成のパターン                       | Accepted |
| [021](./021-ecs-image-tag-strategy.md)         | ECS タスク定義のイメージタグ管理戦略                         | Accepted |

## ADR 記述フォーマット

各 ADR は以下のセクションを必須とする:

- **Status**: Proposed / Accepted / Deprecated / Superseded by ADR XXX
- **Date**: 決定日
- **Deciders**: 意思決定者
- **Context**: 背景・制約
- **Decision**: 決定内容
- **Alternatives Considered**: 検討した代替案と却下理由
- **Consequences**: 結果(Positive / Negative)

## 運用ルール

- **ADR は不変記録**: 一度 Accepted になった ADR は原則書き換えず、方針変更時は
  新しい ADR で置き換え(Superseded by ADR XXX と記載)
- **Design Doc は生きた文書**: プロジェクトの現状を反映して継続的に更新する
- **ADR は資産、Design Doc は現状**: PoC を捨てても ADR に記録された技術判断の
  学びは次のプロジェクトに引き継がれる
