# ADR 021: ECS タスク定義のイメージタグ管理戦略

- Status: Accepted
- Date: 2026-04-21
- Deciders: Lead Engineer

## Context

ECS デプロイにおいて、Docker イメージのタグ管理に関して以下の矛盾が発生していた:

1. **ECR リポジトリは `IMMUTABLE` タグ**（ADR 003 で AWS 一元管理を決定した
   際の暗黙的な前提）。同一タグでの上書き push は不可
2. **Terraform の ECS モジュール** (`infra/modules/ecs/`) が `image_tag`
   変数のデフォルト値として `"latest"` を使用
3. **GitHub Actions CI/CD** (`deploy-api.yml`) はコミット SHA をタグに使用し、
   ECS render/deploy アクションで正しいイメージをデプロイ
4. **ECS サービス**に `lifecycle { ignore_changes = [task_definition] }` を
   設定し、CI/CD がタスク定義を管理する設計

この構成により、Terraform が直接 apply される場面（シークレット追加、環境変数変更
等）で **イメージタグが `latest` のタスク定義が作成される**。ECR に `latest` タグの
イメージは存在しないため、ECS タスクが `CannotPullContainerError` で起動失敗した。

### 実際に発生した障害（2026-04-21）

1. PR #27（Secrets Manager 統合）マージ → Terraform apply → タスク定義
   revision:4 が `image_tag=latest` で作成された
2. サービスを手動で revision:4 に更新 → ECR に `latest` が存在せず起動失敗
3. 手動で revision:5（正しいイメージタグ）を登録・デプロイして復旧

## Decision

**Terraform はイメージタグを管理しない。CI/CD（GitHub Actions）がイメージタグの
唯一の管理者とする。**

具体的な設計:

1. **ECS モジュールの `image_tag` 変数を削除**し、イメージを
   `"${ecr_repository_url}:initial"` で固定する（Terraform 初回 apply 用の
   プレースホルダー）
2. **`lifecycle { ignore_changes = [task_definition] }`** を維持し、Terraform
   apply でタスク定義が変更されてもサービスは影響を受けない
3. **CI/CD がタスク定義のイメージタグを管理**:
   - `deploy-api.yml` がコミット SHA タグでビルド・プッシュ
   - `amazon-ecs-render-task-definition` が現在のタスク定義のイメージを差し替え
   - `amazon-ecs-deploy-task-definition` がサービスを更新
4. **Terraform apply で環境変数やシークレットを変更した場合**、タスク定義は
   更新されるがサービスは旧タスク定義のまま。CI/CD の次回実行時に新しいタスク
   定義をベースにイメージタグが差し替えられ、正しくデプロイされる

### イメージタグの役割分担

| 操作                      | イメージタグ        | 管理者                  |
| ------------------------- | ------------------- | ----------------------- |
| Terraform 初回 apply      | `initial`（ダミー） | Terraform               |
| 通常デプロイ              | コミット SHA        | GitHub Actions          |
| Terraform apply（2回目〜) | `initial`（固定）   | Terraform（無視される） |

## Alternatives Considered

### A. Terraform でイメージタグも管理する

Terraform の変数に最新のコミット SHA を渡し、Terraform apply で毎回タスク定義を
更新する方式。`lifecycle { ignore_changes = [task_definition] }` を除去し、
Terraform がデプロイの単一管理者になる。

却下理由: CI/CD パイプラインの apply 時に常に最新のコミット SHA を取得・注入する
仕組みが必要になる。また、Terraform apply のたびにタスク定義が変更されるため、
シークレット変更のような非イメージ変更でもデプロイが発生し、変更の影響範囲が
不明確になる。

### B. ECR を MUTABLE にして `latest` タグを使う

`image_tag_mutability = "MUTABLE"` に変更し、CI/CD で `latest` タグを常に
上書き push する方式。Terraform の `image_tag = "latest"` がそのまま動作する。

却下理由: MUTABLE タグはイメージの一意性が保証されず、ロールバック時にどの
バージョンに戻すか不明確になる。セキュリティスキャンの結果と実行バイナリの
対応も取れなくなる。IMMUTABLE タグはコンテナセキュリティのベストプラクティスで
ある。

## Consequences

### Positive

- Terraform apply が意図せず壊れたタスク定義をデプロイするリスクがなくなる
- イメージタグの管理者が CI/CD に一元化され、責任が明確になる
- ECR IMMUTABLE タグのメリット（監査可能性、ロールバック確実性）を維持できる

### Negative

- Terraform 初回 apply 直後はダミーイメージのためタスクが起動しない。
  CI/CD で最初のデプロイを実行する必要がある
- 環境変数やシークレットを Terraform で変更した場合、反映には CI/CD の再実行
  が必要（`workflow_dispatch` で手動トリガー可能）
