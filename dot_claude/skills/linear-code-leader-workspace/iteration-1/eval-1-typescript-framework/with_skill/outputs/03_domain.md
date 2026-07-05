# Phase 3: ドメインモデル

Hono は「業務ドメイン」を持つアプリではなくフレームワークなので、ドメイン = **フレームワークが扱う一次概念** (Request/Route/Handler/Middleware/Context など) として捉える。

## 型・インタフェース関係図 (Mermaid)

```mermaid
classDiagram
  class Hono~E,S,BasePath~ {
    +get/post/put/delete/...
    +use(path?, ...mw)
    +route(path, subApp)
    +mount(path, externalHandler)
    +fetch(req, env?, ctx?) Response
    +request(input) Response
    -router: Router
    -routes: RouterRoute[]
    -errorHandler
    -notFoundHandler
  }
  class HonoBase
  class Router~T~ {
    <<interface>>
    +name
    +add(method, path, handler)
    +match(method, path) Result~T~
  }
  class SmartRouter
  class RegExpRouter
  class TrieRouter
  class RouterRoute {
    +basePath: string
    +path: string
    +method: string
    +handler: H
  }
  class Result~T~ {
    [[T, ParamIndexMap][], ParamStash] | [[T, Params][]]
  }

  class Context~E,P,I~ {
    +req: HonoRequest
    +res: Response
    +env: E.Bindings
    +finalized: bool
    +error?: Error
    +text() / json() / html() / body()
    +set(k,v) / get(k) / var
    +status(code) / header(k,v)
    +redirect() / notFound() / newResponse()
  }
  class HonoRequest~P,I~ {
    +raw: Request
    +path: string
    +method
    +routeIndex
    +param(key)
    +query(key?)
    +header(key?)
    +json/text/parseBody/formData
    +valid(target)
  }

  class Handler~E,P,I,R~ {
    <<type>>
    (c, next) => R
  }
  class MiddlewareHandler {
    <<type>>
    (c, next) => Promise~R|void~
  }
  class H {
    <<type>>
    Handler | MiddlewareHandler
  }
  class ErrorHandler {
    <<type>>
    (err, c) => Response
  }
  class NotFoundHandler {
    <<type>>
    (c) => Response
  }
  class HTTPException {
    +status
    +res?
    +getResponse() Response
  }

  class Env {
    <<type>>
    Bindings? + Variables?
  }
  class Schema {
    <<type>>
    record of route schemas
  }
  class Input {
    <<type>>
    in / out / outputFormat
  }

  Hono <|-- HonoBase : extends
  HonoBase o-- Router : has-a
  Router <|.. SmartRouter
  Router <|.. RegExpRouter
  Router <|.. TrieRouter
  SmartRouter o-- RegExpRouter
  SmartRouter o-- TrieRouter
  Router ..> Result : returns
  Router ..> RouterRoute : stores tuple [H, RouterRoute]

  HonoBase ..> Context : creates per request
  Context o-- HonoRequest
  HonoRequest ..> Result : holds matchResult

  HonoBase ..> Handler : invokes
  Handler <|.. MiddlewareHandler : sibling type (union H)
  HonoBase o-- ErrorHandler
  HonoBase o-- NotFoundHandler
  ErrorHandler ..> HTTPException : may receive
  HTTPException ..> Response : getResponse()

  Hono ..> Env : generic
  Hono ..> Schema : generic
  Handler ..> Input : generic I
  HonoRequest ..> Input : generic I
```

## 用語集 (Hono 固有 + Web 標準の用語確認)

| 用語 | 意味 |
|---|---|
| **Hono (instance)** | `new Hono()` で得る App。`fetch(req)` を持つ呼べるオブジェクトでもある。 |
| **HonoBase** | `Hono` の親クラス。実装本体。`Hono` は Router を差し替えるだけの薄いサブクラス。 |
| **Router** | `(method, path)` → ハンドラ列の解決装置。`add` と `match` の 2 メソッドのみ。 |
| **SmartRouter** | 登録ルートを試行し、`UnsupportedPathError` を投げない最初の Router にバインドする実装。 |
| **RegExpRouter** | 全静的・動的ルートを 1 本の合成正規表現にビルドする最速 Router。任意の正規表現にできない制約あり。 |
| **TrieRouter** | トライ木ベースの汎用 Router。RegExp が扱えないパターンを受け持つ。 |
| **Result&lt;T&gt;** | `match()` の戻り値型。`[ [handler, paramIndexMap][], paramStash ]` か `[ [handler, params][] ]` の二形態。 |
| **RouterRoute** | `{ basePath, path, method, handler }`。`HonoBase.routes` に積まれる登録メタ情報。 |
| **Handler** | `(c, next) => Response | TypedResponse | Promise<...>`。エンドポイントハンドラ。 |
| **MiddlewareHandler** | `(c, next) => Promise<Response | void>`。`next()` を呼ぶことで下層に制御を渡す Koa 風中間処理。 |
| **H (union)** | `Handler | MiddlewareHandler`。Router は `[H, RouterRoute]` のタプルを保持する。 |
| **Context (c)** | 1 リクエスト分の状態と応答ファクトリ。`c.req`, `c.res`, `c.env`, `c.var`, `c.text()`, `c.json()` 等。**全関数に第 1 引数で渡る主役**。 |
| **HonoRequest (c.req)** | 標準 `Request` をラップ。型付き `param('id')`, `query('q')`, `json<T>()`, `valid('json')` を提供。 |
| **Env (型パラメタ)** | `{ Bindings?: ..., Variables?: ... }`。Cloudflare の `env` と `c.set/get` の名前空間を型付ける。 |
| **Bindings** | Cloudflare Workers の `env` (KV, D1, R2, Secret) を表す型スロット。Node では単なる object。 |
| **Variables** | `c.set/get/var` で読み書きするリクエストスコープの値の型スロット。 |
| **Schema (型パラメタ)** | 「このパスで何が in/out できるか」を型レベルで蓄積するレコード。`hono/client` で利用される。 |
| **Input** | バリデータの入出力型ペア (`in`/`out`)。`c.req.valid('json')` の戻り値型に効く。 |
| **HTTPException** | フレームワーク標準のエラー型。`throw new HTTPException(401)` で `errorHandler` 経由で Response 化。 |
| **ErrorHandler / NotFoundHandler** | `(err, c) => Response` / `(c) => Response`。`app.onError()` / `app.notFound()` で差し替え可能。 |
| **compose** | Koa 風ミドルウェアコンポーザ。配列 `[[handler, paramMap]...]` を受けて `(c, next?) => Promise<Context>` を返す。 |
| **Adapter** | 各ランタイム入口 → `app.fetch(req, env, ctx)` を繋ぐ薄いブリッジ。 |
| **fire()** | Service Worker 環境で `addEventListener('fetch', ...)` を勝手に登録するヘルパ (Deprecated)。 |
| **route() / mount() / basePath()** | サブアプリ合成、外部フレームワーク合成、ベースパス付き clone。 |
| **finalized** | `Context` が「もう Response が確定した」ことを示すフラグ。`compose` がこれを見て不要な NotFound 処理を抑止する。 |

## 重要な状態フラグ・列挙

- **`Context.finalized: boolean`**: `c.res = ...` または `c.text()/json()/body()` 系で確定する。Phase 4 のフローで重要な分岐点。
- **`Result<T>` の 2 形態**: RegExpRouter は `[handlers, paramStash]` を返し、TrieRouter/LinearRouter は `[handlers with concrete params]` を返す。`HonoRequest.param()` 側でこの 2 形態を吸収して同じ API になる。
- **`METHODS`**: `'get' | 'post' | 'put' | 'delete' | 'options' | 'patch'` (`src/router.ts:17`)。これ + `'all'` が `app.<method>` 動的メソッドの集合。
- **`METHOD_NAME_ALL = 'ALL'`**: `app.use()` は内部で `METHOD_NAME_ALL` 付きで登録される。

## 「Order と User の関係を 3 文で」相当の確認

> 「Hono の中心には `Hono` インスタンスと `Context` がある。`Hono` は `Router` (登録ルート集) と `errorHandler`/`notFoundHandler` を持ち、1 リクエストごとに `Context` を生成して `compose` で合成したハンドラ列に渡す。`Context` は `HonoRequest`(c.req) を内包し、`c.json()` などで `Response` を作る。」 — これが言えれば Phase 3 終了。
