# 07. Express → Hono Cheat Sheet

実装中に開く用の対応表。**左が Express、右が Hono**。

---

## 1. アプリ起動 / リッスン

```ts
// Express
import express from 'express'
const app = express()
app.listen(3000)
```

```ts
// Hono (Node.js)
import { Hono } from 'hono'
import { serve } from '@hono/node-server'
const app = new Hono()
serve({ fetch: app.fetch, port: 3000 })

// Hono (Cloudflare Workers)
export default app

// Hono (AWS Lambda)
import { handle } from 'hono/aws-lambda'
export const handler = handle(app)
```

---

## 2. ルーティング

```ts
// Express
app.get('/users/:id', (req, res) => {
  res.json({ id: req.params.id })
})
```

```ts
// Hono
app.get('/users/:id', (c) => {
  return c.json({ id: c.req.param('id') })   // ★ return が必要
})
```

| 操作 | Express | Hono |
|---|---|---|
| GET 登録 | `app.get(path, h)` | `app.get(path, h)` |
| 任意メソッド | `app.use(h)` / `app.all(...)` | `app.use(h)` / `app.all(...)` / `app.on(['GET','POST'], path, h)` |
| パラメータ | `req.params.id` | `c.req.param('id')` |
| クエリ | `req.query.q` | `c.req.query('q')` |
| 全クエリ | `req.query` | `c.req.query()` |
| body (JSON) | `req.body` (要 `express.json()`) | `await c.req.json()` |
| body (form) | `req.body` (要 `express.urlencoded()`) | `await c.req.parseBody()` |
| header | `req.headers['x-foo']` | `c.req.header('X-Foo')` |
| Cookie | `req-cookie-parser` | `import { getCookie } from 'hono/cookie'` |
| ファイルアップロード | `multer` | `await c.req.parseBody()` (multipart 標準対応) |

---

## 3. レスポンス

```ts
// Express
res.status(201).json({ ok: true })
res.set('X-Foo', 'bar')
res.redirect('/login')
res.send(buffer)
```

```ts
// Hono — どれも Response を return する
return c.json({ ok: true }, 201)
c.header('X-Foo', 'bar'); return c.text('...')
return c.redirect('/login')
return c.body(buffer)
```

ハマりやすい:
- `c.json(...)` を return せず処理が終わると `'Context is not finalized'` エラー (`hono-base.ts:449`)。

---

## 4. ミドルウェア

```ts
// Express
app.use((req, res, next) => {
  console.log(req.url)
  next()
})

app.use('/api', (req, res, next) => {
  if (!req.headers.authorization) return res.status(401).end()
  next()
})
```

```ts
// Hono
app.use(async (c, next) => {
  console.log(c.req.url)
  await next()                                // ★ await が必要
})

app.use('/api/*', async (c, next) => {        // ★ wildcard を明示
  if (!c.req.header('Authorization')) {
    return c.json({ error: 'unauthorized' }, 401)
  }
  await next()
})
```

|  | Express | Hono |
|---|---|---|
| シグネチャ | `(req, res, next) => void` | `async (c, next) => Promise<Response | void>` |
| 次へ進む | `next()` (同期) | `await next()` (async) |
| エラー throw | `next(err)` | `throw err` (普通に投げる) |
| 早期 return | `res.json(...); return` | `return c.json(...)` |
| path prefix | `app.use('/api', ...)` (= `/api` 配下全部) | `app.use('/api/*', ...)` (= **`*` 明示**) |

---

## 5. エラーハンドリング

```ts
// Express
app.use((err, req, res, next) => {
  res.status(500).json({ error: err.message })
})
```

```ts
// Hono
import { HTTPException } from 'hono/http-exception'

// 投げる側
app.post('/login', async (c) => {
  if (!ok) throw new HTTPException(401, { message: 'bad creds' })
  return c.json({ ok: true })
})

// 受ける側
app.onError((err, c) => {
  if (err instanceof HTTPException) return err.getResponse()
  console.error(err)
  return c.json({ error: 'server error' }, 500)
})

app.notFound((c) => c.json({ error: 'not found' }, 404))
```

---

## 6. ルータのグループ化

```ts
// Express
const users = express.Router()
users.get('/', listUsers)
users.post('/', createUser)
app.use('/users', users)
```

```ts
// Hono
const users = new Hono()
  .get('/', listUsers)
  .post('/', createUser)
app.route('/users', users)
```

ポイント:
- Hono は **method chain** で書くと型 (`Schema`) が蓄積され、`hc<typeof app>()` で client を生やせる。

---

## 7. テスト

```ts
// Express + supertest
import request from 'supertest'
const res = await request(app).get('/users/1').expect(200)
```

```ts
// Hono — 内蔵
const res = await app.request('/users/1')          // Response 標準
expect(res.status).toBe(200)

// 型付き client
import { testClient } from 'hono/testing'
const client = testClient(app)
const res = await client.users[':id'].$get({ param: { id: '1' } })
```

---

## 8. 型の習慣 (Express にはなかった)

```ts
type AppEnv = {
  Bindings: { DB: D1Database; SECRET: string }
  Variables: { user: User; reqId: string }
}

const app = new Hono<AppEnv>()
  .use('*', async (c, next) => {
    c.set('reqId', crypto.randomUUID())
    await next()
  })
  .get('/me', (c) => c.json(c.var.user))

export type AppType = typeof app   // ★ client で import するため
export default app
```

---

## 9. よく使う標準モジュールの import パス

```ts
import { Hono } from 'hono'
import { HTTPException } from 'hono/http-exception'
import { cors } from 'hono/cors'
import { logger } from 'hono/logger'
import { jwt } from 'hono/jwt'
import { secureHeaders } from 'hono/secure-headers'
import { etag } from 'hono/etag'
import { compress } from 'hono/compress'
import { csrf } from 'hono/csrf'
import { bearerAuth } from 'hono/bearer-auth'
import { basicAuth } from 'hono/basic-auth'
import { bodyLimit } from 'hono/body-limit'
import { timeout } from 'hono/timeout'
import { requestId } from 'hono/request-id'
import { prettyJSON } from 'hono/pretty-json'
import { trimTrailingSlash } from 'hono/trailing-slash'
import { contextStorage } from 'hono/context-storage'

import { validator } from 'hono/validator'
// or import { zValidator } from '@hono/zod-validator'

import { getCookie, setCookie, deleteCookie } from 'hono/cookie'
import { stream, streamText, streamSSE } from 'hono/streaming'

import { hc } from 'hono/client'
import { testClient } from 'hono/testing'
```

各 import パスは repo の `package.json` の `exports` フィールドで `src/middleware/<name>/index.ts` 等にマッピングされている。**読みたい時はそのまま `src/middleware/<name>/index.ts` を開けば良い**。

---

## 10. 落とし穴 まとめ

| 落とし穴 | 対策 |
|---|---|
| handler の最後で `c.json(...)` を return し忘れる | "Context is not finalized" エラー → `return` を必ず付ける |
| middleware で `next()` を await し忘れ | 後処理が同期に見えて実は実行前 → 必ず `await next()` |
| `next()` を 2 回呼ぶ | runtime error。条件分岐は片側で early return |
| `app.use('/api', ...)` で `*` を忘れる | 完全一致だけになる → `app.use('/api/*', ...)` |
| `c.set` した key を `Variables` 型に書き忘れ | `c.var.x` の型推論が効かない |
| `Response` を **再度 mutate** したい (header 追加など) | `c.res.headers.set(...)` で OK。setter 内で rewrite される (`context.ts:414`) |
| Express の `req.body` 感覚で `c.req.json()` を await し忘れ | Promise が返るので `await` 必須 |
| `c.executionCtx` を Workers 以外で参照 | "This context has no ExecutionContext" throw |

---

これで来週の実装開始時の手戻りは大部分防げる。`00-overview.md` ~ `06-reading-roadmap.md` と合わせて、必要に応じて辞書的に開く。
