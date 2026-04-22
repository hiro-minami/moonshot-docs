# ADR 005: TanStack Query (v5) による状態管理と楽観的 UI

- Status: Accepted (Q3 Server Components 境界は継続検討)
- Date: 2026-04-17
- Deciders: Lead Engineer
- Related Open Question: Design Doc Q3

## Context

モードレスなインライン編集を実現するため、サーバーへの保存完了を待たずに UI を
即座に更新する「楽観的 UI(Optimistic UI)」をバグなく実装するためのフロントエンド
キャッシュ戦略が必要だった。

## Decision

データフェッチおよびクライアント状態の管理に **TanStack Query (v5)** を採用する。
Hono RPC クライアント (`hc`) と組み合わせ、インライン編集時の楽観的更新を高度に
制御する。

## Alternatives Considered

- **SWR:**
  Next.js と同じ Vercel 製で軽量だが、`useMutation` 相当の機能における `onMutate`
  (リクエスト前のキャッシュ改変)やエラー時の自動ロールバックの細やかな制御に
  おいて、TanStack Query v5 の方が堅牢であるため却下

- **Redux Toolkit + RTK Query:**
  学習コストとボイラープレート(記述量)が過剰であり、Hono の軽量な RPC クライアント
  (`hc`) の良さを殺してしまうため却下

- **React 19 `useOptimistic`:**
  ネイティブフックだが Next.js Server Actions への依存度が強固であり、外部の
  Hono API と通信する今回の構成では柔軟性に欠けるため保留。Open Question Q3
  (Server Components と TanStack Query の責務分担)が決着した段階で再評価する

## Consequences

### Positive

- インラインでのステータス変更時、遅延を感じさせないネイティブアプリに近い
  操作感を実現できる
- Hono RPC (`hc`) の Fetch 関数をそのまま渡すだけで型安全なデータ層が完成する
- `onMutate` / `onError` / `onSettled` のライフサイクルフックが細かく分かれて
  おり、ロールバック制御が容易

### Negative

- ライブラリのバンドルサイズ(~13KB gzipped)が追加される
- キャッシュキー(Query Keys)の設計を誤ると、意図しないデータの不整合や
  再レンダリングループを引き起こすリスクがある
  (Design Doc の Pre-mortem シナリオ A で最大のリスクとして明記)
- DevTools を入れないとキャッシュ状態のデバッグが難しい
