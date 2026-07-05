# Phase 1: 鳥瞰 (Orientation)

## リポジトリ種別 (1 行)

**Web Standards (`Request` / `Response`) のみに依存する、ランタイム非依存・超軽量 TypeScript Web フレームワーク (ライブラリパッケージ)。**

## 1 段落要約

Hono は Express ライクな API (`app.get('/path', handler)` / `app.use(middleware)`) を提供しながら、内部実装は Node の `IncomingMessage` / `ServerResponse` には触れず、**標準の `Request` を受け `Response` を返す `fetch(req) => Response` 関数を中核**に据えている。これによって Cloudflare Workers, Bun, Deno, Node, AWS Lambda, Vercel など複数ランタイムを `src/adapter/*` の薄い橋渡しだけでサポートする。ルーティングは複数実装 (`RegExpRouter`, `TrieRouter`, `LinearRouter`, `PatternRouter`) を持ち、デフォルトでは `SmartRouter` が登録済みルートから最適なものを実行時に選ぶ。ミドルウェアは Koa スタイルの `compose` (next() で深さ方向に進み、戻ってきて後処理) で連結される。型システムが特徴的で、`app.get('/users/:id', ...)` のパスから `c.req.param('id')` の戻り値型を推論し、`hono/client` と組み合わせると RPC ライクなクライアント型まで導出する。

## 役割注釈付き src/ ツリー (深さ 1〜2)

```
src/
├── index.ts                # 公開エントリ。`Hono` クラスと主要 type を再エクスポート
├── hono.ts                 # 既定の `Hono` クラス。HonoBase に SmartRouter を注入するだけの薄いラッパ
├── hono-base.ts            # ★ 本体。ルート登録 (.get/.post/.use/.route/.mount) と `.fetch()`/`.#dispatch()`
├── compose.ts              # Koa 風ミドルウェアコンポーザ (next() 制御 + error/notFound フック)
├── context.ts              # ★ `Context` クラス: c.req / c.res / c.text() / c.json() / c.var / c.set 等
├── request.ts              # `HonoRequest`: 標準 Request のラッパ。param/query/json/body を提供
├── http-exception.ts       # 認証等で投げる `HTTPException` (status + Response を持つ Error)
├── router.ts               # Router インタフェース定義 + Result 型 + 共通定数 (METHODS など)
├── router/                 # ルーターの実装群
│   ├── smart-router/       #   登録ルートから最良の Router を実行時に選ぶ
│   ├── reg-exp-router/     #   最速。1 本の合成正規表現にコンパイル
│   ├── trie-router/        #   汎用。任意のパターンを扱える
│   ├── linear-router/      #   登録のみ高速 (短命プロセス向け)
│   └── pattern-router/     #   URLPattern ベース
├── types.ts                # ★ 中核型。Env/Schema/Handler/HandlerInterface/Input など。型推論の心臓
├── adapter/                # ランタイム別の入口 (cloudflare-workers/bun/deno/node 等への橋渡し)
├── middleware/             # 同梱ミドルウェア (cors, jwt, logger, basic-auth, bearer-auth, etag, ...)
├── helper/                 # ユーティリティ系ヘルパ (cookie, ssg, streaming, testing, factory, ...)
├── validator/              # `validator()` バリデーションミドルウェアファクトリ
├── client/                 # `hc<typeof app>()` 型安全 HTTP クライアント
├── jsx/                    # 同梱の JSX/SSR ランタイム (React 互換ライク)
├── preset/                 # `hono/tiny`, `hono/quick` 等の Router プリセット
└── utils/                  # 低レベルユーティリティ (url/body/jwt/cookie/headers/...)
```

## エントリポイント

- **ライブラリ公開エントリ**: `/tmp/eval-1/hono/src/index.ts` (`export { Hono }` と型のみ)
- **中核クラス**: `/tmp/eval-1/hono/src/hono.ts` (`new Hono()` でユーザーが触れる主役)
- **実装本体**: `/tmp/eval-1/hono/src/hono-base.ts` (`HonoBase` クラス。`.fetch()` / `.#dispatch()`)
- **ランタイムへの入口**: 各 `src/adapter/<runtime>/handler.ts` (ユーザー視点では `export default app` で十分なケースが多い)

`package.json` の主要シグナル:
- `"type": "module"` / `"main": "dist/cjs/index.js"` / `"module": "dist/index.js"`
- `exports` フィールドが極めて細かく、`hono`, `hono/cors`, `hono/jwt`, `hono/cloudflare-workers`, `hono/bun`, ... と機能別 / ランタイム別にサブパス分割されている。**つまり利用者はツリーシェイクのために用途別のサブパス import を使うのが前提**。

## ユーザーが「これは何か」を 1 段落で言えるか

> 「Hono は Web Standards の `Request`/`Response` だけで動く軽量 Web フレームワーク。`new Hono()` で作ったインスタンスが `fetch(req): Response` という関数として振る舞い、それを Cloudflare Workers/Bun/Deno/Node などのランタイムに繋ぐ。内部ではルーターが path にマッチするハンドラ列を返し、Koa 風の `compose` でミドルウェアを実行する。`Context` がリクエスト・レスポンス・変数袋として全関数を貫く主役オブジェクト。」 — ここまで言えれば Phase 1 終了。
