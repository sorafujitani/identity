# 05. TypeScript & Validator — 型駆動 API の組み立て方

Express 経験者がいちばん驚くのが Hono の型システム。**ルートを定義した瞬間に "そのアプリの API スキーマ" 自体が型として育つ** ようになっている。

---

## 1. 型のジェネリクス全体像

```ts
// hono-base.ts:98-103
class Hono<
  E extends Env = Env,             // Bindings + Variables (実行時環境とアプリ内 state)
  S extends Schema = {},           // ルートが追加されるたび蓄積される "API スキーマ"
  BasePath extends string = '/',   // basePath() で動くやつ
  CurrentPath extends string = BasePath
>
```

- `E` = `{ Bindings?: ..., Variables?: ... }` (`types.ts:30-33`)
- `S` = ルート毎に `{ '/path': { 'get': { input, output } } }` の形で積まれる (`types.ts` 内 `Schema`, `ToSchema`)
- `BasePath` / `CurrentPath` = string literal 型として保持され、`basePath('/api')` で `MergePath` される

ユーザ側で意識するのは **`E`** だけで十分。`S` は内部で自動的に育つ。

---

## 2. `Env` を 1 回だけ定義する流儀

```ts
type AppEnv = {
  Bindings: {
    DB: D1Database
    JWT_SECRET: string
  }
  Variables: {
    user: { id: string; email: string }
    requestId: string
  }
}

const app = new Hono<AppEnv>()
```

これだけで:
- `c.env.DB` / `c.env.JWT_SECRET` の補完
- `c.set('user', ...)` の引数 / `c.var.user` の戻り値が型付き
- middleware を `MiddlewareHandler<AppEnv>` で書ける

→ 全 handler / middleware が同じ `AppEnv` を共有することで、状態の追加忘れや型ずれを防止。

---

## 3. ルートを書いた瞬間に `param` が型推論される

```ts
app.get('/users/:userId/posts/:postId', (c) => {
  const u = c.req.param('userId')   // string (typed)
  const p = c.req.param('postId')   // string (typed)
  // const x = c.req.param('xxx')   // ← compile error
})
```

`request.ts:94-104` の overload と `types.ts` の `ParamKeys` 型 (`:userId` → `'userId'` の literal 抽出) が裏方。
オプショナル param (`:id?`) は `string | undefined` になる。

---

## 4. Validator — `c.req.valid()` で型付き入力を取り出す

### 仕組み

`src/validator/validator.ts` の `validator(target, fn)` は middleware を返す。

```ts
import { validator } from 'hono/validator'

app.post('/users',
  validator('json', (value, c) => {
    if (!value.name) return c.text('name is required', 400)
    return { name: String(value.name).trim() }   // ← この戻り値が次工程の入力
  }),
  (c) => {
    const body = c.req.valid('json')   // { name: string }
    return c.json({ ok: true, body })
  }
)
```

ポイント:
- validator は `Content-Type` を見て自動で `json` / `form` / `query` / `param` / `header` / `cookie` のどれかから値を抜く (`validator.ts:91-` のブロック分岐)。
- 検証関数が `Response` (= `c.text(..., 400)`) を返すと **そこで short-circuit** され、handler に行かない。
- オブジェクトを `return` すれば次の handler で `c.req.valid('json')` で型付きで取り出せる。

### Zod / Valibot 等との連携

外部パッケージ `@hono/zod-validator` がこの `validator` を thin wrap する。実装は本質的に:

```ts
zValidator('json', schema) => validator('json', (v, c) => {
  const r = schema.safeParse(v)
  if (!r.success) return c.json({ error: r.error.issues }, 400)
  return r.data
})
```

つまりこの repo の `validator/validator.ts` だけ理解すれば、外部 validator も同じパターンで読める。

---

## 5. `app.get(...).post(...)` チェーンと `hc` クライアント

```ts
const route = new Hono()
  .get('/users/:id', (c) => c.json({ id: c.req.param('id') }))
  .post('/users',
    validator('json', (v, c) => ({ name: String(v.name) })),
    (c) => c.json(c.req.valid('json'))
  )
export type AppType = typeof route

// 別ファイル: クライアント
import { hc } from 'hono/client'
const client = hc<AppType>('https://api.example.com')

const res = await client.users[':id'].$get({ param: { id: '42' } })
//          ↑ path / method / param / json が全部型付き
const json = await res.json()  // { id: string }
```

- `client/client.ts` が **`Schema` 型を Proxy で辿って fetch を組み立てる** 構造。
- 「サーバの route 定義をクライアントに型として import するだけ」で OpenAPI / tRPC 的な体験が手に入る。
- API 用途では今すぐ使わなくても、`export type AppType = typeof app` を **習慣にしておく** とあとから client を生やせる。

---

## 6. 型まわりで困った時の grep ポイント

| 探したい型 | 定義場所 |
|---|---|
| `Env`, `Bindings`, `Variables`, `Handler`, `MiddlewareHandler`, `Next` | `src/types.ts` 上半分 |
| `Schema`, `ToSchema`, `MergeSchemaPath`, `MergePath` | `src/types.ts` 中盤 |
| `Input`, `InferInput`, `ValidationTargets` | `src/types.ts` + `src/validator/utils.ts` |
| `Context`, `ContextVariableMap`, `ContextRenderer` | `src/context.ts` 冒頭 |
| `HonoRequest`, `ParamKeys` | `src/request.ts` + `src/types.ts` |
| `TypedResponse`, `InferRequestType`, `InferResponseType` | `src/types.ts` 末尾 + `src/client/types.ts` |

`types.ts` は **読まない**。必要になったら symbol 単位で grep するだけで十分回る。

---

## 7. 「型を強くするために来週からやる事」チェックリスト

- [ ] `type AppEnv = { Bindings: ..., Variables: ... }` を切って `new Hono<AppEnv>()` する
- [ ] Variables を増やしたら `AppEnv['Variables']` に追加 (= middleware で `c.set` した key は必ず型に書く)
- [ ] route ファイルは `const route = new Hono<AppEnv>()` でメソッドチェーンで書く (型蓄積のため)
- [ ] `export type AppType = typeof route` を必ず出す (将来 `hc` 用)
- [ ] body / query / param を読むときは `c.req.valid('...')` を経由する (= `validator` か `@hono/zod-validator`)
- [ ] エラーは `throw new HTTPException(401, { message })` 形式で統一

---

次は `06-reading-roadmap.md` の半日プラン詳細と、`07-express-vs-hono-cheatsheet.md` の Express→Hono 変換表。
