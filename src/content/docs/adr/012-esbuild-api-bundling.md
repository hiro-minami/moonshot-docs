---
title: "ADR 012: esbuild による API バンドルビルド"
---


- Status: Accepted
- Date: 2026-04-19
- Deciders: Lead Engineer

## Context

`apps/api/` の本番ビルドにおいて、以下の課題があった:

1. **ワークスペースパッケージの解決**: `@moonshot/db` は TypeScript ソースを
   直接 export しており（ビルドステップなし）、`node_modules` 内の `.ts`
   ファイルは Node.js の `--experimental-strip-types` では処理できない
2. **Docker イメージの軽量化**: ワークスペースパッケージのソースやビルドツールを
   ランタイムイメージに含めたくない
3. **ビルド速度**: CI/CD パイプラインでのビルド時間を最小化したい

## Decision

**esbuild の JS API** を使い、API ソースとワークスペースパッケージを単一ファイルに
バンドルする。ビルドスクリプトは `scripts/build-api.js` に配置する。

```
tsc --noEmit (型チェック) → esbuild (バンドル + minify) → dist/index.js
```

### esbuild JS API を選択した理由

esbuild にはプラグイン機構を使えるのは JS API のみという制約がある。
今回は「`@moonshot/*` ワークスペースパッケージはバンドルに含め、npm パッケージは
external にする」という選択的バンドルが必要であり、これには `onResolve` プラグインが
不可欠だったため、CLI ではなく JS API を採用した。

### ビルド成果物

- `apps/api/dist/index.js` — 単一ファイル（minify 済み、約 20KB）
- 外部依存は npm パッケージのみ（`hono`, `drizzle-orm`, `@clerk/backend` 等）
- `@moonshot/db` のスキーマ定義・クライアントはすべてインライン化

## Alternatives Considered

- **tsc のみ（従来方式）:**
  `@moonshot/db` が `.ts` ソースを直接 export しているため、ビルド出力の
  `import { createDb } from "@moonshot/db"` がランタイムで解決できない。
  db にもビルドステップを追加する案もあったが、開発時の DX が悪化するため却下

- **Vite (SSR モード):**
  内部で esbuild + Rollup を使うが、バックエンド API のバンドルには不要な
  抽象レイヤーが増える。HMR やフロントエンド向け機能は不要なため却下

- **Rollup:**
  プラグインエコシステムは豊富だが、esbuild と比較してビルド速度が大幅に劣る。
  現時点で Rollup 固有のプラグインが必要な場面はないため却下

- **tsup:**
  esbuild のラッパーで設定が簡潔だが、プラグインのパススルーが制限される場合が
  あり、直接 esbuild を使う方が透明性が高いため却下

## Consequences

### Positive

- Docker イメージにワークスペースパッケージのソースが不要（`dist/index.js` +
  npm の `node_modules` のみ）
- ビルド時間が極めて短い（< 100ms）
- 単一ファイル出力のため、デプロイ成果物が明確
- `@moonshot/db` はビルドステップ不要のまま維持でき、開発時の DX を損なわない

### Negative

- `scripts/build-api.js` という非 TypeScript ファイルがリポジトリに存在する
  （esbuild の設定ファイル相当だが、初見では用途がわかりにくい）
- ソースマップなし（本番デバッグ時にスタックトレースが読みにくい。必要になれば
  `sourcemap: true` を追加する）
- esbuild は型チェックを行わないため、tsc との 2 段階ビルドが必要
