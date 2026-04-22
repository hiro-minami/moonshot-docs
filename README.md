# Moonshot Docs

Moonshot プロジェクトの技術ドキュメント。

📖 **https://hiro-minami.github.io/moonshot-docs/**

## Contents

- **[ADR (Architecture Decision Records)](src/content/docs/adr/)** — 技術選定・設計判断の記録（全 21 件）
- **[Design Documents](src/content/docs/design/)** — プロダクト設計ドキュメント

## Tech Stack

- [Astro](https://astro.build/) + [Starlight](https://starlight.astro.build/) (ADR 022)
- GitHub Pages (GitHub Actions でデプロイ)

## Development

```bash
pnpm install
pnpm dev      # http://localhost:4321/moonshot-docs/
pnpm build    # dist/ に静的サイト生成
```

## About

このリポジトリは [moonshot](https://github.com/hiro-minami/moonshot) 本体の `docs/` を公開するためのものです。
