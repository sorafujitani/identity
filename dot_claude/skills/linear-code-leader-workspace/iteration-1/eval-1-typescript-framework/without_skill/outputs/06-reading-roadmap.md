# 06. Half-Day Reading Roadmap — 半日で読み切る具体プラン

「フレームワークの全体像と中核フローを把握する」ことだけにフォーカスした 4 時間プラン。各フェーズの冒頭にゴール、最後に到達確認を置いた。

> 行番号は `/tmp/eval-1/hono/src/` の v4.12.19 時点。マイナーアップデートで多少ずれても近辺を見れば OK。

---

## Phase 0: 助走 (10 分)

**ゴール**: 「Hono は何である / 何でないか」を 1 段落で言える。

- [ ] `README.md` の冒頭 30 行
- [ ] このディレクトリの `00-overview.md` (本ドキュメント群の起点)

到達確認:
- "Web Standards" と "ランタイム非依存 adapter" の 2 つのキーワードを自分の言葉で説明できる。

---

## Phase 1: 入口 (20 分)

**ゴール**: ユーザが import するものと、それが内部でどこへ繋がっているかを見える化。

- [ ] `src/index.ts` (52 行) — 公開 API の全リスト。
- [ ] `src/hono.ts` (34 行) — `Hono` の正体は `HonoBase` + `SmartRouter(RegExp+Trie)`。
- [ ] `src/preset/tiny.ts` / `src/preset/quick.ts` (各 20 行)。router 差し替えの例。

到達確認:
- `import { Hono } from 'hono'` した時、`Hono` クラスがどこで定義されているか即答できる (`hono-base.ts:98-)。
- `hono/tiny` と `hono/quick` の違いを 1 行で説明できる (= router 差替え)。

---

## Phase 2: 心臓部 — `hono-base.ts` + `compose.ts` (60 分) ★最重要

**ゴール**: リクエスト 1 本の流れを **行番号付き** で説明できる。

### 2-1. `hono-base.ts` を 3 区画に分けて読む (40 分)

| 区画 | 行 | 何が見える |
|---|---|---|
| 構成 | `:31-87` | デフォルト notFound / errorHandler、`HonoOptions` 型 |
| クラス本体 | `:98-173` | `constructor` で `get/post/use/on` が動的に生やされる |
| ルート操作 | `:175-391` | `#clone` / `route` / `basePath` / `onError` / `notFound` / `mount` / `#addRoute` |
| 実行 | `:393-460` | `#handleError` / `#dispatch` (← 必読) |
| 公開 entry | `:462-536` | `fetch` / `request` / `fire` |

注目箇所:
- **`#dispatch`** (`:400-460`): 「path 抽出 → router.match → Context 生成 → compose / fast-path」の 5 ステップ。
- 1 handler 最適化のロジック (`:424-442`)。
- `'Context is not finalized'` の発生条件 (`:449-453`)。

### 2-2. `compose.ts` (15 分)

- 全 73 行を 2 周読む。
- `dispatch` 内の `if (i <= index) throw 'next() called multiple times'` (line 33-35)。
- `context.req.routeIndex = i` (line 44) が **なぜ必要か** を `request.ts:107` (`#matchResult[0][this.routeIndex][1][key]`) と照合。

### 2-3. 自分の手で 1 経路 trace する (5 分)

`app.get('/x', mwA, handlerB); app.fetch(new Request('http://x/x'))` を実行したつもりで、行番号を 5-7 個並べる。

到達確認:
- `#dispatch` の 5 ステップを順に挙げられる。
- 「`next()` を 2 回呼ぶと何が起きるか」を即答 (= `'next() called multiple times'` throw)。

---

## Phase 3: ユーザ API — `Context` & `HonoRequest` (45 分)

**ゴール**: 来週の実装で `c.json` / `c.req.param` / `c.set` を迷わず使える。

### 3-1. `src/context.ts` を **要点だけ** (25 分)

- constructor `:352-361`
- `c.req` getter `:366-369` (HonoRequest は **lazy**)
- `c.res` getter / setter `:403-434` (Response の rewrite roundtrip に注目)
- `c.header` `:515-527`, `c.status` `:529-531`
- `c.set/get/var` `:546-602`
- response helpers: `c.body` `:664`, `c.text` `:682`, `c.json` `:708`, `c.html` `:723`, `c.redirect` `:750`, `c.notFound` `:776`
- `c.env`, `c.executionCtx`, `c.event` (Cloudflare/Workers 関連) `:303-397`

スキップして OK:
- `render` / `setRenderer` / `setLayout` 系 (JSX 用)
- `c.var` の高度な型 (`IsAny` 分岐)

### 3-2. `src/request.ts` を **API だけ拾い読み** (15 分)

- `param/query/queries/header` (`:94-` 周辺)
- `json/text/arrayBuffer/blob/formData/parseBody` の body cache (`:200-` 周辺、`bodyCache` フィールドに注目)
- `valid('json'|'query'|...)` (`:430-` 周辺)
- `routePath` / `matchedRoutes` (デバッグ用)

### 3-3. middleware 1 本を読む (5 分)

`src/middleware/logger/index.ts` (96 行)。`await next()` の前後で時間計測する典型例。**全 middleware は同じパターン**。

到達確認:
- `c.json(obj)` した時に Headers と Status がどう統合されるか、`#newResponse` (`:604-639`) を指さして説明できる。
- `c.req.param` が `#matchResult` をどう使っているかが見える。

---

## Phase 4: Router 層 (40 分)

**ゴール**: 「Smart=RegExp+Trie」と「いつ Linear/Pattern を使うか」を判断できる。

- [ ] `src/router.ts` (103 行) — interface と `Result<T>` の二形態。
- [ ] `src/router/smart-router/router.ts` (70 行) — `match` の自己書き換え (`:46`)。
- [ ] `src/router/linear-router/router.ts` (~145 行) — 構造が単純で trie の挙動理解の足掛かり。
- [ ] `src/router/trie-router/node.ts` の `insert` / `search` だけ眺める。
- [ ] (任意) `src/router/reg-exp-router/router.ts` 冒頭 100 行で「全 path → 巨大 regex」の発想を確認。
- [ ] `src/router/pattern-router/router.ts` (50 行未満) で `URLPattern` の薄いラッパーを確認。

到達確認:
- `UnsupportedPathError` が出ると `SmartRouter` が何をするか即答 (= 次の router にフォールバック)。
- `paramStash` 形式と `Params` (object) 形式の使い分けが分かる。

---

## Phase 5: Validator & 型駆動 API (30 分)

**ゴール**: 来週の API で型安全な request 入出力を書ける。

- [ ] `src/http-exception.ts` (79 行) — エラーの基本形。
- [ ] `src/validator/validator.ts` 冒頭 100 行 — `validator(target, fn)` の動き。
- [ ] `src/validator/utils.ts` (型ユーティリティ) を流し見。
- [ ] `src/types.ts` の `Env`, `Handler`, `MiddlewareHandler`, `Input` の定義だけ確認 (上から 100 行)。

到達確認:
- `c.req.valid('json')` の型がどこで決まっているかを 1 経路で説明 (= `validator()` の generic 推論)。
- `HTTPException` を投げた時のレスポンス組立を `hono-base.ts:35-42` を指して説明できる。

---

## Phase 6: Adapter (Cloudflare or Node) (20 分)

**ゴール**: 採用予定のランタイムで `app.fetch` がどう呼ばれるかを把握。

### Cloudflare Workers 採用なら

- [ ] `src/adapter/cloudflare-workers/index.ts` を開く (5 行)。中身は helper のみ — **本体は `export default app` で完結**。
- [ ] Workers の `fetch(req, env, ctx)` シグネチャは `app.fetch` と同じなので、特別な配線が要らない。

### AWS Lambda 採用なら

- [ ] `src/adapter/aws-lambda/handler.ts:239-276` の `handle()` を読む。
- [ ] event → Request 変換 (`createRequest` / `EventProcessor` `:278-`)、Response → APIGatewayProxyResult 変換 (`createResult`) のペア構造を理解。

### Node.js 採用なら

- [ ] このリポジトリには **無い**。`@hono/node-server` を別途調べる: `serve({ fetch: app.fetch, port: 3000 })` パターン。
- [ ] 概念だけ: Node の `http.IncomingMessage` を Fetch `Request` に正規化して `app.fetch` に渡す。

到達確認:
- "ランタイムの違いを吸収するのは adapter で、コアは `fetch(req)=>Response` だけ" を実コードで指せる。

---

## Phase 7: 仕上げ (15 分)

**ゴール**: 来週の出発点を確認。

- [ ] `src/helper/testing/index.ts` (28 行) — `testClient(app)` を使うと型付きの test が書ける。
- [ ] `src/middleware/cors/index.ts` の使い方コメント (`:24-61`) で標準 middleware の典型 API 形を確認。
- [ ] `src/helper/factory/index.ts` の `createFactory` (型情報を持った handler を切り出す helper) の概念だけ確認。

---

## 全体到達確認チェックリスト

- [ ] **「`app.fetch` が呼ばれてから handler が動くまで」** をファイル + 行番号で 5-7 ステップで言える
- [ ] **`compose.ts`** の onion 構造を 30 秒で説明できる
- [ ] **`c.json/text/html` は Response を作るだけで送信しない** (return が必要) を即答
- [ ] **Smart/Reg/Trie/Linear/Pattern** の 5 router の使い分けを 1 行ずつ言える
- [ ] **`Env / Variables / Bindings`** を使った型付け方を書ける
- [ ] **`HTTPException`** と `app.onError` の連携を実コードで指せる
- [ ] **`validator`** と `c.req.valid('...')` の型の流れを追える
- [ ] **採用予定 adapter** の入口ファイルを開いて、`app.fetch` を呼んでいる行を指せる

ここまで来たら「初見で読みました」「中核フローを把握しました」と胸を張って言える。

---

最後に `07-express-vs-hono-cheatsheet.md` を置いておく。実装中に手元で開くと便利。
