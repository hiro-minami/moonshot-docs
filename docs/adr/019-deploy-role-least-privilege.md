---
layout: default
title: "ADR 019: Deploy ロールの最小権限化戦略"
---

# ADR 019: Deploy ロールの最小権限化戦略

- Status: Proposed
- Date: 2026-04-20
- Deciders: hiro-minami

## Context

ADR 018 で GitHub Actions の AWS 認証を OIDC に移行した。deploy ロール (`moonshot-dev-github-deploy`) には Terraform apply に必要な権限を網羅するため、暫定的に `AdministratorAccess` マネージドポリシーをアタッチしている。

この状態は以下のリスクを持つ:

- deploy ロールが全 AWS サービスに対して全操作を実行可能（過剰権限）
- GitHub Actions のワークフロー改竄やトークン漏洩時の被害範囲が最大化する
- AWS Well-Architected Framework の最小権限の原則に違反している

一方、PoC/開発段階ではインフラ構成が頻繁に変わるため、早期に権限を絞り込むと Terraform 変更のたびに「権限不足で apply 失敗 → ポリシー修正 → 再 apply」のループが発生し、開発速度が低下する。

トラッキング: [Issue #23](https://github.com/hiro-minami/moonshot/issues/23)

## Decision

**インフラ構成が安定したタイミングで、IAM Access Analyzer を使って最小権限ポリシーに移行する。**

### 対応タイミング

以下の条件を **すべて** 満たした時点で着手する:

1. Terraform で管理するリソースの種類が 2 週間以上変わっていない（新モジュール追加がない）
2. `deploy-infra.yml` が 3 回以上連続で正常に完了している（apply の安定性が確認できている）
3. 本番環境 (`prod`) のセットアップが計画されている（`prod` では `AdministratorAccess` を許容しない）

### 移行手順

#### Phase 1: 権限の可視化（1-2 時間）

1. AWS CloudTrail で deploy ロールの過去 30 日の API コールを確認する
2. IAM Access Analyzer の「ポリシー生成」機能を使い、CloudTrail のアクティビティに基づく最小権限ポリシーを自動生成する
   - IAM コンソール → ロール → `moonshot-dev-github-deploy` → 「ポリシーを生成」
   - CloudTrail 証跡と期間（30 日）を選択
   - 生成されたポリシーをレビューする

#### Phase 2: ポリシーの適用（30 分）

3. 生成されたポリシーを Terraform コード化する（`infra/modules/github-oidc/main.tf`）
   ```hcl
   # AdministratorAccess を削除し、カスタムポリシーに置き換え
   resource "aws_iam_role_policy" "deploy_terraform" {
     name   = "terraform-apply"
     role   = aws_iam_role.deploy.id
     policy = data.aws_iam_policy_document.deploy_terraform.json
   }
   ```
4. `AdministratorAccess` のアタッチメントを削除する
5. `terraform plan` で差分を確認し、apply する

#### Phase 3: 検証（1 時間）

6. `deploy-infra.yml` を `workflow_dispatch` で手動実行し、Terraform apply が成功することを確認する
7. `deploy-api.yml` を `workflow_dispatch` で手動実行し、ECR push + ECS deploy が成功することを確認する
8. 権限不足エラーが発生した場合は、不足権限をポリシーに追加して再実行する

#### Phase 4: 継続的メンテナンス

- Terraform に新しい AWS サービスのリソースを追加した場合、対応する権限を deploy ロールのポリシーに追加する
- 使わなくなったリソースを削除した場合、対応する権限もポリシーから削除する
- 四半期ごとに IAM Access Analyzer で未使用権限を確認し、不要な権限を削除する

### ポリシー構成の方針

権限は用途別に分離し、可読性と管理性を高める:

| ポリシー名        | 用途                                | 対象                                 |
| ----------------- | ----------------------------------- | ------------------------------------ |
| `ecr-push`        | ECR イメージプッシュ                | 既存（変更なし）                     |
| `ecs-deploy`      | ECS タスク定義・サービス更新        | 既存（変更なし）                     |
| `terraform-apply` | Terraform が管理するリソースの CRUD | 新規（`AdministratorAccess` の代替） |

## Alternatives Considered

### 手動で権限を洗い出してポリシーを作成する

- Terraform のドキュメントやソースコードから必要な API コールを特定する
- 却下理由: 網羅性の担保が困難。プロバイダの内部実装に依存する API コール（例: `DescribeVpcs` を明示的に書いていなくても `terraform plan` で呼ばれる）を見落とすリスクがある

### AWS Organizations SCP で制限する

- `AdministratorAccess` のままだが、SCP で危険な操作（IAM ユーザー作成、ルートアカウント操作等）を組織レベルでブロックする
- 却下理由: 個人開発で Organizations を使っていない。SCP はアカウント単位の制御で、ロール単位の最小権限化にはならない

## Consequences

### Positive

- deploy ロールの権限が必要最小限になり、漏洩時の被害範囲が限定される
- IAM Access Analyzer による自動生成で、手動での権限洗い出しの手間を削減できる
- `prod` 環境に適用可能なセキュリティ水準になる
- 権限が明示的にコード化され、変更履歴を追跡できる

### Negative

- 新しい AWS サービスを Terraform に追加するたびにポリシーの更新が必要になる
- IAM Access Analyzer の生成ポリシーは 30 日分のアクティビティに基づくため、まれにしか実行しない操作（例: 初回のみ必要な `CreateVpc`）が含まれない場合がある
- ポリシーのメンテナンスを怠ると、将来の Terraform 変更時に apply が失敗するリスクがある
