---
title: "ADR 010: デザイントークンと CSS 変数を用いたテーマ管理"
---


- Status: Accepted
- Date: 2026-04-17
- Deciders: Lead Engineer
- Related: ADR 006 (shadcn/ui + Tailwind CSS)

## Context

Moonshot 特有の「深宇宙 × ネオン (Violet / Cyan)」というダークモード・
ファーストの世界観を実装するにあたり、UI 全体のトーン & マナーを統一し、
後からのカラー調整を容易にする仕組みが必要だった。

コンポーネント内にカラーコード(例: `bg-[#0f172a]`)をハードコードすると
保守性が著しく低下する。また、ADR 006 で採用した shadcn/ui (Tailwind v4 ベース) は
CSS 変数ベースのテーマ管理を前提としており、その設計思想に整合させる必要があった。

## Decision

**Tailwind CSS v4 の CSS-first configuration** と **OKLCH 色空間**を採用し、
以下の 3 層構造でデザイントークンを管理する:

1. **プリミティブトークン層** (`:root` 内): `--moonshot-violet-500` のような
   生の色値を OKLCH で定義
2. **セマンティックトークン層** (`:root` および `.dark` 内): `--primary` や
   `--background` のような用途ベースの割当
3. **Tailwind 公開層** (`@theme inline` ディレクティブ): セマンティック
   トークンを `--color-primary` として Tailwind ユーティリティに公開

この方式は shadcn/ui の公式テーマ管理方式と完全に一致する。
`tailwind.config.ts` は基本的に使用せず、すべての設定を `globals.css` の
`@theme` / `@theme inline` ディレクティブ内で完結させる。

## Alternatives Considered

- **Tailwind v3 + `tailwind.config.ts` の `theme.extend`**:
  従来の方式だが、v4 の CSS-first configuration への移行が業界標準。2026 年時点で
  新規プロジェクトを v3 で始めるのは技術的負債化するため却下

- **HSL 色空間**:
  shadcn/ui の初期版で使われていた形式だが、知覚的均一性に劣り、ダークモードでの
  アクセシビリティ制御が難しい。また sRGB 限定のため、Moonshot のネオン発光の
  鮮やかさを P3 以上の wide gamut で表現できないため却下

- **CSS-in-JS (Emotion / styled-components)**:
  動的スタイリングには強力だが、Next.js App Router の Server Components との
  互換性が低く、パフォーマンスのオーバーヘッドがあるため却下

- **Panda CSS / Vanilla Extract**:
  zero-runtime CSS-in-JS として優秀だが、shadcn/ui は Tailwind v4 前提で設計
  されており、置き換えコストと Tailwind エコシステム (tweakcn 等のツール)
  の喪失が過大なため却下

- **Open Props (プリミティブ層のみ採用案)**:
  汎用 CSS 変数集として採用する案も検討。プリミティブ層を自作する手間は省けるが、
  Moonshot 独自のネオン色階調を最初から設計したかったため却下

- **Tailwind Arbitrary Values (`text-[#8B5CF6]` ベタ書き)**:
  小規模なら早いが、Moonshot のような独自ブランドの統一感を保つには
  意味論的な命名ができないため却下

## Consequences

### Positive

- 開発者は `text-primary` や `bg-background` のような意味論的な Tailwind
  クラスを使うだけでよく、デザイン変更は `globals.css` のセマンティック層を
  1 箇所書き換えるだけでシステム全体に適用される
- OKLCH による知覚的均一性で、ダークモードのコントラスト調整が `L` 値の調整
  だけで直感的に行える
- wide gamut (P3) サポート対応画面で、ネオン発光の鮮やかさが最大化される
- shadcn/ui 公式のテーマ管理方式と完全一致するため、新規コンポーネント追加時の
  カスタマイズコストが最小化される
- プリミティブ / セマンティックの 2 層分離により、将来のリブランド時は
  セマンティック層のみの書き換えで済む

### Negative

- CSS 変数の 3 層構造(プリミティブ / セマンティック / Tailwind 公開)を
  チーム全体で正しくメンテしていく規約が必要になる
- OKLCH は HSL に比べて一部の旧ブラウザ(~2023 年以前)でサポートが弱い
  (ターゲットユーザーはエンジニア/モダンブラウザ使用のため実用上問題なし)
- tweakcn 等の外部テーマジェネレータでベーステーマを作成後、手動で Moonshot
  独自色に調整するワークフローを確立する必要がある

## 実装メモ

### ファイル構成

```
apps/web/src/app/globals.css   # すべてのトークン定義をここに集約
```

### 3 層構造の実装例

```css
/* layer 1: プリミティブトークン */
:root {
  --moonshot-violet-500: oklch(0.62 0.26 295);
  --moonshot-cyan-400: oklch(0.8 0.15 210);
  --moonshot-deep-space: oklch(0.12 0.02 270);
  --moonshot-star-dust: oklch(0.95 0.02 270);
}

/* layer 2: セマンティックトークン (ダークモード優先) */
:root {
  --background: var(--moonshot-deep-space);
  --foreground: var(--moonshot-star-dust);
  --primary: var(--moonshot-violet-500);
  --accent: var(--moonshot-cyan-400);
}

.dark {
  /* ダークモード用の上書き (Moonshot は基本ダークのため差分は最小) */
}

/* layer 3: Tailwind への公開 */
@theme inline {
  --color-background: var(--background);
  --color-foreground: var(--foreground);
  --color-primary: var(--primary);
  --color-accent: var(--accent);
}
```

### デザインツール連携

Solo 開発期間中は Figma 等のデザインツールは使用せず、ブラウザ DevTools +
[tweakcn](https://tweakcn.com/) による直接調整で進める。OKLCH の値は DevTools
でライブ編集できるため、Figma 経由での往復作業より効率的。

将来デザイナー参画時は、`globals.css` のプリミティブ層 (`--moonshot-*` 値) を
Figma Variables に移植することでトークン整合を保つ方針とする。

### 命名規則

- プリミティブ: `--moonshot-{色名}-{階調}` (例: `--moonshot-violet-500`)
- セマンティック: shadcn/ui 標準に準拠 (`--primary`, `--background`,
  `--accent`, `--muted`, `--destructive` 等)
- Tailwind 公開: shadcn/ui 標準の `--color-*` プレフィックス
