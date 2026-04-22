---
title: "ADR 002: Hono と Clean Architecture (手動DI) の採用"
---


- Status: Accepted
- Date: 2026-04-17
- Deciders: Lead Engineer

## Context

バックエンド API の開発において、かつて利用していた tRPC のような高い型安全性
(エンドツーエンドの型共有)を維持しつつ、Next.js から API 層を物理的・論理的に
切り離す必要があった。

また、TypeScript 環境でのドメインロジックの分離において、重厚なオブジェクト指向
フレームワークによるオーバーヘッドは避けたかった。

## Decision

Web フレームワークに **Hono** を採用し、アーキテクチャには高階関数
(Higher-Order Functions)を用いた **手動DI(Dependency Injection)による
Clean Architecture** を適用する。

処理を Controller 層 / Usecase 層 / Repository 層 に分離し、DI ライブラリに
頼らず関数クロージャを用いて依存性を注入する。

## Alternatives Considered

- **tRPC (Next.js 内包型):**
  開発初期のスピードは最速だが、API とフロントエンドが密結合しやすく、将来的な
  API の別クライアントへの切り出し(モバイルアプリ対応等)や、エッジデプロイ時の
  柔軟性に欠けるため却下

- **NestJS:**
  クリーンアーキテクチャと DI を標準で備えるが、クラスベース(OOP)の重厚な記述や
  デコレータの多用が必要であり、今回の「軽量で高速な API」というコンセプトに
  合致しないため却下

- **InversifyJS 等の DI コンテナライブラリ:**
  依存関係の解決を自動化できるが、初期設定の複雑さや、型パズルによるコンパイル
  エラーの追跡の難しさが、手動 DI のシンプルさに劣ると判断し却下

## Consequences

### Positive

- Hono の RPC 機能 (`hc`) により、フロントエンドへ Zod ベースの型を自動提供できる
- Usecase 層にフレームワークの知識が一切入らないため、Repository 層をモックの
  関数に差し替えるだけで、DB を必要としない爆速なユニットテスト(Vitest)が可能
- 関数ベースの軽量な記述で、コールドスタートの影響を最小化できる

### Negative

- tRPC やシンプルな Express ルーターと比較すると、Controller / Usecase /
  Repository と複数のファイルを作成するボイラープレート(記述量)の増加が
  避けられない
- 深くネストした依存関係が発生した場合、手動 DI のバケツリレーが煩雑になるリスク
  がある(発生時は再評価してDIコンテナ導入を検討)
