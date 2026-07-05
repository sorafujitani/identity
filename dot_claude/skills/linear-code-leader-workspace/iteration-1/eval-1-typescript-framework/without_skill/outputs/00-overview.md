# Hono Onboarding — Overview & Mental Model

> 対象: TypeScript + Express 経験者 / hono 初見 / 半日で全体像と中核フローを掴む
> 元リポジトリ: `/tmp/eval-1/hono` (honojs/hono, v4.12.19)

---

## 1. Hono を 1 段落で

Hono は **Web Standards (Fetch API / Request / Response)** だけで動く、ランタイム非依存の超軽量 Web フレームワーク。アプリ本体は「**1 つの `fetch(request) => Response` 関数**」に集約され、Cloudflare Workers / Deno / Bun / AWS Lambda / Node.js などの差異は **adapter** が吸収する。Express でいう `app.listen` や Node `http` の世界は完全に外に出ていて、Hono のコアは「ルータ + ミドルウェアコンポーザ + Context オブジェクト」の薄い層しか持たない。

---

## 2. Express 経験者向けの 3 つの「翻訳」

| Express | Hono | コメント |
|---|---|---|
| `app.get('/x', (req, res) => res.json({...}))` | `app.get('/x', (c) => c.json({...}))` | `req`/`res` が 1 つの `Context` (`c`) に統合され、handler は **`Response` を return する** |
| `(req, res, next) => { ...; next() }` | `(c, next) => { ...; await next() }` | `next` は同期コールバックではなく **async function**。`koa-compose` 系のスタイル |
| `app.listen(3000)` (Node) | `export default app` (Workers) / `serve(app)` (Node, `@hono/node-server`) | listen はコアにない。**adapter** がランタイムごとに `fetch` を呼び出す |

これだけ押さえれば、サンプルコードはほぼ読める。

---

## 3. 中核フロー (Request → Response) を一行で

```
Request
  → adapter (ランタイム → 標準 Request に正規化)
  → Hono#fetch
  → Hono#dispatch (path 抽出 → router.match → Context 生成)
  → compose([mw1, mw2, ..., handler]) (koa スタイル onion)
  → handler が Response を return
  → c.res が finalize される
  → dispatch が Response を返す
  → adapter (Response → ランタイム固有レスポンスに戻す)
```

ファイル単位だと:
`adapter/*/handler.ts` → `src/hono-base.ts#fetch/#dispatch` → `src/compose.ts` → ユーザの handler → `src/context.ts`(`c.json` 等) → back up.

---

## 4. パッケージ構造の俯瞰 (src/ 直下)

| ディレクトリ / ファイル | 役割 | 重要度 |
|---|---|---|
| `index.ts` | エントリ。`Hono` クラスと型を re-export | ★ (ざっと見る) |
| `hono.ts` | `Hono` クラス本体 (= `HonoBase` + デフォルト router) | ★★ |
| `hono-base.ts` | ルーティング登録 / `fetch` / `dispatch` / `mount` / `route` 等の本体。**ここが心臓部** | ★★★ |
| `context.ts` | `Context` (= `c`) オブジェクト。`c.json`, `c.text`, `c.req`, `c.var` ... | ★★★ |
| `request.ts` | `HonoRequest` (= `c.req`)。`param`, `query`, `json`, `valid` 等 | ★★ |
| `compose.ts` | koa-compose 風の onion 合成。**わずか 73 行**、必読 | ★★★ |
| `router.ts` | `Router<T>` インタフェース定義 + `Result<T>` 型 | ★★ |
| `router/*` | 5 種類の router 実装 (後述) | ★★ (RegExp + Smart を中心に) |
| `types.ts` | `Env`, `Handler`, `MiddlewareHandler`, `Schema` 型のフォーマット定義 | ★ (必要時に参照) |
| `http-exception.ts` | `HTTPException` クラス (ミドルウェア中で `throw` して 4xx/5xx を返す) | ★ |
| `middleware/*` | 標準ミドルウェア (cors, logger, jwt, csrf, secure-headers, etag, timeout, ...) | ★ (使うとき) |
| `helper/*` | factory, testing, cookie, streaming, ssg, route 等のユーティリティ | ★ (使うとき) |
| `adapter/*` | aws-lambda / cloudflare-workers / bun / deno / vercel / netlify / lambda-edge / cloudflare-pages / service-worker | ★★ (デプロイ先のだけ) |
| `preset/tiny.ts`, `preset/quick.ts` | router を入れ替えた `Hono` 別ビルド | ★ |
| `validator/` | 型安全な request validator (zod-validator 等の土台) | ★★ (来週から API 書くなら) |
| `client/` | `hc<typeof app>()` — RPC 風型付き fetch クライアント | ★ (将来) |
| `jsx/` | Hono 内蔵 JSX (server-side rendering) | API 用途では基本不要 |

---

## 5. なぜ「速い」と言われるか (アーキテクチャ視点)

3 つのレイヤーで効率化が積まれている:

1. **Web Standards 直結** — Node の `http` モジュールや Express の `req.body` パーサのオーバーヘッドなし。
2. **`RegExpRouter`** — 全ルートを 1 つの巨大 regex に compile して、O(1) 相当でマッチ。初回 match 時に build される (lazy)。
3. **`SmartRouter`** — `RegExpRouter` → 失敗したら `TrieRouter` にフォールバック。最初の `match` 呼び出しでどちらを使うか確定し、以降は `match` を bind して書き換え (`hono-base.ts` ではなく `router/smart-router/router.ts:46`)。
4. **single-handler fast path** — `hono-base.ts:#dispatch` で `matchResult[0].length === 1` のときは `compose` を呼ばず handler を直接実行 (line 424-442)。

---

## 6. 4 つのキーコンセプト

1. **`Hono` インスタンス = ルートテーブル + dispatch 関数**
   - `app.get/post/use/on/route/mount` で登録するだけ。
   - `app.fetch(req, env, ctx)` が唯一の入口。
2. **`Context` (`c`) = リクエスト/レスポンスのファサード**
   - `c.req` (HonoRequest), `c.res` (Response, lazy), `c.env` (Workers の bindings 等), `c.var`/`c.get`/`c.set`, `c.json/text/html/body/redirect/notFound`, `c.executionCtx`。
3. **ミドルウェアは Promise を返す koa スタイル**
   - 形: `(c, next) => Promise<Response | void>`。`await next()` の前後で前処理/後処理。`return c.json(...)` で短絡可能。
4. **Type-driven API**
   - `app.get('/users/:id', (c) => { c.req.param('id') /* typed as string */ })`。
   - `app.get(...).post(...)` のチェーンで `Schema` 型がビルドされ、`hc<typeof app>()` で RPC 風の型付き client を生成できる。

---

## 7. 半日プラン (詳細は `06-reading-roadmap.md`)

- **0:00 - 0:30** 本ファイル + README + `src/index.ts` + `src/hono.ts`
- **0:30 - 1:30** `hono-base.ts` (constructor → `#addRoute` → `fetch` → `#dispatch`) + `compose.ts`
- **1:30 - 2:30** `context.ts` (要点だけ。`c.req` getter / `c.json` / `c.set/get/var`) + `request.ts`
- **2:30 - 3:30** Router 群 (`router.ts` インタフェース → `smart-router/router.ts` → `reg-exp-router/router.ts` の概要 → `trie-router/node.ts` の `insert/search`)
- **3:30 - 4:00** 使いそうな middleware を 1 つ (`cors` または `logger`) を読み、`validator/validator.ts` を流し読み
- **4:00 - 4:30** 採用予定の adapter (Cloudflare Workers なら `adapter/cloudflare-workers/`, Node なら `@hono/node-server` 別パッケージ) と `helper/testing` を確認

---

次は `01-architecture-map.md` で構造の地図、`02-core-request-flow.md` で実コードを辿る形のトレースに進む。
