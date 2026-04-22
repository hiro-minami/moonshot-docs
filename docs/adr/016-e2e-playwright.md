# ADR 016: Playwright による E2E テストの採用

- Status: Accepted
- Date: 2026-04-20
- Deciders: hiro-minami

## Context

Moonshot は Next.js (フロントエンド) + Hono (API) + Clerk (認証) で構成される OKR 管理 SaaS である。機能追加に伴いリグレッションリスクが増大しており、認証フロー・ダッシュボード操作を含む主要ユーザーパスの自動テストが必要になった。

要件:

- 認証付きフロー (Clerk) をテスト可能であること
- ローカル開発と CI (GitHub Actions) の両方で実行可能であること
- フロントエンド + API を統合してテストできること

## Decision

**Playwright** を E2E テストフレームワークとして採用し、`@clerk/testing` パッケージで認証フローをテストする。

### 構成

- テストディレクトリ: `apps/web/e2e/`
- 設定: `apps/web/playwright.config.ts`
- 認証方式: `@clerk/testing/playwright` の `clerkSetup()` + `setupClerkTestingToken()` + `clerk.signIn()`
- サーバー起動: `webServer` 配列で Web + API の両方を待機 (後述)
- レポーター: CI では `github`、ローカルでは `html` (`--host 0.0.0.0` でコンテナ外アクセス対応)

### テストカバレッジスコープ

1. **ランディングページ**: ロゴ表示、サインイン/サインアップリンク遷移
2. **認証フロー**: 未認証リダイレクト、認証後リダイレクト
3. **ダッシュボード**: ヘッダー表示、Objective CRUD 操作

### webServer 配列パターン

`turbo dev` は API (Hono) と Web (Next.js) を同時起動するが、Playwright の `webServer` は単一 URL の ready check しかできない。Web (`:3000`) の起動完了後も API (`:8080`) が未起動の場合、API 依存テスト (Objective CRUD 等) が失敗する。

これを解決するため、`webServer` を配列にして 2 段階の ready check を行う:

```ts
webServer: [
  {
    command: "pnpm dev",           // turbo dev で API + Web 同時起動
    url: "http://localhost:3000",   // Web の ready check
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
    cwd: "../..",                   // monorepo root から実行
  },
  {
    command: "echo 'API started by pnpm dev above'", // 実際の起動は不要
    url: "http://localhost:8080/health",              // API の ready check
    reuseExistingServer: true,      // 常に既存サーバーを再利用
    timeout: 30_000,
  },
],
```

ポイント:

- 1 つ目のエントリが `pnpm dev` (= `turbo dev`) で API と Web を同時起動する
- 2 つ目のエントリは `echo` コマンド (即座に終了) を指定し、`reuseExistingServer: true` で既に起動済みの API の `/health` エンドポイントを待機する
- Playwright は配列を順番に処理するため、Web 起動完了 → API ヘルスチェック通過の順序が保証される
- CI (`process.env.CI`) では 1 つ目の `reuseExistingServer` が `false` になり、毎回 `pnpm dev` を起動する

### CI 実装方針 (将来)

- GitHub Actions で Clerk Testing Token + DB (PostgreSQL service container) を使用
- テストレポートは `actions/upload-artifact` でアーティファクトとしてアップロード
- CI 用 Clerk API キーは GitHub Secrets で管理

## Alternatives Considered

### Cypress

- ブラウザ内実行で DX は良いが、マルチタブ・マルチブラウザ対応が Playwright に劣る
- Clerk 公式テスティングサポートが Playwright を優先している
- 却下理由: Clerk 公式の `@clerk/testing` が Playwright ファーストで提供されている

### Vitest + Testing Library (統合テスト)

- レンダリングテストは高速だが、認証フロー・リダイレクト・API 統合の検証が困難
- 却下理由: 認証付きフルスタック統合テストには不十分

## Consequences

### Positive

- Clerk 公式の Testing Token 機構により、実際の認証フローを安全にテスト可能
- ローカルと CI で同一テストコードが動作する
- Chromium ヘッドレスで高速実行 (9テスト / 約22秒)
- `reuseExistingServer` により開発中は既存サーバーを再利用

### Negative

- ローカル実行には 1Password CLI サインイン (環境変数解決) が前提
- devcontainer 内ではレポートサーバーに `--host 0.0.0.0` が必要
- Clerk Development Keys の rate limit に注意が必要
- テスト用ユーザーを Clerk ダッシュボードに事前作成する必要がある

## Lessons Learned (実装時の知見)

### 環境構築

| 問題                                          | 原因                                 | 解決策                                        |
| --------------------------------------------- | ------------------------------------ | --------------------------------------------- |
| `op run` でシークレットが子プロセスに渡らない | turbo が env を passthrough しない   | `turbo.json` に `globalPassThroughEnv` を追加 |
| Next.js が API の PORT を奪う                 | `PORT` 環境変数を Next.js が読む     | `API_PORT` にリネーム                         |
| esbuild platform mismatch                     | devcontainer 再構築で darwin → linux | `pnpm install --force`                        |
| TypeScript parameter properties エラー        | `--experimental-strip-types` 非対応  | `--experimental-transform-types` に変更       |
| DB 接続エラー                                 | PG 15→17 でデータ互換性なし          | Docker volume 再作成                          |

### Clerk テスティング

| 問題                                    | 原因                           | 解決策                                                |
| --------------------------------------- | ------------------------------ | ----------------------------------------------------- |
| `clerk.signIn()` 後にセッション未反映   | `signInParams` API が不正      | `emailAddress` + `password` を直接渡す (公式デモ準拠) |
| `clerk.signIn()` 前に Clerk JS 未ロード | ページ遷移前に signIn 呼び出し | `page.goto("/")` で先にページロード                   |
| `clerkSetup()` が Unauthorized          | `CLERK_SECRET_KEY` 未設定      | `op run` 経由で環境変数を注入                         |

### Playwright 設定

| 問題                            | 原因                                      | 解決策                                                                                              |
| ------------------------------- | ----------------------------------------- | --------------------------------------------------------------------------------------------------- |
| HTML レポートサーバーがハング   | コンテナ内でブラウザ open 試行            | `open: "never"` + `--host 0.0.0.0`                                                                  |
| API 未起動で Objective 作成失敗 | `webServer` が単一 URL (`:3000`) のみ待機 | `webServer` を配列化し、2 つ目のエントリで API `/health` を待機 (上述の webServer 配列パターン参照) |
| WebServer タイムアウト (30s)    | API 初回起動が遅い                        | Web 側を 60s、API 側を 30s に設定 + `reuseExistingServer` 活用                                      |
