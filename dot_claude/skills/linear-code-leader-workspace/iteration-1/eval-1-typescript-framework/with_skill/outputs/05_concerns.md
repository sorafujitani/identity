# Phase 5: 横断的関心事

ユーザーの目的は「来週から Hono で API を書き始める」ので、API 実装に効く関心事を優先する。

## 1. エラーハンドリング

- **基本原則**: ハンドラ/ミドルウェア内で `throw` すると `compose` (`src/compose.ts:52-60`) が捕まえ、`HonoBase` の `errorHandler` (`src/hono-base.ts:35-42`) に流す。`finalized=true` で `c.res` に Response がセットされる。
- **標準例外型**: `HTTPException` (`src/http-exception.ts`)。`status` と省略可能な `res` を持ち `getResponse()` で `Response` を返す。Errorhandler 側は `'getResponse' in err` で分岐 (`src/hono-base.ts:36-39`)。
- **カスタマイズ**: `app.onError((err, c) => c.json({ error: ... }, 500))` (`src/hono-base.ts:271-274`)。
- **NotFound**: `app.notFound((c) => ...)` (`src/hono-base.ts:291-294`)。`compose` の最深部で `onNotFound` が呼ばれる (`src/compose.ts:62-65`) か、シングルハンドラ高速パスでも呼ばれる (`src/hono-base.ts:424-442`)。
- **使い方の指針**: 認証/認可で 401・403 を返すなら `throw new HTTPException(401, { message: '...' })`。バリデーション失敗は `validator` ミドルウェアが内部で `HTTPException` を投げる仕組み (`src/validator/validator.ts`)。

## 2. 認証 / 認可

- **方式**: ミドルウェアで実装するのが基本パターン。標準同梱は `basic-auth`, `bearer-auth`, `jwt`, `jwk` (`src/middleware/`)。
- **例**: `src/middleware/bearer-auth/index.ts` は `Authorization: Bearer <token>` を見て、`timingSafeEqual` で照合し、失敗時に `throw new HTTPException(401, { res: ... })`。
- **配置**: 認可ロジックは「ハンドラの前段ミドルウェア」として置く。`app.use('/api/*', bearerAuth({ token: ... }))` のように。
- **JWT**: `src/middleware/jwt/index.ts` は `c.set('jwtPayload', payload)` で `c.var.jwtPayload` から型付きアクセス可能にする (型は `Variables` 経由で渡す)。
- **指針**: Express の `app.use(authMiddleware)` と全く同じ感覚で書ける。ただし `req.user` 相当は `c.set('user', ...)` / `c.var.user` で扱う。

## 3. ロギング・観測性

- **同梱**: `src/middleware/logger/` (`logger.ts` ではなく `index.ts`)、`src/middleware/timing/` (Server-Timing)、`src/middleware/request-id/`。
- **`console` ベース**: Hono 自体は console.error 程度しか使わない (`src/hono-base.ts:40`)。本番ロガーは pino/ など外部を `app.use` で接続。
- **トレース**: `ExecutionContext.waitUntil(...)` を使って fire-and-forget の送信を寿命に紐づけられる (`src/context.ts:31-52`)。

## 4. 設定管理

- **Cloudflare 流の `env` バインディング**: `app.fetch(req, env, ctx)` の第 2 引数が `c.env` として渡される (`src/hono-base.ts:415-421` の Context 構築)。型は `Env['Bindings']`。
- **Node 等で .env を使う場合**: 利用者側で `process.env` を `c.env` に注入する/直接参照する。Hono 自体はランタイム非依存のため env 読込は持たない。
- **型付け**: `new Hono<{ Bindings: { DB: D1Database }, Variables: { user: User } }>()` のジェネリクスで `c.env.DB` と `c.var.user` の型がつく。

## 5. 永続化 / トランザクション

- Hono はストレージ抽象を持たない (フレームワーク責務外)。
- ただし `c.executionCtx.waitUntil(...)` で「Response 返却後にバックグラウンドで完了させる」ことができ、これがログ/メトリクス送信/二段 DB 書込みのよくある拠り所。

## 6. 非同期 / 並行性

- 全ハンドラは `async (c, next) => ...` 形。`compose` 内で `await handler(...)` (`src/compose.ts:51`) するので、ハンドラが Promise を返せば直列に実行される。
- 並列処理は利用者責任 (`Promise.all` を c.json の中で呼ぶ等)。
- 「`next()` を 2 回呼ぶ」は禁止 (`src/compose.ts:33-35` でガード)。

## 7. テスト戦略

- 同梱: vitest + Multi-project (cloudflare/workerd/node/bun/deno/lambda/fastly/lambda-edge) — `vitest.config.ts`, `runtime-tests/`。
- Hono アプリのテストは `app.request('/path', { method: 'POST', body: ... })` で実行可能 (`src/hono-base.ts:493-511`)。Express の supertest 相当が組み込み。
- ユニットテスト例: `src/hono.test.ts` (107k 行近い網羅テスト) を読むとほぼ全 API の使用例が分かる。**API 利用時の辞書代わりになる最良の資料**。

## 8. 型システム (Hono 特有・必読)

- `src/types.ts` (≈90k 行!) が型推論の中枢。`Handler<E,P,I,R>` / `HandlerInterface` / `Schema` / `ToSchema` / `MergePath` / `Input` 等。
- `app.get('/users/:id', ...)` の `'/users/:id'` から `c.req.param('id'): string` が静的に出る。`P extends string` のパス文字列リテラルを `ParamKeys<P>` で解析。
- `app` の型を `typeof app` として `hc<typeof app>('http://...')` (`src/client/`) に渡すと、メソッド/パス/入出力すべてが型付いた fetch クライアントが得られる (= tRPC ライク)。
- バリデータ (`src/validator/validator.ts`) は `c.req.valid('json')` の戻り値型を Schema に積む。
- 指針: **新規 API では `new Hono<{ Bindings, Variables }>()` でジェネリクスを最初に決め、ルートごとに validator + handler 形式を採用すると型推論が最大限効く**。
