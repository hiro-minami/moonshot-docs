# ADR 011: 環境変数アクセスパターン

- Status: Proposed
- Date: 2026-04-18
- Deciders: Lead Engineer

## Context

バックエンド (`apps/api/`) で環境変数を読み取る際、TypeScript の型システムが
`process.env[key]` を `string | undefined` と扱うため、実用上は以下のいずれかの
回避策が必要になる:

```typescript
// A. ?? "" フォールバック（実際には空文字列が渡る可能性を示唆してしまう）
secretKey: process.env["CLERK_SECRET_KEY"] ?? "",

// B. ! アサーション（ESLint no-non-null-assertion を抑制するコメントが必要）
// eslint-disable-next-line @typescript-eslint/no-non-null-assertion
secretKey: process.env["CLERK_SECRET_KEY"]!,
```

現状は `index.ts` の起動時チェックで必須変数の存在を保証しているが、
ミドルウェアや DI コンテナが `process.env` を直接読むため、
チェックが通った後でも型上は `string | undefined` のままとなり
コードの意図が伝わりにくい。

## Decision

起動時バリデーションを Zod スキーマに統一し、検証済みの型付き `env` オブジェクトを
アプリケーション全体で利用する。

```typescript
// apps/api/src/env.ts
import { z } from "zod";

const envSchema = z.object({
  DATABASE_URL: z.string().min(1),
  CLERK_SECRET_KEY: z.string().min(1),
  CLERK_PUBLISHABLE_KEY: z.string().min(1),
  PORT: z.coerce.number().default(8080),
});

export const env = envSchema.parse(process.env);
```

```typescript
// apps/api/src/index.ts
import { env } from "./env.js";
const db = createDb(env.DATABASE_URL);
```

```typescript
// apps/api/src/middleware/auth.ts
import { env } from "../env.js";
const client = createClerkClient({
  secretKey: env.CLERK_SECRET_KEY, // string — ! も ?? も不要
  publishableKey: env.CLERK_PUBLISHABLE_KEY,
});
```

バリデーション失敗時は `ZodError` が起動時にスローされ、
不足・不正な環境変数の一覧が明示される。

## Alternatives Considered

- **`?? ""` フォールバック（現状）:**
  コード上は「空文字列でも動く」と読めてしまい、実際のセマンティクス（起動時に
  必須チェック済み）と乖離する。低コストだが意図が伝わりにくいため将来的に除去する

- **`!` アサーション:**
  意図は明確だが ESLint `no-non-null-assertion` ルールを抑制するコメントが必要に
  なり、コードが冗長になる。変数が増えるたびに同じコメントが増殖するため却下

- **`requireEnv(key)` ヘルパー関数:**
  呼び出し側にエラーが移るためシンプルだが、起動時ではなくミドルウェア初回呼び出し時に
  エラーが発覚する点が Zod スキーマ案に劣後する。単純な代替としては有効

- **ミドルウェアに config を引数で渡す:**
  ミドルウェアが `process.env` を直接参照しなくなり、テスト容易性は最も高い。
  ただし `createApp` などのシグネチャ変更が波及するためリファクタコストが大きく、
  Zod スキーマ案と組み合わせて段階的に導入するのが現実的

## Consequences

### Positive

- 環境変数の型が `string`（`undefined` なし）となり `!` や `?? ""` が不要
- バリデーション失敗時に欠損変数名が一覧表示され、デプロイ時の問題特定が速い
- 環境変数の定義・バリデーション・デフォルト値が `env.ts` に集約される
- Zod の `.default()` / `.coerce` / `.url()` 等で制約を宣言的に記述できる

### Negative

- `zod` の import が `apps/api/` に追加される（すでに依存済みのため実質コストなし）
- `process.env` を直接読んでいる既存箇所を `env.ts` 経由に置き換える作業が発生する

## 実装メモ

- `apps/api/src/env.ts` を新規作成し、`index.ts` の `requiredEnvVars` ループを削除
- `middleware/auth.ts` / `di/container.ts` / `index.ts` の `process.env` 参照を
  `env.*` に置き換える
- テスト時は `env.ts` をモックするか、テスト用の環境変数を `.env.test` で管理する
