# 04. Context & Middleware — 毎日触る API のリファレンス

Hono のユーザ視点で見えるのはほぼ `Context` (= `c`) と middleware の作法だけ。ここを抑えれば来週から書ける。

---

## 1. `Context` (`c`) の主要 API

実装: `src/context.ts`。780 行あるが、半分は JSDoc。実用上覚えるのは下記。

### リクエスト読み取り (`c.req` 経由)

| API | 戻り値 | 備考 |
|---|---|---|
| `c.req.raw` | `Request` | Web 標準オブジェクトそのもの |
| `c.req.method` | `string` | — |
| `c.req.url` | `string` | — |
| `c.req.path` | `string` | パス部分のみ |
| `c.req.param('id')` | `string` (or `undefined` for `?` 付き) | path パラメータ |
| `c.req.param()` | `Record<string,string>` | 全 param |
| `c.req.query('q')` / `c.req.query()` | `string`/`undefined` または `Record<string,string>` | クエリ |
| `c.req.queries('tags')` | `string[]` | 同名複数 (`?tags=a&tags=b`) |
| `c.req.header('X-Foo')` / `c.req.header()` | `string` / `Record` | リクエストヘッダ |
| `await c.req.json()` | `unknown` (validator あれば typed) | body キャッシュあり |
| `await c.req.text()` | `string` | |
| `await c.req.formData()` | `FormData` | |
| `await c.req.parseBody()` | `BodyData` | multipart/x-www-form-urlencoded を統合 |
| `c.req.valid('json' \| 'query' \| 'form' \| ...)` | validator が書き込んだ型付き値 | `validator` middleware と組み合わせ |
| `c.req.routePath` | `string` | match した route の元 path (e.g. `/users/:id`) |
| `c.req.matchedRoutes` | `RouterRoute[]` | デバッグ用 |

### レスポンス作成

| API | 例 | 内部 |
|---|---|---|
| `c.text('hi')` | `text/plain` で返す | `context.ts:682-694` |
| `c.json({ok:true})` | `application/json` | `:708-721` |
| `c.html(<MyComp/>)` | JSX を HTML に | `:723-733` |
| `c.body(buffer, 200, {...})` | 任意の body | `:664-668` |
| `c.notFound()` | 登録された `notFound` handler を実行 | `:776-779` |
| `c.redirect('/login', 302)` | Location header + status | `:750-762` |
| `c.newResponse(data, init)` | 低レベル | `:641` |
| `c.header('X-Foo','v')` | response header 書き込み | `:515-527` |
| `c.status(201)` | response status を先にセット | `:529-531` |

ハマりやすい点:
- handler は **必ず `Response` を `return`** すること。`c.text(...)` 等は **Response を作るだけ** で、自動送信されない (Express の `res.send` とは違う)。
- `c.res = response` のように setter に代入する書き方もあるが、`return response` が一般的。

### State / DI

| API | 用途 |
|---|---|
| `c.set('user', user)` | middleware 内で値を入れる |
| `c.get('user')` | handler で取り出す。**型推論される** (後述) |
| `c.var.user` | `c.get` の読み取り専用 alias (TypeScript で補完されやすい) |
| `c.env` | Cloudflare Workers の bindings (KV, D1, R2, env vars) |
| `c.executionCtx` | `waitUntil` / `passThroughOnException`。Workers 等 |
| `c.event` | Service Worker 環境の FetchEvent |
| `c.error` | onError 内で `err` (`compose.ts:54` でセット) |

### Rendering (JSX 系)

| API | 用途 |
|---|---|
| `c.setRenderer((content)=>c.html(<Layout>...</Layout>))` | middleware でレイアウト注入 |
| `c.render(<Page/>)` | 上記 renderer を通して HTML を返す |
| `c.setLayout(layout)` / `c.getLayout()` | ネスト layout |

API サーバ用途では基本不要。

---

## 2. ミドルウェアの書き方 (3 パターン)

### (a) 標準形

```ts
import type { MiddlewareHandler } from 'hono'

export const tracker = (): MiddlewareHandler => async (c, next) => {
  const start = Date.now()
  await next()                        // ← 下流を実行
  c.res.headers.set('X-Time', `${Date.now() - start}ms`)
}
app.use('*', tracker())
```

ポイント:
- `await next()` の前 = リクエスト処理前 / 後 = レスポンス処理後。
- `next()` を呼ばないと下流に行かない (= short-circuit)。
- `c.res` は handler 確定後、setter が `finalized=true` を立てている。後処理で header を書くだけなら `c.res.headers.set` で OK (`context.ts:414-434` で getter が新しい Response を作って返す挙動を確認)。

### (b) 早期 return (Express の `res.json(...); return;` に相当)

```ts
export const requireAuth: MiddlewareHandler = async (c, next) => {
  const token = c.req.header('Authorization')
  if (!token) {
    return c.json({ error: 'unauthorized' }, 401)   // ← await next() しない
  }
  c.set('user', verify(token))
  await next()
}
```

### (c) HTTPException で投げる (推奨パターン)

```ts
import { HTTPException } from 'hono/http-exception'

export const requireAuth: MiddlewareHandler = async (c, next) => {
  const token = c.req.header('Authorization')
  if (!token) {
    throw new HTTPException(401, { message: 'unauthorized' })
  }
  await next()
}
```

`compose.ts` で `onError` に届き、デフォルト errorHandler (`hono-base.ts:35`) が `err.getResponse()` を呼んで 401 を返してくれる。

---

## 3. middleware の登録方法

```ts
app.use(mw)                  // 全 path に適用 (path='*')
app.use('/api/*', mw)        // /api/ 配下のみ
app.use('/api/*', mw1, mw2)  // 複数同時
app.get('/users/:id', mw1, mw2, handler)  // route 単位の middleware
```

実装: `hono-base.ts:157-168` (`use`), `:129-141` (method)。
**全部最終的に `#addRoute(method, path, handler)` を呼ぶだけ**。`use` の場合は method を `'ALL'`、path 省略時は `'*'`。

---

## 4. `app.route` / `app.basePath` / `app.mount`

### `app.route(path, subApp)` — Express の `app.use('/api', router)` 相当

```ts
const users = new Hono()
users.get('/', ...).post('/', ...)
const app = new Hono()
app.route('/users', users)
```

実装 (`hono-base.ts:208-232`):
- `subApp = this.basePath(path)` で base path を持つ clone を作り、
- `app.routes` を 1 件ずつ `subApp.#addRoute(...)` で **親の router に再登録**。
- ここで `app.errorHandler` がオーバーライドされていれば、その errorHandler を「子だけに」適用するため `compose([], app.errorHandler)` でラップする (line 224-226)。

つまり子 Hono は最後に **「ルート定義の運び屋」** として消費される。実行時には親の router 1 つだけが動く。

### `app.basePath(path)`

```ts
const api = new Hono().basePath('/api/v1')
api.get('/users', ...)         // GET /api/v1/users
```

実装は `#clone()` + `_basePath` 書き換え (`hono-base.ts:247-253`)。

### `app.mount(path, anotherFetch)`

Hono 以外のフレームワーク (itty-router, anywhere `fetch`-shaped handler) を組み込める (`hono-base.ts:328-383`)。実体は middleware を 1 つ生やして、URL を rewrite してから外部の handler に流すだけ。

---

## 5. 推奨される実装パターン

### Variables を型付ける

```ts
type Variables = { user: User; reqId: string }
const app = new Hono<{ Variables: Variables }>()

app.use('*', async (c, next) => {
  c.set('reqId', crypto.randomUUID())   // c.set の引数が typed
  await next()
})

app.get('/me', (c) => {
  const u = c.var.user      // user: User
  return c.json(u)
})
```

`Context<E, P, I>` の `E['Variables']` が `c.set/get/var` の型を駆動する (`context.ts:546-602`)。

### Bindings (Cloudflare Workers)

```ts
type Bindings = { DB: D1Database; KV: KVNamespace; API_KEY: string }
const app = new Hono<{ Bindings: Bindings }>()
app.get('/', (c) => c.text(c.env.API_KEY))
```

### グローバル onError / notFound

```ts
app.notFound((c) => c.json({ error: 'not found' }, 404))
app.onError((err, c) => {
  if (err instanceof HTTPException) return err.getResponse()
  console.error(err)
  return c.json({ error: 'server' }, 500)
})
```

---

## 6. 「composed handler」の小ネタ

`hono-base.ts:226` で:

```ts
;(handler as any)[COMPOSED_HANDLER] = r.handler
```

これは `app.route(path, subApp)` 経由で **エラーハンドラを内蔵した形** に wrap した時、元の handler を symbol で保持するための物 (`utils/constants.ts` の `COMPOSED_HANDLER` 参照)。テストや debug helper が元 handler を取り出すのに使う。初見では知らなくて OK、コードを読んでて謎の symbol が出てきたら思い出す程度。

---

次は `05-typescript-and-validator.md`。Hono の最大セールスポイントの 1 つ「型」を整理する。
