# ADR 015: View Transitions API によるページ遷移アニメーション

- Status: Accepted
- Date: 2026-04-19
- Deciders: moonshot-team

## Context

Moonshot の PoC Goals に「View Transitions API によるネイティブライクな状態遷移」が含まれている。現状、ランディングページ → ダッシュボードの遷移は瞬間的なページ切り替えであり、空間的な連続性が感じられない。

React 19.2 (stable) と Next.js 16.2 の組み合わせでは、以下の 2 つのアプローチが存在する:

1. **React `<ViewTransition>` コンポーネント**: 宣言的に per-element アニメーションを制御できるが、React canary (19.3.0-canary) にしか存在しない
2. **CSS-based View Transitions**: `next.config.ts` の `experimental.viewTransition: true` + CSS `view-transition-name` / `::view-transition-*` 疑似要素で制御する。React stable で動作する

## Decision

**CSS-based View Transitions** を採用する。React canary へのアップグレードは行わない。

### 具体的な実装方針

1. **ルート遷移**: Next.js の `experimental.viewTransition: true`（設定済み）により、ルートナビゲーション時にブラウザが自動的に `document.startViewTransition()` を呼ぶ。`::view-transition-old(root)` / `::view-transition-new(root)` の CSS でフェード + blur + 微小な Y 軸シフトを適用する
2. **ヘッダーアンカリング**: ダッシュボードヘッダーに `view-transition-name: site-header` を設定し、ルート遷移中にヘッダーが動かないようにする（空間的アンカー）
3. **ロゴモーフィング**: ランディングとダッシュボードの「moonshot」テキストに同一の `view-transition-name: moonshot-logo` を設定し、サイズ・位置がスムーズに遷移するようにする
4. **コンポーネントアニメーション**: カード追加時の entry アニメーション、Task ステータス Badge の色遷移は CSS transition / animation で対応する（View Transitions API の範囲外）
5. **アクセシビリティ**: `prefers-reduced-motion: reduce` 時に全 View Transition アニメーションを無効化する

### 補足: `experimental.viewTransition` の動作

Next.js 16 では `experimental.viewTransition: true` を設定すると、App Router のルートナビゲーション（`<Link>` クリックや `router.push()`）がブラウザの `document.startViewTransition()` でラップされる。これにより CSS `view-transition-name` を設定した要素が自動的にアニメーション対象になる。React の `<ViewTransition>` コンポーネントは不要。

## Alternatives Considered

### 1. React canary (19.3.0-canary) へのアップグレード

React `<ViewTransition>` コンポーネントによる宣言的な per-element 制御が可能になる。以下の理由で却下:

- canary チャンネルは不安定であり、PoC の信頼性に影響する
- Clerk / TanStack Query 等の依存ライブラリが canary を公式サポートしていない
- CSS-based アプローチで PoC の検証目標（ネイティブライクな遷移体験）は十分達成可能
- 将来 React stable に `<ViewTransition>` が含まれた時点で段階的に移行できる

### 2. Framer Motion / GSAP 等のアニメーションライブラリ

高度なアニメーション制御が可能。以下の理由で却下:

- View Transitions API はブラウザネイティブであり、バンドルサイズ増加なしで利用できる
- PoC のアニメーション要件（ページ遷移 + 要素モーフィング）はブラウザ API で十分
- ライブラリ選定基準（ADR: 標準 API 優先）に従い、外部依存を追加しない

## Consequences

### Positive

- **ゼロバンドルサイズ**: ブラウザネイティブ API + CSS のみで実現。追加の JS ライブラリ不要
- **段階的改善**: CSS ルールの追加・変更のみでアニメーションを調整できる
- **React stable 互換**: canary への依存なし。将来の React バージョンアップ時にリスクがない
- **アクセシビリティ**: `prefers-reduced-motion` による一括無効化が容易

### Negative

- **per-element 制御の限界**: React `<ViewTransition>` の `enter` / `exit` / `share` prop による宣言的制御ができない。CSS `view-transition-name` の手動設定が必要
- **クライアントサイド状態変更は非対応**: 楽観的更新による DOM 変更は `startTransition()` 経由でないと View Transitions API が発火しない。カード追加/削除のアニメーションは CSS animation で個別対応する必要がある
- **ブラウザ互換性**: Safari はView Transitions API のサポートが限定的（2026 年 4 月時点で基本的な crossfade のみ）。非対応ブラウザではアニメーションなしのフォールバック

---

## Appendix: Pitfall — React `<ViewTransition>` は stable にない

React 19.2.5 (stable) で `import { ViewTransition } from 'react'` を試みると `undefined` になる。`<ViewTransition>` は `@types/react/canary.d.ts` に型定義があるが、ランタイムは React 19.3.0-canary にしか含まれない。

Next.js 16 のドキュメントでは `import { ViewTransition } from 'react'` と記載されているが、これは React canary の使用を前提としている。`experimental.viewTransition: true` の設定自体は React stable でも有効で、ルートナビゲーション時の `document.startViewTransition()` ラッピングは機能する。
