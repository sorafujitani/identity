# 01. Architecture Map — モジュール構造の地図

`src/` の依存関係を、初見で迷子にならない順で並べた構造図。

---

## 1. レイヤー図 (上から下に依存)

```
┌─────────────────────────────────────────────────────────────┐
│  User Code (your API)                                       │
│  import { Hono } from 'hono'                                │
└─────────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────┴───────────────────────────────────┐
│  Entry / Presets                                            │
│  src/index.ts  (re-export)                                  │
│  src/hono.ts   (Hono = HonoBase + SmartRouter(RegExp+Trie)) │
│  src/preset/tiny.ts    (PatternRouter)                      │
│  src/preset/quick.ts   (LinearRouter + TrieRouter)          │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────┴───────────────────────────────────┐
│  Core                                                       │
│  src/hono-base.ts  ── ルーティング登録 / fetch / dispatch    │
│  src/compose.ts    ── koa-compose 風 onion                  │
│  src/context.ts    ── Context (c) / Response builder        │
│  src/request.ts    ── HonoRequest (c.req)                   │
│  src/http-exception.ts ── HTTPException                     │
│  src/types.ts      ── 全公開型 (Env, Handler, ...)           │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────┴───────────────────────────────────┐
│  Router 層                                                  │
│  src/router.ts            ── interface Router<T> / Result<T>│
│  src/router/reg-exp-router/  ── 巨大 regex で O(1) match    │
│  src/router/trie-router/     ── 文字 trie                   │
│  src/router/smart-router/    ── RegExp → Trie の自動切替    │
│  src/router/linear-router/   ── for ループ (登録/動的に強い) │
│  src/router/pattern-router/  ── URLPattern API ベース       │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────┴───────────────────────────────────┐
│  Utils                                                      │
│  src/utils/url.ts, body.ts, headers.ts, html.ts,            │
│  cookie.ts, jwt/, crypto.ts, encode.ts, types.ts ...        │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────┴───────────────────────────────────┐
│  Sideways modules (依存はあるが Core から見ると消費側)         │
│  src/middleware/*  cors, logger, jwt, csrf, secure-headers… │
│  src/helper/*      factory, testing, cookie, streaming, ssg │
│  src/validator/    type-driven validation middleware        │
│  src/client/       hc<typeof app>() — RPC 風 fetch client   │
│  src/jsx/          内蔵 JSX SSR                              │
└─────────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────┴───────────────────────────────────┐
│  Adapter 層 (Core の外、ランタイム差分を吸収)                   │
│  adapter/cloudflare-workers   adapter/cloudflare-pages      │
│  adapter/aws-lambda           adapter/lambda-edge           │
│  adapter/bun                  adapter/deno                  │
│  adapter/vercel               adapter/netlify               │
│  adapter/service-worker                                     │
│  ※ Node.js は @hono/node-server (別 repo)                   │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 重要ファイルの一覧 (行数 = コードの濃さの目安)

| Path | LoC | 役割 |
|---|---:|---|
| `src/index.ts` | 52 | 公開 API の re-export だけ。最初に開く |
| `src/hono.ts` | 34 | `Hono` クラス = `HonoBase` 継承 + default router |
| `src/hono-base.ts` | 539 | **本丸。** `app.get/use/route/mount` 実装 / `#addRoute` / `fetch` / `#dispatch` |
| `src/compose.ts` | 73 | onion 合成。短いので必読 |
| `src/context.ts` | 780 | `Context` 本体。ただし API のドキュ JSDoc 多数。実コードは半分弱 |
| `src/request.ts` | 505 | `HonoRequest`。`param/query/json/form/text/header/valid` 等 |
| `src/router.ts` | 103 | `Router<T>` interface (`add` / `match`) + `Result<T>` 型 |
| `src/router/smart-router/router.ts` | 70 | router 自動選択。短い |
| `src/router/reg-exp-router/router.ts` | ~190 | 最速 router (Trie → 巨大 regex) |
| `src/router/trie-router/node.ts` | ~250 | 汎用 trie。`insert/search` がコア |
| `src/router/linear-router/router.ts` | ~145 | 登録時間 0 / match は O(n) |
| `src/types.ts` | 巨大 | 公開する全型。最初は読まず必要時に grep |
| `src/http-exception.ts` | 79 | `throw new HTTPException(401, ...)` |
| `src/validator/validator.ts` | ~200 | `validator(target, fn)` ミドルウェア |
| `src/client/client.ts` | 大 | `hc<typeof app>()` 実装 |

---

## 3. 「ここを開く順」3 ステップ

1. `src/index.ts` → `src/hono.ts` → `src/hono-base.ts` の **constructor** だけ
   - `app.get / app.post / app.use / app.on` がここでまとめて生成されているのを確認 (`hono-base.ts:127-168`)。
2. `src/hono-base.ts` の `#dispatch` (`:400-460`) → `src/compose.ts`
   - 「**リクエストが来てから handler に到達するまで**」がこの 2 ファイルで完結する。
3. `src/context.ts` を **要点だけ**
   - constructor (`:352`), `req` getter (`:366`), `res` getter/setter (`:403`, `:414`), `text/json/html/body/redirect` (`:682-762`), `set/get/var` (`:546-602`)。
   - 残り (rendering / layout / streaming) は使うときに戻る。

これだけで「Hono を読んだ」と言えるラインに到達する。残りは Router の中身、middleware の作法、adapter の薄さの確認。

---

## 4. 外部の重要パッケージ (この repo に**ない**もの)

- `@hono/node-server` — Node.js 上で `serve({ fetch: app.fetch, port: 3000 })` を提供する公式 adapter。**Express 経験者が来週使うならこれが入口**。
- `@hono/zod-validator` / `@hono/typebox-validator` 等 — `validator/validator.ts` の薄いラッパー。
- `hono/jwt`, `hono/cookie`, `hono/utils/*` のような **sub-export** はこの repo の `src/middleware/`, `src/helper/`, `src/utils/` がそのまま該当する (`package.json` の `exports` で公開)。

---

次は `02-core-request-flow.md` で、実際にリクエストが流れる順にコードを辿る。
