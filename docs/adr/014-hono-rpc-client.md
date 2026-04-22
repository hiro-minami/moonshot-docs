# ADR 014: Hono RPC クライアントによる型安全な API 呼び出し

- Status: Accepted
- Date: 2026-04-19
- Deciders: moonshot-team

## Context

Moonshot のフロントエンド (Next.js) → バックエンド (Hono) の API 通信は、汎用的な `apiFetch<T>` / `apiFetchVoid` ラッパー関数で行っていた。この方式には以下の問題があった:

1. **型の二重管理**: フロントエンドに手書きの `Objective` / `KeyResult` / `Task` 型定義があり、バックエンドの DB スキーマ変更時に同期が漏れるリスクがあった
2. **URL の手動構築**: `"/api/tasks?keyResultId=${id}"` のような文字列連結でパスとクエリパラメータを組み立てており、タイポや構造変更に対して脆弱だった
3. **レスポンス型の手動指定**: `apiFetch<Task[]>(...)` のジェネリクスが実際のレスポンス構造と一致する保証がなかった

Hono v4 は組み込みの RPC クライアント (`hc`) を提供しており、ルート定義から型を自動推論できる。同一 monorepo 内でバックエンドとフロントエンドが共存する Moonshot の構成では、この仕組みを活用することでエンドツーエンドの型安全性を実現できる。

## Decision

Hono 組み込みの RPC クライアント (`hono/client` の `hc<AppType>`) を採用し、フロントエンドの API 呼び出しを型安全にする。

### バックエンド側の変更

1. **ルートチェーン化**: `createApp` の return 文で `.route()` をチェーンし、`AppType` にルート型情報を保持する
2. **`validator` ミドルウェア適用**: `json` / `param` に対して `hono/validator` の `validator()` を使い、Zod スキーマでバリデーション + 型情報を RPC に公開する
3. **`query` は手動パース維持**: GET リストの `query` パラメータには `validator("query", ...)` を適用しない（理由は後述の Pitfalls を参照）

```typescript
// apps/api/src/delivery/app.ts
return app
  .route("/api/objectives", objectivesRoute)
  .route("/api/key-results", keyResultsRoute)
  .route("/api/tasks", tasksRoute);

export type AppType = ReturnType<typeof createApp>;
```

### フロントエンド側の変更

1. **RPC クライアント**: `hc<AppType>(baseUrl, { headers })` でクライアントを生成
2. **型導出**: `InferResponseType` でバックエンドのレスポンス型からフロントエンド型を自動導出
3. **手書き型定義の廃止**: `Objective` / `KeyResult` / `Task` 型を RPC 応答から導出し、手動同期を排除

```typescript
// apps/web/src/shared/types/okr.ts
type ObjectivesResponse = InferResponseType<ApiClient["api"]["objectives"]["$get"], 200>;
export type Objective = ObjectivesResponse["data"][number];
```

### `@hono/zod-validator` を使わない

Hono 組み込みの `validator()` に Zod の `.parse()` を渡す方式を採用する。`@hono/zod-validator` パッケージは追加しない。理由:

- 組み込み `validator()` + `schema.parse()` で型推論は十分機能する
- バリデーション失敗時は `ZodError` が throw され、既存の `errorHandler` ミドルウェアで 400 レスポンスに変換される
- 追加依存を増やさずに済む

## Alternatives Considered

### 1. tRPC

フルスタック型安全 RPC フレームワーク。型推論の品質は高いが、以下の理由で却下:

- Hono を既に採用しており (ADR 002)、tRPC を追加すると HTTP レイヤーが二重になる
- tRPC は独自のルーティング体系を持ち、Hono のミドルウェア（認証、冪等性キー等）との統合に追加の adapter 設定が必要
- Hono RPC は Hono のルート定義をそのまま型として利用するため、追加のレイヤーが不要

### 2. OpenAPI スキーマ自動生成 + クライアントコード生成

`@hono/zod-openapi` でスキーマを生成し、`openapi-typescript` 等でクライアント型を生成する方式。以下の理由で却下:

- コード生成ステップが CI/開発フローに追加される
- 生成物の管理（gitignore するか、コミットするか）の判断が必要になる
- monorepo 内の直接型参照で十分であり、OpenAPI の外部公開要件は現時点でない

### 3. 現状維持（apiFetch ラッパー）

手書きの fetch ラッパーを改善していく方式。以下の理由で却下:

- 型の二重管理問題が根本的に解決しない
- URL の文字列構築によるタイポリスクが残る
- Hono RPC は Hono に組み込まれており、追加コストなく移行できる

## Consequences

### Positive

- **エンドツーエンド型安全**: バックエンドのルート定義変更がフロントエンドのコンパイルエラーとして即座に検出される
- **型の一元管理**: フロントエンドの型はバックエンドから自動導出され、手動同期が不要になった
- **URL 構築の安全性**: パスパラメータ・クエリパラメータがオブジェクトとして渡され、タイポがコンパイル時に検出される
- **追加依存なし**: Hono に組み込まれた機能のみで実現。新たなパッケージ追加は不要

### Negative

- **ルートチェーン制約**: `app.route()` をステートメントではなくチェーンで記述する必要がある（Pitfall 1 を参照）
- **query validator の制限**: Zod の `.default()` を含むスキーマを `validator("query", ...)` に渡すと、RPC 型でデフォルト値付きフィールドが必須になる（Pitfall 2 を参照）
- **DB 型と RPC 型の乖離**: Drizzle の `numeric` 型（文字列）や `text` 型（広い string）が RPC 型に露出し、フロントエンドの楽観的更新で型不整合が生じうる（Pitfall 3 を参照）
- **monorepo 前提**: `AppType` の直接 import は monorepo 内パス参照に依存しており、バックエンドを別リポジトリに分離する場合は OpenAPI 等への移行が必要になる

---

## Appendix: 実装時の Pitfalls

移行時に遭遇した問題と解決策を記録する。Hono RPC 導入時の参考とする。

### Pitfall 1: ルートチェーン制約 — `AppType` が型情報を失う

**問題**: `app.route("/api/objectives", objectivesRoute)` をステートメントとして実行すると、戻り値が捨てられ `AppType = ReturnType<typeof createApp>` にルート型情報が含まれない。RPC クライアント側で `client.api.objectives.$get` が存在しないと型エラーになる。

**原因**: Hono の `.route()` は新しい型情報を持つ Hono インスタンスを **返す** が、ステートメント実行では元の `app` 変数の型は変わらない。TypeScript の型システムは副作用による型の変更を追跡しない。

```typescript
// NG: ステートメント — app の型にルート情報が含まれない
const app = new Hono();
app.route("/api/objectives", objectivesRoute);
app.route("/api/key-results", keyResultsRoute);
return app; // AppType にルート型なし

// OK: チェーン — return 値の型にルート情報が保持される
return app.route("/api/objectives", objectivesRoute).route("/api/key-results", keyResultsRoute); // AppType にルート型あり
```

**解決策**: `createApp` の return 文で `.route()` をチェーンして返す。チェーンに含めない（型情報が不要な）ルート（例: Webhook）はステートメントで事前に登録する。

### Pitfall 2: query validator + Zod `.default()` で必須フィールド化

**問題**: GET リストのクエリスキーマに `z.coerce.number().default(20)` のようなデフォルト値を含む場合、`validator("query", ...)` を通すと RPC クライアント側の型で `limit` / `offset` が**必須**フィールドになる。

```typescript
// Zod スキーマ
const listQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  offset: z.coerce.number().int().min(0).default(0),
});

// validator 使用時の RPC クライアント側の型
client.api.objectives.$get({
  query: {
    objectiveId: "...",
    limit: "20", // ← 必須（省略不可）
    offset: "0", // ← 必須（省略不可）
  },
});
```

**原因**: Hono の `validator("query", fn)` は入力型を `fn` のパラメータ型から推論する。Zod の `.default()` は **input 型**では `optional` だが、Hono の validator が捕捉するのは `.parse()` の**出力型**であり、出力型ではデフォルト値が適用された後の必須フィールドになる。さらに、query パラメータは `string | string[]` 型で渡されるため、`number` 型のフィールドを RPC から渡す際に型変換の問題も生じる。

**解決策**: GET リストの `query` パラメータには `validator()` を適用せず、ハンドラ内で `c.req.query()` を手動パースする。`json` と `param` には `validator()` を適用する（これらはデフォルト値を持たず、型が素直に対応する）。

### Pitfall 3: DB 型と楽観的更新の型不整合

**問題**: Hono RPC の `InferResponseType` で導出された型がフロントエンドの楽観的更新（`queryClient.setQueryData`）で型エラーを起こす。

具体的に 2 つのケースが発生した:

**ケース A: `numeric` 型 → `string` vs mutation input の `number`**

Drizzle の `numeric("current_value")` は PostgreSQL の `NUMERIC` 型に対応し、TypeScript では `string` として返される。一方、mutation の input では `currentValue: number` として受け取る。楽観的更新で `{ ...kr, ...input }` とスプレッドすると、`currentValue` が `string | number` のユニオン型になり `KeyResult` 型（`currentValue: string`）と互換性がなくなる。

```typescript
// 解決: スプレッド前に string に変換
const { currentValue, ...restInput } = input;
queryClient.setQueryData<KeyResult[]>(listKey, (old) =>
  old?.map((kr) =>
    kr.id === input.id
      ? {
          ...kr,
          ...restInput,
          ...(currentValue !== undefined && {
            currentValue: String(currentValue),
          }),
        }
      : kr,
  ),
);
```

**ケース B: `text("status")` → `string` vs Zod enum の union**

Drizzle の `text("status")` は TypeScript で `string` になる。しかし、PATCH の Zod スキーマでは `z.enum(["NOT_STARTED", "IN_PROGRESS", "DONE"])` と定義されている。RPC の `InferResponseType` で導出された `Task["status"]` は `string` だが、mutation input に `Task["status"]` を使うと `string` が `"NOT_STARTED" | "IN_PROGRESS" | "DONE"` に代入できず型エラーになる。

```typescript
// 解決: mutation input では明示的な union 型を使用
status?: "NOT_STARTED" | "IN_PROGRESS" | "DONE";
```

**根本原因**: Drizzle ORM のスキーマ定義（`text`, `numeric`）が PostgreSQL の型を広い TypeScript 型（`string`）にマッピングするため、アプリケーション層の制約（enum、数値）と乖離する。将来的には Drizzle スキーマ側で `.$type<>()` を使った型の絞り込みや、`pgEnum` の使用で対応できる。
