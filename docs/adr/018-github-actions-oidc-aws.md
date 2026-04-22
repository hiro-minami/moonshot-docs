---
layout: default
title: "ADR 018: GitHub Actions OIDC による AWS 認証"
---

# ADR 018: GitHub Actions OIDC による AWS 認証

- Status: Accepted
- Date: 2026-04-20
- Deciders: hiro-minami

## Context

ADR 017 で導入した GitHub Actions CI/CD パイプラインでは、AWS デプロイ（ECR push、ECS デプロイ、Terraform apply）に IAM アクセスキー (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) を GitHub Secrets に格納して使用している。

この方式には以下の問題がある:

- 長期間有効なアクセスキーの漏洩リスク（ローテーション運用が必要）
- GitHub Secrets に静的なクレデンシャルを保存するセキュリティ上の懸念
- キーのローテーション時にシークレットの手動更新が必要

GitHub Actions は OpenID Connect (OIDC) をネイティブサポートしており、AWS IAM の OIDC ID プロバイダーと信頼関係を結ぶことで、一時的なクレデンシャルを自動取得できる。

## Decision

GitHub Actions の OIDC ID トークンを使用して AWS に認証する。

### 構成

1. **AWS 側**: IAM OIDC ID プロバイダー (`token.actions.githubusercontent.com`) を作成
2. **AWS 側**: デプロイ用 IAM ロールを作成し、OIDC プロバイダーとの信頼ポリシーを設定
3. **GitHub Actions 側**: `aws-actions/configure-aws-credentials` の `role-to-assume` パラメータを使用
4. **Terraform**: OIDC プロバイダーと IAM ロールを `infra/modules/` に追加

### IAM ロールの信頼ポリシー

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:hiro-minami/moonshot:*"
        }
      }
    }
  ]
}
```

### ワークフローの変更

```yaml
# Before (アクセスキー方式)
- uses: aws-actions/configure-aws-credentials@...
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: ap-northeast-1

# After (OIDC 方式)
permissions:
  id-token: write
  contents: read

- uses: aws-actions/configure-aws-credentials@...
  with:
    role-to-assume: arn:aws:iam::<ACCOUNT_ID>:role/moonshot-github-actions
    aws-region: ap-northeast-1
```

### 必要なリソース

| リソース              | 説明                                                 |
| --------------------- | ---------------------------------------------------- |
| IAM OIDC Provider     | `token.actions.githubusercontent.com`                |
| IAM Role (デプロイ用) | ECR push, ECS デプロイ, Terraform apply に必要な権限 |
| IAM Role (plan 用)    | Terraform plan に必要な読み取り権限（最小権限）      |

### 移行手順

1. Terraform で OIDC プロバイダーと IAM ロールを作成（`infra/modules/github-oidc/`）
2. ワークフローを `role-to-assume` 方式に変更
3. 動作確認後、`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` シークレットを削除
4. IAM ユーザーのアクセスキーを無効化・削除

## Alternatives Considered

### アクセスキー方式を継続

- ローテーションスクリプトを定期実行して運用
- 却下理由: 長期クレデンシャルの管理負荷が残る。OIDC が AWS 公式推奨

### AWS SSO (IAM Identity Center) 連携

- GitHub Actions から SSO セッションを取得
- 却下理由: 個人開発規模では過剰。SSO の初期セットアップコストが高い

## Consequences

### Positive

- 長期アクセスキーが不要になり、漏洩リスクが大幅に低減
- 一時的なクレデンシャル（デフォルト 1 時間）が自動発行・自動失効
- GitHub Secrets から AWS キーを削除でき、シークレット管理がシンプルに
- IAM ロールの信頼ポリシーでリポジトリ・ブランチ単位のアクセス制御が可能
- AWS 公式推奨のベストプラクティスに準拠

### Negative

- IAM OIDC プロバイダーと IAM ロールの初期セットアップが必要
- ワークフローに `permissions.id-token: write` の明示が必要
- IAM ロールの権限設計（最小権限の原則）に注意が必要
