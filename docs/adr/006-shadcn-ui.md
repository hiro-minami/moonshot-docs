---
layout: default
title: "ADR 006: shadcn/ui + Tailwind CSS v4 による UI 基盤"
---

# ADR 006: shadcn/ui + Tailwind CSS v4 による UI 基盤

- Status: Accepted
- Date: 2026-04-17
- Deciders: Lead Engineer
- Related: ADR 010 (デザイントークン管理)

## Context

「深宇宙 × 星の光」という独自のダークモード・デザインシステム(Moonshot カラー
トークン)を構築するにあたり、アクセシビリティを担保しつつ極限までカスタマイズ
できる UI ライブラリが必要だった。

## Decision

UI 基盤に **shadcn/ui** を採用し、スタイリングに **Tailwind CSS v4** を用いる。
Tailwind v4 は CSS-first configuration(`@theme` ディレクティブによる CSS 内
設定)を採用しており、shadcn/ui の CSS 変数ベースのテーマ管理と自然に統合される。

独自のカラートークン(Violet, Cyan 等)の具体的な管理方式は ADR 010 を参照。

## Alternatives Considered

- **MUI (Material-UI):**
  コンポーネントは充実しているが、Google マテリアルデザインの思想が強く、
  Moonshot の独自の世界観(ダークモード、ネオン発光)に上書きするための CSS
  オーバーライド工数が高いため却下

- **Chakra UI:**
  優れた DX とアクセシビリティを持つが、内部構造が隠蔽されているため、複雑な
  アニメーションや Glow 効果のカスタマイズに限界があると判断し却下

- **Tailwind CSS v3 (従来版):**
  `tailwind.config.ts` ベースの設定は長年のベストプラクティスだが、v4 の
  CSS-first configuration への業界移行が進んでおり、新規プロジェクトを v3 で
  始めると半年以内に技術的負債化するため却下

## Consequences

### Positive

- コンポーネントが npm パッケージではなく生コードとしてリポジトリにコピー
  されるため(コードの所有)、Tailwind のクラスを用いてデザインの隅々まで完全に
  制御できる
- 裏側の Radix UI により、キーボードナビゲーション等の WAI-ARIA アクセシビリティが
  初期状態で担保される
- Tailwind v4 の `@theme` ディレクティブにより、`tailwind.config.ts` を介さず
  CSS ファイル内で設定が完結する(管理ファイル数削減)
- OKLCH 色空間のネイティブサポート(ADR 010 参照)
- Tailwind v4 の JIT とツリーシェイクでバンドルサイズを最小化できる

### Negative

- ライブラリ自体の自動アップデートの恩恵を受けられない(新機能やバグ修正は
  手動で `npx shadcn@latest add` 等でコードを取り込む必要がある)。
  四半期ごとの棚卸し運用を想定
- チームメンバー全員に対して Tailwind CSS の高いリテラシーが要求される
- デザイントークンの一貫性を自分たちで維持する責任が生じる(ADR 010 で
  3 層構造の規約を定義)
- Tailwind v4 は 2025 年に登場したばかりで、周辺エコシステム(ライブラリや
  ドキュメント)が v3 と比べて成熟途上。トラブル時の情報源が v3 に偏る可能性
