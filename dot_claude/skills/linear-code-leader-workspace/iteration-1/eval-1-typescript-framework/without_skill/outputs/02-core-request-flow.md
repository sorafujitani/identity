# 02. Core Request Flow — リクエストが流れる順にコードを辿る

サンプル `app.get('/hello/:name', (c) => c.json({ name: c.req.param('name') }))` に対し
`GET /hello/world` が来た場合のフローを、**実際のソース行**を引きながら辿る。

> ファイル参照は全て `/tmp/eval-1/hono/src/` を root とする相対パス。

---

## 0. ステップ 0 — `new Hono()` の時点で何が起きているか

```ts
// hono.ts
export class Hono ... extends HonoBase {
  constructor(options = {}) {
    super(options)
    this.router = options.router ?? new SmartRouter({
      routers: [new RegExpRouter(), new TrieRouter()],
    })
  }
}
```

- `Hono` は `HonoBase` の薄いサブクラス。**router を差し込むだけ**。
- `HonoBase` のコンストラクタ (`hono-base.ts:126-173`) で:
  - `METHODS = ['get','post','put','delete','options','patch']` + `'all'` をループし、`this.get`, `this.post`, ... を **動的に生成** (line 129-141)。
    - 中身は `(args1, ...args) => { this.#addRoute(method, path, handler); return this as any }`。
    - 同じ path に対する複数 handler は `app.get('/x', mw, handler)` のように 1 行で渡せる。
  - `this.on`, `this.use` も同じ要領で生成 (line 144-168)。
  - `getPath` を strict モードに応じて選択 (line 172)。

---

## 1. ステップ 1 — `app.get('/hello/:name', handler)` で何が起きているか

```ts
// hono-base.ts:385-391
#addRoute(method, path, handler) {
  method = method.toUpperCase()
  path = mergePath(this._basePath, path)
  const r: RouterRoute = { basePath: this._basePath, path, method, handler }
  this.router.add(method, path, [handler, r])
  this.routes.push(r)
}
```

ポイント:
- handler を **`[handler, RouterRoute]` のタプル**として router に渡す。後で `route()` 経由のマージや `mount()` で `r` 側のメタデータ (元 path 等) が要るため。
- `SmartRouter#add` は実は **登録時に何もしない**: routes 配列にプッシュするだけ (`router/smart-router/router.ts:13-19`)。
- 実際に regex / trie が build されるのは **最初の `match` 呼び出し時** (lazy)。

---

## 2. ステップ 2 — リクエスト到着: `app.fetch(req, env, ctx)`

```ts
// hono-base.ts:473-479
fetch = (request, ...rest) => {
  return this.#dispatch(request, rest[1], rest[0], request.method)
}
```

- ランタイム adapter は最終的に **`app.fetch(req, env?, ctx?)` を呼ぶだけ**。
- たとえば AWS Lambda adapter:
  ```ts
  // adapter/aws-lambda/handler.ts:252-275
  const req = processor.createRequest(event)
  const res = await app.fetch(req, { event, requestContext, lambdaContext })
  return processor.createResult(event, res, { isContentTypeBinary })
  ```
- Cloudflare Workers では `export default app` するだけで Workers ランタイムが `fetch(req, env, ctx)` を直接呼ぶ。

---

## 3. ステップ 3 — `#dispatch`: コアの中のコア

```ts
// hono-base.ts:400-460 (要約)
#dispatch(request, executionCtx, env, method) {
  if (method === 'HEAD') {
    // GET で dispatch し直して body 抜き Response を返す
    return (async () => new Response(null, await this.#dispatch(request, executionCtx, env, 'GET')))()
  }

  const path = this.getPath(request, { env })           // (1) path 抽出
  const matchResult = this.router.match(method, path)   // (2) match
  const c = new Context(request, {                       // (3) Context 生成
    path, matchResult, env, executionCtx,
    notFoundHandler: this.#notFoundHandler,
  })

  if (matchResult[0].length === 1) {                     // (4) fast path
    let res
    try {
      res = matchResult[0][0][0][0](c, async () => {
        c.res = await this.#notFoundHandler(c)
      })
    } catch (err) { return this.#handleError(err, c) }
    // Promise なら resolve 待ち / そうでなければ即返す
    return res instanceof Promise
      ? res.then(...).catch(err => this.#handleError(err, c))
      : (res ?? this.#notFoundHandler(c))
  }

  const composed = compose(matchResult[0], this.errorHandler, this.#notFoundHandler)
  return (async () => {                                  // (5) onion 実行
    try {
      const context = await composed(c)
      if (!context.finalized) throw new Error('Context is not finalized. ...')
      return context.res
    } catch (err) {
      return this.#handleError(err, c)
    }
  })()
}
```

**ここで覚えるべき 5 つの事**:
1. **path 抽出は差し替え可能** (`getPath` オプション、host header ルーティング用)。
2. **HEAD は GET の薄いラッパー** で実装。
3. `matchResult` は `[[handler, paramIndexMap | params][], paramStash?]` の形 (`router.ts:98` の `Result<T>` 参照)。
4. **handler が 1 つだけなら compose しない** — `c.json()` だけ返すような最頻ケースを最適化。
5. handler が `Response` を返さず `c.res` に書き終わっていなければ `'Context is not finalized'` というエラーになる (Express の `res.send` 忘れに相当)。

---

## 4. ステップ 4 — `compose.ts` の onion

```ts
// compose.ts (要点)
export const compose = (middleware, onError, onNotFound) => {
  return (context, next) => {
    let index = -1
    return dispatch(0)

    async function dispatch(i) {
      if (i <= index) throw new Error('next() called multiple times')
      index = i

      const handler = middleware[i]
        ? middleware[i][0][0]   // (handler, paramMap) の handler 部
        : (i === middleware.length && next) || undefined

      let res, isError = false
      if (handler) {
        try {
          context.req.routeIndex = i   // ← param 解決用に現在 index を持つ
          res = await handler(context, () => dispatch(i + 1))
        } catch (err) {
          if (err instanceof Error && onError) {
            context.error = err
            res = await onError(err, context)
            isError = true
          } else { throw err }
        }
      } else if (context.finalized === false && onNotFound) {
        res = await onNotFound(context)
      }

      if (res && (context.finalized === false || isError)) {
        context.res = res
      }
      return context
    }
  }
}
```

**読みどころ**:
- **`koa-compose` とほぼ同じ**。各 middleware の `next()` で再帰的に次を呼ぶ → onion 構造で前処理/後処理を書ける。
- `next()` を 2 回呼ぶとエラー (line 33-35)。
- `context.req.routeIndex = i` が地味だが重要。同じ Request に対し handler ごとに **path params が違う** ことがあるため (例: `app.use('/api/*', mw)` と `app.get('/api/:id', h)` で `:id` の解決は h の index でしか起きない)。`HonoRequest#param` がこの `routeIndex` を使う (`request.ts:107`)。
- `onError` (= `app.onError(...)` で登録した handler) はここで catch。`HTTPException` の場合は `hono-base.ts:35-42` の default error handler で `err.getResponse()` を返す扱い。

---

## 5. ステップ 5 — handler 内で `c.json(...)` した瞬間

```ts
// context.ts:708-721
json = (object, arg, headers) => {
  return this.#newResponse(
    JSON.stringify(object),
    arg,
    setDefaultContentType('application/json', headers)
  ) as any
}
```

- `#newResponse` (line 604-639) が `this.#preparedHeaders`, `this.#status`, 引数を統合して 1 つの `Response` を作る。
- `c.res` setter (line 414-434) は `this.finalized = true` を立てる。
- **handler が `Response` を return** すると compose の `if (res && ...) context.res = res` で context にセットされ、dispatch の `context.res` がそのまま fetch の戻り値になる。

---

## 6. シーケンス図 (テキスト)

```
[Runtime] --(req)--> [adapter.handle]
                       |
                       v
                     app.fetch(req, env, ctx)
                       |
                       v
                     #dispatch
                       |--> getPath(req)             ── path 抽出
                       |--> router.match(method,p)   ── 初回は build もする
                       |--> new Context(req, {...})
                       |
                       v
                     compose([mw1, mw2, handler], onError, onNotFound)
                       |
                       v
                     dispatch(0)
                       mw1(c, next=()=>dispatch(1))
                         "前処理"
                         await next() ───────────────►
                           mw2(c, next=()=>dispatch(2))
                             "前処理"
                             await next() ─────────►
                               handler(c, next=undef)
                                 return c.json({...})
                             "後処理"
                         "後処理"
                       <───── return context (finalized=true)
                       |
                       v
                     return context.res
                       |
[adapter.handle] <──(Response)──+
       |
[Runtime] <-- adapter が runtime 固有の形式に変換
```

---

## 7. エラー経路

- `throw new HTTPException(401, { message: 'no token' })` のように handler/middleware で投げる。
- `compose.ts:50-59` で catch → `context.error = err` → `onError(err, context)`。
- デフォルト `onError` (`hono-base.ts:35-42`):
  ```ts
  const errorHandler = (err, c) => {
    if ('getResponse' in err) {
      const res = err.getResponse()
      return c.newResponse(res.body, res)
    }
    console.error(err)
    return c.text('Internal Server Error', 500)
  }
  ```
- `app.onError((err, c) => c.json({ error: err.message }, 500))` でユーザがオーバーライドできる。
- `app.notFound((c) => c.json({ msg: 'not found' }, 404))` も同じパターン (`hono-base.ts:291-294`)。

---

これで「初手から最後まで」のソースコード経路を 1 周した。
次は Router の内側 (`03-router-deep-dive.md`)、Context/middleware の API 詳細 (`04-context-and-middleware.md`)。
